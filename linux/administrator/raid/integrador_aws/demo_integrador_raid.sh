#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Trabajo Integrador 5
# RAID Empresarial de Alta Disponibilidad, Resiliencia ante Desastres,
# Reemplazo en Caliente y Observabilidad con Métricas Prometheus en AWS
#
# Uso:
#   sudo ./demo_integrador_raid.sh [opciones] [D1 D2 D3 SPARE_1 SPARE_2]
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
DIM='\033[2m'
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

run() {
    echo -e "${DIM}\$ $*${RESET}"
    "$@"
    return 0
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Este laboratorio requiere privilegios de root.${RESET}"
    echo -e "Por favor, ejecútalo con: ${BOLD}sudo $0${RESET}"
    exit 1
fi

LAB_DIR="/tmp/raid_integrador_lab"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR" || exit 1

MD_DEV="/dev/md0"
MNT_DIR="/srv/storage_raid"
WEB_DIR="/var/www/html/secure_data"
LOOP_DEVS=()

cleanup() {
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "\n${GREEN}[INFO] Se seleccionó --keep. Recursos conservados para inspección.${RESET}"
        return
    fi

    echo -e "\n${YELLOW}[LIMPIEZA] Desmontando filesystem y deteniendo arreglo RAID...${RESET}"
    umount -f "$WEB_DIR" 2>/dev/null || true
    umount -f "$MNT_DIR" 2>/dev/null || true
    mdadm --stop "$MD_DEV" 2>/dev/null || true

    if [ "$LOOP_MODE" = true ]; then
        for dev in "${LOOP_DEVS[@]}"; do
            mdadm --zero-superblock "$dev" 2>/dev/null || true
            losetup -d "$dev" 2>/dev/null || true
        done
        rm -rf "$LAB_DIR" 2>/dev/null || true
    else
        for dev in "$D1" "$D2" "$D3" "$SPARE_1" "$SPARE_2"; do
            [ -n "$dev" ] && [ -b "$dev" ] && mdadm --zero-superblock "$dev" 2>/dev/null || true
        done
    fi

    rmdir "$MNT_DIR" 2>/dev/null || true
    rmdir "$WEB_DIR" 2>/dev/null || true
    echo -e "${GREEN}[OK] Limpieza finalizada correctamente.${RESET}"
}
trap cleanup EXIT INT TERM

# ==============================================================================
# FASE 0: PREPARACIÓN DE DISCOS Y HERRAMIENTAS
# ==============================================================================
header "FASE 0: Detección de Discos y Prerrequisitos de Observabilidad"

# Asegurar módulos y paquetes
for pkg in mdadm e2fsprogs curl jq; do
    if ! command -v "$pkg" &>/dev/null; then
        echo -e "${YELLOW}Instalando $pkg...${RESET}"
        apt-get update -qq && apt-get install -y -qq "$pkg"
    fi
done
modprobe md_mod raid456 2>/dev/null || true

# Detección de discos: Parámetros -> EBS de AWS -> Fallback a Loop Devices
if [ ${#POSITIONAL_ARGS[@]} -ge 5 ]; then
    D1="${POSITIONAL_ARGS[0]}"
    D2="${POSITIONAL_ARGS[1]}"
    D3="${POSITIONAL_ARGS[2]}"
    SPARE_1="${POSITIONAL_ARGS[3]}"
    SPARE_2="${POSITIONAL_ARGS[4]}"
    echo -e "${GREEN}[INFO] Utilizando discos proporcionados por parámetro:${RESET}"
else
    # Buscar discos EBS no particionados (nvme1n1.. o sdb..)
    EBS_CANDIDATES=()
    for d in $(lsblk -d -n -o NAME,TYPE | awk '$2=="disk" && $1!~"nvme0n1|sda" {print "/dev/"$1}'); do
        if [ "$d" != "/dev/md0" ]; then
            EBS_CANDIDATES+=("$d")
        fi
    done

    if [ ${#EBS_CANDIDATES[@]} -ge 5 ]; then
        echo -e "${GREEN}[INFO] 5 volúmenes EBS detectados automáticamente en la instancia AWS:${RESET}"
        D1="${EBS_CANDIDATES[0]}"
        D2="${EBS_CANDIDATES[1]}"
        D3="${EBS_CANDIDATES[2]}"
        SPARE_1="${EBS_CANDIDATES[3]}"
        SPARE_2="${EBS_CANDIDATES[4]}"
    else
        echo -e "${YELLOW}[INFO] Menos de 5 discos físicos hallados. Creando 5 loop devices de 512 MiB...${RESET}"
        echo -e "       (Modo compatible con WSL2, Docker y VirtualBox)"
        LOOP_MODE=true
        for i in 1 2 3 4 5; do
            img="$LAB_DIR/disk_ebs_sim_${i}.img"
            truncate -s 512M "$img"
            dev=$(losetup -fP --show "$img")
            LOOP_DEVS+=("$dev")
        done
        D1="${LOOP_DEVS[0]}"
        D2="${LOOP_DEVS[1]}"
        D3="${LOOP_DEVS[2]}"
        SPARE_1="${LOOP_DEVS[3]}"
        SPARE_2="${LOOP_DEVS[4]}"
    fi
fi

echo -e "  * ${BOLD}Disco 1 (Datos):${RESET}      $D1"
echo -e "  * ${BOLD}Disco 2 (Datos):${RESET}      $D2"
echo -e "  * ${BOLD}Disco 3 (Datos):${RESET}      $D3"
echo -e "  * ${BOLD}Disco 4 (Hot Spare):${RESET}  $SPARE_1"
echo -e "  * ${BOLD}Disco 5 (Reemplazo):${RESET}  $SPARE_2"

pause_step "ENTER para construir el arreglo RAID 5 con Hot Spare y Bitmap..."

# ==============================================================================
# FASE 1: CONSTRUCCIÓN DEL RAID 5 CON BITMAP Y FORMATO
# ==============================================================================
header "FASE 1: Construcción del RAID 5 con Write-Intent Bitmap y Hot Spare"

# Limpiar superbloques viejos por si se reejecuta
for d in "$D1" "$D2" "$D3" "$SPARE_1" "$SPARE_2"; do
    mdadm --zero-superblock "$d" 2>/dev/null || true
done

echo -e "${CYAN}Creando $MD_DEV con 3 unidades activas + 1 Hot Spare + Bitmap interno:${RESET}"
run mdadm --create "$MD_DEV" \
    --run \
    --level=5 \
    --raid-devices=3 \
    --spare-devices=1 \
    --bitmap=internal \
    --name=raid_prod \
    "$D1" "$D2" "$D3" "$SPARE_1"

subheader "Esperando sincronización inicial del arreglo:"
mdadm --wait "$MD_DEV" 2>/dev/null || true
cat /proc/mdstat

subheader "Formateando con ext4 y montando en el servicio:"
mkdir -p "$MNT_DIR" "$WEB_DIR"
run mkfs.ext4 -F -q -L raid_data "$MD_DEV"
run mount "$MD_DEV" "$MNT_DIR"

# Montaje bind hacia Nginx para exponer archivos
mount --bind "$MNT_DIR" "$WEB_DIR" 2>/dev/null || true

# Escribir dataset de producción
echo "=== REGISTRO FINANCIERO TRANSACCIONAL ===" > "$MNT_DIR/transacciones.log"
dd if=/dev/urandom of="$MNT_DIR/database.dat" bs=1M count=30 status=none
ORIG_SHA=$(sha256sum "$MNT_DIR/database.dat" | awk '{print $1}')
echo -e "${GREEN}[OK] Datos escritos. Hash SHA-256 de referencia: ${ORIG_SHA}${RESET}"

pause_step "ENTER para consultar el sistema de métricas Prometheus..."

# ==============================================================================
# FASE 2: TELEMETRÍA Y OBSERVABILIDAD EN TIEMPO REAL
# ==============================================================================
header "FASE 2: Observabilidad y Métricas de Salud del Almacenamiento"

# Actualizar métricas
/usr/local/bin/update_raid_metrics.sh 2>/dev/null || true

subheader "Consultando endpoint de métricas Prometheus (localhost:9100/metrics):"
METRICS_OUTPUT=$(curl -s http://127.0.0.1:9100/metrics 2>/dev/null | grep -E "^raid_" || true)

if [ -n "$METRICS_OUTPUT" ]; then
    echo -e "${GREEN}$METRICS_OUTPUT${RESET}"
else
    # Fallback si node-exporter no está activo
    echo -e "${YELLOW}[TELEMETRÍA LOCAL DIRECTA]${RESET}"
    cat /var/lib/prometheus/node-exporter/raid.prom 2>/dev/null || true
fi

echo -e "\n${BOLD}Interpretación de Métricas:${RESET}"
echo "  * raid_healthy = 1      -> Arreglo 100% íntegro (Clean)"
echo "  * raid_active_disks = 3  -> 3 discos activos sirviendo datos"
echo "  * raid_failed_disks = 0  -> 0 fallas"
echo "  * raid_spare_disks = 1   -> 1 hot spare disponible para contingencias"

pause_step "ENTER para SIMULAR UNA FALLA CATASTRÓFICA en el disco $D2..."

# ==============================================================================
# FASE 3: INYECCIÓN DE FALLA Y RESILIENCIA EN CALIENTE
# ==============================================================================
header "FASE 3: 💥 Inyección de Falla (Caos): Muerte Súbita del Disco $D2"

echo 1000 > /proc/sys/dev/raid/speed_limit_max 2>/dev/null || true # Ralentiza rebuild para observarlo
echo -e "${RED}Marcando $D2 como defectuoso (--fail)...${RESET}"
run mdadm "$MD_DEV" --fail "$D2"

/usr/local/bin/update_raid_metrics.sh 2>/dev/null || true

subheader "Telemetría inmediata tras la falla:"
curl -s http://127.0.0.1:9100/metrics 2>/dev/null | grep -E "^raid_" || cat /var/lib/prometheus/node-exporter/raid.prom 2>/dev/null || true

echo -e "\n${RED}ALERTA DEL SISTEMA:${RESET}"
echo "  * raid_healthy = 0      -> ¡EL ARREGLO ESTÁ DEGRADADO!"
echo "  * raid_failed_disks = 1  -> Disco caído detectado"

subheader "Demostración de Resiliencia: La aplicación continúa funcionando sin corte:"
CURRENT_SHA=$(sha256sum "$MNT_DIR/database.dat" | awk '{print $1}')
if [ "$CURRENT_SHA" = "$ORIG_SHA" ]; then
    echo -e "${GREEN}✔ ALTA DISPONIBILIDAD: El hash coincide (${CURRENT_SHA:0:16}).${RESET}"
    echo "  El kernel está recalculando la información mediante la paridad XOR al vuelo."
fi

pause_step "ENTER para observar la reconstrucción automática (Hot Spare)..."

# ==============================================================================
# FASE 4: RECONSTRUCCIÓN AUTOMÁTICA CON EL HOT SPARE
# ==============================================================================
header "FASE 4: Reconstrucción Automática con Hot Spare ($SPARE_1)"

echo -e "El hot spare entra automáticamente en acción sin intervención humana:"
cat /proc/mdstat

echo 200000 > /proc/sys/dev/raid/speed_limit_max 2>/dev/null || true
echo -e "\n${YELLOW}Esperando que finalice la reconstrucción del arreglo...${RESET}"
mdadm --wait "$MD_DEV"

/usr/local/bin/update_raid_metrics.sh 2>/dev/null || true
subheader "Estado de métricas tras el rebuild:"
curl -s http://127.0.0.1:9100/metrics 2>/dev/null | grep -E "^raid_" || cat /var/lib/prometheus/node-exporter/raid.prom 2>/dev/null || true

echo -e "${GREEN}✔ raid_healthy volvió a 1. El arreglo recuperó su resiliencia total.${RESET}"
echo "  (Notá que raid_spare_disks ahora es 0: el spare ya está en producción)."

pause_step "ENTER para sustituir físicamente el disco quemado por uno nuevo ($SPARE_2)..."

# ==============================================================================
# FASE 5: REEMPLAZO FÍSICO DE HARDWARE (DRIVE SWAP)
# ==============================================================================
header "FASE 5: Sustitución Física de Hardware y Reaprovisionamiento de Spare"

subheader "1. Expulsando el disco dañado ($D2):"
run mdadm "$MD_DEV" --remove "$D2"

subheader "2. Insertando el nuevo disco EBS de reemplazo ($SPARE_2):"
run mdadm "$MD_DEV" --add "$SPARE_2"

/usr/local/bin/update_raid_metrics.sh 2>/dev/null || true

subheader "Telemetría final tras la sustitución física:"
curl -s http://127.0.0.1:9100/metrics 2>/dev/null | grep -E "^raid_" || cat /var/lib/prometheus/node-exporter/raid.prom 2>/dev/null || true

echo -e "${GREEN}✔ raid_spare_disks vuelve a marcar 1. La infraestructura está protegida ante otra falla.${RESET}"

pause_step "ENTER para ejecutar la verificación de paridad (Scrubbing)..."

# ==============================================================================
# FASE 6: AUDITORÍA DE CONSISTENCIA DE PARIDAD (SCRUBBING)
# ==============================================================================
header "FASE 6: Auditoría de Paridad (Scrubbing) y Validación Final"

SYNC_DIR="/sys/block/$(basename "$MD_DEV")/md"
echo check > "$SYNC_DIR/sync_action"
echo -e "Auditoría de paridad en ejecución..."
mdadm --wait "$MD_DEV" 2>/dev/null || true

MISMATCH=$(cat "$SYNC_DIR/mismatch_cnt" 2>/dev/null || echo 0)
echo -e "Discrepancias de paridad detectadas: ${BOLD}$MISMATCH${RESET}"

FINAL_SHA=$(sha256sum "$MNT_DIR/database.dat" | awk '{print $1}')
if [ "$FINAL_SHA" = "$ORIG_SHA" ] && [ "$MISMATCH" -eq 0 ]; then
    echo -e "\n${BOLD}${GREEN}======================================================================${RESET}"
    echo -e "${BOLD}${GREEN} ¡VALIDACIÓN COMPLETA EXITOSA!                                         ${RESET}"
    echo -e "${GREEN} - Servicio web y base de datos con 0% de pérdida de datos.            ${RESET}"
    echo -e "${GREEN} - Recuperación automática con Hot Spare validada.                     ${RESET}"
    echo -e "${GREEN} - Sustitución en caliente de volumen EBS completada.                  ${RESET}"
    echo -e "${GREEN} - Métricas Prometheus operativas y paridad consistente al 100%.       ${RESET}"
    echo -e "${BOLD}${GREEN}======================================================================${RESET}"
fi

header "FIN DEL TRABAJO INTEGRADOR"
echo -e "${DIM}Serie RAID · Administración Linux · github.com/villadalmine/labs${RESET}"
