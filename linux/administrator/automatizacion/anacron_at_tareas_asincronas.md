---
id: lab-2.5-anacron-at-tareas-asincronas
title: 'Planificación en Sistemas Intermitentes y Ejecución Efímera: Anacron (/etc/anacrontab)
  y el Comando at (atq, atrm, batch)'
difficulty_level: 2
difficulty_label: 'Nivel 2: Supervisión & Gobernanza Moderna (Systemd & Automatización)'
section: '2.5'
sections:
- '2.5'
- '2'
category: systemd
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- systemd
- automatizacion
- planificacion
- anacron
- anacrontab
- at
- atd
- atq
- atrm
- batch
- laptops
- sistemas-intermitentes
tools:
- anacron
- at
- atq
- atrm
- batch
- date
- cat
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-automatizacion-systemd (Fedora 41 + systemd 256)
  os: Fedora Linux 41 (Container Image)
  kernel: 6.19.6-200.fc43.x86_64
  status: PASSED
  test_date: '2026-11-06'
  notes: Ejecutado en vivo con demo_anacron_at.sh contra atd.service activo (at 3.2.5)
    y cronie-anacron (1.7.2), verificando recuperación de spool YYYYMMDD y colas at/atq/atrm.
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Rocky Linux 10.2
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-11-06'
  notes: Validación completa con demo_anacron_at.sh cubriendo /etc/anacrontab, /var/spool/anacron,
    recuperación de tareas perdidas y encolado efímero con at/atq/atrm.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-06'
  notes: Ejecución verificada con paquetes anacron y at en instancias cloud y workstations.
environments:
- WSL2
- AWS EC2
- Bare-Metal
operating_systems:
- Ubuntu 24.04 LTS
- Rocky Linux 10.2
- Debian 12
status: PASSED
rag_summary: Laboratorio práctico e interactivo sobre expansión del ecosistema de
  planificación en Linux mediante Anacron y el comando at. Explica por qué cron pierde
  irrecuperablemente las tareas cuando un equipo (laptop, desktop o VM de desarrollo)
  está apagado a la hora programada, y cómo Anacron resuelve este problema verificando
  sellos de fecha (YYYYMMDD) en /var/spool/anacron/ y aplicando retardos escalonados
  (delay) definidos en /etc/anacrontab (period, delay, job-identifier, command) junto
  con START_HOURS_RANGE y RANDOM_DELAY. Además, aborda la ejecución efímera de tareas
  únicas con el demonio atd y los comandos at, atq, atrm y batch, demostrando cómo
  at captura el entorno del usuario y evita dejar código residual en crontab.
files:
  guide: automatizacion/anacron_at_tareas_asincronas.md
  script: automatizacion/demo_anacron_at.sh
  terraform: null
prerequisites:
- lab-2.0-automatizacion-arquitecturas-comparativa
- lab-2.4-cron-crontab-planificacion
next_recommended_labs:
- lab-2.6-systemd-timers-vs-cron-chrony
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Sistemas Intermitentes (`Anacron`) y Ejecución Efímera (`at` / `batch`)

> **Dificultad:** Intermedio (Nivel 2) | **Tiempo estimado:** 35 minutos | **Ambiente:** Terminal Linux, Workstation, Laptop o WSL2

El servicio `cron` clásico fue concebido en 1979 bajo una premisa estricta: **el servidor permanece encendido las 24 horas de los 365 días del año** y las tareas programadas deben repetirse indefinidamente.

Sin embargo, en la vida real nos enfrentamos a dos escenarios donde `cron` fracasa o resulta contraproducente:
1. **Equipos Intermitentes (Laptops, Workstations, VMs bajo demanda):** Si programás un mantenimiento en `cron` a las `04:00 AM` y la máquina está apagada o suspendida a esa hora, **la tarea se pierde irrecuperablemente**. Aquí entra en acción **`Anacron`**.
2. **Tareas de Ejecución Única (*Ad-Hoc / One-Shot*):** Si necesitás reiniciar un servicio o correr una migración pesada **una sola vez** mañana a las `02:00 AM`, usar `crontab` es ineficiente y peligroso porque deja código residual que volverá a dispararse en el futuro si olvidás borrarlo. Aquí entra en acción **`at`**.

---

## ⚡ 1. Cuadro Comparativo Rápido: `Cron` vs `Anacron` vs `at`

| Característica | `Cron` (`crontab`) | `Anacron` (`/etc/anacrontab`) | `at` (`atd` / `batch`) |
| :--- | :--- | :--- | :--- |
| **¿Qué pregunta evalúa?** | *"¿Es exactamente la hora y minuto programados?"* | *"¿Han pasado X días desde la última vez que corrí esta tarea?"* | *"¿Llegó el momento único en el que debo ejecutar y borrar esta orden?"* |
| **Si el equipo estaba apagado...** | ❌ La tarea se pierde hasta el siguiente ciclo. | ✅ La lanza minutos después del próximo encendido. | ✅ La ejecuta al iniciar el demonio `atd` si la hora ya pasó. |
| **Unidad mínima de tiempo** | **1 Minuto** | **1 Día** (`1`, `7`, `30`, `@monthly`) | **1 Minuto** (pero se ejecuta una sola vez) |
| **Persistencia de estado** | Ninguna (solo mira el reloj actual). | Archivos `YYYYMMDD` en `/var/spool/anacron/`. | Scripts temporales en `/var/spool/cron/atjobs/` o `/var/spool/at/`. |
| **Entorno de variables** | Minimalista (`/usr/bin:/bin`). | Definido en `/etc/anacrontab`. | **Clona todo el entorno actual (`env`) y `$PWD` del usuario.** |

---

## 💻 2. Parte A: `Anacron` para Sistemas Intermitentes

### 2.1 ¿Cómo funciona internamente `Anacron`?
A diferencia de `cron`, `anacron` no es un demonio que quede despierto minuto a minuto esperando una hora exacta. Cuando el sistema operativo arranca (o cuando es invocado por un timer/hook de energía), `anacron` lee `/etc/anacrontab` y para cada tarea realiza tres pasos:
1. Busca el archivo de marca de tiempo en **`/var/spool/anacron/<identificador_tarea>`** (que contiene una fecha de 8 dígitos como `20261101`).
2. Compara esa fecha con el día de hoy. Si la diferencia es mayor o igual al **período en días (`period`)**, determina que la tarea está vencida.
3. Espera los minutos indicados en la columna **`delay`** (más un margen aleatorio opcional `RANDOM_DELAY`) para no congelar el disco recién encendido el equipo, ejecuta el comando y actualiza el archivo en `/var/spool/anacron/` con la fecha del día actual.

### 2.2 Anatomía de `/etc/anacrontab`

```bash
# cat /etc/anacrontab
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
# Retraso aleatorio adicional de hasta 45 minutos sumado al delay base:
RANDOM_DELAY=45
# Rango horario permitido de ejecución (ej. de 03:00 a 22:00 hs):
START_HOURS_RANGE=3-22

# Formato de las 4 columnas:
# period(días)   delay(min)   job-identifier      command
1                5            cron.daily          nice run-parts --report /etc/cron.daily
7                10           cron.weekly         nice run-parts --report /etc/cron.weekly
@monthly         15           cron.monthly        nice run-parts --report /etc/cron.monthly
```

#### Desglose de las 4 columnas obligatorias:
1. **`period` (Frecuencia en días):** Cada cuántos días debe ejecutarse la tarea (`1` = diario, `7` = semanal, `30` o `@monthly` = mensual).
2. **`delay` (Retardo en minutos):** Cuántos minutos debe esperar `anacron` después de ser invocado antes de disparar el comando. Evita que `cron.daily`, `cron.weekly` y `cron.monthly` arranquen exactamente en el mismo segundo tras encender la laptop.
3. **`job-identifier` (Identificador único):** Nombre del archivo que se creará dentro de `/var/spool/anacron/` para registrar la fecha `YYYYMMDD` de la última ejecución exitosa.
4. **`command` (Comando a ejecutar):** La orden o script que se correrá como `root`.

### 2.3 Práctica Forense: Simulando una Tarea Perdida durante un Apagado

```bash
# 1. Crear una configuración de prueba de Anacron y su directorio de spool:
export LAB_ANA="/tmp/lab_anacron"
mkdir -p "${LAB_ANA}/spool" "${LAB_ANA}/logs"

cat << 'EOF' > "${LAB_ANA}/anacrontab_test"
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# period  delay  job-identifier       command
1         0      backup_workstation   echo "[$(date '+%F %T')] Backup recuperado tras encendido" >> /tmp/lab_anacron/logs/anacron.log
EOF

# 2. Simular que la última vez que se encendió la laptop fue hace 5 días:
FECHA_VIEJA=$(date -d "5 days ago" '+%Y%m%d')
echo "$FECHA_VIEJA" > "${LAB_ANA}/spool/backup_workstation"
echo "Sello de tiempo antiguo en spool: $(cat ${LAB_ANA}/spool/backup_workstation)"

# 3. Validar la sintaxis del archivo anacrontab (-T):
anacron -T -t "${LAB_ANA}/anacrontab_test"

# 4. Ejecutar anacron ahora (-n = now, sin esperar el delay) apuntando a nuestra configuración:
anacron -t "${LAB_ANA}/anacrontab_test" -S "${LAB_ANA}/spool" -n

# 5. Comprobar que la tarea se ejecutó y el sello de fecha se actualizó a HOY:
cat "${LAB_ANA}/logs/anacron.log"
echo "Nuevo sello de tiempo en spool (HOY): $(cat ${LAB_ANA}/spool/backup_workstation)"
```

---

## ⏳ 3. Parte B: El Comando `at` y Ejecución Efímera

### 3.1 ¿Cómo funciona el ecosistema `at` (`atd`, `atq`, `atrm`, `batch`)?
El paquete `at` está gobernado por el demonio ligero `atd.service`. En lugar de editar tablas permanentes, el usuario le entrega un comando por tubería (`pipe`) o consola interactiva indicando cuándo debe ejecutarse:

```bash
# Ejemplo clásico del temario: programar un reinicio único mañana a las 2:00 AM
echo "reboot" | at 2:00 AM tomorrow
```

#### Comandos principales de la suite `at`:
| Comando | Equivalente | Función Operativa |
| :--- | :--- | :--- |
| **`at <tiempo>`** | — | Encola un nuevo trabajo único para el horario o fecha especificados. |
| **`atq`** | `at -l` | **Lista la cola (*queue*)** de trabajos pendientes del usuario (muestra ID del job, fecha, hora, cola `a` y propietario). |
| **`at -c <job_id>`** | — | **Inspección forense:** Muestra el script completo generado por `at`, incluyendo todas las variables de entorno capturadas y el `cd` al directorio donde estabas parado. |
| **`atrm <job_id>`** | `at -r <job_id>` | **Cancela y elimina** inmediatamente el trabajo pendiente antes de que se ejecute. |
| **`batch`** | `at -q b` | Encola una tarea pesada que **solo se ejecutará cuando el promedio de carga del sistema (`load average`) baje de `1.5`**. |

### 3.2 Sintaxis Amigable de Tiempo en `at`
`at` incluye un analizador de lenguaje natural sumamente flexible:
- **Relativos al momento actual:** `at now + 5 minutes`, `at now + 2 hours`, `at now + 3 days`, `at now + 1 week`.
- **Horas exactas y palabras clave:** `at 14:30`, `at 2:00 AM tomorrow`, `at midnight`, `at noon` (12:00 PM), `at teatime` (16:00 PM).
- **Fechas específicas:** `at 03:00 2026-12-31`, `at 9am Fri`, `at 10:00 Jul 25`.

### 3.3 Práctica Paso a Paso con `at`, `atq`, `at -c` y `atrm`

```bash
# 1. Asegurar que el demonio atd esté activo:
sudo systemctl enable --now atd.service

# 2. Encolar una tarea efímera para mañana a las 02:00 AM:
echo "/usr/local/bin/mantenimiento_unico.sh" | at 2:00 AM tomorrow

# 3. Encolar una segunda tarea para dentro de 10 minutos:
echo "echo ' Auditoria ad-hoc completada' > /tmp/auditoria_at.txt" | at now + 10 minutes

# 4. Consultar la cola de tareas pendientes con atq:
atq

# 5. Inspeccionar el interior del primer trabajo encolado (variables de entorno y directorio):
JOB_ID=$(atq | head -n 1 | awk '{print $1}')
at -c "$JOB_ID" | tail -n 20

# 6. Cancelar y purgar los trabajos de prueba con atrm:
for id in $(atq | awk '{print $1}'); do
    atrm "$id"
done
atq
```

> [!TIP]
> **Control de acceso en `at`:**
> Al igual que `cron`, el acceso a `at` se gobierna mediante **`/etc/at.allow`** y **`/etc/at.deny`**. Por defecto en la mayoría de las distribuciones existe únicamente `/etc/at.deny` (que bloquea cuentas de sistema como `www-data` o `nobody`). Si creás `/etc/at.allow`, solo los usuarios listados allí podrán encolar trabajos.

---

## 🎯 4. Retos de Autoevaluación ("Ponte a Prueba")

<details>
<summary><b>1. ¿Por qué <code>anacron</code> no sirve para programar una tarea que deba ejecutarse cada 15 minutos?</b></summary>
<br>
<b>Respuesta:</b> Porque la granularidad mínima de diseño de <code>anacron</code> es de <b>1 día</b> (almacena únicamente la fecha en formato <code>YYYYMMDD</code> sin horas ni minutos en <code>/var/spool/anacron/</code>). Para intervalos en minutos u horas se debe usar <code>cron</code> o un <code>Systemd Timer</code>.
</details>

<details>
<summary><b>2. Si en <code>/etc/anacrontab</code> ves la línea <code>7 10 cron.weekly nice run-parts /etc/cron.weekly</code>, ¿qué significan el <code>7</code> y el <code>10</code>?</b></summary>
<br>
<b>Respuesta:</b> El <code>7</code> es el <b>período en días</b> (la tarea debe ejecutarse una vez cada 7 días). El <code>10</code> es el <b>retardo (delay) en minutos</b> que <code>anacron</code> esperará después de iniciarse antes de lanzar el comando, evitando saturar la CPU y el disco simultáneamente con las tareas diarias durante el arranque.
</details>

<details>
<summary><b>3. ¿Qué ventaja ofrece el comando <code>at</code> frente a <code>crontab</code> respecto a las variables de entorno del usuario?</b></summary>
<br>
<b>Respuesta:</b> Mientras que <code>cron</code> ejecuta las tareas en un entorno vacío con un <code>PATH</code> mínimo, el comando <code>at</code> <b>captura y clona automáticamente todas las variables de entorno actuales de tu terminal</b>, tu <code>umask</code> y tu directorio de trabajo actual (<code>$PWD</code>), restaurándolos cuando llega el momento de ejecutar la tarea.
</details>

<details>
<summary><b>4. ¿Qué comando te permite ver qué trabajos están encolados en <code>at</code> y qué comando permite cancelar el trabajo número 4?</b></summary>
<br>
<b>Respuesta:</b> <code>atq</code> (o <code>at -l</code>) lista los trabajos pendientes en la cola, y <code>atrm 4</code> (o <code>at -r 4</code>) elimina el trabajo número 4 antes de su ejecución.
</details>

---

## 🛠️ 5. Demostración Interactiva y Limpieza

Ejecutá el script interactivo para experimentar en vivo con `anacron`, la recuperación de sellos de tiempo en `/var/spool/anacron` y las colas de `at`:

```bash
cd linux/administrator/automatizacion

# Ejecutar demostración interactiva:
sudo ./demo_anacron_at.sh

# O en modo automático:
sudo ./demo_anacron_at.sh --auto 2

# Limpiar recursos temporales:
sudo ./limpiar_anacron_at.sh
```
