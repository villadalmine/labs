#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Inspección X11/Xorg Headless con Xvfb y Seguridad xauth
# Laboratorio: linux/administrator/graficos/x11_inspeccion_headless_xvfb_xauth.md (Lab 3.27)
#
# Cubre:
#  - Detección GPU (lspci), Xorg -version y configuración modular xorg.conf.d/ (cvt, 00-keyboard.conf)
#  - Servidor X11 virtual en RAM (Xvfb :99) protegido con cookie xauth MIT-MAGIC-COOKIE-1
#  - Inspección de $DISPLAY, xdpyinfo, pidof xclock y xwininfo (-root -tree / -id -all)
#  - Prueba controlada del peligro de xhost + vs xhost - y reglas si:localuser
#  - Comparativa con Wayland ($WAYLAND_DISPLAY, Xwayland), systemd target y .xsession-errors
#
# Uso:
#   ./demo_x11_headless.sh [--auto <segundos>] [--keep] [--clean] [--help]
# ==============================================================================

set -uo pipefail

if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[0;36m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Uso: ./demo_x11_headless.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/lab_x11_headless"
XAUTH_FILE="${WORK_DIR}/Xauthority"
EMPTY_AUTH="${WORK_DIR}/empty_Xauthority"
XVFB_PID=""
XCLOCK_PID=""

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${C_YELLOW}⏳ [MODO AUTO] Esperando ${AUTO_DELAY}s: ${mensaje}${C_RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${mensaje}${C_RESET}"
        read -r </dev/tty 2>/dev/null || read -r
    fi
}

step_banner() {
    local num="$1"
    local title="$2"
    echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_YELLOW}PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💡 EXPLICACIÓN TEÓRICA:${C_RESET} $1"
}

run_and_show() {
    local cmd_desc="$1"
    local cmd_str="$2"
    echo -e "\n${C_BLUE}┌──[ COMMAND ]─────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_BLUE}│${C_RESET} ${C_DIM}# ${cmd_desc}${C_RESET}"
    echo -e "${C_BLUE}│${C_RESET} ${C_BOLD}\$ ${cmd_str}${C_RESET}"
    echo -e "${C_BLUE}└──────────────────────────────────────────────────────────────────────────────────────${C_RESET}"
    eval "$cmd_str"
    local rc=$?
    return $rc
}

pie_clase() {
    echo -e "\n${C_YELLOW}┌──[ 🎓 PREGUNTA PARA LA CLASE ]───────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_YELLOW}│${C_RESET} $1"
    echo -e "${C_YELLOW}└──────────────────────────────────────────────────────────────────────────────────────${C_RESET}"
}

cleanup() {
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "\n${C_YELLOW}[INFO] Modo --keep activo: Xvfb/procesos y archivos conservados en ${WORK_DIR}.${C_RESET}"
        echo -e "${C_YELLOW}       Para limpiar luego ejecutá: ${SCRIPT_DIR}/limpiar_x11_headless.sh${C_RESET}"
        return 0
    fi
    if [ -n "$XCLOCK_PID" ] && kill -0 "$XCLOCK_PID" 2>/dev/null; then
        kill "$XCLOCK_PID" 2>/dev/null || true
        wait "$XCLOCK_PID" 2>/dev/null || true
    fi
    if [ -n "$XVFB_PID" ] && kill -0 "$XVFB_PID" 2>/dev/null; then
        kill "$XVFB_PID" 2>/dev/null || true
        wait "$XVFB_PID" 2>/dev/null || true
    fi
    pkill -f "Xvfb :99" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}

trap cleanup EXIT INT TERM

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    echo -e "${C_GREEN}✅ Entorno del Lab 3.27 limpiado completamente.${C_RESET}"
    exit 0
fi

# Verificar dependencias requeridas
MISSING=()
for bin in Xvfb xauth xdpyinfo xwininfo xhost xclock cvt; do
    command -v "$bin" >/dev/null 2>&1 || MISSING+=("$bin")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${C_RED}[ERROR] Faltan comandos requeridos: ${MISSING[*]}${C_RESET}"
    echo -e "${C_YELLOW}Instalá en Ubuntu 24.04 con:${C_RESET}"
    echo "  sudo apt update && sudo apt install -y xvfb xserver-xorg-core xcvt x11-utils x11-xserver-utils x11-apps xauth pciutils procps"
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "${WORK_DIR}/xorg.conf.d"
chmod 700 "$WORK_DIR"

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_CYAN}======================================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}   LABORATORIO 3.27: INSPECCIÓN X11 HEADLESS (Xvfb), xdpyinfo, xwininfo Y xhost +     ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================================${C_RESET}"
echo -e "${C_DIM}   Host: $(hostname) | SO: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"') | Usuario: $(id -un)${C_RESET}"

# ==============================================================================
# PASO 1: Hardware GPU, Xorg -version y Configuración Modular
# ==============================================================================
step_banner "1" "Auditoría de GPU, Xorg -version y /etc/X11/xorg.conf.d/"
explain "En Linux moderno, /etc/X11/xorg.conf casi no existe porque Xorg autodetecta hardware vía Kernel KMS/udev. Solo se añaden fragmentos en /etc/X11/xorg.conf.d/*.conf (el último en orden alfanumérico gana)."

run_and_show "Detectar GPUs VGA / 3D en el bus PCI (en contenedores/VMs headless puede aparecer virtualizado o vacío)" \
    "lspci 2>/dev/null | grep -iE 'vga|3d|display' || echo '(Sin GPU VGA física expuesta en este bus — entorno headless/contenedor)'"

run_and_show "Consultar versión instalada del servidor Xorg (nota: Xorg -version imprime por stderr)" \
    "Xorg -version 2>&1 | head -n 10"

run_and_show "Inspeccionar existencia de /etc/X11/xorg.conf y fragmentos en /etc/X11/xorg.conf.d/" \
    "ls -la /etc/X11/xorg.conf 2>&1 || true; ls -la /etc/X11/xorg.conf.d/ 2>/dev/null || true"

run_and_show "Calcular Modeline 1920x1080@60Hz con cvt y crear configuraciones de práctica en sandbox" \
    "MODELINE=\$(cvt 1920 1080 | grep Modeline); echo \"\$MODELINE\"; cat <<EOF > ${WORK_DIR}/xorg.conf.d/10-monitor.conf
Section \"Monitor\"
    Identifier \"HDMI-1\"
    \${MODELINE}
    Option \"PreferredMode\" \"1920x1080_60.00\"
EndSection
EOF
cat <<'EOF' > ${WORK_DIR}/xorg.conf.d/00-keyboard.conf
Section \"InputClass\"
    Identifier \"system-keyboard\"
    MatchIsKeyboard \"on\"
    Option \"XkbLayout\" \"latam\"
    Option \"XKbOptions\" \"terminate:ctrl_alt_bksp\"
EndSection
EOF
head -n 20 ${WORK_DIR}/xorg.conf.d/*.conf"

pie_clase "¿Por qué en Linux actual /etc/X11/xorg.conf ya no suele existir y qué driver genérico usa Xorg sobre KMS?"
pause_step

# ==============================================================================
# PASO 2: Levantar Servidor X11 Real en RAM (Xvfb :99) + Cookie xauth
# ==============================================================================
step_banner "2" "Servidor X11 en RAM (Xvfb :99) y Cookie MIT-MAGIC-COOKIE-1 con xauth"
explain "Xvfb (X Virtual Framebuffer) implementa el protocolo X11 completo dibujando en memoria RAM sin monitor físico. Generamos una cookie de 128 bits con xauth para impedir accesos anónimos."

COOKIE=$(od -tx1 -An -N16 /dev/urandom | tr -d ' \n')
run_and_show "Crear cookie MIT-MAGIC-COOKIE-1 de 128 bits en archivo Xauthority aislado" \
    "xauth -f '${XAUTH_FILE}' add :99 . '${COOKIE}'; xauth -f '${XAUTH_FILE}' info; xauth -f '${XAUTH_FILE}' list"

echo -e "\n${C_CYAN}🚀 Iniciando Xvfb :99 (1366x768, 24 bits de color) con extensión SECURITY...${C_RESET}"
Xvfb :99 -screen 0 1366x768x24 +extension SECURITY -auth "${XAUTH_FILE}" >"${WORK_DIR}/xvfb.log" 2>&1 &
XVFB_PID=$!

for _ in $(seq 1 30); do
    if [ -S /tmp/.X11-unix/X99 ] && DISPLAY=:99 XAUTHORITY="${XAUTH_FILE}" xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo -e "${C_RED}[ERROR] Xvfb no pudo iniciar. Log:${C_RESET}"
    cat "${WORK_DIR}/xvfb.log"
    exit 1
fi

run_and_show "Verificar proceso Xvfb :99 vivo y su socket Unix /tmp/.X11-unix/X99" \
    "ps -fp ${XVFB_PID}; ls -la /tmp/.X11-unix/X99"

pie_clase "En esta arquitectura con Xvfb, ¿quién actúa como X Server (monitor virtual en RAM) y quiénes serán los X Clients?"
pause_step

# ==============================================================================
# PASO 3: Inspección de Pantalla y Ventanas ($DISPLAY, xdpyinfo, pidof, xwininfo)
# ==============================================================================
step_banner "3" "Inspección de Pantalla y Ventanas: \$DISPLAY, xdpyinfo, pidof y xwininfo"
explain "Con DISPLAY=:99 y XAUTHORITY apuntando a nuestra cookie, cualquier cliente X se conecta al servidor virtual. Consultaremos la resolución activa, lanzaremos xclock y rastrearemos su ventana y PID."

run_and_show "Consultar propiedades del screen #0 y dimensiones exactas con xdpyinfo" \
    "DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xdpyinfo | grep -A 7 'screen #0'; echo '---'; DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xdpyinfo | grep dimensions"

DISPLAY=:99 XAUTHORITY="${XAUTH_FILE}" xclock -geometry 220x220+40+40 >/dev/null 2>&1 &
XCLOCK_PID=$!
sleep 0.5

run_and_show "Obtener PID de la aplicación X lanzada con pidof y ps" \
    "pidof xclock; ps -fp ${XCLOCK_PID}"

WIN_ID=$(DISPLAY=:99 XAUTHORITY="${XAUTH_FILE}" xwininfo -root -tree | awk '/xclock/ {print $1; exit}')
run_and_show "Inspeccionar el árbol de ventanas del servidor X y los detalles completos de xclock (${WIN_ID})" \
    "DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xwininfo -root -tree; echo '--- Detalle xwininfo -id ${WIN_ID} -all ---'; DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xwininfo -id '${WIN_ID}' -all | grep -iE 'Window id|Absolute upper-left|Width|Height|Depth|Map State|Process'"

pie_clase "¿Cómo se relacionan el Window ID de X11 con el PID de Linux en el escritorio (pidof vs _NET_WM_PID en xwininfo)?"
pause_step

# ==============================================================================
# PASO 4: Seguridad X11 en Vivo — xauth vs. xhost + vs. xhost -
# ==============================================================================
step_banner "4" "Laboratorio de Seguridad X11: Rechazo xauth vs. Brecha Crítica con xhost +"
explain "xauth exige presentar una cookie criptográfica. En cambio, 'xhost +' desactiva toda ACL del display: cualquier proceso local (o remoto si escucha TCP) entra sin contraseña y puede capturar teclado o pantalla."

touch "$EMPTY_AUTH"
chmod 600 "$EMPTY_AUTH"

run_and_show "1) Intentar conectar xdpyinfo SIN cookie válida (archivo empty_Xauthority) -> DEBE FALLAR" \
    "DISPLAY=:99 XAUTHORITY='${EMPTY_AUTH}' xdpyinfo 2>&1 | head -n 5 || true"

run_and_show "2) SIMULACIÓN DE ERROR OPERATIVO: habilitar 'xhost +' (acceso indiscriminado)" \
    "DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xhost +"

run_and_show "3) Reintentar xdpyinfo SIN cookie tras 'xhost +' -> BRECHA: ahora logra leer el servidor X" \
    "DISPLAY=:99 XAUTHORITY='${EMPTY_AUTH}' xdpyinfo | grep dimensions"

run_and_show "4) MITIGACIÓN INMEDIATA: reactivar ACL con 'xhost -' y volver a verificar bloqueo sin cookie" \
    "DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xhost -; DISPLAY=:99 XAUTHORITY='${EMPTY_AUTH}' xdpyinfo 2>&1 | head -n 5 || true"

CURRENT_USER=$(id -un)
run_and_show "5) Alternativa acotada Server Interpreted (SI): autorizar únicamente a un usuario local exacto" \
    "DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xhost +si:localuser:${CURRENT_USER}; DISPLAY=:99 XAUTHORITY='${XAUTH_FILE}' xhost"

pie_clase "¿Por qué 'xhost +' es especialmente peligroso en X11 incluso en una estación con un solo usuario humano?"
pause_step

# ==============================================================================
# PASO 5: Comparativa con Wayland, Systemd Target y Troubleshooting .xsession-errors
# ==============================================================================
step_banner "5" "Contraste con Wayland, Systemd Target y Diagnóstico de ~/.xsession-errors"
explain "En Wayland cada cliente está aislado bajo \$WAYLAND_DISPLAY y las apps X11 heredadas corren dentro de XWayland. En servidores headless el target por defecto es multi-user.target, no graphical.target."

cat <<'EOF' > "${WORK_DIR}/xsession-errors.sample"
dbus-update-activation-environment: setting DISPLAY=:0
Xsession: X session started for alumno at lun nov 21 09:05:10 UTC 2026
gnome-keyring-daemon: insufficient process capabilities, unencrypted memory
(xfwm4:2140): Gtk-WARNING **: 09:05:11.102: Theme parsing error: gtk.css:42:10
** (xfce4-session:2102): WARNING **: 09:05:12.441: Unable to contact settings server
EOF

run_and_show "Inspeccionar variables de sesión del host actual, XWayland y default target de systemd" \
    "echo \"XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-headless/unset}\"; echo \"WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}\"; echo \"DISPLAY=${DISPLAY:-unset}\"; pgrep -a Xwayland 2>/dev/null || echo 'Xwayland no activo en este host'; systemctl get-default 2>/dev/null || true"

run_and_show "Revisar ejemplo clásico de ~/.xsession-errors para depuración de arranque de escritorio" \
    "cat '${WORK_DIR}/xsession-errors.sample'"

echo -e "\n${C_GREEN}======================================================================================${C_RESET}"
echo -e "${C_GREEN}✅ LAB 3.27 COMPLETADO: Inspección Xvfb, xdpyinfo, xwininfo, xauth y hardening xhost.${C_RESET}"
echo -e "${C_GREEN}======================================================================================${C_RESET}"
