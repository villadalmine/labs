#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA TOTAL: Taller Integrador Web sobre LVM RAID 1 & Monitoreo
# Referencia: linux/administrator/monitoreo/taller_integrador_web_lvm_monitoreo.md (Lab 3.16)
#
# Purgas y reversiones realizadas:
#   1. Servidor Web Python (puerto 8080) y generador de tráfico en background
#   2. Agente Node Exporter (puerto 9100) si fue iniciado para el taller
#   3. Punto de montaje /var/www/html_lab y contenido HTML5
#   4. Volumen lógico lv_html y Grupo de Volúmenes vg_web (LVM RAID 1)
#   5. Firmas LVM (pvremove) y wipefs sobre loop devices (/dev/loop10..12 o dinámicos)
#   6. Desvinculación de loop devices (losetup -d)
#   7. Archivos de imagen en /tmp/taller_integrador y /tmp/raid_web
#   8. Métricas textfile (web_traffic.prom) y contadores temporales
#
# Uso:
#   sudo ./limpiar_taller_integrador_web_lvm_monitoreo.sh
# ==============================================================================

set -uo pipefail

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_CYAN="\033[0;36m"
C_DIM="\033[2m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Error: Este script requiere privilegios de superusuario (root).${C_RESET}"
    echo -e "Ejecutá: ${C_BOLD}sudo $0${C_RESET}"
    exit 1
fi

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 🧹 LIMPIEZA TOTAL: TALLER INTEGRADOR WEB LVM RAID 1 & MONITOREO (3.16) ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}\n"

# ------------------------------------------------------------------------------
# 1. Detener Servidor Web y Tráfico
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}[1/6] Deteniendo servidor web HTTP y procesos de tráfico...${C_RESET}"

# Matar procesos en puerto 8080
if command -v fuser &>/dev/null; then
    fuser -k 8080/tcp 2>/dev/null || true
fi
pkill -f "python3 -m http.server 8080" 2>/dev/null || true
pkill -f "http.server.*8080" 2>/dev/null || true
pkill -f "tui_monitoreo.sh" 2>/dev/null || true
pkill -f "alerta_centinela.sh" 2>/dev/null || true
echo -e "  ${C_GREEN}✔ Procesos de servidor web, TUI y centinela finalizados.${C_RESET}"

# ------------------------------------------------------------------------------
# 2. Detener Procesos de Telemetría (Node Exporter, Prometheus y Grafana)
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[2/6] Verificando y finalizando Node Exporter, Prometheus y Grafana...${C_RESET}"

pkill -f "node_exporter" 2>/dev/null || true
pkill -f "prometheus.*--config.file" 2>/dev/null || true
pkill -f "grafana.*server" 2>/dev/null || true
echo -e "  ${C_GREEN}✔ Procesos de Node Exporter, Prometheus y Grafana finalizados.${C_RESET}"

# ------------------------------------------------------------------------------
# 3. Desmontar /var/www/html_lab
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[3/6] Desmontando sistema de archivos de la web corporativa...${C_RESET}"

MOUNT_DIR="/var/www/html_lab"
if mountpoint -q "$MOUNT_DIR" 2>/dev/null || grep -qs "$MOUNT_DIR" /proc/mounts; then
    echo -e "  ${C_YELLOW}⚠ Desmontando ${MOUNT_DIR}...${C_RESET}"
    umount -f "$MOUNT_DIR" 2>/dev/null || umount -l "$MOUNT_DIR" 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ ${MOUNT_DIR} desmontado.${C_RESET}"
else
    echo -e "  ${C_DIM}• ${MOUNT_DIR} no está montado.${C_RESET}"
fi

if [ -d "$MOUNT_DIR" ]; then
    rm -rf "$MOUNT_DIR"
    echo -e "  ${C_GREEN}✔ Directorio ${MOUNT_DIR} eliminado.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 4. Desmantelar LVM RAID 1 (vg_web / lv_html)
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[4/6] Desmantelando almacenamiento LVM RAID 1 (vg_web)...${C_RESET}"

VG_NAME="vg_web"
if vgs "$VG_NAME" &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Desactivando volúmenes lógicos en ${VG_NAME}...${C_RESET}"
    lvchange -an "$VG_NAME" 2>/dev/null || true
    echo -e "  ${C_YELLOW}⚠ Eliminando Grupo de Volúmenes ${VG_NAME}...${C_RESET}"
    vgremove -f -y "$VG_NAME" 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Volume Group ${VG_NAME} eliminado exitosamente.${C_RESET}"
else
    echo -e "  ${C_DIM}• Volume Group ${VG_NAME} no existe en el sistema.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 5. Purgar Loop Devices y Firmas Físicas
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[5/6] Desvinculando loop devices y limpiando firmas de bloque...${C_RESET}"

# Buscar loop devices asociados a imágenes del taller
ASSOCIATED_LOOPS=$(losetup -a 2>/dev/null | grep -E 'taller_integrador|raid_web|disk[0-9]|disk_spare' | cut -d: -f1 || true)
CANDIDATE_LOOPS=("/dev/loop10" "/dev/loop11" "/dev/loop12")

ALL_LOOPS=()
for l in $ASSOCIATED_LOOPS; do
    ALL_LOOPS+=("$l")
done
for l in "${CANDIDATE_LOOPS[@]}"; do
    if [ -b "$l" ]; then
        ALL_LOOPS+=("$l")
    fi
done

# Eliminar duplicados
UNIQUE_LOOPS=($(echo "${ALL_LOOPS[@]:-}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

if [ "${#UNIQUE_LOOPS[@]}" -gt 0 ]; then
    for dev in "${UNIQUE_LOOPS[@]}"; do
        if [ -n "$dev" ] && [ -b "$dev" ]; then
            echo -e "  ${C_YELLOW}⚠ Limpiando ${dev}...${C_RESET}"
            pvremove -ff -y "$dev" 2>/dev/null || true
            wipefs -a -f "$dev" 2>/dev/null || true
            losetup -d "$dev" 2>/dev/null || true
            echo -e "  ${C_GREEN}✔ Loop device ${dev} liberado.${C_RESET}"
        fi
    done
else
    echo -e "  ${C_DIM}• No se encontraron loop devices del taller activos.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 6. Eliminar Archivos Temporales e Imágenes de Disco
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[6/6] Purgando imágenes de disco y métricas temporales...${C_RESET}"

DIRS_TO_PURGE=(
    "/tmp/taller_integrador"
    "/tmp/raid_web"
    "/tmp/prometheus_data"
)

# Nota: Preservamos los binarios descargados /tmp/prometheus y /tmp/grafana-*
# para que las siguientes ejecuciones de clase inicien en milisegundos sin re-descargar.
# Si deseás purgar los binarios portables: rm -rf /tmp/prometheus /tmp/grafana-* /tmp/dashboards

for d in "${DIRS_TO_PURGE[@]}"; do
    rm -rf $d 2>/dev/null || true
done

FILES_TO_PURGE=(
    "/tmp/web_requests.count"
    "/tmp/web_traffic.count"
    "/tmp/node_exporter_taller.log"
    "/tmp/prometheus.log"
    "/tmp/prometheus.yml"
    "/tmp/grafana.log"
    "/tmp/root_mail.log"
    "/var/lib/node_exporter/textfile_collector/web_traffic.prom"
    "/var/lib/node_exporter/textfile_collector/web.prom"
    "/var/lib/node_exporter/textfile_collector/storage_mirror.prom"
)

for f in "${FILES_TO_PURGE[@]}"; do
    if [ -f "$f" ]; then
        rm -f "$f"
        echo -e "  ${C_GREEN}✔ Archivo eliminado: ${f}${C_RESET}"
    fi
done

# Si textfile_collector quedó vacío, limpiarlo
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
if [ -d "$TEXTFILE_DIR" ] && [ -z "$(ls -A "$TEXTFILE_DIR" 2>/dev/null)" ]; then
    rmdir "$TEXTFILE_DIR" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# Verificación de Estado Final
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "${C_BOLD}🔍 ESTADO FINAL DEL SISTEMA:${C_RESET}"

check_port() {
    local port="$1"
    local desc="$2"
    if ss -tlpn 2>/dev/null | grep -E ":${port}\s" &>/dev/null; then
        echo -e " • Puerto :${port} (${desc}): ${C_RED}⚠ AÚN ESCUCHANDO${C_RESET}"
    else
        echo -e " • Puerto :${port} (${desc}): ${C_GREEN}✔ CERRADO (Limpio)${C_RESET}"
    fi
}

check_port 8080 "Servidor Web"
check_port 9100 "Node Exporter"
check_port 9090 "Prometheus"
check_port 3000 "Grafana"

if vgs "$VG_NAME" &>/dev/null; then
    echo -e " • Volume Group ${VG_NAME}:       ${C_RED}⚠ Aún registrado en LVM${C_RESET}"
else
    echo -e " • Volume Group ${VG_NAME}:       ${C_GREEN}✔ ELIMINADO${C_RESET}"
fi

if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
    echo -e " • Montaje ${MOUNT_DIR}:    ${C_RED}⚠ Aún montado${C_RESET}"
else
    echo -e " • Montaje ${MOUNT_DIR}:    ${C_GREEN}✔ DESMONTADO Y LIMPIO${C_RESET}"
fi

REMAINING_LOOPS=$(losetup -a 2>/dev/null | grep -E 'taller_integrador|raid_web' || true)
if [ -n "$REMAINING_LOOPS" ]; then
    echo -e " • Loop Devices:                ${C_RED}⚠ Aún activos: ${REMAINING_LOOPS}${C_RESET}"
else
    echo -e " • Loop Devices:                ${C_GREEN}✔ LIBERADOS${C_RESET}"
fi

echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}✔ Desmantelamiento y limpieza de Lab 3.16 completados exitosamente.${C_RESET}\n"
