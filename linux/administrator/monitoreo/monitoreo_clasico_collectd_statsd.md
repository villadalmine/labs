---
id: lab-3.6.4-monitoreo-clasico-collectd-statsd
title: 'Monitoreo Clásico y Embebido en Linux: Daemons en C (collectd), UDP Push (StatsD)
  y Métricas por Terminal'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.6'
sections:
- '3.6'
- '3'
category: observability
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- observability
- monitoring
- monitoreo-clasico
- collectd
- statsd
- udp
- rrdtool
- cli
- embedded
- csv-metrics
- dstat
- sysadmin
tools:
- nc
- python3
- curl
- bash
- collectd
- dstat
- vmstat
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Rocky Linux 10.2
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-31'
  notes: Laboratorio probado con daemon UDP StatsD, colector CSV estilo collectd y
    script interactivo demo_monitoreo_clasico.sh.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-31'
  notes: Validación de telemetría UDP StatsD y compatibilidad con scripts de terminal.
environments:
- WSL2
- AWS EC2
- Bare Metal
operating_systems:
- Ubuntu 24.04 LTS
- Rocky Linux 10.2
- Debian 12
status: PASSED
rag_summary: Guía práctica y teórica sobre la arquitectura de monitoreo clásico y
  embebido de la "vieja escuela" en Linux (década de 2000 a 2015), previa a la era
  de Prometheus y los contenedores. Analiza en profundidad el daemon en C collectd
  (recolección periódica de bajo impacto hacia bases RRDtool y archivos CSV), el protocolo
  StatsD creado por Etsy (transmisión no bloqueante de contadores, medidores y temporizadores
  por UDP mediante fire-and-forget), y las herramientas de diagnóstico en tiempo real
  nativas de terminal (vmstat, dstat, iostat). Compara la estructura jerárquica de
  métricas con puntos frente a los modelos dimensionales modernos por etiquetas, analizando
  los trade-offs de pérdida de paquetes, resolución fija y consumo de recursos en
  hardware embebido.
files:
  guide: monitoreo/monitoreo_clasico_collectd_statsd.md
  script: monitoreo/demo_monitoreo_clasico.sh
  terraform: null
prerequisites:
- lab-3.1-anatomia-filesystems
next_recommended_labs:
- lab-3.6-monitoreo-metricas
- lab-3.6.0-monitoreo-arquitecturas-comparativa
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Monitoreo Clásico y Embebido en Linux: Daemons en C (collectd), UDP Push (StatsD) y Métricas por Terminal

> *"Antes de la llegada de Prometheus, Grafana y los contenedores efímeros, la infraestructura se administraba con daemons ultraligeros en C, sockets UDP no bloqueantes y volcados periódicos a bases de datos circulares RRD."*

Para comprender a fondo la observabilidad contemporánea, todo administrador de sistemas Linux debe conocer las tecnologías que forjaron la disciplina entre los años 2000 y 2015. En servidores con hardware modesto, routers de red, dispositivos embebidos o sistemas monolíticos masivos, levantar un servidor web HTTP o un motor de indexación pesado no era una opción viable.

En esta guía analizaremos los tres pilares del monitoreo de la **"vieja escuela"**:
1. **`collectd`**: El estándar de facto de daemons de sistema en lenguaje C puro.
2. **`StatsD`**: El protocolo de telemetría de aplicación sobre UDP basado en el principio *Fire-and-Forget*.
3. **Herramientas de diagnóstico embebido por consola**: Inspección directa de kernel mediante `vmstat`, `dstat` y sockets locales.

---

## 🧭 1. La Filosofía del Monitoreo Clásico

```
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                              PARADIGMA VIEJA ESCUELA vs PARADIGMA MODERNO                         │
│                                                                                                   │
│  VIEJA ESCUELA (collectd / StatsD / RRDtool)     MODERNO (Prometheus / OpenMetrics / TSDB)       │
│  - Formato jerárquico por puntos:                 - Formato multidimensional por etiquetas:       │
│    `servers.web01.cpu.idle`                         `node_cpu_seconds_total{mode="idle"}`         │
│  - Transporte: UDP Fire-and-Forget o C local      - Transporte: HTTP GET Scraping (PULL)          │
│  - Almacenamiento: Archivos circulares de         - Almacenamiento: Bloques comprimidos (Gorilla) │
│    tamaño fijo en disco (RRDtool / CSV)             con retención flexible                        │
│  - Huella de memoria: < 10 MB RAM                 - Huella de memoria: 500 MB - 4 GB RAM          │
│  - Orientado a: Servidores estáticos (Pets)       - Orientado a: Cargas dinámicas (Cattle/Cloud)  │
+───────────────────────────────────────────────────────────────────────────────────────────────────+
```

---

## ⚙️ 2. El Daemon `collectd`: Arquitectura en C y Plugins

Desarrollado en 2005 por Florian Forster, **`collectd`** es un demonio escrito en C que recolecta estadísticas periódicamente cada `interval` (por defecto 10s) con un consumo de CPU inferior al 0.5% y menos de 10 MB de RAM.

```
                  ARQUITECTURA DE PLUGINS DE COLLECTD
  ┌─────────────────────────────────────────────────────────────────────┐
  │                           COLLECTD CORE                             │
  │                                                                     │
  │   PLUGINS DE ENTRADA (READ)            PLUGINS DE SALIDA (WRITE)    │
  │   - cpu (procfs /proc/stat)     ──►    - csv (/var/log/collectd/csv)│
  │   - memory (/proc/meminfo)      ──►    - rrdtool (/var/lib/collectd)│
  │   - df (statvfs)                ──►    - network (UDP socket binario│
  │   - load (getloadavg)           ──►    - carbon / statsd            │
  └─────────────────────────────────────────────────────────────────────┘
```

### Configuración Típica (`/etc/collectd/collectd.conf`):
```apache
Hostname "servidor-web-01"
Interval 10

LoadPlugin cpu
LoadPlugin memory
LoadPlugin df
LoadPlugin load
LoadPlugin csv

<Plugin csv>
    DataDir "/var/log/collectd/csv"
    StoreRates false
</Plugin>
```

---

## 📡 3. Protocolo StatsD: UDP Fire-and-Forget

Creado por John Goulah y el equipo de ingeniería de **Etsy** en 2008, StatsD resolvió el mayor dilema de los desarrolladores: **¿Cómo registrar métricas de transacciones en una aplicación web de alto tráfico sin ralentizar el servidor?**

Si cada petición HTTP intentaba conectarse a una base de datos o abrir un socket TCP para enviar una métrica, cualquier congestión o caída del servidor de monitoreo bloquearía las peticiones de los usuarios.

### La Solución: UDP no bloqueante
StatsD utiliza **UDP (puerto 8125)**:
* La aplicación envía un paquete UDP y no espera respuesta (*Fire-and-Forget*).
* Si el servidor de monitoreo está caído, el paquete simplemente se descarta a nivel de red sin impactar a la aplicación.

```
       [ APLICACIÓN WEB ]
               │
               ▼ (UDP 8125 - Fire & Forget)
   "web.login.clicks:1|c"  ──► [ Servidor StatsD ]
   "api.latency:42.5|ms"   ──► (Agrega en RAM durante 10s)
   "users.online:150|g"    ──►         │
                                       ▼ (Volcado agrupado)
                               [ Almacenamiento CSV / RRD ]
```

### La Sintaxis del Protocolo StatsD:
```text
<nombre_métrica>:<valor>|<tipo>

1. CONTADOR (Counter - 'c'):
   cart.item_added:1|c
   auth.login_failures:5|c

2. MEDIDOR (Gauge - 'g'):
   mysql.active_threads:32|g
   disk.temperature:48|g

3. TEMPORIZADOR (Timer - 'ms'):
   db.query_execution_time:18.4|ms
```

---

## 💻 4. Diagnóstico Embebido por Terminal: `vmstat`, `iostat` y `dstat`

Antes de los dashboards gráficos en navegador, los administradores de sistemas diagnosticaban contenciones de hardware directamente por consola:

### A. `vmstat` (Virtual Memory Statistics)
```bash
# Monitorear cada 1 segundo durante 5 muestras
vmstat 1 5
```
* **Columnas críticas:**
  * `r`: Procesos en cola de ejecución (*run queue*). Si $r > \text{núcleos CPU}$, hay saturación.
  * `b`: Procesos bloqueados en I/O (*uninterruptible sleep*).
  * `si` / `so`: Páginas leídas o escritas hacia el área de Swap. Si `so > 0`, la RAM física se agotó.

### B. `iostat` (Estadísticas de Discos y Particiones)
```bash
# Mostrar uso de disco y tasa de transferencia
iostat -xz 1 3
```
* `%util`: Porcentaje de tiempo que el disco físico estuvo atendiendo peticiones. Si alcanza el 100%, el almacenamiento es el cuello de botella absoluto del sistema.

---

## 🧪 5. Laboratorio Práctico: Despliegue de Monitoreo Clásico

El repositorio incluye un daemon embebido de monitoreo clásico [`statsd_collectd_mini.py`](scripts/statsd_collectd_mini.py) y un script automatizado [`demo_monitoreo_clasico.sh`](demo_monitoreo_clasico.sh).

### Paso 1: Ejecutar la Demostración Automatizada
```bash
# Otorgar permisos y ejecutar
chmod +x linux/administrator/monitoreo/demo_monitoreo_clasico.sh
chmod +x linux/administrator/monitoreo/limpiar_monitoreo_clasico.sh

./linux/administrator/monitoreo/demo_monitoreo_clasico.sh
```

---

### Paso 2: Envío Manual de Métricas por Socket UDP desde Bash
Podés interactuar directamente con el daemon de StatsD enviando paquetes UDP con `nc` (netcat) o usando el pseudo-dispositivo `/dev/udp/` nativo de Bash:

```bash
# 1. Enviar un contador de visitas
echo -n "pagina.visitas:1|c" | nc -u -w1 127.0.0.1 8125

# 2. Enviar un indicador de conexiones activas
echo -n "clientes.conectados:75|g" | nc -u -w1 127.0.0.1 8125

# 3. Enviar una métrica de tiempo de respuesta
echo -n "backend.latencia_ms:38.2|ms" | nc -u -w1 127.0.0.1 8125
```

---

### Paso 3: Inspeccionar los Archivos CSV Estilo collectd
El daemon muestrea periódicamente la carga del sistema y las métricas acumuladas, persistiendo registros en formato CSV:

```bash
tail -n 15 /tmp/classic_monitoring/csv/system_metrics.csv
```

*Ejemplo de salida:*
```csv
epoch,metric_type,instance,value
1730339200,load,1min,0.45
1730339200,load,5min,0.52
1730339200,load,15min,0.48
1730339200,counter,pagina.visitas,2.00
1730339200,gauge,clientes.conectados,75.00
```

---

## 🧹 6. Saneamiento del Laboratorio
Para detener el daemon en segundo plano y purgar los archivos temporales:

```bash
./linux/administrator/monitoreo/limpiar_monitoreo_clasico.sh
```

---

## ⚖️ 7. ¿Por qué la Industria Migró a Prometheus?

| Limitación del Monitoreo Clásico | Solución Moderna en Prometheus / OpenMetrics |
| :--- | :--- |
| **Explosión de Nombres Jerárquicos:** `servidor.us-east.web01.cpu.idle` exigía expresiones rígidas con comodines (`*`). | **Modelo Dimensional:** Etiquetas clave-valor ortogonales (`cpu{host="web01", dc="us-east"}`). |
| **Pérdida Silenciosa de Paquetes en UDP:** Si la red se congestionaba, los contadores perdían incrementos sin aviso. | **PULL sobre HTTP con reintentos:** Scrapes confiables con control de cadencia. |
| **Resolución Fija RRDtool:** Promediar valores antiguos (*downsampling*) borraba permanentemente los picos de latencia. | **Compresión TSDB Gorilla:** Conservación de muestras precisas con compresión de 1-2 bytes por punto. |
