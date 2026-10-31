#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA TOTAL: Labs de Monitoreo y Métricas
# Referencia: 
#   - linux/administrator/monitoreo/monitoreo_metricas.md (Lab 3.6)
#   - linux/administrator/monitoreo/monitoreo_disco_custom.md (Lab 3.14)
#
# Elimina y purga:
#   1. Timers y servicios systemd (lab-metrics.timer, lab-metrics.service)
#   2. Procesos en segundo plano de Node Exporter y demonios de prueba
#   3. Scripts colectores creados en /usr/local/bin/
#   4. Archivos de métricas textfile (.prom) y directorios en /var/lib/node_exporte
#   5. Archivos de backups simulados en /var/backups/lab
#   6. Binarios y archivos temporales en /tmp/
#
# Uso:
#   sudo ./limpiar_monitoreo.sh
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
echo -e "${C_BOLD}${C_CYAN} 🧹 LIMPIEZA AUTOMATIZADA: LABS DE MONITOREO Y MÉTRICAS LINUX         ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}\n"

# ------------------------------------------------------------------------------
# 1. Detener y deshabilitar Systemd Timers y Servicios
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}[1/6] Deteniendo Systemd Timers y Servicios automáticos...${C_RESET}"

if systemctl is-active lab-metrics.timer &>/dev/null || systemctl is-enabled lab-metrics.timer &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Deteniendo y deshabilitando lab-metrics.timer...${C_RESET}"
    systemctl stop lab-metrics.timer 2>/dev/null || true
    systemctl disable lab-metrics.timer 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ lab-metrics.timer detenido.${C_RESET}"
else
    echo -e "  ${C_DIM}• lab-metrics.timer no está activo.${C_RESET}"
fi

if systemctl is-active lab-metrics.service &>/dev/null; then
    systemctl stop lab-metrics.service 2>/dev/null || true
fi

# Eliminar archivos unitarios si existen
if [ -f /etc/systemd/system/lab-metrics.timer ] || [ -f /etc/systemd/system/lab-metrics.service ]; then
    rm -f /etc/systemd/system/lab-metrics.timer /etc/systemd/system/lab-metrics.service
    systemctl daemon-reload
    echo -e "  ${C_GREEN}✔ Archivos de servicio de lab-metrics removidos de /etc/systemd/system/.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 2. Detener procesos de Node Exporte
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[2/6] Deteniendo procesos de Node Exporter...${C_RESET}"

# Detener servicio de distribución si está activo
if systemctl is-active prometheus-node-exporter &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Deteniendo servicio prometheus-node-exporter...${C_RESET}"
    systemctl stop prometheus-node-exporter 2>/dev/null || true
    systemctl disable prometheus-node-exporter 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Servicio prometheus-node-exporter detenido.${C_RESET}"
fi

# Matar procesos standalone si se lanzaron en segundo plano
NODE_PIDS=$(pgrep -f "node_exporter" || true)
if [ -n "$NODE_PIDS" ]; then
    echo -e "  ${C_YELLOW}⚠ Terminando procesos independientes de node_exporter (PIDs: ${NODE_PIDS})...${C_RESET}"
    pkill -f "node_exporter" 2>/dev/null || true
    sleep 1
    echo -e "  ${C_GREEN}✔ Procesos de node_exporter finalizados.${C_RESET}"
else
    echo -e "  ${C_DIM}• No se detectaron procesos activos de node_exporter.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 3. Eliminar scripts colectores en /usr/local/bin
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[3/6] Eliminando scripts colectores en /usr/local/bin/...${C_RESET}"

COLECTORES=(
    "/usr/local/bin/colector_mirror.sh"
    "/usr/local/bin/colector_sistema_lab.sh"
    "/usr/local/bin/colector_sistema.sh"
    "/usr/local/bin/backup_simulado.sh"
    "/usr/local/bin/backup_con_metricas.sh"
    "/usr/local/bin/colector_disco.sh"
    "/usr/local/bin/check_lab_mirror.sh"
    "/usr/local/bin/node_exporter"
)

REMOVED_SCRIPTS=0
for script in "${COLECTORES[@]}"; do
    if [ -f "$script" ]; then
        rm -f "$script"
        echo -e "  ${C_GREEN}✔ Eliminado: ${script}${C_RESET}"
        REMOVED_SCRIPTS=$((REMOVED_SCRIPTS + 1))
    fi
done

if [ "$REMOVED_SCRIPTS" -eq 0 ]; then
    echo -e "  ${C_DIM}• No se encontraron scripts colectores residuales en /usr/local/bin/.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 4. Limpiar directorio Textfile Collector y archivos de métricas (.prom)
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[4/6] Limpiando métricas textfile (.prom)...${C_RESET}"

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
if [ -d "$TEXTFILE_DIR" ]; then
    rm -rf "$TEXTFILE_DIR"
    echo -e "  ${C_GREEN}✔ Directorio ${TEXTFILE_DIR} eliminado.${C_RESET}"
else
    echo -e "  ${C_DIM}• Directorio ${TEXTFILE_DIR} no existe.${C_RESET}"
fi

# Si /var/lib/node_exporter quedó vacío, borrarlo
if [ -d "/var/lib/node_exporter" ] && [ -z "$(ls -A /var/lib/node_exporter 2>/dev/null)" ]; then
    rmdir "/var/lib/node_exporter" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 5. Limpiar backups simulados de prueba
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[5/6] Eliminando copias de seguridad de prueba (/var/backups/lab)...${C_RESET}"

if [ -d "/var/backups/lab" ]; then
    rm -rf "/var/backups/lab"
    echo -e "  ${C_GREEN}✔ Directorio /var/backups/lab eliminado.${C_RESET}"
else
    echo -e "  ${C_DIM}• No hay respaldos de prueba en /var/backups/lab.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 6. Limpiar archivos temporales en /tmp
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[6/6] Purgando archivos temporales en /tmp/...${C_RESET}"

rm -f /tmp/metricas_artesanales.sh
rm -f /tmp/node_exporter.log
rm -f /tmp/node_exporter*.tar.gz
rm -rf /tmp/node_exporter*
rm -f /tmp/simular_falla_mirro
rm -f /tmp/lab_http_requests.count
rm -rf /tmp/mock_backup_di
echo -e "  ${C_GREEN}✔ Archivos temporales purgados en /tmp/.${C_RESET}"

# ------------------------------------------------------------------------------
# Verificación de Estado Final
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "${C_BOLD}🔍 ESTADO FINAL DEL SISTEMA:${C_RESET}"

PORT_CHECK=$(ss -tlpn 2>/dev/null | grep ":9100 " || true)
if [ -z "$PORT_CHECK" ]; then
    echo -e " • Puerto :9100 (Node Exporter): ${C_GREEN}✔ CERRADO (Limpio)${C_RESET}"
else
    echo -e " • Puerto :9100 (Node Exporter): ${C_RED}⚠ Aún escuchando: ${PORT_CHECK}${C_RESET}"
fi

TIMER_CHECK=$(systemctl list-timers --all 2>/dev/null | grep "lab-metrics" || true)
if [ -z "$TIMER_CHECK" ]; then
    echo -e " • Systemd Timers (lab-metrics): ${C_GREEN}✔ NO EXISTE (Limpio)${C_RESET}"
else
    echo -e " • Systemd Timers (lab-metrics): ${C_RED}⚠ Aún registrado${C_RESET}"
fi

if [ ! -d "/var/lib/node_exporter/textfile_collector" ]; then
    echo -e " • Textfile Collector:          ${C_GREEN}✔ ELIMINADO (Limpio)${C_RESET}"
else
    echo -e " • Textfile Collector:          ${C_RED}⚠ Directorio aún presente${C_RESET}"
fi

echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}✔ Entorno de monitoreo desmantelado y 100% limpio.${C_RESET}\n"
