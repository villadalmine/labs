---
id: lab-2.6-systemd-timers-vs-cron-chrony
title: 'El Estándar Moderno: Systemd Timers vs Cron (.timer + .service), Control Cgroups
  y Sincronización NTP con Chrony'
difficulty_level: 2
difficulty_label: 'Nivel 2: Supervisión & Gobernanza Moderna (Systemd & Automatización)'
section: '2.6'
sections:
- '2.6'
- '2'
category: systemd
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- systemd
- timers
- services
- cron
- anacron
- at
- chrony
- chronyc
- ntp
- timedatectl
- systemd-analyze
- systemd-run
- cgroups
- journalctl
tools:
- systemctl
- systemd-analyze
- systemd-run
- journalctl
- timedatectl
- chronyc
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
  notes: Ejecutado en vivo con demo_systemd_timers_chrony.sh sobre systemd 256.17
    y chrony 4.7, verificando timedatectl, systemd-analyze calendar, unidades .timer/.service
    con Persistent=true, cgroups y systemd-run --on-active.
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Rocky Linux 10.2
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-11-06'
  notes: Validación con demo_systemd_timers_chrony.sh probando auditoría NTP (timedatectl/chronyc),
    systemd-analyze calendar, unidades .timer/.service con Persistent=true y cgroups.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-06'
  notes: Sincronización con Amazon Time Sync Service vía Chrony y ejecución nativa
    de Systemd Timers.
environments:
- WSL2
- AWS EC2
- Bare-Metal
operating_systems:
- Ubuntu 24.04 LTS
- Rocky Linux 10.2
- Debian 12
status: PASSED
rag_summary: 'Laboratorio integrador sobre el estándar moderno de planificación en
  Linux con Systemd Timers y sincronización de reloj con Chrony (NTP). Demuestra en
  la práctica la Regla de Oro del SysAdmin: auditar y sincronizar primero la capa
  base de tiempo con timedatectl y chronyc (tracking, sources, makestep) antes de
  orquestar tareas. Guía paso a paso en la traducción de expresiones crontab hacia
  OnCalendar verificadas con systemd-analyze calendar, el desacoplamiento lógico entre
  mi_tarea.timer (cuándo) y mi_tarea.service (qué), la emulación de Anacron con Persistent=true,
  la emulación de at con systemd-run --on-active, las dependencias condicionales de
  red (After=network-online.target), la contención de recursos con cgroups v2 (CPUQuota,
  MemoryMax) y el monitoreo centralizado en journalctl.'
files:
  guide: automatizacion/systemd_timers_vs_cron_chrony.md
  script: automatizacion/demo_systemd_timers_chrony.sh
  terraform: null
prerequisites:
- lab-2.0-automatizacion-arquitecturas-comparativa
- lab-2.1-systemd-memlogger
- lab-2.4-cron-crontab-planificacion
- lab-2.5-anacron-at-tareas-asincronas
next_recommended_labs:
- lab-3.5-borg-systemd-timers
- lab-3.6-monitoreo-metricas
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: El Estándar Moderno (`Systemd Timers` vs `Cron`) y Sincronización `Chrony (NTP)`

> **Dificultad:** Intermedio-Avanzado (Nivel 2) | **Tiempo estimado:** 40 minutos | **Ambiente:** Terminal Linux, WSL2 con Systemd o AWS EC2

En las distribuciones Linux empresariales actuales (Ubuntu, Debian, RHEL, Rocky Linux, Arch), **Systemd Timers** es la solución predeterminada para automatizar tareas críticas del sistema. En lugar de comprimir toda la configuración en una sola línea de `crontab`, `systemd` aplica un **desacoplamiento lógico** separando la planificación en dos unidades independientes:
1. **`mi_tarea.timer` (Define el CUÁNDO):** Calendarios exactos (`OnCalendar`), timers monotónicos desde el arranque (`OnBootSec`), persistencia tipo Anacron (`Persistent=true`) y dispersión aleatoria (`RandomizedDelaySec`).
2. **`mi_tarea.service` (Define el QUÉ):** Comando a ejecutar (`ExecStart`), usuario, variables de entorno seguras (`EnvironmentFile`), dependencias condicionales (`After=network-online.target`), gobernanza de recursos con **`cgroups v2` (`CPUQuota`, `MemoryMax`)** y registro automático en **`journalctl`**.

Además, como establece la **Regla de Oro del SysAdmin**, antes de programar cualquier arquitectura con `Cron` o `Systemd`, aprenderás a auditar y asegurar la capa base de tiempo exacto mediante **`Chrony (NTP)`** y **`timedatectl`**.

---

## 🕰️ 1. Fase 1: La Regla de Oro — Sincronización de Tiempo con `Chrony (NTP)`

Ningún motor de planificación funcionará en el instante esperado si el reloj del kernel tiene deriva (*clock drift*) o una zona horaria errónea.

### Paso 1: Auditar el Reloj del Sistema y RTC con `timedatectl`
```bash
# Inspeccionar hora local, hora universal (UTC), reloj RTC y estado de sincronización NTP:
timedatectl status
```

Verificá en la salida que **`System clock synchronized: yes`** y **`NTP service: active`** estén activos.

### Paso 2: Auditar el Estrato y Desfase Atómico con `chronyc`
`Chrony` (`chronyd.service`) es el demonio NTP de alta precisión. Podemos interrogarlo en vivo con su herramienta CLI `chronyc`:

```bash
# 1. Ver el estado de sincronización del reloj interno (Reference ID, Stratum, System time offset):
chronyc tracking

# 2. Listar los servidores NTP remotos (fuentes de tiempo) y su estado (* = sincronizado actual):
chronyc sources -v

# 3. (Opcional en emergencias) Forzar corrección inmediata si el reloj estuviera muy desfasado:
sudo chronyc makestep
```

> [!IMPORTANT]
> **¿Qué significa el `Stratum` (Estrato) en `chronyc tracking`?**
> Mide la distancia en saltos de red hasta un reloj atómico o GPS de referencia (`Stratum 0`). Un servidor directamente conectado al reloj atómico es `Stratum 1`; tu servidor en la nube o laptop sincronizando contra ese servidor operará típicamente en **`Stratum 2` o `Stratum 3`** con una precisión de pocos milisegundos o microsegundos.

---

## 🔄 2. Fase 2: Tabla de Traducción Directa `Cron` ➔ `Systemd Timers`

En `Systemd`, las expresiones de calendario (`OnCalendar=`) utilizan el formato:
`DíaDeLaSemana Año-Mes-Día Hora:Minuto:Segundo`

Aquí tenés la tabla de equivalencias exactas respecto a los patrones de `crontab` vistos en clase:

| Patrón Operativo | Sintaxis Clásica `Crontab` | Sintaxis Moderna `Systemd OnCalendar` |
| :--- | :--- | :--- |
| **Diariamente a las 04:00 AM** | `0 4 * * *` | `OnCalendar=*-*-* 04:00:00` |
| **Cada 5 minutos** | `*/5 * * * *` | `OnCalendar=*:0/5:00` |
| **Cada 5 horas (al minuto 0)** | `0 */5 * * *` | `OnCalendar=*-*-* 00/5:00:00` |
| **Rango de 09:00 a 18:00 hs** | `0 9-18 * * *` | `OnCalendar=*-*-* 09..18:00:00` |
| **Día 1 de cada mes a las 05:00 AM** | `0 5 1 * *` | `OnCalendar=*-*-01 05:00:00` |
| **Todos los viernes a medianoche** | `0 0 * * Fri` *(o `5`)* | `OnCalendar=Fri *-*-* 00:00:00` |
| **Solo en Mayo y Octubre** | `0 0 * 5,10 *` | `OnCalendar=*-05,10-* 00:00:00` |
| **Macros `@daily`, `@hourly`, `@yearly`** | `@daily` / `@hourly` / `@yearly` | `OnCalendar=daily` / `hourly` / `yearly` |
| **En el arranque (`@reboot`)** | `@reboot` | `OnBootSec=1min` |
| **Modo Anacron (Si estaba apagado)** | En `/etc/anacrontab` | Directiva **`Persistent=true`** en `[Timer]` |
| **Modo `at` (Ejecución única efímera)** | `echo cmd \| at now + 10m` | `sudo systemd-run --on-active=10m cmd` |

### El Superpoder de Validación: `systemd-analyze calendar`
Con `cron`, si te equivocás en un asterisco no te enterás hasta que la tarea falla a la madrugada. `systemd` incluye un simulador matemático que valida tu expresión y te dice exactamente a qué hora correrán las próximas iteraciones:

```bash
# Probar y simular las próximas 5 ejecuciones de nuestros patrones:
systemd-analyze calendar --iterations=5 "*-*-* 04:00:00"
systemd-analyze calendar --iterations=5 "*:0/5:00"
systemd-analyze calendar --iterations=5 "*-*-* 09..18:00:00"
systemd-analyze calendar --iterations=5 "Fri *-*-* 00:00:00"
systemd-analyze calendar --iterations=5 "*-05,10-* 00:00:00"
```

---

## 🛠️ 3. Fase 3: Migración Real de `Cron` a `Systemd Timers` Desacoplados

Vamos a construir un servicio de mantenimiento empresarial que reemplace simultáneamente a `cron` y `anacron`, incorporando dependencias de red, límites de `cgroups` y logs en `journalctl`.

### Paso 1: Crear el Script de Mantenimiento
```bash
sudo tee /usr/local/bin/lab-mantenimiento-enterprise.sh > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "=== [INICIO] Mantenimiento Automatizado Enterprise ==="
echo "Fecha y Hora UTC : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Espacio en /tmp  : $(df -h /tmp | awk 'NR==2 {print $4 " libres (" $5 " usado)"}')"
echo "Carga del Kernel : $(cat /proc/loadavg)"
echo "=== [FIN] Ejecución completada exitosamente (Status 0) ==="
EOF

sudo chmod +x /usr/local/bin/lab-mantenimiento-enterprise.sh
```

### Paso 2: Crear la Unidad `.service` (Define el QUÉ, Dependencias y Cgroups)
Creamos `/etc/systemd/system/lab-mantenimiento.service`:

```bash
sudo tee /etc/systemd/system/lab-mantenimiento.service > /dev/null << 'EOF'
[Unit]
Description=Servicio de Mantenimiento y Auditoría Enterprise (Lab 2.6)
# Dependencias condicionales: exigir que la red esté activa antes de iniciar
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/lab-mantenimiento-enterprise.sh

# Gobernanza de Recursos con Cgroups v2 y Prioridad I/O
CPUQuota=25%
MemoryMax=128M
Nice=10
IOSchedulingClass=best-effort
EOF
```

### Paso 3: Crear la Unidad `.timer` (Define el CUÁNDO + Comportamiento Anacron)
Creamos `/etc/systemd/system/lab-mantenimiento.timer`:

```bash
sudo tee /etc/systemd/system/lab-mantenimiento.timer > /dev/null << 'EOF'
[Unit]
Description=Temporizador para Mantenimiento Enterprise (Reemplazo de Cron + Anacron)

[Timer]
# Ejecutar cada minuto para demostración en vivo (o *-*-* 03:00:00 en producción)
OnCalendar=*:0/1
# Precisión de disparo de 1 segundo (por defecto systemd agrupa en ventanas de 1 min para ahorrar energía)
AccuracySec=1s
# Comportamiento Anacron: si el equipo estaba apagado, ejecutar al encender
Persistent=true
Unit=lab-mantenimiento.service

[Install]
WantedBy=timers.target
EOF
```

### Paso 4: Probar el Servicio Manualmente y Activar el Timer
Una de las mayores ventajas del desacoplamiento es que podemos probar el `.service` de inmediato antes de habilitar el `.timer`:

```bash
# 1. Recargar el demonio de systemd:
sudo systemctl daemon-reload

# 2. Ejecutar una prueba manual inmediata del servicio:
sudo systemctl start lab-mantenimiento.service

# 3. Habilitar e iniciar el temporizador periódico:
sudo systemctl enable --now lab-mantenimiento.timer

# 4. Consultar el cronograma de ejecución (cuándo corrió por última vez y cuánto falta para la próxima):
systemctl list-timers lab-mantenimiento.timer --no-pager

# 5. Auditar los registros estructurados en journalctl:
sudo journalctl -u lab-mantenimiento.service -n 20 --no-pager
```

---

## ⚡ 4. Fase 4: Reemplazando al Comando `at` con `systemd-run`

¿Qué ocurre si queremos encolar una tarea única efímera (como hacíamos con `at now + 10 minutes`), pero queremos que quede registrada en `journalctl` y gobernada por `systemd`? Utilizamos **`systemd-run`**:

```bash
# Programar una tarea única efímera que se disparará en 10 segundos y luego desaparecerá:
sudo systemd-run --unit=lab-tarea-efimera \
    --on-active=10s \
    --timer-property=AccuracySec=1s \
    /bin/bash -c 'echo "Tarea efímera estilo AT ejecutada con éxito desde systemd-run en $(date)"'

# Ver el timer efímero en cuenta regresiva:
systemctl list-timers lab-tarea-efimera.timer --no-pager

# Esperar 12 segundos y consultar el log capturado en journalctl:
sleep 12
sudo journalctl -u lab-tarea-efimera.service --no-pager
```

---

## 🎯 5. Retos de Autoevaluación ("Ponte a Prueba")

<details>
<summary><b>1. ¿Qué directiva dentro de un archivo <code>.timer</code> de systemd permite replicar el comportamiento de <code>Anacron</code> en una laptop?</b></summary>
<br>
<b>Respuesta:</b> La directiva <code>Persistent=true</code> dentro de la sección <code>[Timer]</code>. Hace que <code>systemd</code> guarde en disco un sello de tiempo de la última ejecución; si el sistema estuvo apagado cuando debía dispararse el <code>OnCalendar</code>, ejecuta el servicio inmediatamente al iniciar.
</details>

<details>
<summary><b>2. Al configurar un par <code>mi_backup.service</code> y <code>mi_backup.timer</code>, ¿cuál de los dos archivos se debe habilitar con <code>systemctl enable --now</code>?</b></summary>
<br>
<b>Respuesta:</b> Se debe habilitar <b>únicamente el archivo <code>.timer</code></b> (<code>sudo systemctl enable --now mi_backup.timer</code>). El archivo <code>.service</code> no lleva sección <code>[Install]</code> porque será invocado automáticamente por el timer cuando corresponda.
</details>

<details>
<summary><b>3. ¿Con qué comando podés verificar si una expresión compleja de <code>OnCalendar</code> está bien escrita sin tener que esperar a que se cumpla la hora?</b></summary>
<br>
<b>Respuesta:</b> Con <code>systemd-analyze calendar "EXPRESION"</code> (por ejemplo: <code>systemd-analyze calendar --iterations=5 "Mon..Fri *-*-* 09:00:00"</code>).
</details>

<details>
<summary><b>4. ¿Por qué es crítico verificar <code>chronyc tracking</code> o <code>timedatectl</code> antes de diseñar automatizaciones en un clúster de servidores?</b></summary>
<br>
<b>Respuesta:</b> Porque si el reloj interno del sistema está desfasado o sin sincronización NTP activa, las tareas programadas se dispararán a destiempo, los backups pueden solaparse con horarios pico de clientes, las métricas en TSDB tendrán timestamps corruptos y los certificados TLS o tokens fallarán.
</details>

---

## 🛠️ 6. Demostración Interactiva y Limpieza

Ejecutá el script interactivo para recorrer las 4 fases en vivo en tu terminal:

```bash
cd linux/administrator/automatizacion

# Ejecutar demostración interactiva:
sudo ./demo_systemd_timers_chrony.sh

# O en modo automático:
sudo ./demo_systemd_timers_chrony.sh --auto 2

# Limpiar las unidades de prueba creadas:
sudo ./limpiar_systemd_timers_chrony.sh
```
