#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Trabajo Integrador 4
# Btrfs: Subvolúmenes, Reflinks Zero-Copy, Conversión RAID 1 en Caliente,
# Replicación btrfs send/receive, Scrub y Reemplazo de Discos
#
# Uso:
#   sudo ./demo_integrador_btrfs.sh [opciones] [DISCO_PRI1 DISCO_PRI2 DISCO_PRI3 DISCO_REP1]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No desmontar ni limpiar los recursos al finalizar
# ==============================================================================

if [ -n "$TMUX" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
RESET='\033[0m'

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false
LOOP_MODE=false

POSITIONAL_ARGS=()
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
            POSITIONAL_ARGS+=("$1")
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

header() {
    echo -e "\n${CYAN}======================================================================${RESET}"
    echo -e "${BOLD}${CYAN} $1 ${RESET}"
    echo -e "${CYAN}======================================================================${RESET}"
}

subheader() {
    echo -e "\n${PURPLE}--- $1 ---${RESET}"
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Este script interactivo de Btrfs requiere privilegios de root.${RESET}"
    echo -e "Por favor, ejecútalo con: ${BOLD}sudo $0${RESET}"
    exit 1
fi

LAB_DIR="/var/tmp/lab_btrfs_demo"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR" || exit 1

LOOP_DEVS=()

cleanup() {
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "\n${GREEN}[INFO] Se seleccionó --keep. Los montajes de Btrfs quedan activos para inspección.${RESET}"
        return
    fi

    echo -e "\n${YELLOW}[LIMPIEZA] Desmontando subvolúmenes y liberando dispositivos de prueba...${RESET}"
    umount -l "$LAB_DIR/mnt_replica" 2>/dev/null || true
    umount -l "$LAB_DIR/mnt_snapshots" 2>/dev/null || true
    umount -l "$LAB_DIR/mnt_data" 2>/dev/null || true
    umount -l "$LAB_DIR/mnt_app" 2>/dev/null || true
    umount -l "$LAB_DIR/mnt_raw" 2>/dev/null || true

    if [ "$LOOP_MODE" = true ]; then
        for dev in "${LOOP_DEVS[@]}"; do
            losetup -d "$dev" 2>/dev/null || true
        done
        rm -rf "$LAB_DIR" 2>/dev/null || true
    fi

    echo -e "${GREEN}[OK] Limpieza de Btrfs finalizada correctamente.${RESET}"
}
trap cleanup EXIT INT TERM

# ==============================================================================
# FASE 0: PREPARACIÓN DE DISCOS Y HERRAMIENTAS
# ==============================================================================
header "FASE 0: Detección de Discos y Prerrequisitos de Btrfs"

if ! command -v btrfs &>/dev/null; then
    echo -e "${YELLOW}Instalando btrfs-progs...${RESET}"
    apt-get update -qq && apt-get install -y -qq btrfs-progs
fi

if [ ${#POSITIONAL_ARGS[@]} -ge 4 ]; then
    DISCO_PRI_1="${POSITIONAL_ARGS[0]}"
    DISCO_PRI_2="${POSITIONAL_ARGS[1]}"
    DISCO_PRI_3="${POSITIONAL_ARGS[2]}"
    DISCO_REP_1="${POSITIONAL_ARGS[3]}"
    echo -e "${GREEN}[INFO] Utilizando discos físicos proporcionados por parámetro:${RESET}"
else
    echo -e "${YELLOW}[INFO] Creando 4 loop devices de 1 GB para simulación Btrfs...${RESET}"
    LOOP_MODE=true
    for i in 1 2 3 4; do
        img="$LAB_DIR/disk_btrfs_${i}.img"
        truncate -s 1G "$img"
        dev=$(losetup -fP --show "$img")
        LOOP_DEVS+=("$dev")
    done
    DISCO_PRI_1="${LOOP_DEVS[0]}"
    DISCO_PRI_2="${LOOP_DEVS[1]}"
    DISCO_PRI_3="${LOOP_DEVS[2]}"
    DISCO_REP_1="${LOOP_DEVS[3]}"
fi

echo -e "  * ${BOLD}Disco Primario 1 (Base Inicial):${RESET}     $DISCO_PRI_1"
echo -e "  * ${BOLD}Disco Primario 2 (Hot-Add RAID 1):${RESET}   $DISCO_PRI_2"
echo -e "  * ${BOLD}Disco Primario 3 (Hot-Replace Disco):${RESET}$DISCO_PRI_3"
echo -e "  * ${BOLD}Disco Réplica    (Destino DR):${RESET}       $DISCO_REP_1"

pause_step "Formatear Disco 1 y crear subvolúmenes jerárquicos..."

# ==============================================================================
# FASE 1: FORMATEO BTRFS Y CREACIÓN DE SUBVOLÚMENES
# ==============================================================================
header "FASE 1: Formateo Btrfs y Creación de Subvolúmenes"
echo -e "${CYAN}TEORÍA CLAVE:${RESET}"
echo -e "Un subvolumen Btrfs es un árbol de inodos independiente que comparte el espacio total del pool."

mkfs.btrfs -f -L BTRFS_LAB "$DISCO_PRI_1"

mkdir -p "$LAB_DIR/mnt_raw"
mount "$DISCO_PRI_1" "$LAB_DIR/mnt_raw"

subheader "1.1 Creando subvolúmenes @app, @data y @snapshots"
btrfs subvolume create "$LAB_DIR/mnt_raw/@app"
btrfs subvolume create "$LAB_DIR/mnt_raw/@data"
btrfs subvolume create "$LAB_DIR/mnt_raw/@snapshots"

echo -e "\nLista de subvolúmenes creados:"
btrfs subvolume list "$LAB_DIR/mnt_raw"

umount "$LAB_DIR/mnt_raw"

pause_step "Montar subvolúmenes con compresión ZSTD..."

# ==============================================================================
# FASE 2: MONTAJE CON COMPRESIÓN TRANSPARENTE ZSTD:3
# ==============================================================================
header "FASE 2: Montaje Avanzado con Compresión Transparente ZSTD:3"

mkdir -p "$LAB_DIR/mnt_app" "$LAB_DIR/mnt_data" "$LAB_DIR/mnt_snapshots"

echo -e "Montando @data con opción compress=zstd:3:"
mount -o subvol=@app,compress=zstd:3 "$DISCO_PRI_1" "$LAB_DIR/mnt_app"
mount -o subvol=@data,compress=zstd:3 "$DISCO_PRI_1" "$LAB_DIR/mnt_data"
mount -o subvol=@snapshots "$DISCO_PRI_1" "$LAB_DIR/mnt_snapshots"

df -h "$LAB_DIR/mnt_app" "$LAB_DIR/mnt_data" "$LAB_DIR/mnt_snapshots"

pause_step "Probar Reflinks y Deduplicación Zero-Copy..."

# ==============================================================================
# FASE 3: REFLINKS Y DEDUPLICACIÓN ZERO-COPY
# ==============================================================================
header "FASE 3: Reflinks Zero-Copy (Clones de Archivo Instantáneos)"
echo -e "${CYAN}CAPACIDAD ÚNICA:${RESET}"
echo -e "cp --reflink=always crea un clon instantáneo apuntando a los mismos extents físicos."
echo -e "Tiempo O(1), 0 bytes extra de disco. Los deltas solo se crean al modificar."

cd "$LAB_DIR/mnt_data"
echo -e "Generando archivo maestro de transacciones (50 MB)..."
for i in $(seq 1 60000); do
    echo "TRANSACCION-SISTEMA-FINANCIERO-ID-$i-ESTADO-COMPLETADO"
done > maestro.db

echo -e "\nEspacio ocupado en Btrfs antes del clon:"
btrfs filesystem df "$LAB_DIR/mnt_data"

subheader "3.1 Clonando con cp --reflink=always"
cp --reflink=always maestro.db clon_desarrollo.db

echo -e "Listado de archivos (ambos reportan el mismo tamaño lógico):"
ls -lh maestro.db clon_desarrollo.db

echo -e "\nEspacio físico ocupado tras el clon (¡CERO BYTES ADICIONALES!):"
btrfs filesystem df "$LAB_DIR/mnt_data"

pause_step "Convertir el disco en caliente a RAID 1 con btrfs balance..."

# ==============================================================================
# FASE 4: CONVERSIÓN EN CALIENTE A RAID 1 CON BTRFS BALANCE
# ==============================================================================
header "FASE 4: Conversión en Caliente de Single a RAID 1 con Rebalance"

subheader "4.1 Añadir segundo disco al filesystem montado"
echo "$ sudo btrfs device add $DISCO_PRI_2 $LAB_DIR/mnt_data"
btrfs device add "$DISCO_PRI_2" "$LAB_DIR/mnt_data"
btrfs filesystem show "$LAB_DIR/mnt_data"

pause_step "Iniciar el rebalanceo de datos y metadatos hacia RAID 1..."

subheader "4.2 Balancear datos (-dconvert=raid1) y metadatos (-mconvert=raid1)"
btrfs balance start -dconvert=raid1 -mconvert=raid1 "$LAB_DIR/mnt_data"

echo -e "\n${GREEN}[OK] Nueva topología RAID 1 verificada en caliente:${RESET}"
btrfs filesystem df "$LAB_DIR/mnt_data"

pause_step "Probar replicación de subvolúmenes con btrfs send/receive..."

# ==============================================================================
# FASE 5: REPLICACIÓN DE SUBVOLÚMENES CON BTRFS SEND / RECEIVE
# ==============================================================================
header "FASE 5: Replicación Remota Atómica de Subvolúmenes"

mkdir -p "$LAB_DIR/mnt_replica"
mkfs.btrfs -f -L BTRFS_BACKUP "$DISCO_REP_1"
mount "$DISCO_REP_1" "$LAB_DIR/mnt_replica"

subheader "5.1 Tomar Snapshot Solo-Lectura de @data"
btrfs subvolume snapshot -r "$LAB_DIR/mnt_data" "$LAB_DIR/mnt_snapshots/data_snap_base"

echo -e "\nEnviando snapshot hacia el volumen de réplica (btrfs send | btrfs receive):"
btrfs send "$LAB_DIR/mnt_snapshots/data_snap_base" | btrfs receive "$LAB_DIR/mnt_replica/"

echo -e "\nContenido replicado en el destino:"
ls -lh "$LAB_DIR/mnt_replica/data_snap_base"

pause_step "Simular corrupción en un disco y auto-reparar con btrfs scrub..."

# ==============================================================================
# FASE 6: CORRUPCIÓN INDUCIDA CON DD Y REPARACIÓN CON BTRFS SCRUB
# ==============================================================================
header "FASE 6: Inyección de Corrupción de Bloques y Detección con Scrub"

echo -e "Inyectando 1 MB de datos aleatorios en $DISCO_PRI_2 con dd para simular bit rot..."
dd if=/dev/urandom of="$DISCO_PRI_2" bs=1M count=1 seek=25 conv=notrunc status=none

echo -e "Ejecutando btrfs scrub en caliente:"
btrfs scrub start -B "$LAB_DIR/mnt_data"

echo -e "\nEstado del scrub y auto-curación:"
btrfs scrub status "$LAB_DIR/mnt_data"

pause_step "Reemplazar el disco dañado en caliente con btrfs replace..."

# ==============================================================================
# FASE 7: REEMPLAZO EN CALIENTE DE DISCO DAÑADO (BTRFS REPLACE)
# ==============================================================================
header "FASE 7: Reemplazo en Caliente de Disco Dañado (btrfs replace)"
echo -e "${CYAN}OPERACIÓN SIN DOWNTIME:${RESET}"
echo -e "Sustituimos el disco $DISCO_PRI_2 por el nuevo disco $DISCO_PRI_3 sin desmontar el filesystem."

echo "$ sudo btrfs replace start $DISCO_PRI_2 $DISCO_PRI_3 $LAB_DIR/mnt_data"
btrfs replace start -B "$DISCO_PRI_2" "$DISCO_PRI_3" "$LAB_DIR/mnt_data"

echo -e "\nDispositivos del filesystem tras el reemplazo exitoso:"
btrfs filesystem show "$LAB_DIR/mnt_data"

header "LABORATORIO BTRFS FINALIZADO CON ÉXITO"
echo -e "${GREEN}${BOLD}Hitos demostrados en este laboratorio:${RESET}"
echo -e "  1. Subvolúmenes independientes (@app, @data, @snapshots) compartiendo espacio dinámico."
echo -e "  2. Compresión transparente nativa ZSTD:3."
echo -e "  3. Reflinks (Zero-Copy) creando clones en O(1) con 0 bytes de sobrecarga."
echo -e "  4. Conversión en caliente de Single a RAID 1 con btrfs device add y btrfs balance."
echo -e "  5. Replicación atómica de subvolúmenes con btrfs send y btrfs receive."
echo -e "  6. Detección de sectores corruptos y auto-curación con btrfs scrub."
echo -e "  7. Reemplazo de disco en caliente con btrfs replace."

if [ "$KEEP_RUNNING" = false ]; then
    echo -e "\n${YELLOW}El script desmontará y limpiará los recursos al salir.${RESET}"
else
    echo -e "\n${GREEN}Modo --keep activo: Los montajes quedan en ejecución.${RESET}"
fi
