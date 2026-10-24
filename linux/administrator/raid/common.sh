#!/usr/bin/env bash
# ==============================================================================
# Biblioteca común de la serie RAID (se carga con: source "$(dirname "$0")/common.sh")
# - Colores, pausas interactivas / automáticas y limpieza segura
# - "Discos" simulados: archivos sparse + loop devices (corre en WSL2, VM o Docker)
# ==============================================================================

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; PURPLE='\033[0;35m'; DIM='\033[2m'; RESET='\033[0m'

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false
RAID_WORKDIR="${RAID_WORKDIR:-/tmp/raidlab}"
DISK_SIZE="${DISK_SIZE:-256M}"
INSTALL_HINT="${INSTALL_HINT:-}"
LOOPS=()

parse_common_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto) AUTO_MODE=true; AUTO_DELAY="${2:-3}"; shift 2 ;;
            --keep) KEEP_RUNNING=true; shift ;;
            --size) DISK_SIZE="${2:-256M}"; shift 2 ;;
            -h|--help)
                echo "Uso: sudo $0 [--auto <segundos>] [--keep] [--size 256M]"
                exit 0 ;;
            *) shift ;;
        esac
    done
}

header()    { echo -e "\n${CYAN}======================================================================${RESET}\n${BOLD}${CYAN} $1 ${RESET}\n${CYAN}======================================================================${RESET}"; }
subheader() { echo -e "\n${PURPLE}--- $1 ---${RESET}"; }
info()      { echo -e "${GREEN}[i]${RESET} $1"; }
warn()      { echo -e "${YELLOW}[!]${RESET} $1"; }
fail()      { echo -e "${RED}[x]${RESET} $1" >&2; }

pause_step() {
    local msg="${1:-Presiona [ENTER] para continuar...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${YELLOW}[AUTO] ${AUTO_DELAY}s: ${msg}${RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${YELLOW}>>> ${msg}${RESET}"
        read -r
    fi
}

# Muestra el comando y lo ejecuta. No aborta la demo si falla (es didáctico).
run() {
    echo -e "${DIM}\$ $*${RESET}"
    "$@"
    local rc=$?
    [ $rc -ne 0 ] && warn "(código de salida $rc)"
    return 0
}

# Igual que run, pero acepta pipes y redirecciones escritos como string.
runsh() {
    echo -e "${DIM}\$ $1${RESET}"
    bash -c "$1"
    local rc=$?
    [ $rc -ne 0 ] && warn "(código de salida $rc)"
    return 0
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "Este laboratorio necesita root. Ejecuta: sudo $0"
        exit 1
    fi
}

require_cmd() {
    local missing=()
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
    if [ ${#missing[@]} -gt 0 ]; then
        fail "Faltan comandos: ${missing[*]}"
        echo "    Instala con: sudo apt update && sudo apt install -y $INSTALL_HINT"
        exit 1
    fi
}

# Verifica soporte del kernel para un módulo/filesystem. Uso: require_kernel_module <nombre>
require_kernel_module() {
    local mod="$1"
    modprobe "$mod" 2>/dev/null && return 0
    grep -qw "$mod" /proc/filesystems /proc/modules 2>/dev/null && return 0
    [ -d "/sys/module/$mod" ] && return 0
    fail "El kernel actual no tiene soporte '$mod' (típico en el kernel por defecto de WSL2)."
    echo "    Opciones: (1) VM Ubuntu en VirtualBox  (2) kernel WSL2 propio con $mod  (3) EC2 del lab integrador."
    exit 1
}

# Crea N discos simulados (archivos sparse + loop devices). Llena el array LOOPS.
make_disks() {
    local n="$1"
    mkdir -p "$RAID_WORKDIR"
    for i in $(seq 1 "$n"); do
        local img="$RAID_WORKDIR/disk${i}.img" dev
        rm -f "$img"
        truncate -s "$DISK_SIZE" "$img"
        dev=$(losetup -f --show "$img") || { fail "losetup falló (¿root? ¿módulo loop?)"; exit 1; }
        LOOPS+=("$dev")
        info "disk${i}.img (${DISK_SIZE}, sparse) -> ${dev}"
    done
}

# Crea un disco extra (repuesto / reemplazo) y devuelve su loop device por stdout
make_spare_disk() {
    local img="$RAID_WORKDIR/disk$1.img"
    rm -f "$img"
    truncate -s "$DISK_SIZE" "$img"
    losetup -f --show "$img"
}

# Genera datos aleatorios y devuelve su sha256 por stdout
make_testdata() {
    local dest="$1" mb="${2:-20}"
    dd if=/dev/urandom of="$dest" bs=1M count="$mb" status=none
    sha256sum "$dest" | awk '{print $1}'
}

detach_loops() {
    losetup -a 2>/dev/null | grep "$RAID_WORKDIR" | cut -d: -f1 | while read -r d; do
        losetup -d "$d" 2>/dev/null || true
    done
}

# Cada script define cleanup_lab() y registra: trap trap_cleanup EXIT
trap_cleanup() {
    if [ "$KEEP_RUNNING" = true ]; then
        warn "--keep: recursos conservados en $RAID_WORKDIR (límpialos a mano al terminar)."
        return
    fi
    info "Limpiando recursos del laboratorio..."
    cleanup_lab 2>/dev/null || true
    detach_loops
    rm -rf "$RAID_WORKDIR"
}

pie_clase() {
    echo -e "\n${DIM}Serie RAID · Administración Linux · github.com/villadalmine/labs${RESET}"
}
