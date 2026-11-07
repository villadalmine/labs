#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA TOTAL: Lab 3.9 · RAID con LVM (dm-raid)
# Referencia: linux/administrator/raid/raid_lvm.md
#
# Elimina en orden inverso seguro de la pila de almacenamiento:
#   1. Filesystem y puntos de montaje (/mnt/raidlab_lvm)
#   2. Logical Volumes y Volume Group (vg_raidlab / lv_prod)
#   3. Firmas de Physical Volumes (pvremove y wipefs)
#   4. Dispositivos loop del kernel vinculados a /tmp/raidlab
#   5. Archivos sparse de disco e imágenes temporales (/tmp/raidlab)
#
# Uso:
#   sudo ./limpiar_raid_lvm.sh
# ==============================================================================

set -uo pipefail

# Colores ANSI para salida en consola
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_CYAN="\033[0;36m"
C_DIM="\033[2m"

# 1. Verificación de privilegios de superusuario
if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Error: Este script requiere privilegios de root.${C_RESET}"
    echo -e "Ejecutá: ${C_BOLD}sudo $0${C_RESET}"
    exit 1
fi

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 🧹 LIMPIEZA AUTOMATIZADA: LAB 3.9 RAID CON LVM (dm-raid)             ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}\n"

VG_NAME="vg_raidlab"
MNT_DIR="/mnt/raidlab_lvm"
WORKDIR="/tmp/raidlab"

# ------------------------------------------------------------------------------
# Paso 1: Desmontar el sistema de archivos
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}[1/5] Verificando montajes del filesystem...${C_RESET}"
if mountpoint -q "$MNT_DIR" 2>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Desmontando ${MNT_DIR}...${C_RESET}"
    # Si algún proceso retiene el directorio, intentar desmontaje normal y luego forzado/lazy
    umount "$MNT_DIR" 2>/dev/null || umount -l "$MNT_DIR" 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Filesystem desmontado.${C_RESET}"
else
    echo -e "  ${C_DIM}• No se detectó ningún montaje en ${MNT_DIR}.${C_RESET}"
fi

if [ -d "$MNT_DIR" ]; then
    rmdir "$MNT_DIR" 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Directorio de montaje ${MNT_DIR} eliminado.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# Paso 2: Desactivar y eliminar Volume Group y Logical Volumes
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[2/5] Verificando grupos de volúmenes LVM (${VG_NAME})...${C_RESET}"
if vgdisplay "$VG_NAME" &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Desactivando volúmenes lógicos en ${VG_NAME}...${C_RESET}"
    lvchange -an "$VG_NAME" 2>/dev/null || true

    echo -e "  ${C_YELLOW}⚠ Eliminando Volume Group ${VG_NAME}...${C_RESET}"
    vgremove -f -y "$VG_NAME" 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Volume Group ${VG_NAME} eliminado exitosamente.${C_RESET}"
else
    echo -e "  ${C_DIM}• El Volume Group ${VG_NAME} no existe o ya fue eliminado.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# Paso 3: Limpiar firmas de Physical Volumes (PVs) y wipefs
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[3/5] Limpiando firmas de Physical Volumes (PV)...${C_RESET}"
# Detectar loop devices asociados al directorio del laboratorio
RAID_LOOPS=$(losetup -a 2>/dev/null | grep "$WORKDIR" | cut -d: -f1 || true)

if [ -n "$RAID_LOOPS" ]; then
    for dev in $RAID_LOOPS; do
        if [ -b "$dev" ]; then
            echo -e "  ${C_YELLOW}• Limpiando PV y firmas en ${dev}...${C_RESET}"
            pvremove -ff -y "$dev" 2>/dev/null || true
            wipefs -a "$dev" 2>/dev/null || true
        fi
    done
    echo -e "  ${C_GREEN}✔ Firmas LVM y superbloques removidos de los dispositivos loop.${C_RESET}"
else
    echo -e "  ${C_DIM}• No se encontraron loop devices activos con firmas de ${WORKDIR}.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# Paso 4: Desconectar los Loop Devices
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[4/5] Desconectando Loop Devices del kernel...${C_RESET}"
if [ -n "$RAID_LOOPS" ]; then
    for dev in $RAID_LOOPS; do
        if [ -b "$dev" ]; then
            losetup -d "$dev" 2>/dev/null || true
            echo -e "  ${C_GREEN}✔ Dispositivo ${dev} desconectado.${C_RESET}"
        fi
    done
else
    echo -e "  ${C_DIM}• No hay loop devices asociados a ${WORKDIR}.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# Paso 5: Eliminar archivos de disco sparse e imágenes temporales
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[5/5] Eliminando archivos de imagen y temporales en disco...${C_RESET}"
if [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
    echo -e "  ${C_GREEN}✔ Directorio ${WORKDIR} eliminado.${C_RESET}"
else
    echo -e "  ${C_DIM}• El directorio ${WORKDIR} no existe.${C_RESET}"
fi

if [ -f "/tmp/sha_lvm.txt" ]; then
    rm -f "/tmp/sha_lvm.txt"
    echo -e "  ${C_GREEN}✔ Archivo temporal /tmp/sha_lvm.txt eliminado.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# Resumen y Verificación de Estado Final
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "${C_BOLD}🔍 ESTADO FINAL DEL SISTEMA:${C_RESET}"

VGS_CHECK=$(vgs "$VG_NAME" 2>&1 || true)
if echo "$VGS_CHECK" | grep -q "not found"; then
    echo -e " • Volume Group ${VG_NAME}: ${C_GREEN}✔ NO EXISTE (Limpio)${C_RESET}"
else
    echo -e " • Volume Group ${VG_NAME}: ${C_RED}⚠ Aún presente en el sistema${C_RESET}"
fi

MOUNT_CHECK=$(mount | grep "$MNT_DIR" || true)
if [ -z "$MOUNT_CHECK" ]; then
    echo -e " • Punto de montaje ${MNT_DIR}: ${C_GREEN}✔ DESMONTADO (Limpio)${C_RESET}"
else
    echo -e " • Punto de montaje ${MNT_DIR}: ${C_RED}⚠ Sigue montado${C_RESET}"
fi

LOOPS_CHECK=$(losetup -a 2>/dev/null | grep "$WORKDIR" || true)
if [ -z "$LOOPS_CHECK" ]; then
    echo -e " • Loop devices de ${WORKDIR}: ${C_GREEN}✔ CERO DISPOSITIVOS (Limpio)${C_RESET}"
else
    echo -e " • Loop devices de ${WORKDIR}: ${C_RED}⚠ Quedaron dispositivos activos: ${LOOPS_CHECK}${C_RESET}"
fi

echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}✔ Todo lo creado en el lab raid_lvm.md fue purgado correctamente.${C_RESET}\n"
