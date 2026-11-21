---
id: lab-3.27-x11-inspeccion-headless-xvfb-xauth
title: 'Inspección X11/Xorg Headless con Xvfb: Hardware GPU, Configuración Modular,
  xdpyinfo, xwininfo, xauth y Peligro de xhost +'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos, Observabilidad
  y Subsistemas'
section: '3.27'
sections:
- '3.27'
- '3'
category: fundamentals
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- x11
- xorg
- xvfb
- xauth
- xhost
- xdpyinfo
- xwininfo
- cvt
- lspci
- wayland
- seguridad
- headless
tools:
- Xorg
- Xvfb
- lspci
- xdpyinfo
- xwininfo
- xhost
- xauth
- cvt
- pidof
- xclock
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
prerequisites:
- lab-3.26-sistemas-graficos-x11-wayland-teoria
- lab-1.5-deteccion-hardware
next_recommended_labs:
- lab-3.28-acceso-grafico-remoto-ssh-x11-vnc-seguro
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: ubuntu:24.04 (Ubuntu 24.04.5 LTS + X.Org X Server 1.21.1.11 / Xvfb
    2:21.1.12)
  os: Ubuntu 24.04.5 LTS
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_x11_headless.sh --auto 0 aprobada (exit 0); validados
    Xvfb :99 1366x768, xdpyinfo, pidof/xwininfo sobre xclock, rechazo sin xauth, demostración
    xhost +/xhost -/+si:localuser y limpieza sin residuos.
environments:
- Podman Systemd Container (Toolbox Host)
operating_systems:
- Ubuntu 24.04.5 LTS
status: PASSED
rag_summary: Laboratorio práctico ejecutable en servidores o VMs Ubuntu 24.04 LTS
  sin escritorio gráfico usando Xvfb como servidor X11 real en memoria RAM. Cubre
  detección de GPU con lspci, Xorg -version, estructura /etc/X11/xorg.conf.d/ (Modeline
  con cvt y 00-keyboard.conf), cookies MIT-MAGIC-COOKIE-1 con xauth, consulta de dimensiones
  con xdpyinfo, identificación de PID y árbol de ventanas con pidof y xwininfo, demostración
  en vivo del fallo de seguridad de xhost + vs xhost - / si:localuser y comparación
  con sesiones Wayland y ~/.xsession-errors.
files:
  guide: graficos/x11_inspeccion_headless_xvfb_xauth.md
  script: graficos/demo_x11_headless.sh
  terraform: null
---

# 🧪 Lab 3.27: Inspección X11/Xorg Headless con `Xvfb`, `xdpyinfo`, `xwininfo`, `xauth` y Peligro de `xhost +`

> *"No necesitas instalar GNOME ni levantar cinco máquinas virtuales pesadas para entender cómo funciona X11 por dentro. Con `Xvfb` levantas un servidor X11 real en memoria RAM en menos de un segundo y puedes inspeccionar pantallas, ventanas, PIDs y cookies de seguridad como si tuvieras un monitor físico conectado."*

---

## 🎯 Objetivos del Laboratorio

1. **Auditar hardware y versión de Xorg:** usar `lspci`, `Xorg -version` e inspeccionar `/etc/X11/xorg.conf` y `/etc/X11/xorg.conf.d/`.
2. **Construir configuración modular:** calcular un `Modeline` real con `cvt 1920 1080` y redactar bloques `Monitor` e `InputClass` (`00-keyboard.conf`).
3. **Levantar un servidor X11 real en RAM:** iniciar `Xvfb :99` en `1366x768x24` protegido con una cookie criptográfica `MIT-MAGIC-COOKIE-1` generada mediante `xauth`.
4. **Inspeccionar pantallas y ventanas en vivo:** verificar `$DISPLAY`, `xdpyinfo | grep dimensions`, `pidof` y `xwininfo -root -tree` / `-id <ID> -all` sobre un cliente gráfico real (`xclock`).
5. **Demostrar en sandbox la brecha de `xhost +`:** comprobar cómo una app sin credenciales es rechazada por `xauth`, cómo `xhost +` abre la puerta de par en par, y cómo cerrarla con `xhost -` o reglas acotadas `si:localuser`.
6. **Contrastar con Wayland y troubleshooting:** revisar `$WAYLAND_DISPLAY`, `Xwayland`, `systemctl get-default` y errores típicos en `~/.xsession-errors`.

---

## 📦 Requisitos e Instalación en Ubuntu 24.04 LTS

No requiere instalar entorno de escritorio ni permisos de `root` (aunque funciona igual como usuario estándar o `root`):

```bash
sudo apt update && sudo apt install -y xvfb xserver-xorg-core xcvt x11-utils \
  x11-xserver-utils x11-apps xauth pciutils procps
```

---

## 🚀 Ejecución Rápida en Clase

```bash
cd linux/administrator/graficos

# Modo interactivo paso a paso (pausa con [ENTER] para explicar cada pantalla)
./demo_x11_headless.sh

# Modo automático (pausa de 2s entre pasos)
./demo_x11_headless.sh --auto 2

# Mantener los archivos temporales tras finalizar para inspección manual
./demo_x11_headless.sh --auto 0 --keep

# Limpieza manual completa
./limpiar_x11_headless.sh
```

---

## 🔍 Anatomía de los 5 Pasos del Laboratorio

### Paso 1: Hardware GPU, `Xorg -version` y `/etc/X11/xorg.conf.d/`

Verificamos primero si hay controlador VGA/3D visible en el bus PCI (`lspci | grep -iE "vga|3d|display"`), comprobamos la versión instalada con **`Xorg -version`** (nota útil de troubleshooting: `Xorg -version` imprime por *stderr*, por lo que para filtrarlo en tuberías debes usar `2>&1`), y revisamos por qué `/etc/X11/xorg.conf` casi nunca existe en distribuciones modernas, mientras `/etc/X11/xorg.conf.d/` aloja fragmentos puntuales como `10-monitor.conf` (generado con `cvt 1920 1080`) y `00-keyboard.conf` (`XkbLayout "latam"`, `terminate:ctrl_alt_bksp`).

### Paso 2: Levantar `Xvfb :99` con Autenticación `xauth`

Creamos un secreto aleatorio de 128 bits y lo inyectamos en un archivo `.Xauthority` aislado del laboratorio:

```bash
COOKIE=$(od -tx1 -An -N16 /dev/urandom | tr -d ' \n')
xauth -f /tmp/lab_x11_headless/Xauthority add :99 . "$COOKIE"
Xvfb :99 -screen 0 1366x768x24 +extension SECURITY -auth /tmp/lab_x11_headless/Xauthority &
xauth -f /tmp/lab_x11_headless/Xauthority list
```

### Paso 3: `$DISPLAY`, `xdpyinfo`, `pidof` y `xwininfo`

Exportando `DISPLAY=:99` y `XAUTHORITY=/tmp/lab_x11_headless/Xauthority`, inspeccionamos la geometría del display y lanzamos un cliente gráfico real (`xclock`):

```bash
xdpyinfo | grep -A 7 "screen #0"
xdpyinfo | grep dimensions        # -> dimensions: 1366x768 pixels

xclock -geometry 220x220+40+40 &
pidof xclock
xwininfo -root -tree
xwininfo -id <WINDOW_ID> -all
```

> 💡 **Tip forense en escritorios completos:** Clientes modernos (Firefox, terminales GTK/Qt, LibreOffice) publican su propiedad `_NET_WM_PID` en la ventana, permitiendo extraer su PID directamente con `xwininfo -all | grep -i Process` o combinarlo con `pidof firefox`.

### Paso 4: Seguridad X11 en Vivo — `xauth` vs. `xhost +` vs. `xhost -`

1. Creamos un archivo `empty_auth` vacío e intentamos ejecutar `XAUTHORITY=empty_auth xdpyinfo` ➔ **rechazado inmediatamente** (`Authorization required` / `unable to open display`).
2. Como experimento controlado, ejecutamos `xhost +` usando la sesión autenticada y repetimos la llamada **sin cookie** ➔ **ahora `xdpyinfo` entra sin credenciales**. En un escritorio real, esto significa que otro usuario o equipo en red podría capturar ventanas y pulsaciones.
3. Cerramos al instante con **`xhost -`**, comprobamos que el acceso sin cookie vuelve a bloquearse, y añadimos una regla quirúrgica basada en usuario del sistema operativo (`xhost +si:localuser:$(id -un)`).

### Paso 5: Wayland, `systemctl get-default` y `.xsession-errors`

Inspeccionamos si el host actual corre una sesión gráfica o *headless* (`XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`, `pgrep -a Xwayland`, `systemctl get-default`) y analizamos un registro modelo de `~/.xsession-errors` para aprender a identificar errores de `dbus-daemon`, permisos o bibliotecas GTK al diagnosticar inicios fallidos de escritorio.

---

## 🧹 Limpieza

El script incluye `trap cleanup EXIT INT TERM` automático. Si ejecutaste `--keep` o cancelaste de forma abrupta, corre:

```bash
./limpiar_x11_headless.sh
```
