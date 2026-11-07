#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: Monitoreo Clásico (StatsD, collectd y Diagnóstico CLI)
# Laboratorio: linux/administrator/monitoreo/monitoreo_clasico_collectd_statsd.md
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Protocolo StatsD: Métricas UDP Push "Fire-and-Forget" (Counters, Gauges, Timers).
#  - Colector periódico estilo collectd: Muestreo del kernel a archivos CSV.
#  - Diagnóstico embebido de terminal (vmstat, iostat).
#  - Preguntas disparadoras ("pie de clase") con respuestas desplegables.
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   ./demo_monitoreo_clasico.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_monitoreo_clasico.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
#   ./demo_monitoreo_clasico.sh --keep   -> Preserva el daemon y los CSVs para pruebas
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
KEEP_RUNNING=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
            shift 2
            ;;
        --keep)
            KEEP_RUNNING=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_SCRIPT="${SCRIPT_DIR}/scripts/statsd_collectd_mini.py"
LAB_DIR="/tmp/classic_monitoring_$$"
PORT_STATSD=8125
DAEMON_PID=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo daemon de monitoreo clásico y liberando recursos...${C_RESET}"
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${C_GREEN}[INFO] Daemon y archivos preservados en: ${LAB_DIR}${C_RESET}"
        echo -e "Para detenerlo manualmente: pkill -f statsd_collectd_mini.py"
        return
    fi

    if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID" 2>/dev/null || true
    fi
    pkill -f "statsd_collectd_mini.py" 2>/dev/null || true
    rm -rf "${LAB_DIR}" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Daemon detenido y directorio temporal eliminado.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_DIM}⏳ [MODO AUTO] Esperando ${AUTO_WAIT}s...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${mensaje}${C_RESET}"
        read -r </dev/tty 2>/dev/null || read -r
    fi
}

step_banner() {
    local num="$1"
    local title="$2"
    echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_YELLOW}PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💡 EXPLICACIÓN TEÓRICA:${C_RESET} $1"
}

pie_clase() {
    local pregunta="$1"
    local respuesta="${2:-}"
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase / autoaprendizaje: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_WAIT" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta esperada...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
    fi
}

run_and_show() {
    local cmd="$1"
    echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR ────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"
    
    local output
    output=$(eval "$cmd" 2>&1) || true
    
    if [ -z "$output" ]; then
        echo -e "${C_YELLOW}(El comando finalizó exitosamente sin imprimir texto en stdout/stderr)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 📟 DEMOSTRACIÓN EN VIVO: MONITOREO CLÁSICO (StatsD, collectd & CLI)          ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "Métricas Push UDP (Fire-and-Forget) ➔ Muestreo C a CSVs ➔ Diagnóstico Embebido"

# ==============================================================================
# PASO 1: INICIAR EL DAEMON DE MONITOREO CLÁSICO
# ==============================================================================
step_banner "1" "Inicio del Receptor StatsD (UDP :8125) y Motor collectd"

explain "En las arquitecturas previas a Prometheus, los sistemas dependían de demonios push locales."
explain "Iniciamos el daemon en segundo plano escuchando paquetes UDP en el puerto ${PORT_STATSD}:"

mkdir -p "${LAB_DIR}"
pkill -f "statsd_collectd_mini.py" 2>/dev/null || true

python3 "${DAEMON_SCRIPT}" --port "${PORT_STATSD}" --dir "${LAB_DIR}" > "${LAB_DIR}/daemon.log" 2>&1 &
DAEMON_PID=$!
sleep 1

if ps -p "${DAEMON_PID}" >/dev/null; then
    echo -e "${C_GREEN}✔ Daemon activo escuchando en UDP 127.0.0.1:${PORT_STATSD} (PID: ${DAEMON_PID})${C_RESET}"
else
    echo -e "${C_RED}[ERROR] No se pudo iniciar el daemon. Consultá ${LAB_DIR}/daemon.log${C_RESET}"
    exit 1
fi

explain "Verificamos los sockets abiertos en el sistema:"
run_and_show "ss -ulnp | grep ':${PORT_STATSD}' || netstat -ulnp 2>/dev/null | grep ':${PORT_STATSD}' || echo 'Socket UDP :${PORT_STATSD} activo por PID ${DAEMON_PID}'"

pie_clase "¿Por qué StatsD utiliza el protocolo de transporte UDP en lugar de TCP?" \
          "Porque UDP es 'Fire-and-Forget' (sin acuse de recibo ni handshake). Si el servidor de métricas colapsa, la aplicación web NO se bloquea esperando timeouts TCP."

pause_step "Presioná [ENTER] para transmitir métricas por UDP..."

# ==============================================================================
# PASO 2: TRANSMISIÓN DE MÉTRICAS STATSD POR UDP
# ==============================================================================
step_banner "2" "Transmisión de Métricas por UDP (Counters, Gauges, Timers)"

explain "Las aplicaciones enviaban métricas inyectando cadenas simples por sockets UDP:"
explain "Formato: <nombre_metrica>:<valor>|<tipo> (c=Counter, g=Gauge, ms=Timer)"

send_udp_metric() {
    local payload="$1"
    echo -e "  ${C_CYAN}Enviando UDP:${C_RESET} ${C_BOLD}${payload}${C_RESET}"
    if command -v nc >/dev/null 2>&1; then
        echo -n "${payload}" | nc -u -w1 127.0.0.1 "${PORT_STATSD}" 2>/dev/null || true
    else
        echo -n "${payload}" > "/dev/udp/127.0.0.1/${PORT_STATSD}" 2>/dev/null || true
    fi
}

send_udp_metric "web.page_views:1|c"
send_udp_metric "web.page_views:1|c"
send_udp_metric "auth.login_success:1|c"
send_udp_metric "auth.login_failures:3|c"
send_udp_metric "mysql.active_connections:42|g"
send_udp_metric "app.worker_pool.busy:7|g"
send_udp_metric "api.checkout_latency:128.5|ms"
send_udp_metric "api.checkout_latency:94.2|ms"

sleep 1

explain "Inspeccionamos el log del daemon para verificar la recepción y agregación en memoria:"
run_and_show "cat ${LAB_DIR}/daemon.log"

pie_clase "¿Qué desventaja crítica tiene enviar métricas por UDP si la red se satura?" \
          "Pérdida silenciosa de paquetes. Como UDP no garantiza entrega ni retransmisión, las métricas se pierden sin que el emisor se entere."

pause_step "Presioná [ENTER] para inspeccionar la persistencia periódica estilo collectd..."

# ==============================================================================
# PASO 3: INSPECCIÓN DE ARCHIVOS CSV ESTILO COLLECTD
# ==============================================================================
step_banner "3" "Persistencia Periódica en Archivos Planos CSV (Estilo collectd)"

explain "Demonios clásicos como collectd escribían métricas a disco en archivos RRD o CSV cada N segundos."
CSV_FILE="${LAB_DIR}/csv/system_metrics.csv"
sleep 2

if [ -f "${CSV_FILE}" ]; then
    explain "Contenido del archivo temporal de series temporales en CSV:"
    run_and_show "tail -n 10 ${CSV_FILE}"
else
    explain "Esperando ciclo de escritura a CSV..."
    sleep 2
    [ -f "${CSV_FILE}" ] && run_and_show "tail -n 10 ${CSV_FILE}"
fi

pie_clase "¿Por qué el almacenamiento en CSV / RRD de collectd no escaló en entornos con miles de contenedores y microservicios?" \
          "Por la saturación masiva de I/O de disco al escribir miles de archivos individuales por segundo, y la rigidez de no admitir etiquetas dinámicas (labels/tags)."

pause_step "Presioná [ENTER] para ver herramientas embebidas de terminal..."

# ==============================================================================
# PASO 4: DIAGNÓSTICO EMBEBIDO EN TERMINAL (VMSTAT & IOSTAT)
# ==============================================================================
step_banner "4" "Diagnóstico Embebido de Terminal (vmstat & iostat)"

explain "Antes de los dashboards gráficos, los operadores diagnosticaban la salud del kernel directamente en consola."
explain "Ejecutamos 'vmstat 1 3' (intervalo de 1s, 3 muestras):"
explain "Columnas críticas: 'r' (procesos esperando CPU), 'si/so' (swapping), 'wa' (I/O wait):"

if command -v vmstat >/dev/null 2>&1; then
    run_and_show "vmstat 1 3"
else
    explain "vmstat no disponible en este entorno."
fi

if command -v iostat >/dev/null 2>&1; then
    explain "Auditoría de latencia de almacenamiento con iostat:"
    run_and_show "iostat -x 1 2 2>/dev/null | head -n 15"
fi

pie_clase "En la salida de vmstat, si la columna 'wa' (wait I/O) es alta y la CPU 'id' (idle) está cerca de cero, ¿dónde está el cuello de botella?" \
          "En el subsistema de almacenamiento (disco saturado o latencia excesiva en operaciones de lectura/escritura)."

pause_step "Presioná [ENTER] para ver el resumen de la evolución de monitoreo..."

# ==============================================================================
# PASO 5: COMPARATIVA Y EVOLUCIÓN HISTÓRICA
# ==============================================================================
step_banner "5" "Evolución: De StatsD/collectd a Prometheus/OpenMetrics"

printf "${C_BOLD}%-25s %-25s %-30s${C_RESET}\n" "CARACTERÍSTICA" "ERA CLÁSICA (StatsD/collectd)" "ERA MODERNA (Prometheus PULL)"
printf "%-25s %-25s %-30s\n" "-------------------------" "-------------------------" "------------------------------"
printf "%-25s %-25s ${C_GREEN}%-30s${C_RESET}\n" "Protocolo" "UDP Push (Fire & Forget)" "HTTP Pull (REST / OpenMetrics)"
printf "%-25s %-25s ${C_GREEN}%-30s${C_RESET}\n" "Modelo de Datos" "Jerárquico (puntos)" "Multi-dimensional (Labels/Tags)"
printf "%-25s %-25s ${C_GREEN}%-30s${C_RESET}\n" "Detección de Caídas" "Imposible (silenciosa)" "Inmediata (up == 0 y scrape timeout)"
printf "%-25s %-25s ${C_GREEN}%-30s${C_RESET}\n" "Persistencia" "Archivos RRD / CSV" "TSDB de alta compresión (Gorilla)"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE MONITOREO CLÁSICO FINALIZADA CON ÉXITO!                  ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}\n"
