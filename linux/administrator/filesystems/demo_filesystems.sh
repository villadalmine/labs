#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Anatomía de Sistemas de Archivos en Linux
# ext4, XFS, Btrfs, tmpfs, tune2fs, Agotamiento de Inodos y Rescate de Superbloque
#
# Uso:
#   sudo ./demo_filesystems.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No desmontar ni limpiar al finalizar (dejar montado)
# ==============================================================================

# Si se ejecuta en tmux, activar scroll con la rueda del ratón
if [ -n "$TMUX" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

# Paleta de colores didáctica
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
RESET='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Este script requiere privilegios de superusuario (sudo).${RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_RUNNING=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

pause_step() {
    local mensaje="${1:-Presiona [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${YELLOW}[MODO AUTOMÁTICO] Esperando ${AUTO_DELAY}s: ${mensaje}${RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${YELLOW}>>> ${mensaje}${RESET}"
        read -r
    fi
}

DIR_LAB="/tmp/lab_demo_fs"
MNT_EXT4="/mnt/lab_demo_ext4"
MNT_XFS="/mnt/lab_demo_xfs"
MNT_BTRFS="/mnt/lab_demo_btrfs"
MNT_RAM="/mnt/lab_demo_ram"

LOOP_EXT4=""
LOOP_XFS=""
LOOP_BTRFS=""
LOOP_INODE=""

cleanup() {
    echo -e "\n${YELLOW}=== Limpieza de recursos del laboratorio ===${RESET}"
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${GREEN}[INFO] Se mantienen los montajes activos por opción --keep.${RESET}"
        echo -e "${CYAN}Puntos de montaje activos:${RESET}"
        df -h | grep "/mnt/lab_demo" || true
        return
    fi

    # Desmontar puntos de montaje
    for m in "$MNT_EXT4" "$MNT_XFS" "$MNT_BTRFS" "$MNT_RAM" "/mnt/lab_demo_inode"; do
        if mountpoint -q "$m" 2>/dev/null; then
            echo "Desmontando: $m..."
            umount -f "$m" 2>/dev/null || true
        fi
        rm -rf "$m" 2>/dev/null || true
    done

    # Desasociar loop devices
    for l in "$LOOP_EXT4" "$LOOP_XFS" "$LOOP_BTRFS" "$LOOP_INODE"; do
        if [ -n "$l" ]; then
            echo "Liberando loop device: $l..."
            losetup -d "$l" 2>/dev/null || true
        fi
    done

    rm -rf "$DIR_LAB"
    echo -e "${GREEN}[OK] Laboratorio limpio correctamente.${RESET}"
}

trap cleanup EXIT INT TERM

clear
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${BOLD}${CYAN}   ANATOMÍA DE SISTEMAS DE ARCHIVOS EN LINUX (ext4, XFS, Btrfs, tmpfs)  ${RESET}"
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${CYAN}Conceptos clave: VFS | Superbloques | Inodos vs Bloques | tune2fs | Rescate${RESET}"
echo -e "${CYAN}Arquitectura: Agnóstico mediante Discos Virtuales Loop (WSL2, VM o EC2)${RESET}"
echo -e "${PURPLE}------------------------------------------------------------------------${RESET}"

# ==============================================================================
# PASO 1: VERIFICAR HERRAMIENTAS DEL SISTEMA
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 1] Verificando herramientas del sistema operativo...${RESET}"
MISSING_PKGS=()
for tool in mkfs.ext4 tune2fs dumpe2fs mkfs.xfs xfs_info xfs_admin xfs_growfs mkfs.btrfs btrfs losetup; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_PKGS+=("$tool")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Faltan herramientas: ${MISSING_PKGS[*]}. Instalando e2fsprogs, xfsprogs, btrfs-progs...${RESET}"
    apt-get update -qq && apt-get install -y -qq e2fsprogs xfsprogs btrfs-progs util-linux
fi
echo -e "${GREEN}✓ Todas las herramientas necesarias están disponibles.${RESET}"

mkdir -p "$DIR_LAB" "$MNT_EXT4" "$MNT_XFS" "$MNT_BTRFS" "$MNT_RAM"

pause_step "Avanzar para crear discos virtuales loop y analizar ext4 con tune2fs..."

# ==============================================================================
# PASO 2: EXT4 AL DETALLE: SUPERBLOQUE Y GESTIÓN CON TUNE2FS
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 2] Creación de Disco ext4 y Análisis de Superbloque${RESET}"
echo -e "Creando disco virtual de 300 MB..."
dd if=/dev/zero of="$DIR_LAB/disco_ext4.img" bs=1M count=300 status=none
LOOP_EXT4=$(losetup -f --show "$DIR_LAB/disco_ext4.img")

echo -e "Asociado a: ${GREEN}${LOOP_EXT4}${RESET}"
echo -e "Formateando con ext4 (Bloque de 4096 bytes y etiqueta DISCO_EXT4)..."
mkfs.ext4 -q -b 4096 -L "DISCO_EXT4" "$LOOP_EXT4"

echo -e "\n${BOLD}1) Leyendo el Superbloque con tune2fs -l:${RESET}"
tune2fs -l "$LOOP_EXT4" | grep -E "(Filesystem volume name|Filesystem state|Block size|Inode count|Reserved block count)"

echo -e "\n${BOLD}2) Reclamando bloques reservados con tune2fs -m (El truco del SysAdmin):${RESET}"
echo -e "Por defecto, ext4 reserva el 5% del disco para root. En discos de datos podemos reducirlo al 1%:"
tune2fs -m 1 "$LOOP_EXT4" >/dev/null
echo -e "Nuevo estado de bloques reservados: ${GREEN}$(tune2fs -l "$LOOP_EXT4" | grep 'Reserved block count')${RESET}"

echo -e "\n${BOLD}3) Modificando la etiqueta del volumen con tune2fs -L:${RESET}"
tune2fs -L "DATA_PROD" "$LOOP_EXT4" >/dev/null
echo -e "Identificación del volumen: ${CYAN}$(lsblk -f "$LOOP_EXT4" | grep -v FSTYPE)${RESET}"

mount "$LOOP_EXT4" "$MNT_EXT4"
echo -e "${GREEN}✓ ext4 montado exitosamente en: $MNT_EXT4${RESET}"

pause_step "Avanzar para simular la catástrofe de producción: Inodos agotados vs Espacio..."

# ==============================================================================
# PASO 3: DESASTRE EN PRODUCCIÓN: AGOTAMIENTO DE INODOS VS ESPACIO
# ==============================================================================
echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${BOLD}${RED}  CASO REAL DE PRODUCCIÓN 1: 'NO SPACE LEFT ON DEVICE' CON DISCO VACÍO  ${RESET}"
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "Explicación:"
echo -e "  * ${BOLD}df -h${RESET} mide espacio físico en bloques (Gigabytes)."
echo -e "  * ${BOLD}df -i${RESET} mide la tabla de inodos (cantidad de archivos permitidos)."
echo -e "  * Si un script genera millones de archivos vacíos (0 bytes), los inodos se agotan"
echo -e "    y el sistema bloquea cualquier nueva escritura, ¡aunque el disco esté al 95% libre!"

mkdir -p /mnt/lab_demo_inode
dd if=/dev/zero of="$DIR_LAB/disco_inode.img" bs=1M count=20 status=none
LOOP_INODE=$(losetup -f --show "$DIR_LAB/disco_inode.img")
# Formatear forzando solo 512 inodos
mkfs.ext4 -q -N 512 "$LOOP_INODE"
mount "$LOOP_INODE" /mnt/lab_demo_inode

echo -e "\n${BOLD}Estado inicial antes de la tormenta de archivos:${RESET}"
printf "%-25s %-15s %-15s\n" "COMANDO" "USO" "ESTADO"
printf "%-25s %-15s %-15s\n" "df -h (Espacio físico)" "$(df -h /mnt/lab_demo_inode | awk 'NR==2 {print $5}')" "Mucho espacio libre"
printf "%-25s %-15s %-15s\n" "df -i (Inodos disponibles)" "$(df -i /mnt/lab_demo_inode | awk 'NR==2 {print $5}')" "Inodos disponibles"

echo -e "\n${YELLOW}Simulando servicio que genera cientos de archivos de sesión vacíos (0 bytes)...${RESET}"
bash -c 'for i in $(seq 1 520); do touch /mnt/lab_demo_inode/sesion_$i.tmp; done 2>/dev/null || true'

echo -e "\nIntentando crear un archivo nuevo esencial: ${CYAN}touch /mnt/lab_demo_inode/archivo_critico.txt${RESET}"
TOUCH_OUT=$(touch /mnt/lab_demo_inode/archivo_critico.txt 2>&1 || true)
echo -e "${RED}[ERROR OBTENIDO] $TOUCH_OUT${RESET}"

echo -e "\n${BOLD}Diagnóstico Forense comparado:${RESET}"
echo -e "  ${YELLOW}1. df -h (Espacio en Bloques):${RESET}"
df -h /mnt/lab_demo_inode | head -n 2
echo -e "  ${RED}2. df -i (Inodos del Sistema):${RESET}"
df -i /mnt/lab_demo_inode | head -n 2

echo -e "\n${GREEN}--> Lección de SysAdmin: Siempre diagnosticar con 'df -h' Y 'df -i' en conjunto.${RESET}"

umount /mnt/lab_demo_inode
losetup -d "$LOOP_INODE"
rm -f "$DIR_LAB/disco_inode.img"

pause_step "Avanzar para simular la catástrofe 2: Superbloque dañado y rescate..."

# ==============================================================================
# PASO 4: DESASTRE EN PRODUCCIÓN: SUPERBLOQUE CORRUPTO Y RECUPERACIÓN
# ==============================================================================
echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${BOLD}${RED}  CASO REAL DE PRODUCCIÓN 2: CORRUPCIÓN DE SUPERBLOQUE Y RESCATE FSCK  ${RESET}"
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"

umount "$MNT_EXT4"

echo -e "1) Localizando los Superbloques de Respaldo (Backup Superblocks)..."
BACKUP_BLOCK=$(dumpe2fs "$LOOP_EXT4" 2>/dev/null | grep -i "Backup superblock at" | head -n 1 | awk '{print $4}' | tr -d ',')
[ -z "$BACKUP_BLOCK" ] && BACKUP_BLOCK="32768"
echo -e "Superbloque de respaldo identificado en el bloque: ${GREEN}${BACKUP_BLOCK}${RESET}"

echo -e "\n2) ${RED}[INYECCIÓN DE FALLA] Destruyendo intencionalmente el Superbloque Primario con dd...${RESET}"
dd if=/dev/urandom of="$LOOP_EXT4" bs=1024 count=4 seek=1 conv=notrunc status=none

echo -e "Intentando montar el sistema de archivos dañado:"
MOUNT_ERR=$(mount "$LOOP_EXT4" "$MNT_EXT4" 2>&1 || true)
echo -e "${RED}[FALLO DE KERNEL] $MOUNT_ERR${RESET}"

pause_step "Presiona [ENTER] para iniciar la Operación de Rescate con e2fsck..."

echo -e "\n3) ${GREEN}[OPERACIÓN DE RESCATE] Reparando usando el Superbloque de Respaldo en bloque ${BACKUP_BLOCK}...${RESET}"
e2fsck -b "$BACKUP_BLOCK" -y "$LOOP_EXT4" >/dev/null 2>&1 || true

echo -e "4) Comprobando si el sistema de archivos resucitó:"
mount "$LOOP_EXT4" "$MNT_EXT4"
if mountpoint -q "$MNT_EXT4"; then
    echo -e "${BOLD}${GREEN}✓ ¡ÉXITO TOTAL! El sistema de archivos fue recuperado y montado intacto.${RESET}"
    df -h "$MNT_EXT4"
else
    echo -e "${RED}[ERROR] No se pudo montar tras la reparación.${RESET}"
fi

pause_step "Avanzar para explorar XFS (Allocation Groups y Expansión en Caliente)..."

# ==============================================================================
# PASO 5: XFS AL DETALLE: ALLOCATION GROUPS Y EXPANSION EN CALIENTE
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 5] XFS en Profundidad: Allocation Groups y xfs_growfs${RESET}"
echo -e "Creando disco virtual de 300 MB para XFS..."
dd if=/dev/zero of="$DIR_LAB/disco_xfs.img" bs=1M count=300 status=none
LOOP_XFS=$(losetup -f --show "$DIR_LAB/disco_xfs.img")

mkfs.xfs -q -L "STORAGE_XFS" "$LOOP_XFS"
mount "$LOOP_XFS" "$MNT_XFS"
echo -e "XFS montado en: ${GREEN}${MNT_XFS}${RESET}"

echo -e "\n${BOLD}1) Geometría interna de XFS con xfs_info:${RESET}"
xfs_info "$MNT_XFS" | grep -E "(data|naming|log)"

echo -e "\n${BOLD}2) Ampliación en caliente (Online Growth):${RESET}"
echo -e "Aumentando el archivo de disco de 300 MB a 600 MB en caliente..."
truncate -s 600M "$DIR_LAB/disco_xfs.img"
losetup -c "$LOOP_XFS"

echo -e "Tamaño antes de xfs_growfs: $(df -h "$MNT_XFS" | awk 'NR==2 {print $2}')"
xfs_growfs "$MNT_XFS" >/dev/null
echo -e "Tamaño después de xfs_growfs: ${GREEN}$(df -h "$MNT_XFS" | awk 'NR==2 {print $2}')${RESET}"
echo -e "${YELLOW}Nota clave: XFS se puede agrandar en caliente, pero NUNCA se puede reducir de tamaño.${RESET}"

pause_step "Avanzar para explorar Btrfs (Copy-on-Write y Snapshots Instantáneos)..."

# ==============================================================================
# PASO 6: BTRFS AL DETALLE: SUBVOLÚMENES Y SNAPSHOTS O(1)
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 6] Btrfs en Profundidad: Subvolúmenes y Snapshots Instantáneos${RESET}"
dd if=/dev/zero of="$DIR_LAB/disco_btrfs.img" bs=1M count=300 status=none
LOOP_BTRFS=$(losetup -f --show "$DIR_LAB/disco_btrfs.img")

mkfs.btrfs -q -L "STORAGE_BTRFS" "$LOOP_BTRFS"
mount "$LOOP_BTRFS" "$MNT_BTRFS"

echo -e "1) Creando subvolumen independiente @app_data..."
btrfs subvolume create "$MNT_BTRFS/@app_data" >/dev/null

echo -e "2) Creando archivo de 20 MB en el subvolumen..."
dd if=/dev/urandom of="$MNT_BTRFS/@app_data/base_de_datos.bin" bs=1M count=20 status=none

echo -e "3) Creando SNAPSHOT instantáneo con Copy-on-Write:"
START_SNAP=$(date +%s%N)
btrfs subvolume snapshot "$MNT_BTRFS/@app_data" "$MNT_BTRFS/@snapshot_seguridad" >/dev/null
END_SNAP=$(date +%s%N)
TIEMPO_MS=$(( (END_SNAP - START_SNAP) / 1000000 ))

echo -e "${GREEN}✓ Snapshot creado en ${TIEMPO_MS} ms con 0 bytes de consumo extra.${RESET}"
btrfs filesystem df "$MNT_BTRFS"

pause_step "Avanzar para explorar tmpfs (Almacenamiento en Memoria RAM)..."

# ==============================================================================
# PASO 7: TMPFS: VELOCIDAD Y VOLATILIDAD EN MEMORIA RAM
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 7] tmpfs: Rendimiento Extremo en Memoria RAM${RESET}"
mount -t tmpfs -o size=100M tmpfs "$MNT_RAM"
echo -e "tmpfs montado en ${GREEN}${MNT_RAM}${RESET} (Límite: 100 MB de RAM)"

echo -e "\nComparativa de velocidad de escritura:"
echo -e "Escribiendo 50 MB en Disco Virtual Loop..."
dd if=/dev/zero of="$DIR_LAB/test_disk.bin" bs=1M count=50 conv=fdatasync 2>&1 | grep -E "copied"

echo -e "Escribiendo 50 MB en Memoria RAM (tmpfs)..."
dd if=/dev/zero of="$MNT_RAM/test_ram.bin" bs=1M count=50 conv=fdatasync 2>&1 | grep -E "copied"

pause_step "Avanzar para ver la Matriz de Síntesis del Laboratorio..."

# ==============================================================================
# PASO 8: RESUMEN Y MATRIZ COMPARATIVA DE SÍNTESIS
# ==============================================================================
echo -e "\n${BOLD}${CYAN}========================================================================${RESET}"
echo -e "${BOLD}${CYAN}            MATRIZ DE SÍNTESIS DE SISTEMAS DE ARCHIVOS LINUX            ${RESET}"
echo -e "${BOLD}${CYAN}========================================================================${RESET}"

printf "${BOLD}%-10s %-25s %-20s %-20s${RESET}\n" "FS" "PARADIGMA" "HERRAMIENTA CLAVE" "CASO DE PRODUCCIÓN"
printf "%-10s %-25s %-20s %-20s\n" "----------" "-------------------------" "--------------------" "--------------------"
printf "%-10s %-25s %-20s %-20s\n" "ext4" "Journaling / Bloques" "tune2fs, dumpe2fs" "General, compatibilidad"
printf "%-10s %-25s %-20s %-20s\n" "XFS" "Allocation Groups" "xfs_info, xfs_growfs" "Bases de datos, RHEL/Rocky"
printf "%-10s %-25s %-20s %-20s\n" "Btrfs" "Copy-on-Write (CoW)" "btrfs subvolume/scrub" "Snapshots, NAS, NextGen"
printf "%-10s %-25s %-20s %-20s\n" "tmpfs" "Memoria RAM Volátil" "mount -t tmpfs" "Caché, sockets, /tmp"

echo -e "\n${BOLD}${GREEN}¡Laboratorio completado exitosamente!${RESET}"
echo -e "${PURPLE}========================================================================${RESET}"
