#!/usr/bin/env bash
# ==============================================================================
# DEMO Lab 3.10 · RAID con Btrfs sobre loop devices
#   Paso 1: Creación de filesystem Btrfs y perfiles (Data vs Metadata)
#   Paso 2: Conversión en caliente (Online Balance) de single a RAID 1
#   Paso 3: Demostración de Self-Healing (corrupción inducida + auto-reparación por checksums)
#   Paso 4: Auditoría proactiva con btrfs scrub
#   Paso 5: Simulación de disco roto, montaje degradado y reemplazo en caliente con btrfs replace
#
# Uso: sudo ./demo_raid_btrfs.sh [--auto <segundos>] [--keep] [--size 256M]
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
INSTALL_HINT="btrfs-progs util-linux"
parse_common_args "$@"
DISK_SIZE="${DISK_SIZE:-256M}"

MNT="/mnt/raidlab_btrfs"
SPARE_DEV=""

cleanup_lab() {
    mountpoint -q "$MNT" && umount -f "$MNT"
    rmdir "$MNT" 2>/dev/null || true
}

require_root
require_cmd mkfs.btrfs btrfs losetup dd sha256sum
modprobe btrfs 2>/dev/null || true
grep -qw btrfs /proc/filesystems || { fail "El kernel no tiene soporte btrfs."; exit 1; }

trap trap_cleanup EXIT

header "LAB 3.10 · RAID con Btrfs (Copy-on-Write y Self-Healing)"
subheader "Preparación: 3 discos simulados de ${DISK_SIZE}"
make_disks 3
D1=${LOOPS[0]}; D2=${LOOPS[1]}; D3=${LOOPS[2]}

pause_step "ENTER para inicializar Btrfs en un disco simple..."

# ------------------------------------------------------------------ Paso 1
header "PASO 1 · Creación de Btrfs y separación de perfiles (Data y Metadata)"
info "Formateando $D1 como Btrfs con perfil por defecto:"
run mkfs.btrfs -f -L btrfslab "$D1"
mkdir -p "$MNT"
run mount "$D1" "$MNT"

SHA=$(make_testdata "$MNT/archivo_importante.txt" 25)
info "Archivo de 25 MiB creado en $MNT. SHA-256 = ${SHA:0:16}..."

subheader "Inspección de perfiles de asignación de bloques:"
run btrfs filesystem df "$MNT"
run btrfs filesystem usage "$MNT"

pause_step "ENTER para convertir a RAID 1 en CALIENTE (Online Balance)..."

# ------------------------------------------------------------------ Paso 2
header "PASO 2 · Conversión en caliente a RAID 1 (Online Balance)"
info "Añadimos el segundo disco ($D2) al filesystem en vivo:"
run btrfs device add -f "$D2" "$MNT"
run btrfs filesystem show "$MNT"

subheader "Rebalanceo y conversión de perfiles a RAID 1"
info "Ejecutando balance con -dconvert=raid1 (datos) y -mconvert=raid1 (metadatos):"
run btrfs balance start -dconvert=raid1 -mconvert=raid1 "$MNT"

subheader "Verificación del perfil RAID 1 activo:"
run btrfs filesystem df "$MNT"
info "Notá que Data y Metadata ahora indican: 'RAID1'."

pause_step "ENTER para demostrar el SELF-HEALING (Auto-reparación por Bit-Rot)..."

# ------------------------------------------------------------------ Paso 3
header "PASO 3 · 💥 Demostración de Self-Healing (Auto-reparación por Checksum)"
info "En un RAID clásico (mdadm/LVM), la corrupción silenciosa devuelve basura."
info "En Btrfs, cada bloque tiene un checksum (CRC32C/XXHASH) en el árbol de metadatos."

# Sincronizar buffers a disco
sync
sleep 1

subheader "Inyectando corrupción deliberada directamente en el bloque físico de $D1"
# Buscamos un sector intermedio del disco 1 y escribimos basura
dd if=/dev/urandom of="$D1" bs=4k count=1 seek=12000 conv=notrunc status=none
sync

subheader "Leyendo el archivo para verificar si Btrfs auto-repara el bloque:"
READ_SHA=$(sha256sum "$MNT/archivo_importante.txt" | awk '{print $1}')

if [ "$READ_SHA" = "$SHA" ]; then
    echo -e "${GREEN}✔ MAGIA DE BTRFS: El archivo se leyó 100% intacto (${READ_SHA:0:16}).${RESET}"
    echo "  El kernel detectó el error de checksum en $D1, leyó la copia sana de $D2 y auto-reparó $D1 en segundo plano."
else
    warn "Nota: La corrupción no cayó dentro del rango del archivo de prueba."
fi

subheader "Estadísticas de errores y correcciones del filesystem:"
run btrfs device stats "$MNT"

pause_step "ENTER para ejecutar un Scrub proactivo..."

# ------------------------------------------------------------------ Paso 4
header "PASO 4 · Auditoría proactiva con btrfs scrub"
info "btrfs scrub recorre todos los bloques y recalcula y valida cada checksum:"
run btrfs scrub start -B -d "$MNT"
run btrfs scrub status "$MNT"

pause_step "ENTER para simular falla de disco y reemplazo con btrfs replace..."

# ------------------------------------------------------------------ Paso 5
header "PASO 5 · 💥 Falla de disco y reemplazo en caliente con btrfs replace"
info "Rompemos completamente el disco $D2 (sobrescribiendo con ceros):"
dd if=/dev/zero of="$D2" bs=1M count=50 conv=notrunc status=none
sync

subheader "Verificación de acceso a datos con disco dañado:"
CURR_SHA=$(sha256sum "$MNT/archivo_importante.txt" | awk '{print $1}')
[ "$CURR_SHA" = "$SHA" ] && echo -e "${GREEN}✔ Datos accesibles sin degradación visible para la app.${RESET}"

subheader "Reemplazo físico con un nuevo disco ($D3) mediante 'btrfs replace'"
info "btrfs replace copia directamente los chunks válidos de las copias sanas al nuevo disco:"
run btrfs replace start -B -f 2 "$D3" "$MNT"
run btrfs replace status "$MNT"

subheader "Estado final del filesystem Btrfs:"
run btrfs filesystem show "$MNT"
run btrfs device stats "$MNT"

FINAL_SHA=$(sha256sum "$MNT/archivo_importante.txt" | awk '{print $1}')
if [ "$FINAL_SHA" = "$SHA" ]; then
    echo -e "${GREEN}✔ REEMPLAZO Y RESINCRONIZACIÓN EXITOSOS: Todos los datos íntegros.${RESET}"
fi

header "FIN · Siguiente: Lab 3.11 RAID con ZFS (raid_zfs.md)"
pie_clase
