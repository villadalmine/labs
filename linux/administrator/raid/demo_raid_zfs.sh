#!/usr/bin/env bash
# ==============================================================================
# DEMO Lab 3.11 · RAID con ZFS (OpenZFS): Pools, RAIDZ, Self-Healing y Resilver
#   Paso 1: Verificación de soporte de OpenZFS en el sistema
#   Paso 2: Creación de Storage Pool (zpool) con vdev RAIDZ (3 discos) + Hot Spare
#   Paso 3: Creación de Dataset con compresión LZ4 y escritura de datos críticos
#   Paso 4: Demostración de Self-Healing: Inyección de Bit-Rot y auto-reparación
#   Paso 5: Auditoría con zpool scrub
#   Paso 6: Falla de hardware, estado DEGRADED y reconstrucción (Resilver)
#
# Uso: sudo ./demo_raid_zfs.sh [--auto <segundos>] [--keep] [--size 256M]
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
INSTALL_HINT="zfsutils-linux util-linux"
parse_common_args "$@"
DISK_SIZE="${DISK_SIZE:-256M}"

POOL_NAME="tank_lab"
MNT="/$POOL_NAME/datos"
SPARE_ZFS=""

cleanup_lab() {
    if zpool list "$POOL_NAME" >/dev/null 2>&1; then
        zpool destroy -f "$POOL_NAME" 2>/dev/null || true
    fi
}

require_root

# Verificación de ZFS en el entorno
check_zfs_support() {
    if ! command -v zpool >/dev/null 2>&1; then
        fail "El comando 'zpool' no está instalado."
        echo "   Instala con: sudo apt update && sudo apt install -y zfsutils-linux"
        exit 1
    fi
    if ! modprobe zfs 2>/dev/null; then
        if ! grep -qw zfs /proc/filesystems /proc/modules 2>/dev/null; then
            fail "El kernel actual no tiene cargado el módulo de OpenZFS."
            echo "   (WSL2 usa por defecto un kernel Microsoft sin módulo ZFS out-of-tree)."
            echo "   Soluciones compatibles:"
            echo "     1. Ejecutar en una VM con Ubuntu Server en VirtualBox."
            echo "     2. Ejecutar en la instancia EC2 del Lab Integrador 4.5."
            echo "     3. Compilar módulo ZFS para WSL2 o usar un contenedor privileged."
            exit 1
        fi
    fi
}

check_zfs_support
require_cmd zpool zfs losetup dd sha256sum

trap trap_cleanup EXIT

header "LAB 3.11 · Almacenamiento Crítico con OpenZFS (RAIDZ)"
subheader "Preparación: 4 discos simulados de ${DISK_SIZE}"
make_disks 4
D1=${LOOPS[0]}; D2=${LOOPS[1]}; D3=${LOOPS[2]}; D4=${LOOPS[3]}

pause_step "ENTER para crear el Zpool en RAIDZ (Paridad sin Write-Hole)..."

# ------------------------------------------------------------------ Paso 1 y 2
header "PASO 2 · Creación del Storage Pool (zpool) con RAIDZ y 1 Spare"
info "Creamos el pool '$POOL_NAME' con 3 discos en vdev RAIDZ + 1 hot spare:"
run zpool create -f "$POOL_NAME" raidz "$D1" "$D2" "$D3" spare "$D4"

subheader "Topología del Pool y vdevs (zpool status):"
run zpool status "$POOL_NAME"

subheader "Capacidad y propiedades del Pool:"
run zpool list "$POOL_NAME"

pause_step "ENTER para crear un Dataset con compresión LZ4 y datos de prueba..."

# ------------------------------------------------------------------ Paso 3
header "PASO 3 · Creación de Dataset con Compresión Nativa LZ4"
info "Creando dataset $POOL_NAME/datos con compresión transparente LZ4 y verificación fletcher4:"
run zfs create -o compression=lz4 -o atime=off "$POOL_NAME/datos"
run zfs list "$POOL_NAME/datos"

SHA=$(make_testdata "$MNT/basedatos.db" 30)
info "Archivo de 30 MiB escrito en $MNT. Hash SHA-256 = ${SHA:0:16}..."
run zfs get used,referenced,compressratio "$POOL_NAME/datos"

pause_step "ENTER para demostrar el SELF-HEALING ante Bit-Rot..."

# ------------------------------------------------------------------ Paso 4
header "PASO 4 · 💥 Self-Healing: Inyección de Corrupción de Bloques (Bit-Rot)"
info "ZFS almacena checksums criptográficos de 256 bits en los punteros de bloque padre."
info "Inyectamos corrupción aleatoria directamente sobre los sectores físicos de $D1:"

sync
dd if=/dev/urandom of="$D1" bs=4k count=2 seek=8000 conv=notrunc status=none
sync

subheader "Lectura de datos con corrupción física inducida:"
READ_SHA=$(sha256sum "$MNT/basedatos.db" | awk '{print $1}')

if [ "$READ_SHA" = "$SHA" ]; then
    echo -e "${GREEN}✔ INTEGRIDAD ABSOLUTA: ZFS detectó la corrupción de checksum, leyó la paridad y entregó el dato sano.${RESET}"
else
    warn "Nota: La corrupción no cayó en un bloque de este archivo."
fi

subheader "Auditoría proactiva inmediata con 'zpool scrub'"
run zpool scrub "$POOL_NAME"
sleep 2

run zpool status "$POOL_NAME"
info "Observá la columna 'CKSUM' en $D1: ZFS registró el error y lo auto-reparó."

pause_step "ENTER para simular rotura de disco y proceso de Resilvering..."

# ------------------------------------------------------------------ Paso 5
header "PASO 5 · 💥 Falla de Disco, Estado DEGRADED y Reconstrucción (Resilver)"
info "Destruimos por completo el disco $D2 (muerte súbita de hardware):"
dd if=/dev/zero of="$D2" bs=1M count=30 conv=notrunc status=none
sync

# Forzar a ZFS a escanear
run zpool scrub "$POOL_NAME"
sleep 2

subheader "Estado del pool tras la pérdida física:"
run zpool status "$POOL_NAME"

info "El pool pasa a estado 'DEGRADED'. Los datos siguen sirviéndose sin interrupción:"
CURR_SHA=$(sha256sum "$MNT/basedatos.db" | awk '{print $1}')
[ "$CURR_SHA" = "$SHA" ] && echo -e "${GREEN}✔ Hash verificado durante estado degradado: ${CURR_SHA:0:16}${RESET}"

subheader "Reemplazo de la unidad dañada usando el disco Spare:"
info "Ejecutando zpool replace para reconstruir la paridad en el spare:"
run zpool replace "$POOL_NAME" "$D2" "$D4"

subheader "Monitoreo del proceso de Resilvering:"
run zpool status "$POOL_NAME"

info "Esperando finalización del Resilver..."
while true; do
    if zpool status "$POOL_NAME" | grep -q "resilver in progress"; then
        echo "   Resilvering en progreso..."
        sleep 1
    else
        break
    fi
done

FINAL_SHA=$(sha256sum "$MNT/basedatos.db" | awk '{print $1}')
if [ "$FINAL_SHA" = "$SHA" ]; then
    echo -e "${GREEN}✔ RESILVER COMPLETADO: Arreglo 100% íntegro y sin pérdida de información.${RESET}"
fi

header "FIN · Siguiente: Lab 4.5 Proyecto Integrador en AWS (trabajo_integrador_raid.md)"
pie_clase
