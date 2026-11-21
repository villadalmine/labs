#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Acceso Gráfico Remoto Seguro (SSH X11 Forwarding y VNC -L)
# Laboratorio: linux/administrator/graficos/acceso_grafico_remoto_ssh_x11_vnc.md (Lab 3.28)
#
# Cubre:
#  - Entorno aislado dual-rol en 1 VM: Laptop Cliente (Xvfb :98) + Servidor SSH (:22230)
#  - SSH X11 Forwarding real (ssh -X Untrusted con extensión SECURITY)
#  - Verificación de proxy DISPLAY=localhost:50.0, inyección xauth y socket 127.0.0.1:6050
#  - Ejecución remota por SSH de xdpyinfo y xclock renderizando en el display cliente :98
#  - Auditoría de sshd_config (X11UseLocalhost yes) y riesgos ssh -Y / XDMCP / VNC abierto
#  - Túnel SSH cifrado (-L 15901:127.0.0.1:25901) protegiendo un servicio RFB/VNC local
#
# Uso:
#   sudo ./demo_acceso_grafico_remoto.sh [--auto <segundos>] [--keep] [--clean] [--help]
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

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere root (sudo) para levantar una instancia sshd aislada en puerto 22230 con StrictModes y llaves temporales.${C_RESET}"
    exit 1
fi

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
            echo "Uso: sudo ./demo_acceso_grafico_remoto.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/lab_gui_remoto"
CLIENT_AUTH="${WORK_DIR}/client.Xauthority"
VNC_DIR="${WORK_DIR}/vnc_demo"
SSHD_PID=""
XVFB_PID=""
SSH_BG_PID=""
VNC_SIM_PID=""
SSH_TUN_PID=""
ROOT_XAUTH_EXISTED=false
ROOT_XAUTH_BACKUP="${WORK_DIR}/root_Xauthority.bak"

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
    return $?
}

pie_clase() {
    echo -e "\n${C_YELLOW}┌──[ 🎓 PREGUNTA PARA LA CLASE ]───────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_YELLOW}│${C_RESET} $1"
    echo -e "${C_YELLOW}└──────────────────────────────────────────────────────────────────────────────────────${C_RESET}"
}

cleanup() {
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "\n${C_YELLOW}[INFO] Modo --keep activo: demonios y archivos conservados en ${WORK_DIR}.${C_RESET}"
        echo -e "${C_YELLOW}       Para limpiar ejecutá: sudo ${SCRIPT_DIR}/limpiar_acceso_grafico_remoto.sh${C_RESET}"
        return 0
    fi
    for pid_var in "$SSH_TUN_PID" "$SSH_BG_PID" "$VNC_SIM_PID" "$SSHD_PID" "$XVFB_PID"; do
        if [ -n "${pid_var:-}" ] && kill -0 "$pid_var" 2>/dev/null; then
            kill "$pid_var" 2>/dev/null || true
            wait "$pid_var" 2>/dev/null || true
        fi
    done
    pkill -f "lab_gui_remoto/sshd_config" 2>/dev/null || true
    pkill -f "Xvfb :98" 2>/dev/null || true
    pkill -f "15901:127.0.0.1:25901" 2>/dev/null || true
    pkill -f "lab_gui_remoto/rfb_sim.py" 2>/dev/null || true

    # Restaurar /root/.Xauthority a su estado exacto previo
    if [ "$ROOT_XAUTH_EXISTED" = true ] && [ -f "$ROOT_XAUTH_BACKUP" ]; then
        cp -p "$ROOT_XAUTH_BACKUP" /root/.Xauthority 2>/dev/null || true
    elif [ "$ROOT_XAUTH_EXISTED" = false ] && [ "$CLEAN_ONLY" = false ]; then
        rm -f /root/.Xauthority
    else
        xauth remove localhost:50 2>/dev/null || true
    fi

    rm -rf "$WORK_DIR"
}

trap cleanup EXIT INT TERM

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    echo -e "${C_GREEN}✅ Entorno del Lab 3.28 limpiado completamente.${C_RESET}"
    exit 0
fi

# Verificar dependencias
MISSING=()
for bin in Xvfb xauth xdpyinfo xwininfo xclock ssh sshd ssh-keygen ss python3; do
    command -v "$bin" >/dev/null 2>&1 || MISSING+=("$bin")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${C_RED}[ERROR] Faltan binarios necesarios: ${MISSING[*]}${C_RESET}"
    echo -e "${C_YELLOW}Instalá en Ubuntu 24.04 con:${C_RESET}"
    echo "  sudo apt update && sudo apt install -y xvfb x11-utils x11-apps xauth openssh-server openssh-client iproute2 procps python3"
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$VNC_DIR" /run/sshd
chmod 700 "$WORK_DIR"
chmod 0755 /run/sshd

if [ -f /root/.Xauthority ]; then
    ROOT_XAUTH_EXISTED=true
    cp -p /root/.Xauthority "$ROOT_XAUTH_BACKUP"
fi

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_CYAN}======================================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}    LABORATORIO 3.28: ACCESO GRÁFICO REMOTO SEGURO (SSH X11 FORWARDING Y TÚNEL VNC)   ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================================${C_RESET}"
echo -e "${C_DIM}   Host: $(hostname) | SO: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"') | SSH: $(ssh -V 2>&1)${C_RESET}"

# ==============================================================================
# PASO 1: Entorno Aislado (Laptop Xvfb :98 + Servidor sshd :22230)
# ==============================================================================
step_banner "1" "Construir Entorno Dual-Rol: X Server Cliente (:98) + sshd Remoto (:22230)"
explain "Simularemos tu laptop (con servidor Xvfb :98 a 1280x720) conectándose por red cifrada SSH contra un servidor headless aislado en 127.0.0.1:22230, sin modificar /etc/ssh/sshd_config del host."

COOKIE=$(od -tx1 -An -N16 /dev/urandom | tr -d ' \n')
xauth -f "$CLIENT_AUTH" add :98 . "$COOKIE"
Xvfb :98 -screen 0 1280x720x24 +extension SECURITY -auth "$CLIENT_AUTH" >"${WORK_DIR}/xvfb98.log" 2>&1 &
XVFB_PID=$!

for _ in $(seq 1 30); do
    if [ -S /tmp/.X11-unix/X98 ] && DISPLAY=:98 XAUTHORITY="${CLIENT_AUTH}" xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

ssh-keygen -q -t ed25519 -N "" -f "${WORK_DIR}/ssh_host_ed25519_key"
ssh-keygen -q -t ed25519 -N "" -f "${WORK_DIR}/client_ed25519"
cp "${WORK_DIR}/client_ed25519.pub" "${WORK_DIR}/authorized_keys"
chmod 600 "${WORK_DIR}/authorized_keys" "${WORK_DIR}/client_ed25519" "${WORK_DIR}/ssh_host_ed25519_key"

cat <<EOF > "${WORK_DIR}/sshd_config"
Port 22230
ListenAddress 127.0.0.1
HostKey ${WORK_DIR}/ssh_host_ed25519_key
AuthorizedKeysFile ${WORK_DIR}/authorized_keys
PidFile ${WORK_DIR}/sshd.pid
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
UsePAM no
StrictModes no
AllowTcpForwarding local
X11Forwarding yes
X11DisplayOffset 50
X11UseLocalhost yes
XAuthLocation $(command -v xauth)
Subsystem sftp internal-sftp
EOF

/usr/sbin/sshd -t -f "${WORK_DIR}/sshd_config"
/usr/sbin/sshd -D -f "${WORK_DIR}/sshd_config" -E "${WORK_DIR}/sshd.log" &
SSHD_PID=$!
sleep 0.4

run_and_show "Verificar cliente X :98 (1280x720) y servidor sshd remoto aislado en TCP 22230" \
    "ps -fp ${XVFB_PID} ${SSHD_PID}; ss -tlpn | grep ':22230'"

pie_clase "En un servidor Linux real al que te conectas con 'ssh -X', ¿necesita ese servidor tener instalado GNOME, KDE o un monitor físico?"
pause_step

# ==============================================================================
# PASO 2: Exportación Real por SSH X11 Forwarding (ssh -X Untrusted)
# ==============================================================================
step_banner "2" "Exportar App Gráfica por SSH (-X): Proxy DISPLAY=localhost:50.0 y Cookie xauth"
explain "Al pasar '-X', el cliente SSH solicita reenvío X11. El sshd remoto crea un proxy en 127.0.0.1:6050, define DISPLAY=localhost:50.0 e inyecta una cookie efímera Untrusted con xauth. La app corre en el servidor remoto pero dibuja en tu display :98."

SSH_OPTS="-p 22230 -i ${WORK_DIR}/client_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=${WORK_DIR}/known_hosts -o LogLevel=ERROR"

run_and_show "Ejecutar xdpyinfo EN EL SERVIDOR REMOTO vía ssh -X y comprobar que lee la pantalla 1280x720 del cliente" \
    "DISPLAY=:98 XAUTHORITY='${CLIENT_AUTH}' ssh -X ${SSH_OPTS} root@127.0.0.1 'echo \"DISPLAY asignado en remoto: \$DISPLAY\"; xauth list | grep \":50\"; xdpyinfo | grep dimensions'"

# Lanzar una sesión ssh -X persistente con xclock remoto para inspeccionar el socket proxy y la ventana
DISPLAY=:98 XAUTHORITY="${CLIENT_AUTH}" ssh -X ${SSH_OPTS} root@127.0.0.1 "xclock -geometry 180x180+25+25" >/dev/null 2>&1 &
SSH_BG_PID=$!
sleep 1.0

run_and_show "Comprobar con ss el proxy loopback 127.0.0.1:6050 creado por sshd y la ventana xclock dibujada en :98" \
    "ss -tlpn | grep -E '22230|6050'; echo '--- Árbol de ventanas en el X Server del cliente (:98) ---'; DISPLAY=:98 XAUTHORITY='${CLIENT_AUTH}' xwininfo -root -tree | grep -iE 'root window|xclock'"

kill "$SSH_BG_PID" 2>/dev/null || true
wait "$SSH_BG_PID" 2>/dev/null || true
SSH_BG_PID=""

pie_clase "¿Cuál es la diferencia de seguridad entre 'ssh -X' (Untrusted / extensión SECURITY) y 'ssh -Y' (Trusted)?"
pause_step

# ==============================================================================
# PASO 3: Hardening sshd_config y Riesgos de X11UseLocalhost no / ssh -Y / XDMCP
# ==============================================================================
step_banner "3" "Hardening de sshd_config y Mitigación de Riesgos Remotos"
explain "Un error clásico es poner 'X11UseLocalhost no' en sshd_config: eso hace que el proxy X11 (puerto 6010/6050) escuche en 0.0.0.0 accesible desde la LAN. Además, usar 'ssh -Y' contra un servidor comprometido permite keylogging en tu laptop."

run_and_show "Auditar directivas efectivas X11 de sshd con 'sshd -T'" \
    "/usr/sbin/sshd -T -f '${WORK_DIR}/sshd_config' | grep -iE 'x11|allowtcpforwarding'"

echo -e "\n${C_YELLOW}📋 Recordatorio de configuración segura en el cliente (~/.ssh/config):${C_RESET}"
echo -e "   Host *.prod.empresa"
echo -e "       ForwardX11 no              # Solo activar bajo demanda con -X"
echo -e "       ForwardX11Trusted no       # Evita promoción silenciosa a -Y"

pie_clase "¿Qué pasa si un administrador configura 'X11UseLocalhost no' para que otra app en Docker use el display?"
pause_step

# ==============================================================================
# PASO 4: Túnel SSH Cifrado (-L) para VNC (TigerVNC + ~/.vnc/xstartup)
# ==============================================================================
step_banner "4" "Asegurar VNC (TigerVNC) en Loopback y Consumirlo vía Túnel SSH (-L)"
explain "Si necesitas un escritorio completo persistente (XFCE en VNC), la regla de oro es: no correr VNC como root, configurar ~/.vnc/xstartup, iniciarlo con '-localhost yes' y acceder SOLO mediante túnel SSH '-L'."

cat <<'EOF' > "${VNC_DIR}/xstartup"
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
vncconfig -nowin &
exec dbus-launch xfce4-session
EOF
chmod 700 "${VNC_DIR}/xstartup"

cat <<'EOF' > "${WORK_DIR}/rfb_sim.py"
import socket
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 25901))
srv.listen(5)
while True:
    conn, _ = srv.accept()
    conn.sendall(b"RFB 003.008\n")
    conn.close()
EOF

python3 "${WORK_DIR}/rfb_sim.py" &
VNC_SIM_PID=$!
sleep 0.3

run_and_show "Revisar plantilla ~/.vnc/xstartup (chmod 700) y confirmar listener VNC/RFB SOLO en 127.0.0.1:25901" \
    "ls -l '${VNC_DIR}/xstartup'; cat '${VNC_DIR}/xstartup'; echo '---'; ss -tlpn | grep ':25901'"

run_and_show "Abrir túnel SSH local (-L 15901:127.0.0.1:25901) y verificar saludo RFB cifrado de extremo a extremo" \
    "ssh -f -N -L 15901:127.0.0.1:25901 ${SSH_OPTS} root@127.0.0.1 && SSH_TUN_PID=\$(pgrep -f '15901:127.0.0.1:25901' | head -n1); ss -tlpn | grep ':15901'; python3 -c 'import socket; s=socket.create_connection((\"127.0.0.1\",15901),2); print(\"Respuesta vía túnel SSH:\", repr(s.recv(32))); s.close()'"
SSH_TUN_PID=$(pgrep -f '15901:127.0.0.1:25901' | head -n1 || true)

pie_clase "¿Por qué al usar 'vncserver -localhost yes :1' + 'ssh -L 5901:127.0.0.1:5901', el comando 'vncviewer' en tu laptop debe apuntar a 127.0.0.1:5901 y no a la IP pública del servidor?"
pause_step

# ==============================================================================
# PASO 5: Guía Rápida para Probar en Vivo Entre Tu Servidor/PC y Tu Laptop
# ==============================================================================
step_banner "5" "Comandos Listos para Exportar una App Real Entre Dos Equipos"
explain "Cuando quieras mostrar en clase cómo levantas una app gráfica desde una VM o PC remota hacia tu laptop (X11 o Wayland/XWayland), este es el checklist exacto."

echo -e "${C_BOLD}1) En el equipo remoto (headless, sin GNOME/KDE):${C_RESET}"
echo -e "   sudo apt install -y openssh-server xauth x11-apps"
echo -e "   # Verificar en /etc/ssh/sshd_config: X11Forwarding yes y X11UseLocalhost yes\n"
echo -e "${C_BOLD}2) Desde tu laptop local:${C_RESET}"
echo -e "   ssh -X usuario@<IP_REMOTA> xeyes            # Seguro por defecto (Untrusted)"
echo -e "   waypipe ssh usuario@<IP_REMOTA> <app>       # Nativos Wayland -> Wayland"
echo -e "   ssh -N -L 5901:127.0.0.1:5901 usuario@<IP>  # Túnel para VNC completo\n"

echo -e "${C_GREEN}======================================================================================${C_RESET}"
echo -e "${C_GREEN}✅ LAB 3.28 COMPLETADO: SSH X11 Forwarding (-X), hardening sshd y túnel VNC -L.${C_RESET}"
echo -e "${C_GREEN}======================================================================================${C_RESET}"
