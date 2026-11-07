#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio Respaldos de Bloque Crudo (dd) y Snapshots LVM
# Referencia: linux/administrator/backup/backup_dd_imagenes_raw_lvm_snapshots.md
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este script requiere privilegios de superusuario (sudo).\033[0m"
    echo "Ejecutá: sudo $0"
    exit 1
fi

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

LAB_DIR="/tmp/lab_dd_lvm"
VG_NAME="vg_backup_lab"
MOUNT_PROD="/mnt/produccion_lab"
MOUNT_SNAP="/mnt/snapshot_seguro"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio de dd y Snapshots LVM...${C_RESET}"

# 1. Desmontar puntos de montaje
for m in "$MOUNT_SNAP" "$MOUNT_PROD"; do
    if mountpoint -q "$m" 2>/dev/null || grep -qs "$m" /proc/mounts; then
        umount -f "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
        echo -e "  ${C_GREEN}✔ Desmontado: ${m}${C_RESET}"
    fi
    rm -rf "$m" 2>/dev/null || true
done

# 2. Desmantelar Logical Volumes y Volume Group LVM
if vgs "$VG_NAME" &>/dev/null; then
    lvremove -f "${VG_NAME}" 2>/dev/null || true
    vgremove -f "$VG_NAME" 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Volume Group ${VG_NAME} eliminado.${C_RESET}"
fi

# 3. Desvincular loop devices asociados
if [ -f "${LAB_DIR}/disco_lvm.img" ]; then
    for l in $(losetup -j "${LAB_DIR}/disco_lvm.img" 2>/dev/null | cut -d: -f1); do
        wipefs -a "$l" 2>/dev/null || true
        pvremove -y "$l" 2>/dev/null || true
        losetup -d "$l" 2>/dev/null || true
        echo -e "  ${C_GREEN}✔ Loop device liberado: ${l}${C_RESET}"
    done
fi

# 4. Eliminar directorio temporal
if [ -d "$LAB_DIR" ]; then
    rm -rf "$LAB_DIR"
    echo -e "  ${C_GREEN}✔ Directorio eliminado: ${LAB_DIR}${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza de dd y Snapshots LVM completada exitosamente.${C_RESET}\n"
