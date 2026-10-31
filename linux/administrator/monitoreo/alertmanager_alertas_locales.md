---
id: lab-3.15-alertmanager-alertas-locales
title: Gestión y Disparo de Alertas con Prometheus y Alertmanager (Receptor Local
  en Terminal sin Dependencias Externas)
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.15'
sections:
- '3.15'
- '3'
category: observability
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- observability
- prometheus
- alertmanager
- alertas
- webhook
- inodos
- disk-space
- incident-response
tools:
- alertmanager
- prometheus
- python3
- curl
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
  notes: Probado de punta a punta con webhook_receiver.py, Alertmanager v0.27 y Prometheus
    v2.54. Soporta ejecución con binarios independientes en /tmp o servicios nativos
    instalados vía APT en Ubuntu/Debian.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Compatible en instancias EC2 sin requerir apertura de puertos de correo (puerto
    25/587 bloqueado por proveedores de nube).
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio de configuración y disparo de alertas con Prometheus Alertmanager
  diseñado para entornos de práctica y estudio sin dependencias externas como SMTP
  o tokens de Slack. Permite usar tanto servicios instalados vía APT como binarios
  portables, implementa un receptor webhook local ultraliviano en Python estándar
  que imprime alertas formateadas en consola, define reglas de alerta para saturación
  de espacio e inodos, simula un incidente de almacenamiento en caliente y explica
  la transición de estados (Inactive, Pending, Firing, Resolved) y la migración a
  canales productivos.
files:
  guide: monitoreo/alertmanager_alertas_locales.md
  script: monitoreo/scripts/webhook_receiver.py
  terraform: null
prerequisites:
- lab-3.6-monitoreo-metricas
- lab-3.14-monitoreo-disco-custom
next_recommended_labs:
- lab-3.16-integrador-web-lvm-raid-monitoreo
- integrador-4.5-raid-metrics-prometheus
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Prometheus Alertmanager (Alertas Locales en Terminal sin Email ni Slack)

Uno de los mayores dolores de cabeza al estudiar o probar **Alertmanager** por primera vez es la configuración de canales de notificación externos:
- Configurar servidores de correo **SMTP** requiere contraseñas de aplicación (App Passwords en Google/Outlook), lidiar con autenticación en dos pasos (2FA), o enfrentarse a puertos de correo bloqueados por defecto en proveedores como AWS o DigitalOcean.
- Crear webhooks en **Slack, Discord o Microsoft Teams** exige registrar una cuenta, crear un espacio de trabajo, generar un Webhook URL y tener salida directa a Internet.

Este laboratorio enseña cómo funciona la arquitectura de alertas de **Prometheus + Alertmanager** de forma **100% local, inmediata y sin configuraciones engorrosas**, utilizando dos mecanismos accesibles:
1. **La interfaz web integrada de Alertmanager (`:9093`)** y de Prometheus (`:9090/alerts`).
2. **Un receptor webhook local ultraliviano en Python** que imprime las alertas en tiempo real en tu propia terminal con colores y formato legible.

Además, conecta con los incidentes de almacenamiento vistos en **[Mantenimiento de Volúmenes (Lab 3.13)](../filesystems/mantenimiento_volumenes.md)**: inyectaremos una falla de **inodos agotados con disco al 90% libre**, veremos a Alertmanager disparar la alerta y verificaremos la autorresolución (`resolved`) al liberar los archivos.

---

> [!TIP]
> ### 💡 Reutilización del Entorno de Laboratorios Anteriores
> - Si ya completaste el **Lab 3.6** o el **Lab 3.14**, tu agente **Node Exporter** ya está ejecutándose en el puerto `:9100` y emitiendo las métricas de disco (`custom_disk_inodes_usage_percent` y `custom_disk_usage_percent`).
> - No necesitás volver a instalar ni configurar Node Exporter.
> - Podés elegir entre ejecutar Prometheus y Alertmanager con los **binarios en `/tmp`** (rápido, sin instalar nada permanente) o mediante **paquetes APT** (`apt install prometheus prometheus-alertmanager`).

---

## 🏗️ 1. Arquitectura del Flujo de Alertas

```
+───────────────────────────────────────────────────────────────────────────────────────────+
| 1. GENERADOR DE MÉTRICAS (Host Monitoreado)                                               |
|    Node Exporter (:9100) ◄── Textfile Collector (colector_disco.sh)                       |
|    Métricas: custom_disk_usage_percent, custom_disk_inodes_usage_percent                   |
+───────────────────────────────────────────────────────────────────────────────────────────+
                                    │
                                    ▼ [ Scraping HTTP cada 5 segundos ]
+───────────────────────────────────────────────────────────────────────────────────────────+
| 2. MOTOR DE EVALUACIÓN (Prometheus en :9090)                                              |
|    Evalúa periódicamente 'alert_rules.yml':                                               |
|      custom_disk_inodes_usage_percent > 80%                                               |
|                                                                                           |
|    Estados de la Regla:                                                                   |
|      [ INACTIVE ] ──(Condición cumplida)──► [ PENDING (15s) ] ──(Persiste)──► [ FIRING ]   |
+───────────────────────────────────────────────────────────────────────────────────────────+
                                    │
                                    ▼ [ HTTP POST /api/v2/alerts ]
+───────────────────────────────────────────────────────────────────────────────────────────+
| 3. GESTOR DE ENRUTAMIENTO (Alertmanager en :9093)                                         |
|    - Agrupa alertas similares (group_by: ['alertname', 'mountpoint'])                     |
|    - Espera para evitar ráfagas (group_wait: 10s)                                         |
|    - Enruta la notificación al receptor configurado                                       |
|    - Permite inspección visual en UI: http://localhost:9093/#/alerts                      |
+───────────────────────────────────────────────────────────────────────────────────────────+
                                    │
                                    ▼ [ HTTP POST JSON ]
+───────────────────────────────────────────────────────────────────────────────────────────+
| 4. RECEPTOR LOCAL DIDÁCTICO (Python Webhook en :9999)                                     |
|    webhook_receiver.py escucha peticiones locales y muestra en tu consola:                |
|                                                                                           |
|    🚨 [ALERTA DISPARADA] 2026-10-24 15:30:10                                             |
|    Alerta: DiscoInodosAgotados | Severidad: CRITICAL                                       |
|    Montaje: /mnt/test_alerta (ext4 en /dev/loop5)                                         |
|    Detalle: El 95% de los inodos están ocupados.                                          |
+───────────────────────────────────────────────────────────────────────────────────────────+
```

---

## 🛠️ 2. Componentes del Laboratorio

Todos los archivos ya están listos en tu repositorio:

1. **Receptor Webhook Local:** [`scripts/webhook_receiver.py`](scripts/webhook_receiver.py)
   - Micro-servidor HTTP en Python estándar (sin `pip install`, sin Flask).
   - Recibe el JSON de Alertmanager y lo formatea con colores en terminal.
2. **Reglas de Alerta de Almacenamiento:** [`alert_rules.yml`](alert_rules.yml)
   - Alerta `DiscoEspacioCritico`: se dispara si el espacio supera el 85%.
   - Alerta `DiscoInodosAgotados`: se dispara si los inodos superan el 80% (falla del Lab 3.13).
3. **Configuración de Alertmanager:** [`alertmanager.yml`](alertmanager.yml)
   - Apunta a `http://127.0.0.1:9999/alert` con `send_resolved: true`.

---

## 🚀 3. Paso a Paso: Despliegue y Simulación

### Paso 1: Iniciar el Receptor Webhook en Terminal 1
Abrí una terminal (o panel de `tmux` según el Lab 1.1) y ejecutá el receptor:

```bash
cd linux/administrator/monitoreo
python3 scripts/webhook_receiver.py 9999
```

**Salida en pantalla:**
```
===============================================================================
 🔔 RECEPTOR DE ALERTAS DE ALERTMANAGER ACTIVO EN PUERTO 9999
===============================================================================
 • Escuchando en: http://127.0.0.1:9999/alert
 • Esperando alertas de Prometheus Alertmanager...
 • Presiona Ctrl+C para detener.
```

Dejá esa terminal visible para observar la llegada de notificaciones.

---

### Paso 2: Iniciar Alertmanager en Terminal 2

Podés elegir entre dos métodos:

#### Opción A: Binario Portable en `/tmp` (Recomendada para pruebas rápidas)
```bash
VER_AM="0.27.0"
if [ ! -f "/tmp/alertmanager" ]; then
    curl -sL "https://github.com/prometheus/alertmanager/releases/download/v${VER_AM}/alertmanager-${VER_AM}.linux-amd64.tar.gz" | tar -xz -C /tmp/
    mv /tmp/alertmanager-${VER_AM}.linux-amd64/alertmanager /tmp/alertmanager
fi

/tmp/alertmanager --config.file=alertmanager.yml --web.listen-address="0.0.0.0:9093"
```

#### Opción B: Si usás APT (`sudo apt install prometheus-alertmanager`)
```bash
sudo apt install -y prometheus-alertmanager
sudo cp alertmanager.yml /etc/prometheus/alertmanager.yml
sudo systemctl restart prometheus-alertmanager
```

> [!NOTE]
> Podés abrir `http://localhost:9093` en tu navegador para ver la interfaz gráfica oficial de Alertmanager. En este momento mostrará 0 alertas activas.

---

### Paso 3: Iniciar Prometheus con Soporte de Alertas en Terminal 3

Creamos un archivo mínimo `prometheus.yml` que vincule Node Exporter, las reglas y Alertmanager:

```yaml
global:
  scrape_interval: 5s
  evaluation_interval: 5s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["127.0.0.1:9093"]

scrape_configs:
  - job_name: "node"
    static_configs:
      - targets: ["127.0.0.1:9100"]
```

#### Opción A: Binario Portable en `/tmp`
```bash
VER_PROM="2.54.1"
if [ ! -f "/tmp/prometheus" ]; then
    curl -sL "https://github.com/prometheus/prometheus/releases/download/v${VER_PROM}/prometheus-${VER_PROM}.linux-amd64.tar.gz" | tar -xz -C /tmp/
    mv /tmp/prometheus-${VER_PROM}.linux-amd64/prometheus /tmp/prometheus
fi

/tmp/prometheus --config.file=prometheus.yml --web.listen-address="0.0.0.0:9090"
```

#### Opción B: Si usás APT (`sudo apt install prometheus`)
```bash
sudo apt install -y prometheus
sudo cp alert_rules.yml /etc/prometheus/
# Modificá /etc/prometheus/prometheus.yml para añadir rule_files: ["alert_rules.yml"]
# y alerting targets: ["127.0.0.1:9093"], luego:
sudo systemctl restart prometheus
```

---

## 💥 4. Inyección de la Falla: Agotamiento Real de Inodos

Ahora pondremos a prueba el sistema reproduciendo el escenario exacto de **[mantenimiento_volumenes.md](../filesystems/mantenimiento_volumenes.md)**.

### 4.1 Crear un volumen pequeño en loop:
```bash
sudo mkdir -p /mnt/test_alerta
sudo dd if=/dev/zero of=/tmp/disco_alerta.img bs=1M count=30 status=none
LOOP_DEV=$(sudo losetup -f --show /tmp/disco_alerta.img)

# Formateamos con pocos inodos intencionalmente:
sudo mkfs.ext4 -N 3000 -q "$LOOP_DEV"
sudo mount "$LOOP_DEV" /mnt/test_alerta
```

### 4.2 Saturar los inodos al 90%:
Creamos 2700 archivos vacíos. Ocupan casi 0 MB de almacenamiento físico, pero consumen el 90% de la tabla de inodos:
```bash
echo "Consumiendo inodos..."
sudo bash -c 'for i in $(seq 1 2700); do touch /mnt/test_alerta/archivo_$i; done'
```

Comprobamos el estado con las herramientas de `mantenimiento_volumenes.md`:
```bash
df -h /mnt/test_alerta    # Mostrará casi 95% LIBRE en espacio
df -i /mnt/test_alerta    # Mostrará 90% OCUPADO en inodos!
```

### 4.3 Actualizar las métricas personalizadas:
Ejecutamos el colector de disco del Lab 3.14:
```bash
sudo ./scripts/colector_disco.sh
```

---

## 🔔 5. Observación del Disparo de la Alerta

### En la Web UI de Prometheus (`http://localhost:9090/alerts`):
1. **Segundo 0 a 5:** La regla `DiscoInodosAgotados` pasa al estado amarillo **`PENDING`** (la condición `custom_disk_inodes_usage_percent > 80` es verdadera, pero espera a que persista por `for: 15s`).
2. **Segundo 15:** La regla pasa al estado rojo **`FIRING`** y despacha la alerta inmediatamente a Alertmanager en el puerto 9093.

### En la Terminal del Receptor Local (`webhook_receiver.py`):
Alertmanager agrupa la alerta, espera los `group_wait: 10s` para evitar duplicados y hace el POST hacia nuestro receptor. En tu terminal verás aparecer:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║ 🚨 [ALERTMANAGER NOTIFICACIÓN: DISPARADA / FIRING] — 2026-10-24 15:35:22
╠══════════════════════════════════════════════════════════════════════════════╝
  #1 🔥 Alerta: DiscoInodosAgotados  |  Severidad: CRITICAL
     • Estado:      FIRING
     • Montaje:     /mnt/test_alerta (FS: ext4)
     • Resumen:     Inodos casi agotados en /mnt/test_alerta
     • Detalle:     El sistema de archivos /mnt/test_alerta (ext4 en /dev/loop5) tiene más del 80% de inodos ocupados (actual: 90%). No se podrán crear nuevos archivos a pesar de tener espacio en bloques libre.
     • Iniciada:    2026-10-24T13:35:05.123Z
────────────────────────────────────────────────────────────────────────────────
```

---

## ✅ 6. Resolución del Incidente (Auto-Recovery)

Ahora simulamos la remediación por parte del administrador (como aprendimos en `mantenimiento_volumenes.md` purgando logs o temporales):

```bash
# Eliminamos los 2700 archivos vacíos
sudo rm -f /mnt/test_alerta/archivo_*

# Actualizamos las métricas
sudo ./scripts/colector_disco.sh
```

En cuestión de 10 a 20 segundos:
1. Prometheus detecta que `custom_disk_inodes_usage_percent` cayó a ~0%.
2. La regla vuelve a estado verde **`INACTIVE`**.
3. Alertmanager recibe la resolución y, gracias a `send_resolved: true`, despacha la notificación a nuestro script en terminal:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║ ✅ [ALERTMANAGER NOTIFICACIÓN: RESUELTA / RESOLVED] — 2026-10-24 15:36:10
╠══════════════════════════════════════════════════════════════════════════════╝
  #1 ✔️ Alerta: DiscoInodosAgotados  |  Severidad: CRITICAL
     • Estado:      RESOLVED
     • Montaje:     /mnt/test_alerta (FS: ext4)
     • Resumen:     Inodos casi agotados en /mnt/test_alerta
     • Detalle:     El sistema de archivos /mnt/test_alerta (ext4 en /dev/loop5) tiene más del 80% de inodos ocupados...
────────────────────────────────────────────────────────────────────────────────
```

### Limpieza de los recursos del lab:
```bash
sudo umount /mnt/test_alerta
sudo losetup -d "$LOOP_DEV"
rm -f /tmp/disco_alerta.img
```

---

## 🏢 7. ¿Cómo se configuraría en Producción Real?

Todo lo que probaste en este laboratorio utiliza la misma arquitectura y sintaxis exacta que un entorno corporativo. Para migrar de tu terminal local a producción, **solo se reemplaza la sección `receivers` en `alertmanager.yml`**:

### Caso A: Enviar a Correo Electrónico (SMTP Corporativo)
```yaml
receivers:
  - name: 'equipo-infraestructura'
    email_configs:
      - to: 'sysadmins@miempresa.com'
        from: 'alertas-linux@miempresa.com'
        smarthost: 'smtp.office365.com:587'
        auth_username: 'alertas-linux@miempresa.com'
        auth_password: 'PasswordSegura123!'
        require_tls: true
        send_resolved: true
        headers:
          subject: '🚨 [{{ .Status | toUpper }}] Alerta en {{ .CommonLabels.instance }}'
```

### Caso B: Enviar a Canal de Slack
```yaml
receivers:
  - name: 'canal-slack-ops'
    slack_configs:
      - api_url: 'https://hooks.slack.example.com/services/TU_WEBHOOK_DE_SLACK'
        channel: '#alertas-servidores'
        send_resolved: true
        title: '[{{ .Status | toUpper }}] {{ .CommonAnnotations.summary }}'
        text: '{{ .CommonAnnotations.description }}\n*Severidad:* `{{ .CommonLabels.severity }}`'
```

### Caso C: Enviar a un Bot de Telegram
```yaml
receivers:
  - name: 'telegram-ops'
    webhook_configs:
      - url: 'https://api.telegram.org/bot<TU_TOKEN>/sendMessage?chat_id=<TU_CHAT_ID>&text={{ .CommonAnnotations.description }}'
        send_resolved: true
```

---

## 🎛️ 8. Conceptos Clave de Alertmanager en Empresas

1. **Agrupación (`group_by: ['alertname', 'cluster']`):** Si 20 servidores se quedan sin disco al mismo tiempo, Alertmanager te manda **1 solo mensaje agrupado** en lugar de 20 mensajes individuales consecutivos.
2. **Tiempos de Gracia (`group_wait` y `group_interval`):** Dan margen para que el sistema recopile alertas hermanas antes de despertar a la guardia.
3. **Silenciamiento (*Silences*):** Durante una ventana de mantenimiento planificada (por ejemplo, al redimensionar un disco con LVM como en el Lab 3.2), podés entrar a `http://localhost:9093/#/silences` y silenciar temporalmente las alertas por 2 horas para no generar falsos positivos.
