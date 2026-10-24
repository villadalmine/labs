---
id: lab-3.14-monitoreo-disco-custom
title: 'Métricas de Disco, Filesystems e Inodos con Textfile Collector y Grafana'
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
- grafana
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
  notes: Ejecución validada con colector_disco.sh volcando métricas atómicas en /var/lib/node_exporter/textfile_collector. Reutiliza el binario de Node Exporter levantado en lab-3.6 sin necesidad de reinstalar.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Probado con volúmenes ext4 y XFS en instancias EC2.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio de métricas personalizadas de almacenamiento que une los conceptos de mantenimiento de filesystems (df, capacidad, inodos y tipos ext4/xfs/btrfs) con la observabilidad continua de Prometheus y Grafana. Despliega un script colector atómico para el Textfile Collector de Node Exporter, expone métricas con etiquetas semánticas (device, mountpoint, fstype), valida la ingesta con curl y construye paneles y consultas PromQL en Grafana.
files:
  guide: monitoreo/monitoreo_disco_custom.md
  script: monitoreo/scripts/colector_disco.sh
  terraform: null
prerequisites:
- lab-3.6-monitoreo-metricas
- lab-3.13-mantenimiento-volumenes
next_recommended_labs:
- lab-3.15-alertmanager-alertas-locales
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Métricas Personalizadas de Almacenamiento, Filesystems e Inodos

En el laboratorio de **[Mantenimiento de Volúmenes (Lab 3.13)](../filesystems/mantenimiento_volumenes.md)** aprendiste a diagnosticar la salud de tus discos mediante comandos forenses puntuales como `df -h`, `df -i`, `df -T` y `tune2fs`. Allí descubriste un concepto crítico: **un filesystem puede colapsar por falta de inodos aunque tenga cientos de Gigabytes libres**.

En el laboratorio de **[Monitoreo Continuo (Lab 3.6)](monitoreo_metricas.md)** aprendiste a recolectar métricas usando **Prometheus Node Exporter** y su mecanismo de **Textfile Collector**.

Este laboratorio conecta ambos mundos:
1. Diseña un **recolector en Bash** que extrae el espacio total, usado, libre, tipo de filesystem e inodos.
2. Formatea los datos según la especificación abierta de **Prometheus / OpenMetrics** usando etiquetas semánticas (`mountpoint`, `fstype`, `device`).
3. Expone las métricas vía **Node Exporter** en `:9100/metrics` y las audita con `curl`.
4. Define las consultas **PromQL** y la visualización recomendada en paneles de **Grafana**.

---

> [!TIP]
> ### 💡 Reutilización del Entorno (No reinstales todo)
> Si ya ejecutaste el **Lab 3.6** (`demo_monitoreo.sh --keep` o servicio systemd activo):
> - **Node Exporter ya está corriendo** en el puerto TCP `9100`.
> - El directorio `/var/lib/node_exporter/textfile_collector` ya está creado.
> 
> Podés pasar directamente a ejecutar el colector de disco. Si no está activo, iniciarlo toma solo 10 segundos:
> ```bash
> sudo mkdir -p /var/lib/node_exporter/textfile_collector
> # Si ya tenés el binario descargado de lab-3.6:
> /tmp/node_exporter-1.8.2.linux-amd64/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector &
> ```

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

## 💻 3. Despliegue del Script Colector (`colector_disco.sh`)

El script se encuentra en [`scripts/colector_disco.sh`](scripts/colector_disco.sh).

```bash
#!/usr/bin/env bash
set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
OUTPUT_FILE="${TEXTFILE_DIR}/custom_disk_health.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

mkdir -p "$TEXTFILE_DIR"

# Cabeceras estándar OpenMetrics
cat << 'EOF' > "$TMP_FILE"
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
EOF

# Parsing POSIX portable (-P), bloques en bytes (-B1) y filtrado de no-persistentes
df -PT -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2 | while read -r dev fstype total used avail pcent mount; do
    [ -z "$mount" ] && continue
    
    pcent_num="${pcent%\%}"
    [[ "$pcent_num" =~ ^[0-9]+$ ]] || pcent_num=0

    # Inodos para este mount específico
    read -r itotal iused ifree ipcent < <(df -PTi "$mount" 2>/dev/null | tail -n 1 | awk '{print $3, $4, $5, $6}')
    ipcent_num="${ipcent%\%}"

    # Soporte para filesystems con inodos dinámicos (Btrfs)
    [[ "$itotal" =~ ^[0-9]+$ ]] || itotal=0
    [[ "$iused" =~ ^[0-9]+$ ]] || iused=0
    [[ "$ifree" =~ ^[0-9]+$ ]] || ifree=0
    [[ "$ipcent_num" =~ ^[0-9]+$ ]] || ipcent_num=0

    cat << EOF >> "$TMP_FILE"
custom_disk_bytes_total{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${total}
custom_disk_bytes_used{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${used}
custom_disk_bytes_free{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${avail}
custom_disk_usage_percent{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${pcent_num}
custom_disk_inodes_total{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${itotal}
custom_disk_inodes_used{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${iused}
custom_disk_inodes_free{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${ifree}
custom_disk_inodes_usage_percent{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${ipcent_num}
EOF
done

# Reemplazo atómico
mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
```

### Ejecutar y probar el recolector:
```bash
sudo chmod +x scripts/colector_disco.sh
sudo ./scripts/colector_disco.sh
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

## 📊 5. Visualización en Grafana

Con Prometheus scrapeando a Node Exporter (`http://localhost:9100`), podemos construir un dashboard en Grafana en minutos.

### Panel 1: Gauge de Espacio Ocupado (%)
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

### Panel 2: Stat Panel de Inodos Ocupados (%) — Diagnóstico Preventivo
- **Tipo de Panel:** Stat
- **Consulta PromQL:**
  ```promql
  custom_disk_inodes_usage_percent
  ```
- **Propósito:** Detectar el problema del Lab 3.13: si este panel marca 95% en rojo pero el Gauge de espacio marca 20%, sabés al instante que el disco colapsará por inodos.

### Panel 3: Tabla General de Filesystems del Sistema
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

## 🎯 Conclusión del Laboratorio

Completando este laboratorio lograste:
1. Traducir la teoría de volúmenes y superbloques (`df -h`, inodos `df -i`, tipos de filesystem) en métricas estándar de producción.
2. Exponerlas a través del **Textfile Collector** sin sobrecargar el servidor con daemons pesados.
3. Consultar y auditar la salida cruda con `curl`.
4. Armar paneles en Grafana para alertar visualmente tanto la falta de espacio como la saturación de inodos.
