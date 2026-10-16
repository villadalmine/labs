#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: LVM2, Extensión en Caliente, Loop Devices y FUSE
# Basado en: linux/administrator/lab_storage.md
# Uso:
#   sudo ./demo_lab_storage.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_lab_storage.sh --auto 5 -> Modo automático (espera 5s entre pasos)
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
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"

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
    echo -e "\n${C_YELLOW}[!] Limpiando recursos del laboratorio...${C_RESET}"
    
    # Desmontar FUSE gocryptfs si estuviera montado
    if command -v fusermount &>/dev/null; then
        fusermount -u "$MOUNT_VISIBLE" 2>/dev/null || umount -f "$MOUNT_VISIBLE" 2>/dev/null || true
    fi

    # Desmontar LVM
    umount -f "$MOUNT_LVM" 2>/dev/null || true

    # Desactivar y remover LVM
    lvremove -y /dev/vg_lab/lv_datos 2>/dev/null || true
    vgremove -y vg_lab 2>/dev/null || true
    pvremove -y "$LOOP_DEV1" "$LOOP_DEV2" "$LOOP_DEV3" 2>/dev/null || true

    # Desconectar loop devices
    losetup -d "$LOOP_DEV1" 2>/dev/null || true
    losetup -d "$LOOP_DEV2" 2>/dev/null || true
    losetup -d "$LOOP_DEV3" 2>/dev/null || true

    # Eliminar directorios temporales
    rm -rf "$DIR_IMG" "$MOUNT_LVM" "$MOUNT_CIFRADO" "$MOUNT_VISIBLE" 2>/dev/null || true
    echo -e "${C_GREEN}[OK] Recursos desmontados y eliminados correctamente.${C_RESET}"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Configuración amigable para TMUX
# ------------------------------------------------------------------------------
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
    echo -e "\n${C_MAGENTA}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW} PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}======================================================================${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💬 EXPLICACIÓN:${C_RESET} $1"
}

command_info() {
    echo -e "${C_BOLD}${C_GREEN}$ ${1}${C_RESET}"
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_YELLOW}👉 ${msg}${C_RESET}"
        read -r
    fi
}

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------
step_banner "0" "Verificación de paquetes y herramientas"

explain "Comprobando la presencia de lvm, util-linux, e2fsprogs y gocryptfs."
MISSING_PKGS=()
for pkg in lvm losetup mkfs.ext4 resize2fs truncate; do
    if ! command -v "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${C_RED}[ERROR] Faltan herramientas necesarias: ${MISSING_PKGS[*]}${C_RESET}"
    echo "Instalalas con: sudo apt update && sudo apt install -y lvm2 e2fsprogs util-linux"
    exit 1
fi
echo -e "${C_GREEN}[OK] Herramientas del sistema disponibles.${C_RESET}"

pause_step "Presioná [ENTER] para comenzar con la creación de los discos virtuales..."

# ------------------------------------------------------------------------------
# 1. Creación de Discos Virtuales con Loop Devices
# ------------------------------------------------------------------------------
step_banner "1" "Discos Virtuales (Archivos dispersos y Loop Devices)"

explain "Un loop device permite asociar un archivo ordinario a un dispositivo de bloques (/dev/loopX)."
explain "Creamos 3 archivos de 2GB como 'sparse files' (archivos dispersos que no consumen espacio hasta que se escribe en ellos)."

command_info "mkdir -p $DIR_IMG $MOUNT_LVM"
mkdir -p "$DIR_IMG" "$MOUNT_LVM"

command_info "truncate -s 2G $DIR_IMG/disk1.img disk2.img disk3.img"
truncate -s 2G "$DIR_IMG/disk1.img"
truncate -s 2G "$DIR_IMG/disk2.img"
truncate -s 2G "$DIR_IMG/disk3.img"

explain "Asociamos cada archivo a los dispositivos /dev/loop20, /dev/loop21 y /dev/loop22:"
command_info "losetup $LOOP_DEV1 $DIR_IMG/disk1.img && losetup $LOOP_DEV2 $DIR_IMG/disk2.img && losetup $LOOP_DEV3 $DIR_IMG/disk3.img"
losetup "$LOOP_DEV1" "$DIR_IMG/disk1.img"
losetup "$LOOP_DEV2" "$DIR_IMG/disk2.img"
losetup "$LOOP_DEV3" "$DIR_IMG/disk3.img"

echo -e "\n${C_BOLD}Dispositivos loop configurados:${C_RESET}"
losetup -a | grep -E "loop2[0-2]"

pause_step "Presioná [ENTER] para inicializar la capa LVM (PV, VG y LV)..."

# ------------------------------------------------------------------------------
# 2. Inicialización de LVM2
# ------------------------------------------------------------------------------
step_banner "2" "Inicialización de LVM (PV -> VG -> LV)"

explain "1) PV (Physical Volume): Inicializamos los 3 loop devices para que LVM los gestione."
command_info "pvcreate $LOOP_DEV1 $LOOP_DEV2 $LOOP_DEV3"
pvcreate -y "$LOOP_DEV1" "$LOOP_DEV2" "$LOOP_DEV3"

explain "2) VG (Volume Group): Agrupamos los 3 PVs en una bolsa común de almacenamiento llamada 'vg_lab' (capacidad total ~6GB)."
command_info "vgcreate vg_lab $LOOP_DEV1 $LOOP_DEV2 $LOOP_DEV3"
vgcreate vg_lab "$LOOP_DEV1" "$LOOP_DEV2" "$LOOP_DEV3"
vgs vg_lab

explain "3) LV (Logical Volume): Creamos un volumen lógico 'lv_datos' de 1GB extraído del VG."
command_info "lvcreate -L 1G -n lv_datos vg_lab"
lvcreate -y -L 1G -n lv_datos vg_lab
lvs vg_lab

pause_step "Presioná [ENTER] para formatear el LV con ext4 y montarlo..."

# ------------------------------------------------------------------------------
# 3. Formateo y Montaje
# ------------------------------------------------------------------------------
step_banner "3" "Formateo con ext4 y punto de montaje"

explain "Creamos el sistema de archivos ext4 sobre /dev/vg_lab/lv_datos y lo montamos en $MOUNT_LVM."
command_info "mkfs.ext4 -F /dev/vg_lab/lv_datos"
mkfs.ext4 -F /dev/vg_lab/lv_datos

command_info "mount /dev/vg_lab/lv_datos $MOUNT_LVM"
mount /dev/vg_lab/lv_datos "$MOUNT_LVM"

echo -e "\n${C_BOLD}Estado inicial del punto de montaje:${C_RESET}"
df -h "$MOUNT_LVM"

pause_step "Presioná [ENTER] para escribir datos de prueba antes de ampliar en caliente..."

# ------------------------------------------------------------------------------
# 4. Escribir datos de prueba
# ------------------------------------------------------------------------------
step_banner "4" "Generación de datos en producción"

explain "Escribimos un archivo de prueba de 200MB mientras el sistema de archivos está montado y en uso."
command_info "dd if=/dev/urandom of=$MOUNT_LVM/test_file.bin bs=1M count=200 status=progress"
dd if=/dev/urandom of="$MOUNT_LVM/test_file.bin" bs=1M count=200 status=progress
ls -lh "$MOUNT_LVM/test_file.bin"

echo -e "\n${C_BOLD}Uso de disco con el archivo cargado (1GB original):${C_RESET}"
df -h "$MOUNT_LVM"

pause_step "Presioná [ENTER] para realizar la EXTENSIÓN EN CALIENTE (Online Resize)..."

# ------------------------------------------------------------------------------
# 5. Extensión en Caliente (Online Resize sin desmontar)
# ------------------------------------------------------------------------------
step_banner "5" "Extensión en caliente del LV y del Sistema de Archivos"

explain "Paso A: Ampliamos el volumen lógico en +1.5GB en LVM (pasa de 1GB a 2.5GB)."
command_info "lvextend -L +1.5G /dev/vg_lab/lv_datos"
lvextend -L +1.5G /dev/vg_lab/lv_datos

explain "Paso B: Ampliamos el sistema de archivos ext4 con resize2fs MIENTRAS SIGUE MONTADO (sin downtime)."
command_info "resize2fs /dev/vg_lab/lv_datos"
resize2fs /dev/vg_lab/lv_datos

echo -e "\n${C_BOLD}${C_GREEN}=== ESTADO FINAL TRAS LA EXTENSIÓN EN CALIENTE ===${C_RESET}"
df -h "$MOUNT_LVM"

explain "¡Mirá el tamaño! Pasó de ~1GB a ~2.5GB de forma transparente y sin interrumpir el servicio ni perder el archivo test_file.bin."

pause_step "Presioná [ENTER] para pasar a la demostración de FUSE y gocryptfs..."

# ------------------------------------------------------------------------------
# 6. Demostración de Cifrado a nivel de archivos con gocryptfs (FUSE)
# ------------------------------------------------------------------------------
step_banner "6" "Cifrado por capas con gocryptfs (FUSE)"

if ! command -v gocryptfs &>/dev/null; then
    explain "gocryptfs no está instalado. Si querés probarlo, ejecutá: sudo apt install -y gocryptfs"
else
    explain "gocryptfs cifra a nivel de archivos usando FUSE (sin tocar particiones completas)."
    explain "Requiere una carpeta para los datos cifrados y otra para la vista descifrada."
    
    mkdir -p "$MOUNT_CIFRADO" "$MOUNT_VISIBLE"
    chown -R "$REAL_USER:$REAL_USER" "$MOUNT_CIFRADO" "$MOUNT_VISIBLE" 2>/dev/null || true

    echo -e "Carpetas preparadas:"
    echo -e " - Cifrada: ${C_BOLD}$MOUNT_CIFRADO${C_RESET}"
    echo -e " - Visible: ${C_BOLD}$MOUNT_VISIBLE${C_RESET}"

    explain "Inicializamos gocryptfs con contraseña demo: 'ClaseLinux2026!':"
    command_info "echo 'ClaseLinux2026!' | gocryptfs -q -init -extpass echo -- $MOUNT_CIFRADO"
    echo "ClaseLinux2026!" | gocryptfs -q -init -extpass "echo 'ClaseLinux2026!'" "$MOUNT_CIFRADO"

    explain "Montamos la carpeta visible con FUSE:"
    command_info "gocryptfs -q -extpass 'echo ClaseLinux2026!' $MOUNT_CIFRADO $MOUNT_VISIBLE"
    gocryptfs -q -extpass "echo 'ClaseLinux2026!'" "$MOUNT_CIFRADO" "$MOUNT_VISIBLE"

    explain "Escribimos un archivo en la carpeta visible:"
    echo "Texto confidencial de la clase" > "$MOUNT_VISIBLE/secreto.txt"

    echo -e "\n${C_BOLD}Contenido visto en la carpeta visible ($MOUNT_VISIBLE):${C_RESET}"
    ls -l "$MOUNT_VISIBLE"
    cat "$MOUNT_VISIBLE/secreto.txt"

    echo -e "\n${C_BOLD}Contenido REAL almacenado en el disco ($MOUNT_CIFRADO):${C_RESET}"
    ls -l "$MOUNT_CIFRADO"

    explain "Fijate: en la carpeta cifrada los nombres de archivo y el contenido están completamente encriptados."

    command_info "fusermount -u $MOUNT_VISIBLE"
    fusermount -u "$MOUNT_VISIBLE"
    explain "Desmontado. Ahora la carpeta visible vuelve a quedar vacía y protegida."
fi

pause_step "Presioná [ENTER] para concluir la demostración y limpiar todos los recursos..."

step_banner "FIN" "Laboratorio completado"
echo -e "${C_GREEN}¡Demostración de LVM, extensión online y FUSE finalizada con éxito!${C_RESET}\n"
