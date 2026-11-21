---
id: lab-3.28-acceso-grafico-remoto-ssh-x11-vnc-seguro
title: 'Acceso Gráfico Remoto Seguro: Exportación de Apps por SSH X11 Forwarding (-X
  vs -Y), Hardening sshd, Túnel VNC (-L) y Riesgos de XDMCP'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos, Observabilidad
  y Subsistemas'
section: '3.28'
sections:
- '3.28'
- '3'
category: security
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- x11-forwarding
- ssh
- sshd
- xauth
- vnc
- tigervnc
- xdmcp
- waypipe
- rdp
- spice
- guacamole
- security
- hardening
tools:
- ssh
- sshd
- xauth
- xdpyinfo
- xwininfo
- xclock
- Xvfb
- ss
- python3
- vncserver
- vncviewer
- waypipe
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
prerequisites:
- lab-3.27-x11-inspeccion-headless-xvfb-xauth
- lab-3.3-ssh-cifrado-cliente-servidor
next_recommended_labs:
- lab-3.30-podman-pod-x11-xvfb-vnc-novnc-doom
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: ubuntu:24.04 (Ubuntu 24.04.5 LTS + OpenSSH 9.6p1 + Xvfb 2:21.1.12)
  os: Ubuntu 24.04.5 LTS
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_acceso_grafico_remoto.sh --auto 0 aprobada (exit 0);
    validados sshd aislado :22230, ssh -X Untrusted con DISPLAY=localhost:50.0, proxy
    127.0.0.1:6050, xdpyinfo/xclock remotos sobre Xvfb :98 (1280x720), túnel SSH -L
    15901 entregando RFB 003.008 y limpieza sin residuos.
environments:
- Podman Systemd Container (Toolbox Host)
operating_systems:
- Ubuntu 24.04.5 LTS
status: PASSED
rag_summary: Laboratorio práctico de seguridad y acceso gráfico remoto en Linux. Levanta
  un demonio sshd aislado (puerto 22230) y un display cliente Xvfb (:98) para demostrar
  en vivo SSH X11 Forwarding real (DISPLAY=localhost:50.0, inyección automática de
  cookie xauth, puerto loopback 127.0.0.1:6050 y renderizado remoto de xdpyinfo/xclock),
  explicar los riesgos entre ssh -X (Untrusted SECURITY) y ssh -Y (Trusted keylogging),
  auditar sshd_config (X11UseLocalhost yes), construir un túnel SSH -L cifrado para
  VNC/RFB en localhost y documentar la exportación real de aplicaciones desde un servidor
  remoto hacia una laptop Linux o Wayland con Waypipe.
files:
  guide: graficos/acceso_grafico_remoto_ssh_x11_vnc.md
  script: graficos/demo_acceso_grafico_remoto.sh
  terraform: null
---

# 🔐 Lab 3.28: Acceso Gráfico Remoto Seguro — Exportar Aplicaciones por SSH (`-X` vs. `-Y`), Hardening `sshd` y Túnel VNC (`-L`)

> *"Cuando administras un servidor sin monitor, casi nunca necesitas instalarle un escritorio completo. Si un día debes lanzar una herramienta gráfica remota, el camino seguro es cifrarla con SSH (`-X` o `waypipe`) o tunelizar VNC en `localhost`; exponer X11 TCP 6000, XDMCP o VNC abierto a la red equivale a entregar tu teclado y tu pantalla al mejor postor."*

---

## 🎯 Objetivos del Laboratorio

1. **Comprobar cómo funciona SSH X11 Forwarding por dentro:** ver cómo `sshd` crea el proxy en loopback (`DISPLAY=localhost:50.0` / puerto TCP `6050`) e inyecta automáticamente una cookie temporal en `~/.Xauthority` vía `xauth`.
2. **Exportar una aplicación gráfica real por SSH:** ejecutar `xdpyinfo` y `xclock` en el servidor SSH remoto y comprobar que renderizan sobre el servidor X del cliente (`1280x720`) sin que el servidor remoto tenga entorno de escritorio ni GPU.
3. **Diferenciar `ssh -X` (*Untrusted*) vs. `ssh -Y` (*Trusted*):** comprender por qué `-Y` expone el X Server local a *keylogging* si el servidor remoto está comprometido, y cómo endurecer cliente y servidor (`X11UseLocalhost yes`, `ForwardX11Trusted no`).
4. **Asegurar VNC (`TigerVNC` + `~/.vnc/xstartup`) detrás de un túnel SSH `-L`:** verificar con `ss -tlpn` que el servicio RFB escucha **exclusivamente en `127.0.0.1`** y consumirlo cifrado desde el puerto local del túnel.
5. **Aplicarlo entre dos máquinas reales:** disponer de los comandos exactos para exportar una app gráfica desde una VM Ubuntu o PC secundaria de laboratorio hacia tu laptop (X11 o Wayland).

---

## 📦 Requisitos e Instalación en Ubuntu 24.04 LTS

```bash
sudo apt update && sudo apt install -y xvfb x11-utils x11-apps xauth \
  openssh-server openssh-client iproute2 procps python3
```

*(Opcional solo si deseas probar escritorio VNC o Waypipe nativo entre dos equipos reales: `sudo apt install -y tigervnc-standalone-server tigervnc-viewer waypipe`)*

---

## 🚀 Ejecución del Laboratorio Autocontenido (1 sola VM / Contenedor)

```bash
cd linux/administrator/graficos

# Modo interactivo paso a paso (ideal para clase)
sudo ./demo_acceso_grafico_remoto.sh

# Modo automático (sin pausas)
sudo ./demo_acceso_grafico_remoto.sh --auto 0

# Limpieza manual si se ejecutó con --keep
sudo ./limpiar_acceso_grafico_remoto.sh
```

> 🧠 **Arquitectura del laboratorio:** Para que puedas ensayar todo en una única VM Ubuntu sin escritorio gráfico, el script simula **dos roles en el mismo host**:
> - **Laptop del SysAdmin (Cliente):** `Xvfb :98` (`1280x720`) + cliente `ssh`.
> - **Servidor Remoto Headless:** instancia aislada de `/usr/sbin/sshd` en `127.0.0.1:22230` (sin tocar tu `/etc/ssh/sshd_config` del sistema) + receptor VNC/RFB en `127.0.0.1:25901`.

---

## 🌍 Guía Práctica Real: Exportar una App desde Otro Equipo (PC / VM) a tu Laptop

Cuando quieras demostrar frente a alumnos cómo levantas **una aplicación gráfica desde tu PC secundaria o VM Ubuntu headless hacia tu laptop** (ya sea corriendo X11 o Wayland con `XWayland`):

### 1. En el Servidor Remoto / PC Secundaria (Headless)

**NO necesitas instalar GNOME, KDE ni Xorg completo.** Basta instalar:

```bash
# Ubuntu / Debian en el equipo remoto:
sudo apt update && sudo apt install -y openssh-server xauth x11-apps
# (En producción podría ser: wireshark, virt-manager, synaptic, etc.)
```

Verifica que `/etc/ssh/sshd_config` tenga activas estas directivas y recarga `sshd`:

```text
X11Forwarding yes
X11DisplayOffset 10
X11UseLocalhost yes
```

```bash
sudo sshd -t && sudo systemctl reload ssh
```

### 2. Desde tu Laptop Local (X11 o Wayland con XWayland)

```bash
# Opción A (RECOMENDADA — Untrusted con aislamiento SECURITY):
ssh -X usuario@<IP_SERVIDOR_O_PC> xeyes

# Opción B (con compresión -C útil en enlaces lentos o Wi-Fi):
ssh -XC usuario@<IP_SERVIDOR_O_PC> xclock

# Opción C (SOLO si una app antigua GTK/Java falla por restricciones SECURITY de -X
# y confías plenamente en el servidor remoto):
ssh -Y usuario@<IP_SERVIDOR_O_PC> wireshark
```

### 3. Alternativa Moderna Wayland ➔ Wayland (`Waypipe`)

Si tu laptop usa Wayland (Sway, GNOME, KDE Plasma) y quieres correr una app nativa Wayland remota sin pasar por X11/XWayland:

```bash
# Instalar 'waypipe' en ambos equipos y ejecutar:
waypipe ssh usuario@<IP_SERVIDOR_O_PC> gnome-calculator
```

---

## 🛡️ Matriz de Riesgos y Mitigaciones en Acceso Gráfico Remoto

| Escenario / Error Frecuente | Riesgo Real de Seguridad | Mitigación Obligatoria |
| :--- | :--- | :--- |
| **`ssh -Y usuario@host_no_confiable`** | El servidor remoto obtiene acceso total a tu X Server local: puede hacer **keylogging silencioso** de tu `sudo` o navegador y capturar tu pantalla. | Usar **`ssh -X`** (Untrusted) y mantener **`ForwardX11Trusted no`** en `~/.ssh/config`; si es Wayland, preferir **`waypipe`**. |
| **`X11UseLocalhost no` en `sshd_config`** | El proxy X11 remoto escucha en `0.0.0.0:6010` en lugar de `127.0.0.1:6010`, exponiendo el socket X forwarding a la red LAN. | Configurar siempre **`X11UseLocalhost yes`** y comprobarlo con `ss -tlpn`. |
| **Ejecutar `xhost +` en tu laptop** | Desactiva la comprobación `xauth` por completo: cualquier proceso o equipo en red permitido alcanza tu sesión X11. | Revertir inmediatamente con **`xhost -`** y depender exclusivamente de `xauth` (`MIT-MAGIC-COOKIE-1`). |
| **VNC expuesto con `-localhost no` (`:5901`)** | El protocolo RFB de TigerVNC estándar no cifra la sesión completa ni protege contra fuerza bruta en red abierta. | Arrancar **`vncserver -localhost yes :1`** y conectar siempre vía túnel **`ssh -N -L 5901:127.0.0.1:5901`**. |
| **Habilitar XDMCP (`UDP 177`) en LightDM** | Login gráfico completo y tráfico X11 en texto plano interceptable con cualquier sniffer (`tcpdump`). | Mantener **`enabled=false`** en `[XDMCPServer]` y usar VPN/SSH o **Apache Guacamole** detrás de HTTPS + MFA. |

---

## 🧹 Limpieza

```bash
sudo ./limpiar_acceso_grafico_remoto.sh
```
