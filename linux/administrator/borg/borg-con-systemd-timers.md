---
id: "lab-3.5-borg-systemd-timers"
title: "Automatización de Respaldos BorgBackup con Systemd Timers y Manejo Seguro de Contraseñas"
difficulty_level: 3
difficulty_label: "Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo"
section: "3.5"
sections:
  - "3.5"
  - "3"
category: "storage"
tags:
  - "storage"
  - "backup"
  - "borg"
  - "systemd"
  - "timers"
  - "seguridad"
  - "rotacion"
tools:
  - "borg"
  - "systemctl"
  - "journalctl"
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
  - environment: "WSL2"
    type: "local"
    instance_type: "virtualized"
    os: "Ubuntu 24.04 LTS"
    kernel: "6.18.54.1-microsoft-standard-WSL2"
    status: "PASSED"
    test_date: "2026-10-17"
    notes: "Configuración de archivo /etc/borgmatic/borg.env protegido con chmod 600 y servicio systemd Type=oneshot."
  - environment: "AWS EC2"
    type: "cloud"
    instance_type: "t3.micro"
    os: "Ubuntu 24.04 LTS"
    status: "VERIFIED"
    test_date: "2026-10-17"
    notes: "Automatización de backups diarios en producción sobre EC2."
environments:
  - "WSL2"
  - "AWS EC2"
operating_systems:
  - "Ubuntu 24.04 LTS"
status: "PASSED"
rag_summary: "Guía de automatización de copias de seguridad continuas con BorgBackup y systemd timers. Explica cómo inyectar la clave BORG_PASSPHRASE de manera segura sin exponerla en la tabla de procesos, crear unidades .service de tipo oneshot con políticas de reinicio y programar la ejecución periódica con rotación automática mediante OnCalendar."
files:
  guide: "borg/borg-con-systemd-timers.md"
  script: null
  terraform: null
---

# Backup automatizado con Borg + systemd timers

Para automatizar tareas recurrentes, Linux moderno ya no recomienda usar `cron`. En su lugar, usamos `systemd` timers, que tienen varias ventajas:

- registran los eventos automáticamente en `journalctl`
- evitan solapamientos si un backup tarda más de lo esperado
- manejan las credenciales de forma más segura que un cron tradicional

Vamos a crear esta automatización usando BorgBackup como ejemplo. La lógica es idéntica para Restic; solo cambia el nombre de la variable de entorno.

---

## Fase 1: Proteger la contraseña

Nunca debes escribir contraseñas en texto plano dentro de un archivo `.service` o de un script Bash. Usaremos la directiva `EnvironmentFile` de `systemd` para inyectar la contraseña en memoria del proceso, leyendo un archivo fuertemente protegido.

### 1) Crear el archivo de secretos

Crea un directorio exclusivo para la configuración de Borg y genera el archivo con tus credenciales:

```bash
sudo mkdir -p /etc/borg
sudo nano /etc/borg/credenciales
```

Añade la variable que Borg lee automáticamente. Si usaras Restic, la variable sería `RESTIC_PASSWORD=...`:

```bash
BORG_PASSPHRASE=TuSuperSecretaContraseñaAqui
```

### 2) Asegurar los permisos

Bloquea el archivo para que ningún otro usuario o proceso del sistema pueda leer la contraseña, excepto el usuario `root`:

```bash
sudo chown root:root /etc/borg/credenciales
sudo chmod 600 /etc/borg/credenciales
```

---

## Fase 2: El script de backup

Aunque puedes poner el comando directamente en `systemd`, usar un script separado te permite hacer limpieza de backups antiguos (`prune`) en la misma ejecución.

### 1) Crear el script

Crea el ejecutable:

```bash
sudo nano /usr/local/bin/backup-diario.sh
```

Pega este código. Ten en cuenta que no hay contraseñas aquí; `systemd` se encargará de inyectarlas antes de ejecutar esto:

```bash
#!/bin/bash
# Detener el script inmediatamente si hay un error
set -e

REPO="/mnt/disco_externo/mi_backup"

echo "Iniciando backup hacia $REPO..."

# 1. Crear el backup
borg create --stats \
    "$REPO::backup-{now:%Y-%m-%d_%H:%M}" \
    /var/www /etc /home

echo "Backup finalizado. Limpiando copias antiguas..."

# 2. Mantener solo los últimos 7 diarios, 4 semanales y 6 mensuales
borg prune -v --list --keep-daily=7 --keep-weekly=4 --keep-monthly=6 "$REPO"

echo "Operación completada con éxito."
```

### 2) Hacerlo ejecutable

```bash
sudo chmod +x /usr/local/bin/backup-diario.sh
```

---

## Fase 3: Las unidades de systemd

Necesitamos dos archivos: el `.service` (qué hacer) y el `.timer` (cuándo hacerlo). Sus nombres antes de la extensión deben coincidir.

### 1) Crear el servicio

Archivo: `/etc/systemd/system/borg-backup.service`

Define el trabajo. Al ser `Type=oneshot`, `systemd` sabe que es una tarea que empieza y termina, y no un demonio infinito:

```bash
sudo nano /etc/systemd/system/borg-backup.service
```

```ini
[Unit]
Description=Backup diario con BorgBackup
# Asegura que el disco externo esté montado antes de intentar hacer el backup
Requires=mnt-disco_externo.mount
After=mnt-disco_externo.mount network-online.target

[Service]
Type=oneshot
# Inyectar las contraseñas de forma segura
EnvironmentFile=/etc/borg/credenciales
ExecStart=/usr/local/bin/backup-diario.sh

# Mejores prácticas: limitar el impacto en el servidor
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
```

### 2) Crear el temporizador

Archivo: `/etc/systemd/system/borg-backup.timer`

Define el horario. `systemd` usa el formato `DíaDeSemana Año-Mes-Día Hora:Minuto:Segundo`:

```bash
sudo nano /etc/systemd/system/borg-backup.timer
```

```ini
[Unit]
Description=Temporizador para el backup diario a las 3 AM

[Timer]
# Ejecutar todos los días a las 03:00:00
OnCalendar=*-*-* 03:00:00

# Si el servidor estaba apagado a las 3AM, haz el backup ni bien lo enciendan
Persistent=true

[Install]
WantedBy=timers.target
```

---

## Fase 4: Activar la automatización

Recarga `systemd` y habilita el temporizador (¡no el servicio!).

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now borg-backup.timer
```

---

## Verificación

Comprueba cuándo será la próxima ejecución programada del backup:

```bash
systemctl list-timers | grep borg
```

Para ver los logs cuando se ejecute (o si falla), usa:

```bash
journalctl -u borg-backup.service -f
```

> Este patrón es ideal para copias de seguridad periódicas, mantenimiento de repositorios y tareas administradas de forma fiable sin depender de `cron`.
