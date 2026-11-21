#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EN VIVO: DOOM en Navegador con Podman Pod Desacoplado (<150 MB RAM)
# Laboratorio: linux/administrator/graficos/podman_x11_vnc_novnc_doom.md (Lab 3.30)
#
# Arquitectura del Pod "lab-doom-graficos":
#   1. doom-xserver : Xvfb :0 (640x480x24) + Openbox + x11vnc (127.0.0.1:5900) + xauth
#   2. doom-client  : chocolate-doom (X Client separado, comparte socket Unix vía volumen)
#   3. doom-novnc   : websockify + noVNC HTML5 (publicado SOLO en 127.0.0.1:6080)
#
# Uso:
#   ./demo_doom_podman_browser.sh [--wad /ruta/DOOM1.WAD] [--port 6080]
#                                 [--auto <seg>] [--keep] [--rebuild] [--clean] [--help]
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
AUTO_DELAY=2
KEEP_FILES=false
CLEAN_ONLY=false
REBUILD=false
PORT=6080
WAD_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --wad)
            WAD_PATH="${2:-}"
            shift 2
            ;;
        --port)
            PORT="${2:-6080}"
            shift 2
            ;;
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-2}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        --rebuild)
            REBUILD=true
            shift
            ;;
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Uso: ./demo_doom_podman_browser.sh [opciones]

Opciones:
  --wad <ruta.wad>   Usa tu propio DOOM1.WAD / DOOM2.WAD montado solo lectura (:ro)
                     (por defecto usa FreeDoom libre incluido en la imagen)
  --port <puerto>    Puerto local en 127.0.0.1 para noVNC (default: 6080)
  --auto <segundos>  Modo automático sin pausa indefinida (pausa N segundos)
  --keep             Deja encendido el Pod tras terminar el script
  --rebuild          Reconstruye la imagen localhost/lab-graficos-doom:latest
  --clean|--limpiar  Detiene y elimina el Pod y el volumen compartido
  --help|-h          Muestra esta ayuda

Controles dentro del navegador:
  Flechas = Mover / Girar  |  Ctrl = Disparar  |  Espacio = Abrir puertas  |  Esc = Menú
EOF
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POD_DIR="${SCRIPT_DIR}/doom-pod"
IMAGE_NAME="localhost/lab-graficos-doom:latest"
POD_NAME="lab-doom-graficos"
VOL_NAME="lab-doom-x11"

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar...}"
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
        echo -e "\n${C_YELLOW}[INFO] Modo --keep activo: el Pod '${POD_NAME}' sigue corriendo en http://127.0.0.1:${PORT}/vnc.html?autoconnect=true&resize=scale${C_RESET}"
        echo -e "${C_YELLOW}       Para apagarlo y liberar RAM luego ejecutá: ${SCRIPT_DIR}/limpiar_doom_podman_browser.sh${C_RESET}"
        return 0
    fi
    podman pod rm -f "${POD_NAME}" >/dev/null 2>&1 || true
    podman volume rm -f "${VOL_NAME}" >/dev/null 2>&1 || true
}

trap cleanup EXIT INT TERM

if ! command -v podman >/dev/null 2>&1; then
    echo -e "${C_RED}[ERROR] No se encontró 'podman' en PATH.${C_RESET}"
    exit 1
fi

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    echo -e "${C_GREEN}✅ Pod '${POD_NAME}' y volumen '${VOL_NAME}' eliminados. Consumo RAM liberado.${C_RESET}"
    exit 0
fi

WAD_REAL=""
if [ -n "$WAD_PATH" ]; then
    if [ ! -r "$WAD_PATH" ]; then
        echo -e "${C_RED}[ERROR] No se puede leer el archivo WAD especificado: ${WAD_PATH}${C_RESET}"
        exit 1
    fi
    WAD_REAL="$(readlink -f "$WAD_PATH")"
fi

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_CYAN}======================================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}     LAB 3.30: STACK GRÁFICO EN PODMAN POD (Xvfb + Openbox + DOOM + noVNC HTML5)      ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================================${C_RESET}"
if [ -f /run/.toolboxenv ]; then
    echo -e "${C_DIM}   Entorno: Fedora Toolbox (Podman remoto) | $(podman --version)${C_RESET}"
else
    echo -e "${C_DIM}   Entorno: $(hostname) | $(podman --version)${C_RESET}"
fi

# ==============================================================================
# PASO 1: Auditoría de RAM e Imagen Ultraliviana
# ==============================================================================
step_banner "1" "Verificar RAM disponible y Construir/Reusar Imagen Ultraliviana"
explain "El cliente gráfico y el servidor X viven en contenedores separados pero reutilizan la misma imagen base (~280 MB en disco), consumiendo menos de 150 MB de RAM en total para no sobrecargar la laptop."

run_and_show "Comprobar RAM disponible y detectar soporte cgroups v2 para límites de memoria" \
    "free -h; podman info --format 'Rootless={{.Host.Security.Rootless}} Cgroups={{.Host.CgroupsVersion}} MemLimit={{.Host.MemTotal}}'"

if [ "$REBUILD" = true ] || ! podman image exists "${IMAGE_NAME}"; then
    echo -e "\n${C_CYAN}🔨 Construyendo imagen ${IMAGE_NAME} desde ${POD_DIR}/Containerfile...${C_RESET}"
    if ! podman build -t "${IMAGE_NAME}" "${POD_DIR}"; then
        echo -e "${C_RED}[ERROR] Falló la construcción de ${IMAGE_NAME}.${C_RESET}"
        exit 1
    fi
else
    echo -e "\n${C_GREEN}✔ Imagen ${IMAGE_NAME} ya disponible en caché local (usa --rebuild para reconstruir).${C_RESET}"
fi

# Detectar si rootless podman tiene controlador de memoria delegado
MEM_CAPABLE=false
if podman info --format '{{.Host.OCIRuntime.Name}}' >/dev/null 2>&1; then
    if podman run --rm --memory=64m "${IMAGE_NAME}" true >/dev/null 2>&1; then
        MEM_CAPABLE=true
    fi
fi

# Limpiar ejecuciones previas huérfanas antes de iniciar
podman pod rm -f "${POD_NAME}" >/dev/null 2>&1 || true
podman volume rm -f "${VOL_NAME}" >/dev/null 2>&1 || true

# ==============================================================================
# PASO 2: Crear Volumen Compartido X11 y Pod Aislado
# ==============================================================================
step_banner "2" "Crear Volumen X11 (${VOL_NAME}) y Pod (${POD_NAME}) Solo en Localhost:${PORT}"
explain "Un Podman Pod comparte el namespace de red (loopback 127.0.0.1). El puerto VNC 5900 queda privado dentro del Pod y SOLO exponemos el puerto web ${PORT} en 127.0.0.1."

run_and_show "Crear volumen nombrado para el socket /tmp/.X11-unix y crear Pod con puerto loopback" \
    "podman volume create '${VOL_NAME}' && podman pod create --name '${POD_NAME}' -p '127.0.0.1:${PORT}:6080'"

# ==============================================================================
# PASO 3: Lanzar los 3 Contenedores Desacoplados (X Server, X Client, Proxy Web)
# ==============================================================================
step_banner "3" "Lanzar 3 Contenedores: doom-xserver + doom-client (DOOM) + doom-novnc"
explain "Cada pieza del stack gráfico corre en su propio contenedor: (1) doom-xserver maneja Xvfb :0 + Openbox + x11vnc, (2) doom-client ejecuta chocolate-doom hablando vía socket Unix X11, y (3) doom-novnc traduce RFB a WebSockets HTML5."

LIMIT_X=(); LIMIT_C=(); LIMIT_W=()
if [ "$MEM_CAPABLE" = true ]; then
    LIMIT_X=(--memory=160m)
    LIMIT_C=(--memory=160m)
    LIMIT_W=(--memory=96m)
    echo -e "${C_GREEN}🛡  Límites duros cgroups aplicados: doom-xserver=160MB | doom-client=160MB | doom-novnc=96MB${C_RESET}"
else
    echo -e "${C_YELLOW}⚠  Controlador de memoria cgroups v2 no delegado para contenedores; ejecutando sin --memory explícito (el Pod consume <150MB igualmente).${C_RESET}"
fi

# 1. Servidor Xvfb + Openbox + x11vnc
podman run -d \
    --name doom-xserver \
    --pod "${POD_NAME}" \
    "${LIMIT_X[@]}" \
    -v "${VOL_NAME}:/tmp/.X11-unix" \
    "${IMAGE_NAME}" \
    /usr/local/bin/entrypoint-xserver.sh >/dev/null

# 2. Cliente X11 (chocolate-doom con FreeDoom o WAD del usuario en :ro)
WAD_MOUNT_ARGS=()
if [ -n "$WAD_REAL" ]; then
    WAD_MOUNT_ARGS=(--security-opt label=disable -v "${WAD_REAL}:/wads/custom.wad:ro")
    echo -e "${C_CYAN}🎮 WAD personalizado montado en solo lectura (:ro): ${WAD_REAL}${C_RESET}"
else
    echo -e "${C_CYAN}🎮 Usando FreeDoom (freedoom1.wad) incluido de serie en el contenedor.${C_RESET}"
fi

podman run -d \
    --name doom-client \
    --pod "${POD_NAME}" \
    "${LIMIT_C[@]}" \
    "${WAD_MOUNT_ARGS[@]}" \
    -v "${VOL_NAME}:/tmp/.X11-unix" \
    "${IMAGE_NAME}" \
    /usr/local/bin/entrypoint-doom.sh >/dev/null

# 3. Proxy HTML5 noVNC / websockify
podman run -d \
    --name doom-novnc \
    --pod "${POD_NAME}" \
    "${LIMIT_W[@]}" \
    "${IMAGE_NAME}" \
    /usr/local/bin/entrypoint-novnc.sh >/dev/null

# Esperar a que noVNC responda HTTP 200 y la ventana de DOOM exista en Xvfb
READY=false
for _ in $(seq 1 60); do
    if podman exec doom-xserver bash -c "DISPLAY=:0 XAUTHORITY=/tmp/.X11-unix/.Xauthority xwininfo -root -tree 2>/dev/null | grep -qiE 'doom|freedoom'" && \
       python3 -c "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:${PORT}/vnc.html', timeout=1); exit(0 if r.status==200 else 1)" 2>/dev/null; then
        READY=true
        break
    fi
    sleep 0.25
done

if [ "$READY" != true ]; then
    echo -e "${C_RED}[ERROR] El Pod no terminó de inicializar a tiempo. Logs recientes:${C_RESET}"
    podman logs --tail 20 doom-xserver 2>&1 || true
    podman logs --tail 20 doom-client 2>&1 || true
    podman logs --tail 20 doom-novnc 2>&1 || true
    exit 1
fi

# ==============================================================================
# PASO 4: Inspección Técnica en Vivo (X11, Socket Privado VNC y RAM Real)
# ==============================================================================
step_banner "4" "Auditoría Técnica: Xvfb, xwininfo, Puerto Privado VNC y RAM Real"
explain "Verificamos desde fuera que la ventana gráfica de DOOM está viva dentro del X Server virtual, que x11vnc solo escucha en loopback 127.0.0.1:5900 del Pod, y que el consumo real de RAM es mínimo."

run_and_show "Listar el Pod y sus 4 contenedores (infra + xserver + client + novnc)" \
    "podman pod ps --filter name=${POD_NAME}; echo '---'; podman ps --pod --filter pod=${POD_NAME}"

run_and_show "Inspeccionar el display X11 :0 y la ventana de DOOM dentro de doom-xserver" \
    "podman exec doom-xserver env DISPLAY=:0 XAUTHORITY=/tmp/.X11-unix/.Xauthority xdpyinfo | grep dimensions; echo '---'; podman exec doom-xserver env DISPLAY=:0 XAUTHORITY=/tmp/.X11-unix/.Xauthority xwininfo -root -tree"

run_and_show "Comprobar puertos dentro del Pod (5900 solo en 127.0.0.1, 6080 hacia websockify)" \
    "podman exec doom-xserver ss -tlpn"

run_and_show "Medir consumo real de memoria RAM por contenedor (podman stats --no-stream)" \
    "podman stats --no-stream doom-xserver doom-client doom-novnc"

pie_clase "Si doom-client NO tiene instalado Xorg ni VNC en su proceso, ¿cómo logra dibujar el juego en la pantalla virtual de doom-xserver y llegar hasta tu navegador?"
pause_step

# ==============================================================================
# PASO 5: Jugar DOOM en el Navegador Web (noVNC HTML5)
# ==============================================================================
step_banner "5" "¡A Jugar! DOOM en Vivo desde tu Navegador Web"

URL="http://127.0.0.1:${PORT}/vnc.html?autoconnect=true&resize=scale"
echo -e "\n${C_BOLD}${C_GREEN}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}║  🌐 ABRÍ ESTA URL EN TU NAVEGADOR PARA JUGAR EN VIVO:                              ║${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}║                                                                                    ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}     ${URL}${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}║                                                                                    ║${C_RESET}"
echo -e "${C_BOLD}${C_YELLOW}║  🎮 Controles: Flechas (Mover) | Ctrl (Disparar) | Espacio (Puertas) | Esc (Menú)  ║${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"

pause_step "Jugá todo lo que quieras en el navegador. Cuando termines la demo, presioná [ENTER] para apagar el Pod y liberar toda la RAM..."

echo -e "\n${C_GREEN}======================================================================================${C_RESET}"
echo -e "${C_GREEN}✅ LAB 3.30 FINALIZADO: El Pod será destruido y tu RAM volverá a quedar libre.${C_RESET}"
echo -e "${C_GREEN}======================================================================================${C_RESET}"
