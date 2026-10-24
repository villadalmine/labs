#!/usr/bin/env bash
# ==============================================================================
# DEMO Lab 3.9 · RAID con LVM (dm-raid) sobre loop devices
#   Paso 1: Inicialización de PVs y VG
#   Paso 2: Tour de tipos RAID en LVM (raid0, raid1, raid5)
#   Paso 3: Creación de RAID 5 (dm-raid) e inspección de sub-LVs (_rmeta / _rimage)
#   Paso 4: Formato, montaje y redimensionamiento en caliente (online resize)
#   Paso 5: Simulación de falla de PV, degradación y verificación de integridad
#   Paso 6: Reparación en vivo con lvconvert --repair y saneamiento del VG
#
# Uso: sudo ./demo_raid_lvm.sh [--auto <segundos>] [--keep] [--size 256M]
# ==============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
INSTALL_HINT="lvm2 e2fsprogs util-linux"
parse_common_args "$@"
DISK_SIZE="${DISK_SIZE:-256M}"

VG_NAME="vg_raidlab"
LV_NAME="lv_prod"
MNT="/mnt/raidlab_lvm"
SPARE_PV=""

cleanup_lab() {
    mountpoint -q "$MNT" && umount -f "$MNT"
    if vgdisplay "$VG_NAME" >/dev/null 2>&1; then
        lvchange -an "$VG_NAME" 2>/dev/null || true
        vgremove -f -y "$VG_NAME" 2>/dev/null || true
    fi
    for d in "${LOOPS[@]}" "$SPARE_PV"; do
        if [ -n "$d" ] && [ -b "$d" ]; then
            pvremove -f -y "$d" 2>/dev/null || true
            wipefs -a "$d" 2>/dev/null || true
        fi
    done
    rmdir "$MNT" 2>/dev/null || true
}

require_root
require_cmd lvm pvcreate vgcreate lvcreate lvconvert lvextend mkfs.ext4 losetup
for m in dm_mod dm_raid raid0 raid1 raid456 raid10; do modprobe "$m" 2>/dev/null; done

trap trap_cleanup EXIT

header "LAB 3.9 · RAID con LVM (dm-raid)"
subheader "Preparación: 4 discos simulados de ${DISK_SIZE}"
make_disks 4
D1=${LOOPS[0]}; D2=${LOOPS[1]}; D3=${LOOPS[2]}; D4=${LOOPS[3]}

pause_step "ENTER para inicializar los Physical Volumes (PV) y el Volume Group (VG)..."

# ------------------------------------------------------------------ Paso 1
header "PASO 1 · Creación de PVs y Volume Group ($VG_NAME)"
run pvcreate -y -ff "$D1" "$D2" "$D3" "$D4"
run vgcreate -y "$VG_NAME" "$D1" "$D2" "$D3" "$D4"
run vgs "$VG_NAME"
pause_step "ENTER para el tour de tipos de RAID en LVM..."

# ------------------------------------------------------------------ Paso 2
header "PASO 2 · Tour de tipos de RAID en LVM"
info "LVM2 no usa el viejo target 'mirror', sino 'dm-raid' (código MD del kernel)."

tour_lvm() {
    local tipo="$1" nombre="$2"; shift 2
    info "Creando LV tipo --type $tipo..."
    run lvcreate -y --type "$tipo" -n "$nombre" "$VG_NAME" "$@"
    run lvs -o name,vg_name,segtype,size,devices "$VG_NAME/$nombre"
    run lvremove -y "$VG_NAME/$nombre" >/dev/null 2>&1
}

# RAID 0 (Striping con 2 discos)
tour_lvm raid0 lv_t0 -L 120M -i 2 "$D1" "$D2"

# RAID 1 (Espejo de 2 vías con metadata y bitmap automáticos)
tour_lvm raid1 lv_t1 -L 120M -m 1 "$D1" "$D2"

# RAID 5 (Paridad simple con 3 discos, 2 stripes de datos + 1 paridad)
tour_lvm raid5 lv_t5 -L 200M -i 2 "$D1" "$D2" "$D3"

pause_step "ENTER para crear el RAID 5 definitivo e inspeccionar sus sub-LVs..."

# ------------------------------------------------------------------ Paso 3
header "PASO 3 · Creación del RAID 5 principal e inspección forense"
info "Creamos $LV_NAME de 300 MiB con paridad rotativa (-i 2 stripes de datos + 1 paridad = 3 discos):"
run lvcreate -y --type raid5 -i 2 -L 300M -n "$LV_NAME" "$VG_NAME" "$D1" "$D2" "$D3"

subheader "La magia oculta: Sub-LVs _rmeta (metadatos/bitmap) y _rimage (datos)"
info "Ejecutando 'lvs -a -o+devices':"
run lvs -a -o lv_name,vg_name,attr,size,copy_percent,devices "$VG_NAME"

echo -e "\n${CYAN}Estructura interna creada automáticamente por LVM:${RESET}"
echo "   ${LV_NAME}_rmeta_0..2  -> Áreas de metadatos y write-intent bitmap (1 PE cada una)"
echo "   ${LV_NAME}_rimage_0..2 -> Franjas reales de datos y paridad distribuidas en cada PV"

pause_step "ENTER para formatear ext4, montar y redimensionar en caliente..."

# ------------------------------------------------------------------ Paso 4
header "PASO 4 · Sistema de Archivos y Redimensionamiento en Caliente"
run mkfs.ext4 -q -L lvmraid "/dev/$VG_NAME/$LV_NAME"
mkdir -p "$MNT"
run mount "/dev/$VG_NAME/$LV_NAME" "$MNT"

SHA=$(make_testdata "$MNT/archivo_critico.dat" 35)
info "Archivo de 35 MiB escrito. Hash SHA-256 = ${SHA:0:16}..."
run df -h "$MNT"

subheader "Redimensionamiento en caliente (Online Grow) de un RAID 5"
info "Ampliando el LV y el filesystem en caliente con 'lvextend -r -L +60M':"
run lvextend -r -L +60M "$VG_NAME/$LV_NAME"
run df -h "$MNT"
info "¡El filesystem creció en caliente sin desmontar y manteniendo la paridad RAID!"

pause_step "ENTER para SIMULAR LA FALLA de un Physical Volume..."

# ------------------------------------------------------------------ Paso 5
header "PASO 5 · 💥 Inyección de falla: rompemos el disco $D2"
info "Sobrescribiendo la cabecera del PV y desconectando el dispositivo:"
dd if=/dev/zero of="$D2" bs=1M count=10 conv=notrunc status=none
blockdev --flushbufs "$D2" 2>/dev/null || true

subheader "Estado de LVM y salud del volumen lógico tras la pérdida"
runsh "vgs --readonly $VG_NAME"
runsh "lvs -a -o lv_name,attr,health_status,devices $VG_NAME"

info "Atributos del LV (columna 1): 'r' = RAID, posición 9 = 'p' (parcial / degraded)."
info "Health status: 'degraded'."

subheader "Verificación de Integridad de Datos en caliente"
NEW_SHA=$(sha256sum "$MNT/archivo_critico.dat" | awk '{print $1}')
if [ "$NEW_SHA" = "$SHA" ]; then
    echo -e "${GREEN}✔ INTEGRIDAD 100%: Los datos se leen perfectamente gracias a la reconstrucción XOR al vuelo.${RESET}"
else
    echo -e "${RED}✘ ERROR: Datos corruptos${RESET}"
fi

pause_step "ENTER para REPARAR el arreglo reemplazando el PV dañado..."

# ------------------------------------------------------------------ Paso 6
header "PASO 6 · Recuperación en vivo: Reemplazo de PV y lvconvert --repair"
info "Insertamos un nuevo disco de repuesto (Spare):"
SPARE_PV=$(make_spare_disk 5)
info "Disco spare creado: $SPARE_PV"

run pvcreate -y "$SPARE_PV"
info "Extendemos el Volume Group con el nuevo PV:"
run vgextend "$VG_NAME" "$SPARE_PV"

subheader "Reparación automática del Logical Volume con lvconvert --repair"
info "LVM detecta el sub-LV dañado, asigna espacio en el nuevo PV y reconstruye la paridad:"
run lvconvert -y --repair "$VG_NAME/$LV_NAME"

subheader "Progreso de resincronización:"
run lvs -a -o lv_name,attr,copy_percent,health_status,devices "$VG_NAME"

info "Esperando sincronización completa del arreglo..."
while true; do
    pct=$(lvs --noheadings -o copy_percent "$VG_NAME/$LV_NAME" 2>/dev/null | tr -d ' ' | cut -d. -f1)
    if [ -z "$pct" ] || [ "$pct" = "100" ]; then break; fi
    echo "   Progreso de reconstrucción: ${pct}%"
    sleep 1
done

subheader "Limpieza del PV huérfano (missing)"
run vgreduce --removemissing --force "$VG_NAME"
run vgs "$VG_NAME"
run lvs -o lv_name,attr,health_status,devices "$VG_NAME"

FINAL_SHA=$(sha256sum "$MNT/archivo_critico.dat" | awk '{print $1}')
if [ "$FINAL_SHA" = "$SHA" ]; then
    echo -e "${GREEN}✔ RECUPERACIÓN EXITOSA: Arreglo 100% sano y datos intactos.${RESET}"
fi

header "FIN · Siguiente: Lab 3.10 RAID con Btrfs (raid_btrfs.md)"
pie_clase
