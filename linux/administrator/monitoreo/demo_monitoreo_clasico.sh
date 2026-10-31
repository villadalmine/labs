#!/usr/bin/env bash
# ==============================================================================
# demo_monitoreo_clasico.sh - Demostración Práctica de Monitoreo Vieja Escuela
#
# Demuestra el funcionamiento de StatsD (UDP Push), collectd (muestreo a CSV)
# y herramientas de diagnóstico embebidas en terminal (vmstat, dstat).
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_SCRIPT="${SCRIPT_DIR}/scripts/statsd_collectd_mini.py"
LAB_DIR="/tmp/classic_monitoring"
PORT_STATSD=8125

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║          📟 MONITOREO VIEJA ESCUELA: StatsD (UDP), collectd & CLI          ║"
echo "║   Protocolos de Baja Sobrecarga, Fire-and-Forget y Diagnóstico Embebido      ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Limpieza preventiva
mkdir -p "${LAB_DIR}"
pkill -f "statsd_collectd_mini.py" 2>/dev/null || true

# 2. Iniciar el Daemon de Monitoreo Clásico
echo -e "${YELLOW}▶ [PASO 1/4] Iniciando Daemon de Monitoreo Clásico (StatsD + collectd)...${NC}"
python3 "${DAEMON_SCRIPT}" --port "${PORT_STATSD}" --dir "${LAB_DIR}" > "${LAB_DIR}/daemon.log" 2>&1 &
DAEMON_PID=$!
sleep 2

if ps -p "${DAEMON_PID}" >/dev/null; then
    echo -e "${GREEN}✓ Daemon activo escuchando en UDP 127.0.0.1:${PORT_STATSD} (PID: ${DAEMON_PID})${NC}"
else
    echo -e "${RED}Error al iniciar el daemon. Consulte ${LAB_DIR}/daemon.log${NC}"
    exit 1
fi

# 3. Envío de Métricas StatsD por UDP (Fire-and-Forget)
echo -e "\n${YELLOW}▶ [PASO 2/4] Transmitiendo métricas por UDP con netcat y /dev/udp...${NC}"
echo -e "${DIM}  En la era 'vieja escuela', las aplicaciones enviaban métricas por UDP para no bloquear el hilo de ejecución si el monitor caía.${NC}\n"

send_udp_metric() {
    local payload="$1"
    echo -e "  ${CYAN}Enviando UDP:${NC} ${BOLD}${payload}${NC}"
    if command -v nc >/dev/null 2>&1; then
        echo -n "${payload}" | nc -u -w1 127.0.0.1 "${PORT_STATSD}" 2>/dev/null || true
    else
        # Fallback a socket nativo de Bash si netcat no está disponible
        echo -n "${payload}" > "/dev/udp/127.0.0.1/${PORT_STATSD}" 2>/dev/null || true
    fi
}

# Simular peticiones y eventos
send_udp_metric "web.page_views:1|c"
send_udp_metric "web.page_views:1|c"
send_udp_metric "auth.login_success:1|c"
send_udp_metric "auth.login_failures:3|c"
send_udp_metric "mysql.active_connections:42|g"
send_udp_metric "app.worker_pool.busy:7|g"
send_udp_metric "api.checkout_latency:128.5|ms"
send_udp_metric "api.checkout_latency:94.2|ms"

sleep 3

# 4. Inspección de Archivos CSV Generados estilo collectd
echo -e "\n${YELLOW}▶ [PASO 3/4] Inspeccionando almacenamiento periódico estilo collectd (CSV)...${NC}"
CSV_FILE="${LAB_DIR}/csv/system_metrics.csv"
if [ -f "${CSV_FILE}" ]; then
    echo -e "${GREEN}✓ Archivo de series temporales generado en: ${CSV_FILE}${NC}"
    echo -e "${DIM}--------------------------------------------------------------------------------${NC}"
    tail -n 12 "${CSV_FILE}"
    echo -e "${DIM}--------------------------------------------------------------------------------${NC}"
else
    echo -e "${YELLOW}Esperando primer ciclo de persistencia collectd...${NC}"
fi

# 5. Herramientas Embebidas de Diagnóstico por Terminal
echo -e "\n${YELLOW}▶ [PASO 4/4] Diagnóstico Embebido de Terminal (vmstat)...${NC}"
echo -e "${DIM}  Herramientas como vmstat o iostat permitían a los sysadmins auditar la salud del kernel sin servidores gráficos:${NC}\n"

if command -v vmstat >/dev/null 2>&1; then
    vmstat 1 3
fi

echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}✅ Demostración de monitoreo clásico finalizada con éxito.${NC}"
echo -e "   ${CYAN}• Los datos persisten en:${NC} ${LAB_DIR}/csv/system_metrics.csv"
echo -e "   ${CYAN}• Para limpiar el laboratorio ejecute:${NC} ./linux/administrator/monitoreo/limpiar_monitoreo_clasico.sh"
