---
id: lab-2.2-systemd-socket-activation
title: Activación de Servicios por Socket (.socket) y Montajes Declarativos (.mount)
  en Systemd
difficulty_level: 2
difficulty_label: 'Nivel 2: Supervisión & Gobernanza Moderna (Systemd)'
section: '2.2'
sections:
- '2.2'
- '2'
category: systemd
tags:
- systemd
- sockets
- socket-activation
- mount
- tmpfs
- red
- inetd
tools:
- systemctl
- nc
- curl
- journalctl
- ss
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
  notes: Creación de unidad .socket en puerto 9999 y activación bajo demanda mediante
    nc/curl con systemd en WSL2.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Socket activation verificado en entorno de red AWS.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio sobre socket activation y unidades .mount en systemd. Demuestra
  cómo el kernel mantiene un puerto de red abierto (ListenStream) sin gastar memoria
  RAM en demonios ociosos, levantando instancias bajo demanda solo cuando llega una
  petición TCP, y cómo declarar puntos de montaje de sistemas de archivos volátiles
  mediante unidades nativas .mount.
files:
  guide: systemd/systemd-scoket.md
  script: null
  terraform: null
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
prerequisites:
- lab-2.1-systemd-memlogger
---

# Unidades `.socket` y `.mount` de systemd

`systemd` puede escuchar en un puerto y arrancar un servicio solo cuando llega una conexión. También puede montar sistemas de archivos mediante unidades `.mount`, como alternativa a definirlos en `/etc/fstab`.

Esta guía muestra ambos patrones:

1. Activar un servicio bajo demanda con una unidad `.socket`.
2. Montar un `tmpfs` con una unidad `.mount`.

---

## Parte A: activar un servicio bajo demanda con `.socket`

En este ejemplo, `systemd` escucha en el puerto local `9999`. Cuando llega una conexión, inicia una instancia de `mi_api@.service` y le entrega la conexión. Así, el servicio no queda ejecutándose mientras nadie lo usa.

### 1) Crear la unidad socket

Creá `/etc/systemd/system/mi_api.socket`:

```bash
sudo nano /etc/systemd/system/mi_api.socket
```

Pegá esta configuración:

```ini
[Unit]
Description=Socket local para mi API

[Socket]
ListenStream=127.0.0.1:9999
Accept=yes
Service=mi_api@.service

[Install]
WantedBy=sockets.target
```

El socket escucha solo en `127.0.0.1`, así que este ejemplo de prueba no expone el puerto a la red.

### 2) Crear el servicio asociado

Creá `/etc/systemd/system/mi_api@.service` (el `@` es obligatorio; no lo llames `mi_api.service`):

```bash
sudo nano /etc/systemd/system/mi_api@.service
```

Pegá esta configuración:

```ini
[Unit]
Description=Servicio iniciado por el socket mi_api

[Service]
StandardInput=socket
StandardOutput=socket
ExecStart=/bin/bash -c "echo 'Hola desde systemd activado por socket!'"
```

El `@` hace que sea una unidad plantilla. Con `Accept=yes`, systemd crea una instancia por cada conexión y conecta el socket aceptado a la entrada y salida estándar del servicio. No hace falta una sección `[Install]` en el servicio: el socket lo inicia cuando recibe una conexión.

### 3) Recargar systemd e iniciar el socket

```bash
sudo systemctl daemon-reload
sudo systemctl start mi_api.socket
```

El servicio todavía no debería estar activo; el socket queda escuchando y espera una conexión.

### 4) Probar la conexión

Comprobá el socket:

```bash
sudo ss -tlpn | grep 9999
```

Con `nc` instalado, conectate desde otra terminal:

```bash
nc 127.0.0.1 9999
```

La respuesta esperada es:

```text
Hola desde systemd activado por socket!
```

Revisá el estado y los logs del socket:

```bash
systemctl status mi_api.socket
journalctl -b -u mi_api.socket --no-pager
```

El servicio por conexión puede aparecer como inactivo después de responder; es normal porque el proceso termina al cerrar la conexión.

Si el socket informa `Failed to load connection service unit`, verificá que exista `/etc/systemd/system/mi_api@.service`, que el nombre coincida con `Service=mi_api@.service` y luego ejecutá `sudo systemctl daemon-reload`.

### 5) Detener el socket

Al detener el socket, systemd deja de escuchar en el puerto:

```bash
sudo systemctl stop mi_api.socket
```

Para habilitarlo en cada arranque:

```bash
sudo systemctl enable mi_api.socket
```

---

## Parte B: montar un `tmpfs` con una unidad `.mount`

Una unidad `.mount` permite declarar un montaje con systemd. En este ejemplo se monta un sistema de archivos temporal en memoria RAM de 100 MB en `/var/mi_ramdisk`.

### 1) Elegir el nombre de la unidad

El nombre del archivo `.mount` se deriva de la ruta de montaje: se reemplazan las barras `/` por guiones `-`.

Para `/var/mi_ramdisk`, el archivo debe llamarse:

```text
var-mi_ramdisk.mount
```

### 2) Crear la unidad de montaje

Creá `/etc/systemd/system/var-mi_ramdisk.mount`:

```bash
sudo nano /etc/systemd/system/var-mi_ramdisk.mount
```

Pegá esta configuración:

```ini
[Unit]
Description=Disco temporal en memoria RAM

[Mount]
What=tmpfs
Where=/var/mi_ramdisk
Type=tmpfs
Options=size=100M
```

### 3) Crear el directorio y montar

```bash
sudo mkdir -p /var/mi_ramdisk
sudo systemctl daemon-reload
sudo systemctl start var-mi_ramdisk.mount
```

### 4) Verificar el montaje

```bash
findmnt /var/mi_ramdisk
df -h /var/mi_ramdisk
systemctl status var-mi_ramdisk.mount
```

### 5) Desmontar

```bash
sudo systemctl stop var-mi_ramdisk.mount
```

Los archivos guardados en este `tmpfs` son temporales: desaparecen al desmontarlo o al apagar el sistema.

---

## Resumen completo

- Una unidad `.socket` escucha y, con `Accept=yes`, inicia una instancia del servicio plantilla por cada conexión.
- `StandardInput=socket` y `StandardOutput=socket` conectan el proceso con el cliente.
- Una unidad `.mount` declara un punto de montaje; su nombre se forma a partir de la ruta donde se monta.
- `daemon-reload` hace que systemd vuelva a leer las unidades nuevas o modificadas.
- `start` y `stop` inician o detienen una unidad ahora; `enable` configura su inicio automático.
- Un `tmpfs` usa memoria RAM y no conserva sus archivos después de desmontar o apagar.

Comandos principales de prueba:

```bash
sudo systemctl daemon-reload
sudo systemctl start mi_api.socket
nc 127.0.0.1 9999
journalctl -u 'mi_api@*.service'
sudo systemctl status mi_api.socket
sudo systemctl stop mi_api.socket

sudo systemctl start var-mi_ramdisk.mount
findmnt /var/mi_ramdisk
sudo systemctl stop var-mi_ramdisk.mount
```