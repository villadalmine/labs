#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: Respaldos de Bloque Crudo (dd) y Snapshots LVM CoW
# Laboratorio: linux/administrator/backup/backup_dd_imagenes_raw_lvm_snapshots.md
#
# Uso:
#   sudo ./demo_backup_dd_snapshots.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_backup_dd_snapshots.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este script requiere privilegios de superusuario (sudo).\033[0m"
    echo "Ejecutá: sudo $0"
    exit 1
fi

AUTO_WAIT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_DIM="\033[2m"

pause_step() {
    local prompt_msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "${C_DIM}⏳ Esperando ${AUTO_WAIT}s...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_YELLOW}${prompt_msg}${C_RESET}"
        read -r
    fi
}

step_banner() {
    local step_num="$1"
    local step_title="$2"
    echo -e "\n${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN} [PASO ${step_num}] ${step_title}${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}\n"
}

run_cmd() {
    local cmd="$1"
    echo -e "${C_BOLD}$ ${cmd}${C_RESET}"
    eval "$cmd"
}

LAB_DIR="/tmp/lab_dd_lvm"
VG_NAME="vg_backup_lab"
LV_PROD="lv_produccion"
LV_SNAP="lv_snap_backup"
MOUNT_PROD="/mnt/produccion_lab"
MOUNT_SNAP="/mnt/snapshot_seguro"
LOOP_DEV=""

echo -e "\n${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║${C_RESET} ${C_BOLD}DEMO: RESPALDOS DE BLOQUES CRUDOS (dd) & SNAPSHOTS LVM CoW${C_RESET}           ${C_BOLD}${C_CYAN}║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"

# ------------------------------------------------------------------------------
# 1. Preparar Entorno LVM
# ------------------------------------------------------------------------------
step_banner "1" "Inicialización de Almacenamiento Virtual LVM"

# Limpieza preventiva
umount "$MOUNT_SNAP" 2>/dev/null || true
umount "$MOUNT_PROD" 2>/dev/null || true
lvremove -f "${VG_NAME}/${LV_SNAP}" 2>/dev/null || true
lvremove -f "${VG_NAME}/${LV_PROD}" 2>/dev/null || true
vgremove -f "$VG_NAME" 2>/dev/null || true
for l in $(losetup -j "${LAB_DIR}/disco_lvm.img" 2>/dev/null | cut -d: -f1); do
    losetup -d "$l" 2>/dev/null || true
done
rm -rf "$LAB_DIR" "$MOUNT_PROD" "$MOUNT_SNAP"

mkdir -p "$LAB_DIR" "$MOUNT_PROD" "$MOUNT_SNAP"
cd "$LAB_DIR"

truncate -s 256M disco_lvm.img
LOOP_DEV=$(losetup -f --show disco_lvm.img)
echo -e "Dispositivo loop creado: ${C_BOLD}${LOOP_DEV}${C_RESET}"

pvcreate -y "$LOOP_DEV" >/dev/null
vgcreate "$VG_NAME" "$LOOP_DEV" >/dev/null
lvcreate -n "$LV_PROD" -L 120M "$VG_NAME" >/dev/null
mkfs.ext4 -F -L "PROD_DATA" "/dev/${VG_NAME}/${LV_PROD}" >/dev/null

mount "/dev/${VG_NAME}/${LV_PROD}" "$MOUNT_PROD"

echo "BASE DE DATOS EMPRESARIAL v1.0" > "${MOUNT_PROD}/database.db"
dd if=/dev/urandom of="${MOUNT_PROD}/tabla_usuarios.dat" bs=1M count=5 status=none

echo -e "\n${C_GREEN}✔ Volumen de producción montado y con datos iniciales:${C_RESET}"
ls -lh "$MOUNT_PROD"

pause_step

# ------------------------------------------------------------------------------
# 2. Respaldo Raw con dd
# ------------------------------------------------------------------------------
step_banner "2" "Respaldo a Nivel de Bloque Crudo con dd y compresión"

echo -e "1. Respaldando primeros 512 bytes del disco (MBR / Tabla particiones):"
run_cmd "dd if=${LOOP_DEV} of=${LAB_DIR}/mbr_backup.bin bs=512 count=1 status=none"
file "${LAB_DIR}/mbr_backup.bin"

echo -e "\n2. Extrayendo imagen de la partición lógica en streaming comprimido con gzip:"
run_cmd "dd if=/dev/${VG_NAME}/${LV_PROD} bs=4M conv=noerror,sync status=none | gzip -c > ${LAB_DIR}/lv_produccion.img.gz"

echo -e "\n${C_GREEN}✔ Imagen comprimida generada:${C_RESET}"
ls -lh "${LAB_DIR}/lv_produccion.img.gz"

pause_step

# ------------------------------------------------------------------------------
# 3. Snapshot LVM Copy-on-Write en Caliente
# ------------------------------------------------------------------------------
step_banner "3" "Creación de Snapshot LVM Copy-on-Write (Zero-Downtime)"

echo -e "Congelando atómicamente el estado del volumen sin detener el servicio..."
run_cmd "lvcreate --snapshot -n ${LV_SNAP} -L 40M /dev/${VG_NAME}/${LV_PROD}"

echo -e "\n${C_CYAN}Inspección del snapshot en LVM:${C_RESET}"
lvs -o lv_name,lv_size,origin,snap_percent "${VG_NAME}"

echo -e "\nSimulando que el servidor web/BD sigue trabajando y escribe datos nuevos:"
echo "TRANSACCIÓN POST-BACKUP (Dato Nuevo de las 14:00)" >> "${MOUNT_PROD}/database.db"
echo "Nuevo registro añadido en caliente" > "${MOUNT_PROD}/registro_nuevo.txt"

echo -e "\n${C_YELLOW}Contenido actual en Producción (con datos nuevos):${C_RESET}"
cat "${MOUNT_PROD}/database.db"

pause_step

# ------------------------------------------------------------------------------
# 4. Montaje Read-Only del Snapshot y Extracción
# ------------------------------------------------------------------------------
step_banner "4" "Montaje Read-Only del Snapshot y Extracción Consistente"

run_cmd "mount -o ro /dev/${VG_NAME}/${LV_SNAP} ${MOUNT_SNAP}"

echo -e "\n${C_GREEN}✔ Contenido visto desde el Snapshot congelado (¡INMUNE a cambios posteriores!):${C_RESET}"
cat "${MOUNT_SNAP}/database.db"

echo -e "\nEmpaquetando copia de seguridad consistente desde el snapshot:"
run_cmd "tar -cvpzf ${LAB_DIR}/backup_consistente_snapshot.tar.gz -C ${MOUNT_SNAP} ."

echo -e "\nDesmontando y liberando el snapshot CoW (¡Buena práctica de administración!):"
run_cmd "umount ${MOUNT_SNAP}"
run_cmd "lvremove -y /dev/${VG_NAME}/${LV_SNAP}"

echo -e "\n${C_GREEN}✔ Snapshot eliminado. Espacio devuelto al Volume Group.${C_RESET}"
lvs "${VG_NAME}"

pause_step

# ------------------------------------------------------------------------------
# 5. Desastre y Restauración de la Imagen Raw
# ------------------------------------------------------------------------------
step_banner "5" "Simulacro de Corrupción Catastrófica y Restauración con dd"

echo -e "${C_RED}💥 SIMULANDO CORRUPCIÓN DEL SISTEMA DE ARCHIVOS...${C_RESET}"
umount "$MOUNT_PROD"
dd if=/dev/zero of="/dev/${VG_NAME}/${LV_PROD}" bs=1M count=15 status=none
echo "Primeros 15MB del volumen sobreescritos con ceros."

echo -e "\nRestaurando la imagen cruda desde el backup con zcat | dd:"
run_cmd "zcat ${LAB_DIR}/lv_produccion.img.gz | dd of=/dev/${VG_NAME}/${LV_PROD} bs=4M status=none"

echo -e "\nEjecutando chequeo de integridad forense con e2fsck:"
run_cmd "e2fsck -f -y /dev/${VG_NAME}/${LV_PROD}"

echo -e "\nMontando el volumen restaurado y verificando datos:"
mount "/dev/${VG_NAME}/${LV_PROD}" "$MOUNT_PROD"

echo -e "\n${C_GREEN}✔ Archivos recuperados al 100%:${C_RESET}"
ls -lh "$MOUNT_PROD"
cat "${MOUNT_PROD}/database.db"

step_banner "FIN" "Demostración de dd y LVM Snapshots Finalizada"
echo -e "${C_GREEN}${C_BOLD}✔ Se demostraron todas las fases:${C_RESET}"
echo -e "  1. Copia de bajo nivel de MBR y partición cruda con dd y compresión."
echo -e "  2. Congelamiento atómico en microsegundos con LVM Snapshot CoW."
echo -e "  3. Respaldo consistente sin frenar las escrituras en producción."
echo -e "  4. Destrucción segura del snapshot para prevenir consumo de I/O."
echo -e "  5. Restauración y validación con e2fsck."
echo -e "\nPara limpiar el entorno, ejecutá:"
echo -e "  ${C_BOLD}sudo ./linux/administrator/backup/limpiar_backup_dd_snapshots.sh${C_RESET}\n"
