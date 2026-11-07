#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Trabajo Integrador 3
# ZFS: Pools, Mirror en Caliente, Replicación Remota, Self-Healing y Failover
#
# Uso:
#   sudo ./demo_integrador_zfs.sh [opciones] [DISCO_ACT1 DISCO_ACT2 DISCO_PAS1]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No desmontar ni destruir los pools al finalizar
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
    echo -e "${RED}[ERROR] Este script interactivo de ZFS requiere privilegios de root.${RESET}"
    echo -e "Por favor, ejecútalo con: ${BOLD}sudo $0${RESET}"
    exit 1
fi

LAB_DIR="/var/tmp/lab_zfs_ha"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR" || exit 1

LOOP_DEVS=()

cleanup() {
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "\n${GREEN}[INFO] Se seleccionó --keep. Los pools quedan activos para inspección.${RESET}"
        return
    fi

    echo -e "\n${YELLOW}[LIMPIEZA] Destruyendo pools y liberando dispositivos de prueba...${RESET}"
    zpool destroy -f zpool_backup 2>/dev/null || true
    zpool destroy -f zpool_web 2>/dev/null || true

    if [ "$LOOP_MODE" = true ]; then
        for dev in "${LOOP_DEVS[@]}"; do
            losetup -d "$dev" 2>/dev/null || true
        done
        rm -rf "$LAB_DIR" 2>/dev/null || true
    fi

    echo -e "${GREEN}[OK] Limpieza de ZFS finalizada correctamente.${RESET}"
}
trap cleanup EXIT INT TERM

# ==============================================================================
# FASE 0: PREPARACIÓN DE RECURSOS Y DISCOS
# ==============================================================================
header "FASE 0: Detección de Discos y Prerrequisitos de ZFS"

if ! command -v zpool &>/dev/null; then
    echo -e "${YELLOW}Instalando zfsutils-linux...${RESET}"
    apt-get update -qq && apt-get install -y -qq zfsutils-linux
fi

if [ ${#POSITIONAL_ARGS[@]} -ge 3 ]; then
    DISCO_ACT_1="${POSITIONAL_ARGS[0]}"
    DISCO_ACT_2="${POSITIONAL_ARGS[1]}"
    DISCO_PAS_1="${POSITIONAL_ARGS[2]}"
    echo -e "${GREEN}[INFO] Utilizando discos físicos proporcionados por parámetro:${RESET}"
else
    echo -e "${YELLOW}[INFO] Creando 3 loop devices de 1 GB para simular Active/Passive y Mirror...${RESET}"
    LOOP_MODE=true
    for i in 1 2 3; do
        img="$LAB_DIR/disk_zfs_${i}.img"
        truncate -s 1G "$img"
        dev=$(losetup -fP --show "$img")
        LOOP_DEVS+=("$dev")
    done
    DISCO_ACT_1="${LOOP_DEVS[0]}"
    DISCO_ACT_2="${LOOP_DEVS[1]}"
    DISCO_PAS_1="${LOOP_DEVS[2]}"
fi

echo -e "  * ${BOLD}Nodo Activo - Disco 1 (Base):${RESET}        $DISCO_ACT_1"
echo -e "  * ${BOLD}Nodo Activo - Disco 2 (Mirror Caliente):${RESET} $DISCO_ACT_2"
echo -e "  * ${BOLD}Nodo Pasivo - Disco 1 (Réplica Backup):${RESET} $DISCO_PAS_1"

pause_step "Crear el Zpool y Dataset en el Nodo Activo..."

# ==============================================================================
# FASE 1: CREACIÓN DEL ZPOOL Y DATASET CON COMPRESIÓN LZ4
# ==============================================================================
header "FASE 1: Creación del Pool 'zpool_web' y Dataset"
echo -e "${CYAN}CONCEPTOS CLAVE:${RESET}"
echo -e "ZFS no usa LVM ni particiones ext4. El pool administra los discos directamente."
echo -e "El dataset gestiona el filesystem dinámico y hereda compresión nativa transparente."

subheader "1.1 Crear zpool_web en Disco Activo 1"
zpool create -f zpool_web "$DISCO_ACT_1"
zpool status zpool_web

pause_step "Crear el dataset del sitio web..."

subheader "1.2 Crear dataset con compresión LZ4 y punto de montaje"
zfs create zpool_web/site
zfs set compression=lz4 zpool_web/site
zfs set mountpoint=/var/tmp/lab_zfs_ha/web_root zpool_web/site

echo -e "\nPropiedades del dataset:"
zfs get compression,mountpoint,used,available zpool_web/site

pause_step "Incorporar el segundo disco en caliente (Mirror / RAID 1)..."

# ==============================================================================
# FASE 2: INCORPORACIÓN DEL SEGUNDO DISCO EN CALIENTE (ATTACH MIRROR)
# ==============================================================================
header "FASE 2: Conversión a Espejo en Caliente (Hot-Attach Mirror)"
echo -e "${CYAN}DEMOSTRACIÓN:${RESET}"
echo -e "Convertimos el vdev lineal de 1 disco en un arreglo Mirror (RAID 1) en caliente con zpool attach."

echo "$ sudo zpool attach -f zpool_web $DISCO_ACT_1 $DISCO_ACT_2"
zpool attach -f zpool_web "$DISCO_ACT_1" "$DISCO_ACT_2"

echo -e "\nEstado del pool tras la incorporación del espejo:"
zpool status zpool_web

pause_step "Escribir datos y simular transacciones del sitio web..."

# ==============================================================================
# FASE 3: ESCRITURA DE DATOS Y REPLICACIÓN REMOTA ZFS SEND/RECEIVE
# ==============================================================================
header "FASE 3: Escritura de Datos y Replicación ZFS Send/Receive"

WEB_DIR="/var/tmp/lab_zfs_ha/web_root"
mkdir -p "$WEB_DIR"

cat <<'EOF' > "$WEB_DIR/index.html"
<!DOCTYPE html>
<html>
<head><title>ZFS HA Cluster</title></head>
<body>
  <h1>Sitio Activo en ZFS Mirror</h1>
  <p>Compresion LZ4 nativa + Copy-on-Write activo.</p>
</body>
</html>
EOF

echo "Registro de Venta #1001: Cliente Empresa ACME" > "$WEB_DIR/transacciones.log"
ls -lh "$WEB_DIR"

subheader "3.1 Preparar el Pool Pasivo (zpool_backup)"
zpool create -f zpool_backup "$DISCO_PAS_1"
zpool status zpool_backup

pause_step "Tomar snapshot y replicar al pool pasivo..."

subheader "3.2 Snapshot Atómico Base y Envío por Tubería Unix"
echo -e "1. Tomando snapshot inicial instantáneo:"
zfs snapshot zpool_web/site@snap_base
zfs list -t snapshot

echo -e "\n2. Transfiriendo bloques atómicos hacia zpool_backup (zfs send | zfs receive):"
zfs send zpool_web/site@snap_base | zfs receive -F zpool_backup/site

# Poner dataset pasivo en solo lectura
zfs set readonly=on zpool_backup/site

echo -e "\nDatasets en el pool de réplica:"
zfs list -r zpool_backup

pause_step "Probar replicación incremental (deltas)..."

subheader "3.3 Modificación y Replicación Incremental"
echo "Registro de Venta #1002: Transacción Bancaria $50,000 USD" >> "$WEB_DIR/transacciones.log"

zfs snapshot zpool_web/site@snap_delta1
echo -e "Enviando ÚNICAMENTE los bloques modificados (-i):"
zfs send -i zpool_web/site@snap_base zpool_web/site@snap_delta1 | zfs receive -F zpool_backup/site

echo -e "\nSnapshots replicados en el nodo pasivo:"
zfs list -t snapshot -r zpool_backup

pause_step "Avanzar a la simulación de corrupción y auto-curación (Self-Healing)..."

# ==============================================================================
# FASE 4: CORRUPCIÓN INDUCIDA CON DD Y AUTO-CURACIÓN (SELF-HEALING)
# ==============================================================================
header "FASE 4: Detección de Corrupción de Bloques y Auto-Curación (Self-Healing)"
echo -e "${CYAN}CAPACIDAD ÚNICA DE ZFS:${RESET}"
echo -e "Inyectamos datos basura directamente en el segundo disco con dd para simular bit rot."
echo -e "ZFS detectará el hash incorrecto y usará el disco sano para reparar los bloques dañados."

echo -e "\nInyectando 1 MB de datos aleatorios en $DISCO_ACT_2 con dd..."
dd if=/dev/urandom of="$DISCO_ACT_2" bs=1M count=1 seek=15 conv=notrunc status=none

echo -e "Ejecutando zpool scrub para verificar integridad criptográfica de todos los bloques:"
zpool scrub zpool_web
sleep 2

echo -e "\n${GREEN}[INFORME DE AUTO-CURACIÓN DE ZFS]:${RESET}"
zpool status zpool_web

pause_step "Simular conmutación por error (Failover)..."

# ==============================================================================
# FASE 5: SIMULACIÓN DE CONMUTACIÓN POR ERROR (FAILOVER)
# ==============================================================================
header "FASE 5: Simulación de Desastre y Failover hacia el Nodo Pasivo"

echo -e "${RED}[DESASTRE] Destruyendo el pool activo para simular pérdida total del servidor 1...${RESET}"
zpool destroy -f zpool_web

echo -e "\nPromoviendo el dataset del Nodo Pasivo a Producción:"
# 1. Quitar solo-lectura
zfs set readonly=off zpool_backup/site
# 2. Asignar nuevo punto de montaje
zfs set mountpoint=/var/tmp/lab_zfs_ha/promoted_web zpool_backup/site

echo -e "\n${GREEN}[VERIFICACIÓN DE RECUPERACIÓN]:${RESET}"
ls -lh /var/tmp/lab_zfs_ha/promoted_web
echo -e "\nContenido íntegro de transacciones recuperadas:"
cat /var/tmp/lab_zfs_ha/promoted_web/transacciones.log

header "LABORATORIO ZFS FINALIZADO CON ÉXITO"
echo -e "${GREEN}${BOLD}Hitos demostrados en este laboratorio:${RESET}"
echo -e "  1. Creación de zpool nativo y dataset con compresión transparente LZ4."
echo -e "  2. Incorporación de espejo (Mirror) en caliente con zpool attach sin desmontar."
echo -e "  3. Replicación remota atómica inicial e incremental con zfs send/receive."
echo -e "  4. Detección de bit-rot y auto-reparación mediante checksums y zpool scrub."
echo -e "  5. Procedimiento de failover con promoción de dataset y 0 pérdida de transacciones."

if [ "$KEEP_RUNNING" = false ]; then
    echo -e "\n${YELLOW}El script desmontará y limpiará los pools temporales.${RESET}"
else
    echo -e "\n${GREEN}Modo --keep activo: Los recursos quedan en ejecución.${RESET}"
fi
