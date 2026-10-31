---
id: lab-3.14-monitoreo-disco-custom
title: Métricas de Disco, Filesystems e Inodos con Textfile Collector y Grafana
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.14'
sections:
- '3.14'
- '3'
category: observability
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- storage
- filesystems
- inodos
- df
- node-exporter
- textfile-collector
- prometheus
- grafana
- observability
- ext4
- xfs
- btrfs
tools:
- df
- awk
- curl
- node_exporter
- prometheus
- grafana
- apt
- bash
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 1024
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-24'
  notes: 'Ejecución validada con colector_disco.sh volcando métricas atómicas en /var/lib/node_exporter/textfile_collector.
    Soporta 3 rutas de despliegue: reutilización de lab-3.6, instalación nativa vía
    APT (Ubuntu/Debian) o binarios portables en /tmp.'
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Probado con volúmenes ext4 y XFS en instancias EC2 con Grafana local y aprovisionamiento
    automático de datasources.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio de métricas personalizadas de almacenamiento que une los
  conceptos de mantenimiento de filesystems (df, capacidad, inodos y tipos ext4/xfs/btrfs)
  con la observabilidad continua de Prometheus y Grafana. Explica tres alternativas
  de preparación (reutilizar laboratorios previos, instalar nativamente con APT como
  servicios systemd o usar binarios portables), despliega un script colector atómico
  para el Textfile Collector de Node Exporter, expone métricas con etiquetas semánticas
  (device, mountpoint, fstype), valida la ingesta con curl y guía la instalación de
  Grafana y la construcción de paneles y consultas PromQL.
files:
  guide: monitoreo/monitoreo_disco_custom.md
  script: monitoreo/scripts/colector_disco.sh
  terraform: null
prerequisites:
- lab-3.6-monitoreo-metricas
- lab-3.13-mantenimiento-volumenes
next_recommended_labs:
- lab-3.15-alertmanager-alertas-locales
- lab-3.16-integrador-web-lvm-raid-monitoreo
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Métricas Personalizadas de Almacenamiento, Filesystems e Inodos

En el laboratorio de **[Mantenimiento de Volúmenes (Lab 3.13)](../filesystems/mantenimiento_volumenes.md)** aprendiste a diagnosticar la salud de tus discos mediante comandos forenses puntuales como `df -h`, `df -i`, `df -T` y `tune2fs`. Allí descubriste un concepto crítico: **un filesystem puede colapsar por falta de inodos aunque tenga cientos de Gigabytes libres**.

En el laboratorio de **[Monitoreo Continuo (Lab 3.6)](monitoreo_metricas.md)** aprendiste a recolectar métricas usando **Prometheus Node Exporter** y su mecanismo de **Textfile Collector**.

Este laboratorio conecta ambos mundos:
1. Te da la opción de **reutilizar lo que ya tenés corriendo**, **instalar con APT** como servicios permanentes, o usar **binarios portables**.
2. Diseña un **recolector en Bash** que extrae el espacio total, usado, libre, tipo de filesystem e inodos.
3. Formatea los datos según la especificación abierta de **Prometheus / OpenMetrics** usando etiquetas semánticas (`mountpoint`, `fstype`, `device`).
4. Expone las métricas vía **Node Exporter** en `:9100/metrics` y las audita con `curl`.
5. Guía la instalación de **Grafana** (con aprovisionamiento automático de Datasource) y define las consultas **PromQL** y paneles recomendados.

---

## ⚙️ 0. Preparación del Entorno: Elige tu Camino

Para no obligarte a reinstalar herramientas si ya las tenés configuradas, podés elegir cualquiera de las siguientes **3 alternativas**:

```
+───────────────────────────────────────────────────────────────────────────────────────────+
| ¿CÓMO DESEAS PREPARAR TU ENTORNO?                                                         |
|                                                                                           |
|  [ RUTA A: Reutilizar Labs Anteriores ]                                                   |
|   • Si ya ejecutaste el Lab 3.6 (demo_monitoreo.sh --keep)                                |
|   • Node Exporter ya está activo en :9100 con el directorio textfile listo.               |
|   ➔ ¡Saltás directo a la Sección 2! No instalás absolutamente nada.                       |
|                                                                                           |
|  [ RUTA B: Instalación Nativa con APT (Estándar Servidor / Producción) ]                  |
|   • Ideal si querés Prometheus y Node Exporter instalados como servicios systemd.         |
|   • Comandos: sudo apt update && sudo apt install -y prometheus prometheus-node-exporter  |
|                                                                                           |
|  [ RUTA C: Binarios Portátiles / Standalone en /tmp (Modo Lab Descartable) ]              |
|   • Descarga directa de binarios Go oficiales en /tmp.                                    |
|   • No requiere apt, no deja servicios residentes, ideal para WSL2 o máquinas prestadas. |
+───────────────────────────────────────────────────────────────────────────────────────────+
```

### Detalle de la Ruta B: Instalación con APT en Ubuntu / Debian
Si preferís instalar Prometheus y Node Exporter mediante los repositorios oficiales de tu distribución:

```bash
# 1. Instalar Prometheus y Node Exporter
sudo apt update
sudo apt install -y prometheus prometheus-node-exporter

# 2. Configurar el directorio del Textfile Collector en Node Exporter de Ubuntu:
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown -R prometheus:prometheus /var/lib/node_exporter/textfile_collector 2>/dev/null || true

# En Ubuntu/Debian, los argumentos se definen en /etc/default/prometheus-node-exporter:
echo 'ARGS="--collector.textfile.directory=/var/lib/node_exporter/textfile_collector"' | sudo tee -a /etc/default/prometheus-node-exporter
sudo systemctl restart prometheus-node-exporter

# 3. Comprobar que Prometheus scrapea al puerto 9100:
# En /etc/prometheus/prometheus.yml ya viene preconfigurado el target localhost:9100
sudo systemctl restart prometheus
sudo systemctl status prometheus-node-exporter --no-pager
```

### Detalle de la Ruta C: Binarios Portátiles en `/tmp`
Si preferís binarios estáticos ultralivianos sin tocar APT:
```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector

# Si no tenés el binario de lab-3.6:
VER="1.8.2"
if [ ! -f "/tmp/node_exporter" ]; then
    curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz" | tar -xz -C /tmp/
    mv /tmp/node_exporter-${VER}.linux-amd64/node_exporter /tmp/node_exporter
fi

/tmp/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector --web.listen-address=":9100" &
```

---

## 🏗️ 1. Arquitectura de Telemetría de Almacenamiento

```
+───────────────────────────────────────────────────────────────────────────────────────────+
| SISTEMA OPERATIVO LINUX (Kernel VFS / df / stat)                                          |
|                                                                                           |
|   / (ext4)              /data (xfs)             /backup (btrfs)                           |
|   Bloques + Inodos      Bloques + Inodos         Bloques dinámicos                        |
+───────────────────────────────────────────────────────────────────────────────────────────+
                                    │
                                    ▼  [ Ejecución periódica (Cron / Timer / Manual) ]
+───────────────────────────────────────────────────────────────────────────────────────────+
| SCRIPT RECOLECTOR PERSONALIZADO: colector_disco.sh                                        |
|   1. Lee df -PT -B1 (Bloques exactos sin prefijos)                                        |
|   2. Lee df -PTi (Inodos libres y consumidos)                                             |
|   3. Excluye pseudo-filesystems virtuales (tmpfs, devtmpfs, overlay, squashfs)            |
|   4. Escribe atómicamente (.prom.$$ ➔ .prom)                                              |
+───────────────────────────────────────────────────────────────────────────────────────────+
                                    │
                                    ▼
+───────────────────────────────────────────────────────────────────────────────────────────+
| DIRECTORIO TEXTFILE COLLECTOR (/var/lib/node_exporter/textfile_collector/)                |
|   └── custom_disk_health.prom                                                             |
+───────────────────────────────────────────────────────────────────────────────────────────+
                                    │
                                    ▼  [ Node Exporter lee e indexa los archivos de texto ]
+───────────────────────────────────────────────────────────────────────────────────────────+
| AGENTE NODE EXPORTER (:9100/metrics)                                                      |
|   Expone métricas del Kernel + Custom Metrics en formato OpenMetrics                      |
+───────────────────────────────────────────────────────────────────────────────────────────+
                    │                                               │
                    ▼ [ PULL Scrape ]                               ▼ [ Inspección manual ]
     [ Prometheus / Grafana Dashboard ]                       [ curl localhost:9100 ]
```

---

## 📋 2. Las Métricas a Exponer

Para reflejar fielmente el estado del disco, el recolector genera **8 series temporales de tipo Gauge** por cada partición persistente:

| Métrica | Tipo | Etiquetas (Labels) | Significado |
| :--- | :--- | :--- | :--- |
| `custom_disk_bytes_total` | Gauge | `device`, `mountpoint`, `fstype` | Capacidad total de almacenamiento en bytes. |
| `custom_disk_bytes_used` | Gauge | `device`, `mountpoint`, `fstype` | Espacio actualmente ocupado en bytes. |
| `custom_disk_bytes_free` | Gauge | `device`, `mountpoint`, `fstype` | Espacio disponible para usuarios no privilegiados. |
| `custom_disk_usage_percent` | Gauge | `device`, `mountpoint`, `fstype` | Porcentaje de ocupación de bloques (0 a 100). |
| `custom_disk_inodes_total` | Gauge | `device`, `mountpoint`, `fstype` | Inodos totales asignados al superbloque. |
| `custom_disk_inodes_used` | Gauge | `device`, `mountpoint`, `fstype` | Inodos consumidos por archivos y directorios. |
| `custom_disk_inodes_free` | Gauge | `device`, `mountpoint`, `fstype` | Inodos aún disponibles para crear ficheros. |
| `custom_disk_inodes_usage_percent` | Gauge | `device`, `mountpoint`, `fstype` | Porcentaje de inodos consumidos (0 a 100). |

---

## ?? 3. Despliegue del Script Colector (`colector_disco.sh`)

Pod?s utilizar el script que ya viene en el repositorio o crearlo directamente en tu m?quina con el siguiente bloque ejecutable:

### Opci?n 1: Crear el archivo con un solo comando copy-paste (Crea el fichero en disco)

```bash
# 1. Asegurar la carpeta y crear el script con privilegios de escritura:
mkdir -p scripts
cat << 'EOF' > scripts/colector_disco.sh
#!/usr/bin/env bash
# ==============================================================================
# SCRIPT COLECTOR EDUCATIVO: M?tricas de Disco, Filesystem e Inodos
# Escribe m?tricas en formato est?ndar OpenMetrics para Node Exporter.
# ==============================================================================
set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
OUTPUT_FILE="${TEXTFILE_DIR}/custom_disk_health.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

# Validaci?n de privilegios si se usa el directorio del sistema
if [ "$EUID" -ne 0 ] && [ "$TEXTFILE_DIR" = "/var/lib/node_exporter/textfile_collector" ]; then
    echo "? Error: Se requieren permisos de superusuario (root) para escribir en $TEXTFILE_DIR" >&2
    echo "Ejecut?: sudo $0" >&2
    exit 1
fi

mkdir -p "$TEXTFILE_DIR"

# 1. Cabeceras OpenMetrics (HELP y TYPE para cada m?trica expuesta)
cat << 'HEADER_EOF' > "$TMP_FILE"
# HELP custom_disk_bytes_total Capacidad total del sistema de archivos en bytes
# TYPE custom_disk_bytes_total gauge
# HELP custom_disk_bytes_used Espacio en disco actualmente utilizado en bytes
# TYPE custom_disk_bytes_used gauge
# HELP custom_disk_bytes_free Espacio libre disponible para usuarios no privilegiados en bytes
# TYPE custom_disk_bytes_free gauge
# HELP custom_disk_usage_percent Porcentaje de ocupacion del espacio en disco (0 a 100)
# TYPE custom_disk_usage_percent gauge
# HELP custom_disk_inodes_total Total de inodos indexables soportados por el filesystem
# TYPE custom_disk_inodes_total gauge
# HELP custom_disk_inodes_used Cantidad de inodos actualmente consumidos por archivos
# TYPE custom_disk_inodes_used gauge
# HELP custom_disk_inodes_free Inodos disponibles para crear nuevos archivos
# TYPE custom_disk_inodes_free gauge
# HELP custom_disk_inodes_usage_percent Porcentaje de consumo de inodos (0 a 100)
# TYPE custom_disk_inodes_usage_percent gauge
HEADER_EOF

# 2. Recolecci?n de sistemas de archivos reales (POSIX portable -P, bloques en bytes -B1)
df -PT -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2 | while read -r dev fstype total used avail pcent mount; do
    [ -z "$mount" ] && continue
    
    pcent_num="${pcent%\%}"
    [[ "$pcent_num" =~ ^[0-9]+$ ]] || pcent_num=0

    # Inodos para este mount espec?fico
    read -r itotal iused ifree ipcent < <(df -PTi "$mount" 2>/dev/null | tail -n 1 | awk '{print $3, $4, $5, $6}')
    ipcent_num="${ipcent%\%}"

    # Soporte para filesystems con inodos din?micos (Btrfs)
    [[ "$itotal" =~ ^[0-9]+$ ]] || itotal=0
    [[ "$iused" =~ ^[0-9]+$ ]] || iused=0
    [[ "$ifree" =~ ^[0-9]+$ ]] || ifree=0
    [[ "$ipcent_num" =~ ^[0-9]+$ ]] || ipcent_num=0

    cat << DATA_EOF >> "$TMP_FILE"
custom_disk_bytes_total{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${total}
custom_disk_bytes_used{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${used}
custom_disk_bytes_free{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${avail}
custom_disk_usage_percent{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${pcent_num}
custom_disk_inodes_total{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${itotal}
custom_disk_inodes_used{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${iused}
custom_disk_inodes_free{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${ifree}
custom_disk_inodes_usage_percent{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${ipcent_num}
DATA_EOF
done

# 3. Reemplazo at?mico y permisos
mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
echo "? M?tricas de disco exportadas exitosamente en: $OUTPUT_FILE"
EOF

# 2. Asignar permisos de ejecuci?n al script creado:
chmod +x scripts/colector_disco.sh
```

### Opci?n 2: Usar el archivo ya provisto en el repositorio

Si clonaste el repositorio, el archivo ya est? disponible en [`scripts/colector_disco.sh`](scripts/colector_disco.sh).

### Ejecutar y probar el recolector:

> [!IMPORTANT]
> Se requiere `sudo` para escribir en `/var/lib/node_exporter/textfile_collector/`. Si lo ejecut?s sin `sudo`, el script te lo advertir? y detendr? la ejecuci?n de forma segura.

```bash
sudo ./scripts/colector_disco.sh
```

**Salida esperada:**
```text
? M?tricas de disco exportadas exitosamente en: /var/lib/node_exporter/textfile_collector/custom_disk_health.prom
```

---

## 🔍 4. Verificación con `curl`

Una vez ejecutado el recolector, Node Exporter lo expone inmediatamente sin necesidad de reiniciar:

```bash
# Consultar únicamente nuestras métricas de disco
curl -s http://localhost:9100/metrics | grep custom_disk_
```

**Salida real observada:**
```
# HELP custom_disk_bytes_total Capacidad total del sistema de archivos en bytes
# TYPE custom_disk_bytes_total gauge
custom_disk_bytes_total{device="/dev/sda1",mountpoint="/",fstype="ext4"} 53687091200
# HELP custom_disk_bytes_used Espacio en disco actualmente utilizado en bytes
# TYPE custom_disk_bytes_used gauge
custom_disk_bytes_used{device="/dev/sda1",mountpoint="/",fstype="ext4"} 18253611008
# HELP custom_disk_usage_percent Porcentaje de ocupacion del espacio en disco (0 a 100)
# TYPE custom_disk_usage_percent gauge
custom_disk_usage_percent{device="/dev/sda1",mountpoint="/",fstype="ext4"} 34
# HELP custom_disk_inodes_usage_percent Porcentaje de consumo de inodos (0 a 100)
# TYPE custom_disk_inodes_usage_percent gauge
custom_disk_inodes_usage_percent{device="/dev/sda1",mountpoint="/",fstype="ext4"} 12
```

---

## 📊 5. Instalación y Visualización en Grafana

Para visualizar las métricas en un panel gráfico necesitás Grafana escuchando en el puerto `3000`.

### 5.1 Cómo instalar y levantar Grafana (Elige una opción)

#### Opción A: Binario Standalone / Tarball (Recomendada para Labs y WSL2)
*No requiere permisos permanentes ni repositorios extras. Se ejecuta en `/tmp` y no deja servicios residentes.*

```bash
cd /tmp
curl -sL https://dl.grafana.com/oss/release/grafana-11.2.0.linux-amd64.tar.gz | tar -xz
cd grafana-v11.2.0/bin
./grafana server &
```

#### Opción B: Docker en 1 solo comando
```bash
docker run -d --name=grafana -p 3000:3000 grafana/grafana-oss:latest
```

#### Opción C: Instalación con APT oficial en Ubuntu / Debian (Como Servicio Systemd)
```bash
sudo apt-get install -y apt-transport-https software-properties-common wget gpg
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl enable --now grafana-server
```

---

### 5.2 Tip de Sysadmin: Aprovisionamiento Automático de Datasource

Para no perder tiempo entrando a la interfaz web a conectar Prometheus manualmente, podés dejar creado este archivo YAML de aprovisionamiento:

```bash
# Si usás APT/Systemd (/etc/grafana):
sudo mkdir -p /etc/grafana/provisioning/datasources/
sudo bash -c 'cat <<EOF > /etc/grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF'

# Si usás el binario standalone en /tmp:
# Creá la misma carpeta en: /tmp/grafana-v11.2.0/conf/provisioning/datasources/prometheus.yaml
```

Cuando Grafana inicie, Prometheus ya estará conectado y listo para usar.

---

### 5.3 Primer Acceso Web
1. Abrí tu navegador en **`http://localhost:3000`**
2. **Usuario:** `admin` | **Contraseña inicial:** `admin` *(podés presionar "Skip" para cambiarla luego)*.

---

### 5.4 Construcción de Paneles en Grafana

Hacé clic en **Dashboards ➔ New Dashboard ➔ Add visualization**, seleccioná el origen de datos **Prometheus** y configurá estos 3 paneles:

#### Panel 1: Gauge de Espacio Ocupado (%)
- **Tipo de Panel:** Gauge
- **Consulta PromQL:**
  ```promql
  custom_disk_usage_percent{mountpoint="/"}
  ```
- **Unidad:** Percent (0-100)
- **Thresholds (Umbrales):**
  - Verde: 0%
  - Amarillo: 70%
  - Rojo: 85%

#### Panel 2: Stat Panel de Inodos Ocupados (%) — Diagnóstico Preventivo
- **Tipo de Panel:** Stat
- **Consulta PromQL:**
  ```promql
  custom_disk_inodes_usage_percent
  ```
- **Propósito:** Detectar el problema del Lab 3.13: si este panel marca 95% en rojo pero el Gauge de espacio marca 20%, sabés al instante que el disco colapsará por inodos.

#### Panel 3: Tabla General de Filesystems del Sistema
- **Tipo de Panel:** Table
- **Consulta PromQL:**
  ```promql
  custom_disk_bytes_free
  ```
- **Transformación de datos en Grafana:** *Labels to fields* para mostrar:
  - `mountpoint`
  - `fstype` (ext4, xfs, btrfs)
  - `device`
  - `Value` formateado como `Bytes (IEC)` -> Muestra automáticamente GiB / TiB legibles.

---

## 🔄 6. Automatización de la Recolección

Para que las métricas se mantengan actualizadas en tiempo real:

### Opción A: Cron Job (Cada 1 minuto)
```bash
sudo crontab -e
# Agregar la siguiente línea:
* * * * * /ruta/al/repo/linux/administrator/monitoreo/scripts/colector_disco.sh >/dev/null 2>&1
```

### Opción B: Systemd Timer (Recomendado según Lab 2.1)
Un timer de systemd ejecutando el script cada 30 segundos sin depender del daemon de cron.

---

## ?? 7. Limpieza del Entorno al Finalizar

Al concluir la pr?ctica, ten?s dos alternativas para desmantelar todos los servicios, procesos en segundo plano y archivos de m?tricas:

### Alternativa A: Limpieza Automatizada con Script (Recomendado)

Ejecut? el script de limpieza provisto en el repositorio:

```bash
sudo ./linux/administrator/monitoreo/limpiar_monitoreo_disco_custom.sh
```

**Opciones avanzadas:**
- `--keep-node`: Conserva Node Exporter activo en el puerto 9100 si vas a continuar con el siguiente laboratorio (`Lab 3.15` o `Lab 3.16`).
  ```bash
  sudo ./linux/administrator/monitoreo/limpiar_monitoreo_disco_custom.sh --keep-node
  ```
- `--purge-packages`: Si instalaste Grafana o Prometheus mediante APT y quer?s desinstalarlos completamente del sistema operativo.
  ```bash
  sudo ./linux/administrator/monitoreo/limpiar_monitoreo_disco_custom.sh --purge-packages
  ```

---

### Alternativa B: Procedimiento Manual Paso a Paso

Si prefer?s realizar el desmantelamiento de forma manual:

#### 1. Detener Grafana (:3000)
```bash
# Si usaste el binario en /tmp:
sudo pkill -f "grafana.*server" || true
sudo rm -rf /tmp/grafana* /tmp/grafana-*.tar.gz

# Si usaste Docker:
docker rm -f grafana 2>/dev/null || true

# Si instalaste con APT:
sudo systemctl stop grafana-server && sudo systemctl disable grafana-server
sudo rm -f /etc/grafana/provisioning/datasources/prometheus.yaml
sudo rm -f /etc/apt/sources.list.d/grafana.list /etc/apt/keyrings/grafana.gpg
```

#### 2. Detener Prometheus (:9090)
```bash
sudo pkill -f "prometheus.*--config.file" || true
sudo systemctl stop prometheus 2>/dev/null || true
sudo rm -rf /tmp/prometheus*
```

#### 3. Detener Node Exporter (:9100) y restaurar configuraci?n
```bash
sudo pkill -f "node_exporter" || true
sudo systemctl stop prometheus-node-exporter 2>/dev/null || true
sudo sed -i '/--collector.textfile.directory/d' /etc/default/prometheus-node-exporter 2>/dev/null || true
sudo rm -rf /tmp/node_exporter*
```

#### 4. Purgar automatizaci?n (Cron y Systemd Timers)
```bash
sudo crontab -l 2>/dev/null | grep -v -E 'colector_disco|custom_disk' | sudo crontab -
sudo systemctl stop colector-disco.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/colector-disco.*
sudo systemctl daemon-reload
```

#### 5. Purgar archivos de m?tricas y colector
```bash
sudo rm -f /var/lib/node_exporter/textfile_collector/custom_disk_health.prom*
sudo rmdir /var/lib/node_exporter/textfile_collector 2>/dev/null || true
sudo rm -f /usr/local/bin/colector_disco.sh
```

#### 6. Comprobaci?n final de puertos libres
```bash
sudo ss -tlpn | grep -E ':(3000|9090|9100)\s' || echo "? Puertos 3000, 9090 y 9100 completamente liberados."
```

---

## 🎯 Conclusión del Laboratorio

Completando este laboratorio lograste:
1. Conocer las **3 vías de despliegue**: reutilizar el entorno, instalar mediante paquetes de distribución con APT, o usar binarios portables sin instalación.
2. Traducir la teoría de volúmenes y superbloques (`df -h`, inodos `df -i`, tipos de filesystem) en métricas estándar de producción.
3. Exponerlas a través del **Textfile Collector** sin sobrecargar el servidor con daemons pesados.
4. Consultar y auditar la salida cruda con `curl`.
5. Levantar Grafana con aprovisionamiento automático y armar paneles para alertar visualmente tanto la falta de espacio como la saturación de inodos.
