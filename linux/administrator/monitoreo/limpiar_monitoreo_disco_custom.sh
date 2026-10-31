#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA TOTAL: Métricas de Disco, Filesystem e Inodos (Lab 3.14)
# Referencia: linux/administrator/monitoreo/monitoreo_disco_custom.md
#
# Purgas y reversiones realizadas:
#   1. Grafana:
#      - Standalone (procesos en /tmp, binarios y tarballs)
#      - Contenedor Docker (si se utilizó la opción B de docker)
#      - Servicio systemd (grafana-server) y aprovisionamiento datasource
#      - Repositorio APT (/etc/apt/sources.list.d/grafana.list) y llaves GPG
#   2. Prometheus:
#      - Procesos standalone y servicio systemd (prometheus)
#   3. Node Exporter:
#      - Procesos standalone y servicio systemd (prometheus-node-exporter)
#      - Reversión de /etc/default/prometheus-node-exporter
#   4. Automatización:
#      - Purgado de entradas crontab de colector_disco.sh
#      - Purgado de timers y servicios systemd (colector-disco.*, lab-metrics.*)
#   5. Métricas y Archivos Temporales:
#      - Métricas custom_disk_health.prom* en textfile_collector
#      - Copias en /usr/local/bin/colector_disco.sh y temporales en /tmp/
#
# Parámetros opcionales:
#   --purge-packages   Desinstala y purga paquetes APT (grafana, prometheus)
#   --keep-node        Conserva Node Exporter activo si se usará para otros labs
#   --help, -h         Muestra esta ayuda
#
# Uso:
#   sudo ./limpiar_monitoreo_disco_custom.sh
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

PURGE_PACKAGES=0
KEEP_NODE=0

for arg in "$@"; do
    case "$arg" in
        --purge-packages)
            PURGE_PACKAGES=1
            ;;
        --keep-node)
            KEEP_NODE=1
            ;;
        --help|-h)
            echo "Uso: sudo $0 [OPCIONES]"
            echo "Opciones:"
            echo "  --purge-packages   Desinstala completamente paquetes APT (grafana, prometheus, node-exporter)"
            echo "  --keep-node        Mantiene Node Exporter corriendo para labs posteriores"
            echo "  --help, -h         Muestra este mensaje"
            exit 0
            ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}❌ Error: Este script requiere privilegios de superusuario (root).${C_RESET}"
    echo -e "Ejecutá: ${C_BOLD}sudo $0${C_RESET}"
    exit 1
fi

echo -e "\n${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 🧹 LIMPIEZA TOTAL: LAB 3.14 (MÉTRICAS DISCO, GRAFANA & TELEMETRÍA)    ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}\n"

# ------------------------------------------------------------------------------
# 1. Purgar Grafana (Standalone, Docker y Systemd)
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}[1/6] Purgando procesos y servicios de Grafana (:3000)...${C_RESET}"

# A. Procesos Standalone
GRAFANA_PIDS=$(pgrep -f "grafana.*server" || true)
if [ -n "$GRAFANA_PIDS" ]; then
    echo -e "  ${C_YELLOW}⚠ Finalizando procesos standalone de Grafana (PIDs: ${GRAFANA_PIDS})...${C_RESET}"
    pkill -f "grafana.*server" 2>/dev/null || true
    sleep 1
    echo -e "  ${C_GREEN}✔ Procesos de Grafana terminados.${C_RESET}"
else
    echo -e "  ${C_DIM}• No hay procesos standalone de Grafana activos.${C_RESET}"
fi

# B. Contenedor Docker (si se ejecutó opción B)
if command -v docker &>/dev/null; then
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '^grafana$' &>/dev/null; then
        echo -e "  ${C_YELLOW}⚠ Removiendo contenedor Docker 'grafana'...${C_RESET}"
        docker rm -f grafana &>/dev/null || true
        echo -e "  ${C_GREEN}✔ Contenedor Docker 'grafana' eliminado.${C_RESET}"
    fi
fi

# C. Servicio Systemd (si se instaló vía APT)
if systemctl is-active grafana-server &>/dev/null || systemctl is-enabled grafana-server &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Deteniendo servicio systemd grafana-server...${C_RESET}"
    systemctl stop grafana-server 2>/dev/null || true
    systemctl disable grafana-server 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Servicio grafana-server detenido y deshabilitado.${C_RESET}"
fi

# D. Aprovisionamiento Datasource y archivos en /tmp
if [ -f /etc/grafana/provisioning/datasources/prometheus.yaml ]; then
    rm -f /etc/grafana/provisioning/datasources/prometheus.yaml
    echo -e "  ${C_GREEN}✔ Datasource provisioning eliminado de /etc/grafana/.${C_RESET}"
fi

rm -rf /tmp/grafana* /tmp/grafana-*.tar.gz 2>/dev/null || true
echo -e "  ${C_GREEN}✔ Archivos temporales de Grafana purgados en /tmp/.${C_RESET}"

# E. Repositorio APT de Grafana
if [ -f /etc/apt/sources.list.d/grafana.list ] || [ -f /etc/apt/keyrings/grafana.gpg ]; then
    rm -f /etc/apt/sources.list.d/grafana.list /etc/apt/keyrings/grafana.gpg
    echo -e "  ${C_GREEN}✔ Repositorio y llaves APT de Grafana removidos.${C_RESET}"
fi

# ------------------------------------------------------------------------------
# 2. Purgar Prometheus (:9090)
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[2/6] Purgando procesos y servicios de Prometheus (:9090)...${C_RESET}"

PROM_PIDS=$(pgrep -f "prometheus.*--config.file" || true)
if [ -n "$PROM_PIDS" ]; then
    echo -e "  ${C_YELLOW}⚠ Finalizando procesos standalone de Prometheus (PIDs: ${PROM_PIDS})...${C_RESET}"
    pkill -f "prometheus.*--config.file" 2>/dev/null || true
    sleep 1
    echo -e "  ${C_GREEN}✔ Procesos standalone de Prometheus terminados.${C_RESET}"
fi

if systemctl is-active prometheus &>/dev/null || systemctl is-enabled prometheus &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Deteniendo servicio systemd prometheus...${C_RESET}"
    systemctl stop prometheus 2>/dev/null || true
    systemctl disable prometheus 2>/dev/null || true
    echo -e "  ${C_GREEN}✔ Servicio prometheus detenido.${C_RESET}"
fi

rm -rf /tmp/prometheus* /tmp/prometheus-*.tar.gz 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Purgar Node Exporter (:9100) (si no se indicó --keep-node)
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[3/6] Purgando Node Exporter (:9100)...${C_RESET}"

if [ "$KEEP_NODE" -eq 1 ]; then
    echo -e "  ${C_YELLOW}ℹ Modo --keep-node activado: Se preserva Node Exporter para otros labs.${C_RESET}"
else
    if systemctl is-active prometheus-node-exporter &>/dev/null || systemctl is-enabled prometheus-node-exporter &>/dev/null; then
        echo -e "  ${C_YELLOW}⚠ Deteniendo servicio prometheus-node-exporter...${C_RESET}"
        systemctl stop prometheus-node-exporter 2>/dev/null || true
        systemctl disable prometheus-node-exporter 2>/dev/null || true
        echo -e "  ${C_GREEN}✔ Servicio prometheus-node-exporter detenido.${C_RESET}"
    fi

    NODE_PIDS=$(pgrep -f "node_exporter" || true)
    if [ -n "$NODE_PIDS" ]; then
        echo -e "  ${C_YELLOW}⚠ Finalizando procesos standalone de node_exporter (PIDs: ${NODE_PIDS})...${C_RESET}"
        pkill -f "node_exporter" 2>/dev/null || true
        sleep 1
        echo -e "  ${C_GREEN}✔ Procesos de node_exporter terminados.${C_RESET}"
    fi

    # Revertir argumentos en /etc/default/prometheus-node-exporter si existe
    if [ -f /etc/default/prometheus-node-exporter ]; then
        sed -i '/--collector.textfile.directory/d' /etc/default/prometheus-node-exporter
        echo -e "  ${C_GREEN}✔ Configuración restaurada en /etc/default/prometheus-node-exporter.${C_RESET}"
    fi

    rm -rf /tmp/node_exporter* /tmp/node_exporter-*.tar.gz 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 4. Purgar Automatización (Crontab y Systemd Timers)
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[4/6] Purgando tareas automáticas (Cron y Systemd Timers)...${C_RESET}"

# A. Limpiar Crontab del usuario root
if crontab -l 2>/dev/null | grep -E 'colector_disco|custom_disk' &>/dev/null; then
    echo -e "  ${C_YELLOW}⚠ Removiendo entrada de colector_disco.sh del crontab de root...${C_RESET}"
    crontab -l 2>/dev/null | grep -v -E 'colector_disco|custom_disk' | crontab -
    echo -e "  ${C_GREEN}✔ Crontab actualizado (tarea eliminada).${C_RESET}"
else
    echo -e "  ${C_DIM}• No se encontraron tareas de colector_disco en crontab.${C_RESET}"
fi

# B. Timers de systemd si se crearon
TIMERS=("colector-disco.timer" "colector-disco.service" "lab-metrics.timer" "lab-metrics.service")
for t in "${TIMERS[@]}"; do
    if systemctl is-active "$t" &>/dev/null || systemctl is-enabled "$t" &>/dev/null; then
        systemctl stop "$t" 2>/dev/null || true
        systemctl disable "$t" 2>/dev/null || true
    fi
    if [ -f "/etc/systemd/system/$t" ]; then
        rm -f "/etc/systemd/system/$t"
        echo -e "  ${C_GREEN}✔ Eliminado: /etc/systemd/system/$t${C_RESET}"
    fi
done
systemctl daemon-reload 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Purgar Métricas Textfile y Scripts Colectores
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}[5/6] Limpiando métricas textfile (.prom) y scripts locales...${C_RESET}"

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
if [ -d "$TEXTFILE_DIR" ]; then
    rm -f "${TEXTFILE_DIR}"/custom_disk_health.prom*
    echo -e "  ${C_GREEN}✔ custom_disk_health.prom removido de ${TEXTFILE_DIR}.${C_RESET}"
    
    # Si no hay otros archivos .prom y no se pidió conservar Node Exporter, borrar carpeta
    if [ "$KEEP_NODE" -eq 0 ] && [ -z "$(ls -A "$TEXTFILE_DIR" 2>/dev/null)" ]; then
        rmdir "$TEXTFILE_DIR" 2>/dev/null || true
        echo -e "  ${C_GREEN}✔ Directorio ${TEXTFILE_DIR} eliminado.${C_RESET}"
    fi
fi

if [ -f /usr/local/bin/colector_disco.sh ]; then
    rm -f /usr/local/bin/colector_disco.sh
    echo -e "  ${C_GREEN}✔ /usr/local/bin/colector_disco.sh eliminado.${C_RESET}"
fi

rm -f /tmp/custom_disk_health.prom* 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Desinstalación opcional de paquetes APT (--purge-packages)
# ------------------------------------------------------------------------------
if [ "$PURGE_PACKAGES" -eq 1 ] && command -v apt-get &>/dev/null; then
    echo -e "\n${C_BOLD}[6/6] Desinstalando paquetes APT (--purge-packages)...${C_RESET}"
    echo -e "  ${C_YELLOW}⚠ Purgando grafana, prometheus y prometheus-node-exporter...${C_RESET}"
    apt-get purge -y grafana prometheus prometheus-node-exporter &>/dev/null || true
    apt-get autoremove -y &>/dev/null || true
    echo -e "  ${C_GREEN}✔ Paquetes purgados exitosamente.${C_RESET}"
else
    echo -e "\n${C_BOLD}[6/6] Paquetes de distribución:${C_RESET} ${C_DIM}No se purgaron paquetes APT (usá --purge-packages si deseás desinstalarlos).${C_RESET}"
fi

# ------------------------------------------------------------------------------
# Verificación de Estado Final
# ------------------------------------------------------------------------------
echo -e "\n${C_BOLD}${C_CYAN}----------------------------------------------------------------------${C_RESET}"
echo -e "${C_BOLD}🔍 ESTADO FINAL DE PUERTOS Y SERVICIOS:${C_RESET}"

check_port() {
    local port="$1"
    local desc="$2"
    if ss -tlpn 2>/dev/null | grep -E ":${port}\s" &>/dev/null; then
        echo -e " • Puerto :${port} (${desc}): ${C_RED}⚠ AÚN ESCUCHANDO${C_RESET}"
    else
        echo -e " • Puerto :${port} (${desc}): ${C_GREEN}✔ CERRADO (Limpio)${C_RESET}"
    fi
}

check_port 3000 "Grafana"
check_port 9090 "Prometheus"
check_port 9100 "Node Exporter"

if crontab -l 2>/dev/null | grep -E 'colector_disco' &>/dev/null; then
    echo -e " • Crontab de root:             ${C_RED}⚠ Tarea aún presente${C_RESET}"
else
    echo -e " • Crontab de root:             ${C_GREEN}✔ SIN TAREAS RESIDUALES${C_RESET}"
fi

if [ -f "/var/lib/node_exporter/textfile_collector/custom_disk_health.prom" ]; then
    echo -e " • custom_disk_health.prom:     ${C_RED}⚠ Aún presente${C_RESET}"
else
    echo -e " • custom_disk_health.prom:     ${C_GREEN}✔ ELIMINADO${C_RESET}"
fi

echo -e "${C_BOLD}${C_CYAN}======================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}✔ Desmantelamiento y limpieza de Lab 3.14 completados exitosamente.${C_RESET}\n"
