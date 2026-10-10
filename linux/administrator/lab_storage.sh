#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LABORATORIO: LVM2 + EXTENSIÓN EN CALIENTE + LOOP DEVICES + FUSE
# Entorno: Debian / CentOS / RHEL / Ubuntu
# Uso: sudo bash lab_storage.sh [run|clean]
# ==============================================================================

set -e

DIR_IMG="/tmp/lab_storage"
MOUNT_LVM="/mnt/lab_lvm"
MOUNT_CIFRADO="$HOME/datos_cifrados"
MOUNT_VISIBLE="$HOME/datos_visibles"

color_green="\030[0;32m"
color_cyan="\033[0;36m"
color_yellow="\033[1;33m"
color_reset="\033[0m"

info() {
    echo -e "${color_cyan}[INFO]${color_reset} $1"
}

success() {
    echo -e "${color_green}[OK]${color_reset} $1"
}

step_title() {
    echo -e "\n${color_yellow}=====================================================${color_reset}"
    echo -e "${color_yellow}  $1${color_reset}"
    echo -e "${color_yellow}=====================================================${color_reset}\n"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Este script requiere privilegios de superusuario (sudo)."
        exit 1
    fi
}

cleanup() {
    step_title "PASO DE LIMPIEZA DEL ENTORNO DE PRUEBAS"
    
    info "Desmontando puntos de montaje..."
    umount -f "$MOUNT_LVM" 2>/dev/null || true
    umount -f "$MOUNT_VISIBLE" 2>/dev/null || true
    
    info "Removiendo LVM (LV, VG, PV)..."
    lvremove -f /dev/vg_lab/lv_datos 2>/dev/null || true
    vgremove -f vg_lab 2>/dev/null || true
    pvremove -f /dev/loop20 /dev/loop21 /dev/loop22 2>/dev/null || true
    
    info "Desvinculando Loop Devices..."
    losetup -d /dev/loop20 2>/dev/null || true
    losetup -d /dev/loop21 2>/dev/null || true
    losetup -d /dev/loop22 2>/dev/null || true
    
    info "Eliminando archivos de imagen temporales y directorios..."
    rm -rf "$DIR_IMG" "$MOUNT_LVM" "$MOUNT_CIFRADO" "$MOUNT_VISIBLE"
    
    success "Entorno limpio correctamente."
}

run_lab() {
    check_root
    
    step_title "1. CREACIÓN DE DISCOS VIRTUALES (LOOP DEVICES)"
    mkdir -p "$DIR_IMG" "$MOUNT_LVM"
    
    info "Creando 3 imágenes de disco dispersas (sparse files) de 2GB cada una..."
    truncate -s 2G "$DIR_IMG/disk1.img"
    truncate -s 2G "$DIR_IMG/disk2.img"
    truncate -s 2G "$DIR_IMG/disk3.img"
    
    info "Asociando las imágenes a loop devices (/dev/loop20, /dev/loop21, /dev/loop22)..."
    losetup /dev/loop20 "$DIR_IMG/disk1.img"
    losetup /dev/loop21 "$DIR_IMG/disk2.img"
    losetup /dev/loop22 "$DIR_IMG/disk3.img"
    
    losetup -a | grep loop2
    success "Loop devices configurados e inspeccionados."
    
    step_title "2. INICIALIZACIÓN DE LVM2 (PV, VG, LV)"
    info "Inicializando Volúmenes Físicos (PV)..."
    pvcreate /dev/loop20 /dev/loop21 /dev/loop22
    
    info "Creando Grupo de Volúmenes (VG) 'vg_lab'..."
    vgcreate vg_lab /dev/loop20 /dev/loop21 /dev/loop22
    
    info "Creando Volumen Lógico (LV) 'lv_datos' inicial de 1GB..."
    lvcreate -L 1G -n lv_datos vg_lab
    
    info "Formateando LV con ext4..."
    mkfs.ext4 /dev/vg_lab/lv_datos
    
    info "Montando el volumen en $MOUNT_LVM..."
    mount /dev/vg_lab/lv_datos "$MOUNT_LVM"
    
    echo "=== ESTADO INICIAL DEL DISCO MONTADO ==="
    df -h "$MOUNT_LVM"
    
    step_title "3. EXTENSIÓN EN CALIENTE (ONLINE RESIZE)"
    info "Escribiendo datos de prueba en el punto de montaje antes de extender..."
    dd if=/dev/urandom of="$MOUNT_LVM/test_file.bin" bs=1M count=200 status=none
    ls -lh "$MOUNT_LVM/test_file.bin"
    
    info "Ampliando el LV en +1.5GB en caliente (lvextend)..."
    lvextend -L +1.5G /dev/vg_lab/lv_datos
    
    info "Expandiendo el sistema de archivos ext4 online sin desmontar (resize2fs)..."
    resize2fs /dev/vg_lab/lv_datos
    
    success "Extensión completada con éxito."
    echo "=== ESTADO FINAL DEL DISCO TRAS EXTENSIÓN EN CALIENTE ==="
    df -h "$MOUNT_LVM"
    
    step_title "4. DEMOSTRACIÓN DE CAPA FUSE (GOCRYPTFS)"
    if command -v gocryptfs &> /dev/null; then
        info "gocryptfs está instalado. Creando estructura de prueba FUSE..."
        mkdir -p "$MOUNT_CIFRADO" "$MOUNT_VISIBLE"
        success "Carpetas preparadas: $MOUNT_CIFRADO y $MOUNT_VISIBLE"
        echo "Para probar gocryptfs interactivamente ejecute:"
        echo "  gocryptfs -init $MOUNT_CIFRADO"
        echo "  gocryptfs $MOUNT_CIFRADO $MOUNT_VISIBLE"
    else
        info "gocryptfs no está instalado actualmente. (Instalar con: apt install gocryptfs / dnf install gocryptfs)"
    fi
    
    step_title "LABORATORIO CONCLUIDO CON ÉXITO"
    echo "Para limpiar todo el laboratorio, ejecute: sudo bash $0 clean"
}

case "$1" in
    clean)
        check_root
        cleanup
        ;;
    run|"")
        run_lab
        ;;
    *)
        echo "Uso: $0 [run|clean]"
        exit 1
        ;;
esac
