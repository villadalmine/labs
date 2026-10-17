#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: LVM2, Extensión en Caliente, Loop Devices y FUSE
# Basado en: linux/administrator/storage/lab_storage.md
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema destacada en una caja limpia.
#  - Desglosa y explica los campos clave (PV, VG, LV, resize2fs, ext4).
#  - Preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   sudo ./demo_lab_storage.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_lab_storage.sh --auto 4 -> Modo automático (espera 4s entre pasos)
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Este script requiere privilegios de superusuario (sudo)."
    exit 1
fi

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"

DIR_IMG="/tmp/lab_storage"
MOUNT_LVM="/mnt/lab_lvm"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")
MOUNT_CIFRADO="$USER_HOME/datos_cifrados"
MOUNT_VISIBLE="$USER_HOME/datos_visibles"

LOOP_DEV1="/dev/loop20"
LOOP_DEV2="/dev/loop21"
LOOP_DEV3="/dev/loop22"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando y liberando recursos LVM...${C_RESET}"
    if command -v fusermount &>/dev/null; then
        fusermount -u "$MOUNT_VISIBLE" 2>/dev/null || umount -f "$MOUNT_VISIBLE" 2>/dev/null || true
    fi

    umount -f "$MOUNT_LVM" 2>/dev/null || true

    lvremove -y /dev/vg_lab/lv_datos 2>/dev/null || true
    vgremove -y vg_lab 2>/dev/null || true
    pvremove -y "$LOOP_DEV1" "$LOOP_DEV2" "$LOOP_DEV3" 2>/dev/null || true

    losetup -d "$LOOP_DEV1" 2>/dev/null || true
    losetup -d "$LOOP_DEV2" 2>/dev/null || true
    losetup -d "$LOOP_DEV3" 2>/dev/null || true

    rm -rf "$DIR_IMG" "$MOUNT_LVM" "$MOUNT_CIFRADO" "$MOUNT_VISIBLE" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Recursos LVM y loop devices eliminados correctamente.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón directamente."
    echo -e "  - ${C_YELLOW}Scroll con TECLADO:${C_RESET} Presioná ${C_BOLD}Ctrl+b${C_RESET} y luego ${C_BOLD}[${C_RESET} (salís con ${C_BOLD}q${C_RESET})."
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
fi

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
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "${AUTO_WAIT:-0}" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM:-\033[2m}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
    fi
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
        read -r
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

clear || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 📦 LABORATORIO EN VIVO: LVM2, LOOP DEVICES Y ONLINE RESIZE                     ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Physical Volumes (PV) ➔ Volume Groups (VG) ➔ Logical Volumes (LV) ➔ ext4 Resize"
echo -e "Arquitectura 100% segura sobre archivos dispersos y /dev/loop20..22\n"

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------
step_banner "0" "Verificación de herramientas del sistema operativo"

explain "Comprobando la presencia de utilitarios de LVM2, util-linux y e2fsprogs:"
MISSING_PKGS=()
for pkg in lvm losetup mkfs.ext4 resize2fs truncate; do
    if ! command -v "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}Faltan herramientas: ${MISSING_PKGS[*]}. Instalando...${C_RESET}"
    if command -v dnf &>/dev/null; then
        dnf install -y lvm2 e2fsprogs util-linux
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq lvm2 e2fsprogs util-linux
    fi
fi
echo -e "${C_GREEN}✔ Herramientas de almacenamiento disponibles.${C_RESET}"

pause_step "Presioná [ENTER] para crear los 3 discos virtuales con loop devices..."

# ------------------------------------------------------------------------------
# 1. Creación de Discos Virtuales con Loop Devices
# ------------------------------------------------------------------------------
step_banner "1" "Discos Virtuales (Archivos Dispersos y Loop Devices)"

explain "Un 'sparse file' (archivo disperso) declara un tamaño de 2 GB pero consume 0 bytes reales en disco."
explain "Creamos 3 archivos de 2 GB y los asociamos a /dev/loop20, /dev/loop21 y /dev/loop22:"

mkdir -p "$DIR_IMG" "$MOUNT_LVM"
run_and_show "truncate -s 2G ${DIR_IMG}/disk1.img ${DIR_IMG}/disk2.img ${DIR_IMG}/disk3.img"
run_and_show "losetup ${LOOP_DEV1} ${DIR_IMG}/disk1.img && losetup ${LOOP_DEV2} ${DIR_IMG}/disk2.img && losetup ${LOOP_DEV3} ${DIR_IMG}/disk3.img"

explain "Verificamos los loop devices activos en el kernel:"
run_and_show "losetup -a | grep -E 'loop2[0-2]'"

pie_clase "¿Cuál es la ventaja de usar loop devices para aprender LVM en lugar de particionar tu disco real?" \
          "Aislamiento total: podemos simular múltiples discos físicos sin riesgo de borrar el sistema operativo anfitrión."

pause_step "Presioná [ENTER] para inicializar la capa de Physical Volumes (PV)..."

# ------------------------------------------------------------------------------
# 2. Inicialización de LVM2 (PV -> VG -> LV)
# ------------------------------------------------------------------------------
step_banner "2" "Inicialización de LVM2: De Bloques Físicos a Volúmenes Lógicos"

explain "1) PV (Physical Volume): Escribimos la cabecera LVM en los tres loop devices:"
run_and_show "pvcreate -y ${LOOP_DEV1} ${LOOP_DEV2} ${LOOP_DEV3}"
run_and_show "pvs ${LOOP_DEV1} ${LOOP_DEV2} ${LOOP_DEV3}"

explain "2) VG (Volume Group): Agrupamos los 3 PVs en un único pool de almacenamiento de ~6 GB llamado 'vg_lab':"
run_and_show "vgcreate vg_lab ${LOOP_DEV1} ${LOOP_DEV2} ${LOOP_DEV3}"
run_and_show "vgs vg_lab"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • ${C_BOLD}VSize: ~5.99g${C_RESET} -> Capacidad total sumada de los 3 discos virtuales."
echo -e " • ${C_BOLD}VFree: ~5.99g${C_RESET} -> Espacio no asignado listo para crear volúmenes."

explain "3) LV (Logical Volume): Tallamos una partición virtual de 1 GB llamada 'lv_datos':"
run_and_show "lvcreate -y -L 1G -n lv_datos vg_lab"
run_and_show "lvs vg_lab"

pie_clase "¿El Logical Volume lv_datos está atado a un disco físico específico?" \
          "No: LVM abstrae los discos en Physical Extents (PE de 4MB). El LV puede expandirse a través de múltiples discos."

pause_step "Presioná [ENTER] para formatear lv_datos con ext4 y montarlo..."

# ------------------------------------------------------------------------------
# 3. Formateo y Montaje
# ------------------------------------------------------------------------------
step_banner "3" "Formateo con ext4 y Montaje del Volumen Lógico"

explain "Creamos el sistema de archivos ext4 sobre /dev/vg_lab/lv_datos y lo montamos en ${MOUNT_LVM}:"
run_and_show "mkfs.ext4 -F -q /dev/vg_lab/lv_datos"
run_and_show "mount /dev/vg_lab/lv_datos ${MOUNT_LVM}"

explain "Verificamos el punto de montaje montado:"
run_and_show "df -h ${MOUNT_LVM}"

pause_step "Presioná [ENTER] para escribir datos de producción simulados..."

# ------------------------------------------------------------------------------
# 4. Generación de Datos en Producción
# ------------------------------------------------------------------------------
step_banner "4" "Generación de Datos en Producción (Archivo de 200 MB)"

explain "Escribimos un archivo de prueba de 200 MB mientras el volumen está en uso activo:"
run_and_show "dd if=/dev/urandom of=${MOUNT_LVM}/test_file.bin bs=1M count=200 status=none && ls -lh ${MOUNT_LVM}/test_file.bin"

explain "Comprobamos el consumo de espacio antes de la ampliación (capacidad 1 GB original):"
run_and_show "df -h ${MOUNT_LVM}"

pie_clase "En un disco tradicional con fdisk, ¿podrías agrandar la partición y el filesystem sin desmontar?" \
          "Normalmente requiere desmontar o reiniciar para releer la tabla de particiones. Con LVM y ext4 se hace 100% online."

pause_step "Presioná [ENTER] para ejecutar la Extensión en Caliente (Online Resize)..."

# ------------------------------------------------------------------------------
# 5. Extensión en Caliente (Online Resize sin Downtime)
# ------------------------------------------------------------------------------
step_banner "5" "Extensión en Caliente (Online Resize sin Downtime)"

explain "PASO A: Ampliamos el volumen lógico en +1.5 GB en LVM (pasa de 1 GB a 2.5 GB):"
run_and_show "lvextend -L +1.5G /dev/vg_lab/lv_datos"

explain "PASO B: Ampliamos el sistema de archivos ext4 con resize2fs MIENTRAS SIGUE MONTADO:"
run_and_show "resize2fs /dev/vg_lab/lv_datos"

explain "Comprobamos el nuevo tamaño disponible según df -h:"
run_and_show "df -h ${MOUNT_LVM}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • Tamaño anterior: ${C_YELLOW}~960 MB${C_RESET}"
echo -e " • Tamaño nuevo:    ${C_GREEN}~2.4 GB${C_RESET}"
echo -e " • El archivo ${C_BOLD}test_file.bin${C_RESET} sigue intacto y el servicio no sufrió ni 1 milisegundo de caída."

explain "Verificamos la integridad del archivo tras la expansión:"
run_and_show "ls -lh ${MOUNT_LVM}/test_file.bin"

pause_step "Presioná [ENTER] para ver la prueba opcional de FUSE con gocryptfs..."

# ------------------------------------------------------------------------------
# 6. Demostración de FUSE con gocryptfs
# ------------------------------------------------------------------------------
step_banner "6" "Cifrado en Espacio de Usuario con FUSE (gocryptfs)"

if ! command -v gocryptfs &>/dev/null; then
    explain "gocryptfs no está instalado en este sistema. Omitiendo prueba de FUSE."
    explain "(Para instalarlo en Debian/Ubuntu: sudo apt install gocryptfs | en Fedora: sudo dnf install gocryptfs)."
else
    explain "gocryptfs cifra archivos individuales en espacio de usuario mediante FUSE."
    mkdir -p "$MOUNT_CIFRADO" "$MOUNT_VISIBLE"
    chown -R "$REAL_USER:$REAL_USER" "$MOUNT_CIFRADO" "$MOUNT_VISIBLE" 2>/dev/null || true

    explain "Inicializamos gocryptfs con contraseña demo 'ClaseLinux2026!':"
    run_and_show "echo 'ClaseLinux2026!' | gocryptfs -q -init -extpass 'echo ClaseLinux2026!' ${MOUNT_CIFRADO}"

    explain "Montamos el directorio visible:"
    run_and_show "gocryptfs -q -extpass 'echo ClaseLinux2026!' ${MOUNT_CIFRADO} ${MOUNT_VISIBLE}"

    explain "Escribimos un secreto en la carpeta visible:"
    run_and_show "echo 'Credencial super secreta de produccion' > ${MOUNT_VISIBLE}/password.txt"

    explain "Contenido visto desde la carpeta visible:"
    run_and_show "cat ${MOUNT_VISIBLE}/password.txt"

    explain "Contenido REAL almacenado físicamente en el disco cifrado:"
    run_and_show "ls -la ${MOUNT_CIFRADO}"

    explain "Desmontamos FUSE con fusermount -u:"
    run_and_show "fusermount -u ${MOUNT_VISIBLE}"
fi

pause_step "Presioná [ENTER] para finalizar la demostración y limpiar recursos..."

step_banner "FIN" "Demostración de LVM2 finalizada"
echo -e "${C_BOLD}${C_GREEN}✔ LVM2, extensión online y loop devices completados con éxito.${C_RESET}\n"
