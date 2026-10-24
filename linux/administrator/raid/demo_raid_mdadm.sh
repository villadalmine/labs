#!/usr/bin/env bash
# ==============================================================================
# DEMO Lab 3.8 · RAID con mdadm sobre loop devices
#   Paso 1: tour de niveles (0/1/5/6/10)   Paso 2: RAID 5 + hot spare + ext4
#   Paso 3: metadatos (--examine) y bitmap  Paso 4: falla, degraded y rebuild
#   Paso 5: scrub (check/repair)            Paso 6: reemplazo manual de disco
#
# Uso: sudo ./demo_raid_mdadm.sh [--auto <segundos>] [--keep] [--size 256M]
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
INSTALL_HINT="mdadm e2fsprogs util-linux"
parse_common_args "$@"
DISK_SIZE="${DISK_SIZE:-256M}"

MD_MAIN=/dev/md100
MNT=/mnt/raidlab_md
MDS_USED=()
OLD_MAX=$(cat /proc/sys/dev/raid/speed_limit_max 2>/dev/null || echo 200000)

cleanup_lab() {
    mountpoint -q "$MNT" && umount "$MNT"
    for md in "${MDS_USED[@]}"; do mdadm --stop "$md" 2>/dev/null; done
    for d in "${LOOPS[@]}" "$SPARE_NEW"; do [ -n "$d" ] && mdadm --zero-superblock "$d" 2>/dev/null; done
    echo "$OLD_MAX" > /proc/sys/dev/raid/speed_limit_max 2>/dev/null
    rmdir "$MNT" 2>/dev/null
}

require_root
require_cmd mdadm losetup mkfs.ext4
for m in md_mod raid0 raid1 raid456 raid10; do modprobe "$m" 2>/dev/null; done
[ -e /proc/mdstat ] || { fail "No hay /proc/mdstat: el kernel no soporta md (ver raid_teoria.md §5)."; exit 1; }
trap trap_cleanup EXIT

header "LAB 3.8 · RAID con mdadm"
subheader "Preparación: 6 discos simulados (sparse + loop)"
make_disks 6
D1=${LOOPS[0]}; D2=${LOOPS[1]}; D3=${LOOPS[2]}; D4=${LOOPS[3]}; D5=${LOOPS[4]}; D6=${LOOPS[5]}
run lsblk -o NAME,SIZE,TYPE,BACKING-FILE "${LOOPS[@]}" 2>/dev/null
pause_step "ENTER para el tour de niveles..."

# ------------------------------------------------------------------ Paso 1
header "PASO 1 · Tour de niveles (todos sobre los mismos discos)"
tour() { # nivel, dispositivo md, discos...
    local lvl="$1" md="$2"; shift 2
    mdadm --create "$md" --run --level="$lvl" --raid-devices=$# "$@" >/dev/null 2>&1
    MDS_USED+=("$md")
    local sz; sz=$(blockdev --getsize64 "$md" 2>/dev/null)
    printf "   RAID %-3s con %d discos -> %-12s útil: %4d MiB\n" "$lvl" $# "$md" $(( ${sz:-0} / 1048576 ))
    mdadm --stop "$md" >/dev/null 2>&1; mdadm --zero-superblock "$@" >/dev/null 2>&1
}
info "Cada disco mide ${DISK_SIZE}. Compará la capacidad útil con la teoría:"
tour 0  /dev/md101 "$D1" "$D2"
tour 1  /dev/md102 "$D1" "$D2"
tour 5  /dev/md103 "$D1" "$D2" "$D3"
tour 6  /dev/md104 "$D1" "$D2" "$D3" "$D4"
tour 10 /dev/md105 "$D1" "$D2" "$D3" "$D4"
MDS_USED=()
pause_step "ENTER para armar el RAID 5 principal con hot spare..."

# ------------------------------------------------------------------ Paso 2
header "PASO 2 · RAID 5 (3 discos) + 1 hot spare + ext4"
echo 1000 > /proc/sys/dev/raid/speed_limit_max   # ralentiza el rebuild para poder observarlo
run mdadm --create "$MD_MAIN" --run --level=5 --raid-devices=3 --spare-devices=1 \
    --bitmap=internal --name=labraid "$D1" "$D2" "$D3" "$D4"
MDS_USED+=("$MD_MAIN")
subheader "Estado durante la sincronización inicial (/proc/mdstat)"
run cat /proc/mdstat
echo 200000 > /proc/sys/dev/raid/speed_limit_max
info "Esperando que termine la sincronización inicial..."
run mdadm --wait "$MD_MAIN"
run mkfs.ext4 -q -L raidlab "$MD_MAIN"
mkdir -p "$MNT"; run mount "$MD_MAIN" "$MNT"
SHA=$(make_testdata "$MNT/datos.bin" 30)
info "Archivo de 30 MiB escrito. sha256 = ${SHA:0:16}..."
run df -h "$MNT"
pause_step "ENTER para ver METADATOS y BITMAP..."

# ------------------------------------------------------------------ Paso 3
header "PASO 3 · Metadatos (superbloque) y bitmap"
subheader "mdadm --detail: visión del arreglo"
run mdadm --detail "$MD_MAIN"
subheader "mdadm --examine: lo que cada DISCO sabe de sí mismo (metadatos 1.2)"
run mdadm --examine "$D1"
subheader "Write-intent bitmap"
runsh "mdadm --examine-bitmap $D1 | head -12"
pause_step "ENTER para ROMPER un disco..."

# ------------------------------------------------------------------ Paso 4
header "PASO 4 · 💥 Falla de disco: degraded → rebuild automático con spare"
echo 1000 > /proc/sys/dev/raid/speed_limit_max
run mdadm "$MD_MAIN" --fail "$D2"
subheader "El arreglo sigue sirviendo datos (reconstruye con XOR al vuelo)"
run cat /proc/mdstat
runsh "mdadm --detail $MD_MAIN | grep -E 'State|Failed|Spare|Active|Working'"
runsh "sha256sum $MNT/datos.bin | cut -c1-16"
info "El sha256 debe seguir siendo ${SHA:0:16} aun con el arreglo degradado/reconstruyendo."
sleep 2
run cat /proc/mdstat
echo 200000 > /proc/sys/dev/raid/speed_limit_max
run mdadm --wait "$MD_MAIN"
NEW=$(sha256sum "$MNT/datos.bin" | awk '{print $1}')
[ "$NEW" = "$SHA" ] && echo -e "${GREEN}✔ Integridad OK tras el rebuild con el spare.${RESET}" || echo -e "${RED}✘ Datos distintos${RESET}"
run mdadm --detail "$MD_MAIN"
pause_step "ENTER para quitar el disco muerto y agregar uno NUEVO..."

# ------------------------------------------------------------------ Paso 5
header "PASO 5 · Reemplazo del disco: --remove y --add"
run mdadm "$MD_MAIN" --remove "$D2"
SPARE_NEW=$(make_spare_disk 7)
info "Disco nuevo (reemplazo físico simulado): $SPARE_NEW"
run mdadm "$MD_MAIN" --add "$SPARE_NEW"
run cat /proc/mdstat
info "Queda como hot spare: el arreglo ya tolera OTRA falla."
runsh "mdadm --detail $MD_MAIN | grep -E 'Active Devices|Spare Devices|Failed Devices|State :'"
pause_step "ENTER para el scrub (check)..."

# ------------------------------------------------------------------ Paso 6
header "PASO 6 · Scrub: verificación de consistencia de la paridad"
SYNC=/sys/block/$(basename "$MD_MAIN")/md
runsh "echo check > $SYNC/sync_action"
sleep 1
run mdadm --wait "$MD_MAIN"
run cat "$SYNC/mismatch_cnt"
info "mismatch_cnt = 0 → paridad consistente. (En producción: cron mensual; Debian/Ubuntu ya trae checkarray)."
subheader "Persistir la configuración (en producción)"
echo -e "${DIM}\$ mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf && sudo update-initramfs -u${RESET}"
mdadm --detail --scan

header "FIN · Siguiente: Lab 3.9 LVM RAID (raid_lvm.md)"
pie_clase
