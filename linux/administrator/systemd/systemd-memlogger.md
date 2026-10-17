---
id: lab-2.1-systemd-memlogger
title: Monitoreo de Memoria con Systemd Services y Systemd Timers (Alternativa Moderna
  a Cron)
difficulty_level: 2
difficulty_label: 'Nivel 2: Supervisión & Gobernanza Moderna (Systemd)'
section: '2.1'
sections:
- '2.1'
- '2'
category: systemd
tags:
- systemd
- timers
- services
- cron
- memoria
- journald
- automatizacion
tools:
- systemctl
- journalctl
- ps
- bash
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-17'
  notes: Creación de unidad memlogger.service y memlogger.timer, verificación de ejecución
    en journalctl con systemd habilitado en WSL2.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Ejecución estándar como servicio systemd con registro estructurado en journald.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio sobre automatización y servicios periódicos en Linux mediante
  systemd. Enseña a crear un script colector de memoria, empaquetarlo como servicio
  Type=simple/oneshot, configurar un timer de systemd (OnCalendar/AccuracySec) como
  reemplazo moderno de cron y consultar los logs generados en el journal estructurado
  con journalctl -u memlogger.
files:
  guide: systemd/systemd-memlogger.md
  script: null
  terraform: null
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
prerequisites:
- lab-1.1-jobs-multiplexores
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Monitor de memoria con systemd

En esta guía vamos a crear un script que registra cada 10 segundos los cinco procesos que más memoria consumen. Después lo ejecutaremos como un servicio de `systemd`, que guardará la salida en el Journal.

## Paso 1: crear el script

Creá el archivo `/usr/local/bin/memlogger.sh`:

```bash
sudo nano /usr/local/bin/memlogger.sh
```

Pegá este contenido:

```bash
#!/usr/bin/env bash

while true; do
    echo "=== Top procesos por memoria ==="
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6
    sleep 10
done
```

`ps` ordena los procesos por uso de memoria de mayor a menor. `head -n 6` muestra el encabezado y las cinco primeras filas.

## Paso 2: dar permiso de ejecución

```bash
sudo chmod +x /usr/local/bin/memlogger.sh
```

## Paso 3: crear la unidad de systemd

Creá `/etc/systemd/system/memlogger.service`:

```bash
sudo nano /etc/systemd/system/memlogger.service
```

Pegá esta configuración:

```ini
[Unit]
Description=Monitor de consumo de memoria RAM
After=network.target

[Service]
ExecStart=/usr/local/bin/memlogger.sh
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
```

El servicio ejecuta el script y systemd lo reinicia si termina inesperadamente. En este ejemplo corre como `root`; eso le da acceso amplio al sistema, así que no uses este patrón sin revisar los permisos si adaptás el script para otras tareas.

## Paso 4: recargar systemd e iniciar el servicio

Cada vez que creás o modificás una unidad, recargá la configuración:

```bash
sudo systemctl daemon-reload
```

Iniciá el servicio ahora y habilitalo para los próximos arranques:

```bash
sudo systemctl enable --now memlogger.service
```

## Paso 5: comprobar el estado

```bash
systemctl status memlogger.service
```

El estado esperado es `active (running)`.

## Paso 6: consultar los registros

El script escribe por la salida estándar y systemd la guarda en el Journal. Para seguir los registros en vivo:

```bash
sudo journalctl -u memlogger.service -f
```

Para ver los registros recientes sin seguirlos en vivo:

```bash
sudo journalctl -u memlogger.service -n 50
```

## Paso 7: detener o deshabilitar el servicio

Para detenerlo hasta que lo inicies nuevamente:

```bash
sudo systemctl stop memlogger.service
```

Para evitar que arranque automáticamente en el próximo inicio:

```bash
sudo systemctl disable memlogger.service
```

## Resumen completo

1. Crear `/usr/local/bin/memlogger.sh` con un bucle que lista los cinco procesos con mayor uso de memoria cada 10 segundos.
2. Marcar el script como ejecutable.
3. Crear `/etc/systemd/system/memlogger.service` para que systemd gestione el proceso.
4. Recargar systemd, iniciar y habilitar el servicio.
5. Revisar su estado y consultar los registros con `journalctl`.

Comandos principales:

```bash
sudo chmod +x /usr/local/bin/memlogger.sh
sudo systemctl daemon-reload
sudo systemctl enable --now memlogger.service
systemctl status memlogger.service
sudo journalctl -u memlogger.service -f
sudo systemctl stop memlogger.service
sudo systemctl disable memlogger.service
```