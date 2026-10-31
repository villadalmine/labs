#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: Respaldos de Bloque Crudo (dd) y Snapshots LVM CoW
# Laboratorio: linux/administrator/backup/backup_dd_imagenes_raw_lvm_snapshots.md
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Clonación de bloques a bajo nivel con dd y compresión en streaming (gzip).
#  - Congelamiento atómico en microsegundos con LVM Snapshot Copy-on-Write (CoW).
#  - Respaldo en caliente sin detener escrituras ni bloquear transacciones de producción.
#  - Inyección de corrupción catastrófica sobre el disco y restauración forense (e2fsck).
#  - Preguntas disparadoras ("pie de clase") con respuestas desplegables.
#  - Limpieza garantizada al finalizar (desmontaje, lvremove, vgremove y losetup -d).
#
# Uso:
#   sudo ./demo_backup_dd_snapshots.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_backup_dd_snapshots.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
#   sudo ./demo_backup_dd_snapshots.sh --keep   -> Preserva los volúmenes para pruebas
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este script requiere privilegios de superusuario (sudo) para crear volúmenes LVM y discos loop.\033[0m"
    echo "Ejecutá: sudo $0"
    exit 1
fi

AUTO_WAIT=0
KEEP_FILES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

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

LAB_DIR="/tmp/lab_dd_snapshots_$$"
IMG_DISK="/tmp/disk_dd_demo_$$.img"
LOOP_DEV=""
VG_NAME="vg_backup_demo_$$"
LV_PROD="lv_produccion"
LV_SNAP="snap_produccion"
MOUNT_PROD="/mnt/demo_prod_$$"
MOUNT_SNAP="/mnt/demo_snap_$$"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando sistemas de archivos y liberando volúmenes LVM...${C_RESET}"
    if [ "$KEEP_FILES" = true ]; then
        echo -e "${C_GREEN}[INFO] Entorno LVM preservado para práctica:${C_RESET}"
        echo -e "  • Montaje: ${MOUNT_PROD}"
        echo -e "  • Volume Group: ${VG_NAME}"
        return
    fi

    if mountpoint -q "$MOUNT_SNAP" 2>/dev/null; then
        umount -f "$MOUNT_SNAP" 2>/dev/null || true
    fi
    if mountpoint -q "$MOUNT_PROD" 2>/dev/null; then
        umount -f "$MOUNT_PROD" 2>/dev/null || true
    fi
    rmdir "$MOUNT_SNAP" 2>/dev/null || true
    rmdir "$MOUNT_PROD" 2>/dev/null || true

    if vgs "$VG_NAME" &>/dev/null; then
        lvremove -y "/dev/${VG_NAME}/${LV_SNAP}" 2>/dev/null || true
        lvremove -y "/dev/${VG_NAME}/${LV_PROD}" 2>/dev/null || true
        vgremove -y "$VG_NAME" 2>/dev/null || true
    fi

    if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ]; then
        pvremove -y "$LOOP_DEV" 2>/dev/null || true
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi

    rm -f "$IMG_DISK" 2>/dev/null || true
    rm -rf "$LAB_DIR" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Volúmenes LVM eliminados, loop liberado y entorno limpio.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_DIM}⏳ [MODO AUTO] Esperando ${AUTO_WAIT}s...${C_RESET}"
        sleep "$AUTO_WAIT"
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
        if [ "$AUTO_WAIT" -gt 0 ]; then
            sleep 1
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

echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 📦 DEMO EN VIVO: IMÁGENES CRUDAS (dd) Y SNAPSHOTS ATÓMICOS LVM CoW           ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "Bloque Crudo ➔ Congelamiento Atómico ➔ Escrituras en Caliente ➔ Rescate con e2fsck\n"

# ==============================================================================
# PASO 1: CREAR ENTORNO LVM
# ==============================================================================
step_banner "1" "Creación de Almacenamiento LVM y Datos de Producción"

mkdir -p "$LAB_DIR" "$MOUNT_PROD" "$MOUNT_SNAP"
truncate -s 512M "$IMG_DISK"
LOOP_DEV=$(losetup --find --show "$IMG_DISK")

explain "Asociamos el disco virtual loop a LVM:"
pvcreate -y -ff "$LOOP_DEV" >/dev/null
vgcreate -y "$VG_NAME" "$LOOP_DEV" >/dev/null
lvcreate -y -L 200M -n "$LV_PROD" "$VG_NAME" >/dev/null
mkfs.ext4 -F -q "/dev/${VG_NAME}/${LV_PROD}"
mount "/dev/${VG_NAME}/${LV_PROD}" "$MOUNT_PROD"

echo "BASE_DE_DATOS_TRANSACCIONES_SQL_2026" > "${MOUNT_PROD}/database.db"
echo "config_produccion_token=xyz987" > "${MOUNT_PROD}/config.env"
dd if=/dev/urandom of="${MOUNT_PROD}/datos_binarios.dat" bs=1M count=5 status=none
sync

run_and_show "lsblk ${LOOP_DEV}"
run_and_show "lvs ${VG_NAME}"
run_and_show "ls -lh ${MOUNT_PROD}"

pie_clase "¿Por qué hacer un respaldo directo con 'dd' sobre un disco que está siendo escrito por una base de datos genera una copia corrupta?" \
          "Porque 'dd' lee los bloques secuencialmente durante minutos. Si un proceso modifica bloques que 'dd' ya leyó o aún no leyó, el archivo resultante tiene datos asíncronos y punteros de filesystem inconsistentes (torn writes)."

pause_step "Presioná [ENTER] para ver cómo 'dd' clona el bloque crudo..."

# ==============================================================================
# PASO 2: BACKUP DE BLOQUE CRUDO CON DD Y COMPRESIÓN
# ==============================================================================
step_banner "2" "Backup de Bloque Crudo con dd y compresión en streaming (gzip)"

explain "Clonamos el Logical Volume completo a nivel de sectores comprimiendo al vuelo:"
run_and_show "dd if=/dev/${VG_NAME}/${LV_PROD} bs=4M conv=sparse status=none | gzip -c > ${LAB_DIR}/lv_produccion.img.gz"

explain "Comparamos el tamaño del volumen original (200 MB) vs la imagen comprimida:"
run_and_show "ls -lh ${LAB_DIR}/lv_produccion.img.gz"

pie_clase "¿Qué ventaja tiene la flag 'conv=sparse' en dd?" \
          "Indica a dd que no escriba bloques de ceros contiguos en el destino, ahorrando espacio si la imagen se descomprime en un archivo sparse."

pause_step "Presioná [ENTER] para congelar la producción con un LVM Snapshot CoW..."

# ==============================================================================
# PASO 3: SNAPSHOT ATÓMICO LVM COPY-ON-WRITE
# ==============================================================================
step_banner "3" "Snapshot Atómico en Microsegundos (Copy-on-Write)"

explain "Creamos una instantánea de 50 MB vinculada al volumen de producción:"
explain "El comando se ejecuta en menos de 10 milisegundos sin importar el tamaño de los datos:"
run_and_show "lvcreate -s -L 50M -n ${LV_SNAP} /dev/${VG_NAME}/${LV_PROD}"

explain "Inspeccionamos los Logical Volumes con 'lvs':"
explain "Notá el atributo 's' (snapshot), la columna Origin ('lv_produccion') y Data% (0.00% al crearse):"
run_and_show "lvs -o lv_name,vg_name,attr,data_percent,origin ${VG_NAME}"

pie_clase "¿Por qué un snapshot CoW ocupa apenas megabytes al inicio aunque el volumen origen tenga 20 Terabytes?" \
          "Porque inicialmente no copia datos, solo crea una tabla de punteros compartida. Solo consume espacio cuando se modifican bloques en el origen (guarda el bloque viejo antes de sobrescribirlo)."

pause_step "Presioná [ENTER] para modificar producción y ver el crecimiento de CoW..."

# ==============================================================================
# PASO 4: ESCRITURAS EN PRODUCCIÓN Y CONSUMO DEL SNAPSHOT
# ==============================================================================
step_banner "4" "Escrituras en Caliente sobre Producción y Divergencia CoW"

explain "Sobrescribimos datos en producción para comprobar que el snapshot mantiene el pasado congelado:"
echo "DATOS_NUEVOS_DEL_FUTURO_MODIFICADOS" > "${MOUNT_PROD}/database.db"
echo "Nuevo archivo temporal" > "${MOUNT_PROD}/archivo_nuevo.txt"
dd if=/dev/urandom of="${MOUNT_PROD}/datos_binarios.dat" bs=1M count=3 status=none
sync

explain "Inspeccionamos el porcentaje de divergencia consumido en el snapshot (Data% subió):"
run_and_show "lvs -o lv_name,vg_name,data_percent,origin ${VG_NAME}"

explain "Montamos el snapshot en modo solo lectura para auditar qué ve:"
mount -o ro,nouuid "/dev/${VG_NAME}/${LV_SNAP}" "$MOUNT_SNAP" 2>/dev/null || mount -o ro "/dev/${VG_NAME}/${LV_SNAP}" "$MOUNT_SNAP"

explain "1. VISIÓN EN PRODUCCIÓN (Datos Modificados):"
run_and_show "cat ${MOUNT_PROD}/database.db"

explain "2. VISIÓN EN EL SNAPSHOT (Estado Congelado Original):"
run_and_show "cat ${MOUNT_SNAP}/database.db"

pie_clase "¿Qué sucede si el volumen de producción sufre tantas escrituras que la tabla CoW del snapshot supera el 100% de su tamaño asignado?" \
          "El snapshot entra en estado INVALID (INACTIVO) y el kernel lo desactiva automáticamente para proteger la integridad del volumen de producción."

pause_step "Presioná [ENTER] para desmontar el snapshot y simular una catástrofe..."

# ==============================================================================
# PASO 5: CORRUPCIÓN CATASTRÓFICA Y RESCATE FORENSE
# ==============================================================================
step_banner "5" "Simulacro de Corrupción Catastrófica y Restauración con dd"

umount "$MOUNT_SNAP"
lvremove -y "/dev/${VG_NAME}/${LV_SNAP}" >/dev/null

explain "Simulamos un desastre de hardware: destruimos los primeros 15 MB del volumen de producción con ceros:"
umount "$MOUNT_PROD"
dd if=/dev/zero of="/dev/${VG_NAME}/${LV_PROD}" bs=1M count=15 status=none

explain "Intentamos montar el volumen dañado:"
run_and_show "mount /dev/${VG_NAME}/${LV_PROD} ${MOUNT_PROD} 2>&1 || echo 'FALLO ESPERADO: Superbloque y tabla de inodos destruidos.'"

explain "Restauramos la imagen cruda desde el backup con zcat | dd:"
run_and_show "zcat ${LAB_DIR}/lv_produccion.img.gz | dd of=/dev/${VG_NAME}/${LV_PROD} bs=4M status=none"

explain "Ejecutamos el chequeo forense de consistencia con e2fsck:"
run_and_show "e2fsck -f -y /dev/${VG_NAME}/${LV_PROD}"

explain "Montamos el volumen restaurado y comprobamos los datos:"
mount "/dev/${VG_NAME}/${LV_PROD}" "$MOUNT_PROD"
run_and_show "cat ${MOUNT_PROD}/database.db"
run_and_show "cat ${MOUNT_PROD}/config.env"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE DD Y LVM SNAPSHOTS FINALIZADA CON ÉXITO!                ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado la clonación de bajo nivel con dd, la creación de snapshots CoW,"
echo -e "la auditoría de divergencia y el rescate de volúmenes corruptos.\n"
