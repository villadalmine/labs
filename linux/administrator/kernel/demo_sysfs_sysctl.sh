#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Estructura de sysfs (/sys), /proc y Tuning con sysctl
# Laboratorio: linux/administrator/kernel/sysfs_proc_sysctl_tuning.md (Lab 1.8)
#
# - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
# - Recorre los pseudo-filesystems /proc y /sys en vivo (block, bus, class, module, kernel).
# - Audita parámetros reales de producción con sysctl (red, VM, seguridad, inotify).
# - Demuestra ajuste temporal y persistente reversible en /etc/sysctl.d/.
# - Demuestra aislamiento de parámetros por network namespace (ip netns).
# - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   sudo ./demo_sysfs_sysctl.sh [--auto <segundos>] [--keep] [--clean] [--help]
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
    case "$1" in
        --auto)
            AUTO_MODE=true
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                AUTO_DELAY="$2"
                shift 2
            else
                AUTO_DELAY=3
                shift
            fi
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
            echo "Uso: sudo ./demo_sysfs_sysctl.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

DIR_LAB="/tmp/lab_demo_sysctl"
SYSCTL_DEMO_CONF="/etc/sysctl.d/99-lab-sysctl-demo.conf"
NETNS_NAME="lab_sysctl_ns"
ORIG_SWAPPINESS=""
ORIG_SOMAXCONN=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Restaurando parámetros sysctl y eliminando namespaces de prueba...${C_RESET}"
    rm -f "$SYSCTL_DEMO_CONF" 2>/dev/null || true

    if [ -n "$ORIG_SWAPPINESS" ] && [ -w /proc/sys/vm/swappiness ]; then
        sysctl -w "vm.swappiness=${ORIG_SWAPPINESS}" >/dev/null 2>&1 || true
    fi
    if [ -n "$ORIG_SOMAXCONN" ] && [ -w /proc/sys/net/core/somaxconn ]; then
        sysctl -w "net.core.somaxconn=${ORIG_SOMAXCONN}" >/dev/null 2>&1 || true
    fi

    if command -v ip &>/dev/null && ip netns list 2>/dev/null | grep -q "^${NETNS_NAME}\b"; then
        ip netns del "$NETNS_NAME" 2>/dev/null || true
    fi

    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan respaldos en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_sysfs_sysctl.sh\n"
    else
        rm -rf "$DIR_LAB" 2>/dev/null || true
        echo -e "${C_GREEN}✔ Entorno y archivos temporales restaurados limpiamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para probar sysctl e ip netns.${C_RESET}"
    exit 1
fi

trap cleanup EXIT INT TERM

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

pie_clase() {
    local pregunta="$1"
    local respuesta="${2:-}"
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase / autoaprendizaje: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_MODE" = true ]; then
            sleep "$AUTO_DELAY"
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta esperada...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
    fi
}

run_and_show() {
    local cmd="$1"
    echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR ────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"

    local output
    output=$(eval "$cmd" 2>&1) || true

    if [ -z "$output" ]; then
        echo -e "${C_YELLOW}(El comando finalizó exitosamente sin imprimir texto en stdout/stderr)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

mkdir -p "$DIR_LAB"
ORIG_SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || true)
ORIG_SOMAXCONN=$(cat /proc/sys/net/core/somaxconn 2>/dev/null || true)

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎛️  DEMOSTRACIÓN EN VIVO: SYSFS (/sys), PROCFS (/proc) Y TUNING CON SYSCTL     ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Interacción diaria del SysAdmin con dispositivos, drivers y perillas en RAM\n"

# ==============================================================================
# PASO 1: PSEUDO-FILESYSTEMS DEL KERNEL EN MEMORIA
# ==============================================================================
step_banner "1" "Pseudo-Sistemas de Archivos del Kernel: procfs, sysfs y devtmpfs"

explain "Verificamos que /proc, /sys y /dev no ocupan disco físico; son interfaces en RAM expuestas por el kernel:"
run_and_show "mount | grep -E '^(proc|sysfs|devtmpfs|udev)\b| on /proc | on /sys | on /dev ' | head -n 12"

pie_clase "¿Por qué /proc y /sys muestran archivos de 0 bytes o tamaño fijo al hacer ls -l?" \
          "Porque no almacenan datos reales en disco; el kernel genera el texto dinámicamente en memoria RAM en el instante exacto en que un proceso hace read()."

pause_step "Presioná [ENTER] para explorar la jerarquía real de /sys (sysfs)..."

# ==============================================================================
# PASO 2: ESTRUCTURA DE SYSFS (/sys) Y UDEV
# ==============================================================================
step_banner "2" "Anatomía de sysfs (/sys): block, bus, class, devices, kernel y module"

explain "Listamos los 8 subdirectorios maestros de /sys:"
run_and_show "ls -la /sys/"

explain "Inspeccionamos /sys/class/net cruzado con el driver real de cada interfaz:"
run_and_show "for iface in /sys/class/net/*; do n=\$(basename \"\$iface\"); d=\$(readlink -f \"\$iface/device/driver\" 2>/dev/null || echo ''); [ -n \"\$d\" ] && drv=\$(basename \"\$d\") || drv='virtual/loopback'; echo \"\$n -> driver: \$drv\"; done"

explain "Inspeccionamos discos en /sys/block (rotacional vs SSD y planificador I/O activo):"
run_and_show "for b in /sys/block/*; do n=\$(basename \"\$b\"); r=\$(cat \"\$b/queue/rotational\" 2>/dev/null || echo '-'); s=\$(cat \"\$b/queue/scheduler\" 2>/dev/null || echo 'N/A'); echo \"\$n | rotational=\$r | scheduler=\$s\"; done | head -n 10"

explain "Inspeccionamos /sys/module (parámetros vivos expuestos por módulos cargados) y /sys/kernel:"
run_and_show "ls /sys/module/*/parameters/ 2>/dev/null | head -n 20"
run_and_show "ls /sys/kernel/ 2>/dev/null | head -n 20"

pie_clase "¿Qué diferencia a /sys/devices del resto de carpetas (/sys/block, /sys/bus, /sys/class)?" \
          "/sys/devices contiene el árbol físico canónico real de hardware; block, bus y class son vistas organizadas mediante enlaces simbólicos que apuntan hacia /sys/devices."

pause_step "Presioná [ENTER] para auditar parámetros reales de producción con sysctl..."

# ==============================================================================
# PASO 3: AUDITORÍA DE PARÁMETROS CRÍTICOS CON SYSCTL
# ==============================================================================
step_banner "3" "Auditoría de Parámetros sysctl de Producción (/proc/sys)"

explain "Consultamos el total de parámetros visibles en /proc/sys y auditamos los de mayor impacto operativo:"
run_and_show "sysctl -a 2>/dev/null | wc -l | xargs -I{} echo 'Total de perillas sysctl disponibles: {}'"

run_and_show "sysctl net.ipv4.ip_forward net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control net.core.somaxconn net.ipv4.tcp_syncookies 2>/dev/null"
run_and_show "sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.max_map_count vm.overcommit_memory 2>/dev/null"
run_and_show "sysctl kernel.kptr_restrict kernel.dmesg_restrict kernel.randomize_va_space fs.protected_symlinks fs.protected_hardlinks fs.inotify.max_user_watches 2>/dev/null"

pie_clase "¿A qué ruta física del pseudo-filesystem equivale exactamente 'sysctl net.ipv4.ip_forward'?" \
          "Equivale exactamente al archivo virtual /proc/sys/net/ipv4/ip_forward."

pause_step "Presioná [ENTER] para probar cambios temporales y persistentes reversibles con sysctl..."

# ==============================================================================
# PASO 4: TUNING TEMPORAL, PERSISTENCIA EN /etc/sysctl.d Y NAMESPACES
# ==============================================================================
step_banner "4" "Tuning Temporal (sysctl -w), Persistencia (/etc/sysctl.d) y Aislamiento NetNS"

explain "Respaldamos los valores originales en ${DIR_LAB}/backup_values.txt antes de tocar nada:"
echo "vm.swappiness=${ORIG_SWAPPINESS}" > "${DIR_LAB}/backup_values.txt"
echo "net.core.somaxconn=${ORIG_SOMAXCONN}" >> "${DIR_LAB}/backup_values.txt"
run_and_show "cat ${DIR_LAB}/backup_values.txt"

if [ -w /proc/sys/vm/swappiness ]; then
    explain "Aplicamos un cambio temporal (solo RAM) de vm.swappiness=10 y verificamos en /proc/sys/vm/swappiness:"
    run_and_show "sysctl -w vm.swappiness=10 && cat /proc/sys/vm/swappiness"
else
    explain "En este entorno el namespace padre tiene /proc/sys/vm en solo lectura; mostramos la sintaxis equivalente:"
    run_and_show "echo 'sysctl -w vm.swappiness=10'"
fi

explain "Creamos un archivo persistente en /etc/sysctl.d/99-lab-sysctl-demo.conf (mayor precedencia) y lo cargamos con sysctl -p:"
cat <<'EOF' > "$SYSCTL_DEMO_CONF"
# Configuración temporal educativa - Lab 1.8
# Preferida para servidores de bases de datos / baja latencia de swapping
vm.swappiness = 10
net.core.somaxconn = 4096
EOF
run_and_show "cat ${SYSCTL_DEMO_CONF}"
run_and_show "sysctl -p ${SYSCTL_DEMO_CONF} 2>&1 || true"

if command -v ip &>/dev/null; then
    explain "Demostración aislada de red: creamos un Network Namespace '${NETNS_NAME}' y activamos ip_forward SOLO dentro de él (sin afectar al host):"
    if ip netns add "$NETNS_NAME" 2>/dev/null; then
        run_and_show "sysctl net.ipv4.ip_forward && ip netns exec ${NETNS_NAME} sysctl -w net.ipv4.ip_forward=1"
        run_and_show "ip netns exec ${NETNS_NAME} sysctl net.ipv4.ip_forward && sysctl net.ipv4.ip_forward"
    else
        explain "El entorno actual no permite crear ip netns (contenedor sin CAP_SYS_ADMIN). Omitiendo paso netns."
    fi
fi

pie_clase "¿Por qué conviene colocar tus ajustes en /etc/sysctl.d/99-custom.conf en lugar de editar archivos bajo /usr/lib/sysctl.d/?" \
          "Porque /usr/lib/sysctl.d/ pertenece a los paquetes del sistema y puede sobrescribirse al actualizar (o ser solo lectura en distros inmutables), mientras que 99-*.conf en /etc/sysctl.d/ tiene prioridad final y sobrevive actualizaciones."

echo -e "\n${C_BOLD}${C_GREEN}✔ Lab 1.8 completado con éxito. El bloque cleanup restaurará los valores originales.${C_RESET}"
