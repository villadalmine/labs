#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: rsyslog Avanzado (RainerScript, TLS y Disk Queues)
# Laboratorio: linux/administrator/logs/rsyslog_filtrado_plantillas_tls_colas.md (Lab 3.21)
#
# Cubre:
#  - Validación de sintaxis con rsyslogd -N1
#  - Instancia servidor aislada (UDP :15514 + TCP/TLS :16514) con RainerScript
#  - Filtrado (descarte *.debug, ruteo $programname == 'mi_aplicacion') + JSON
#  - PKI efímera OpenSSL con SAN y autenticación mutua x509/name
#  - Instancia cliente aislada con imfile + omfwd TLS + Disk-Assisted Queue
#  - Caos en vivo: caída del colector, retención en cola y drenaje con 0% pérdida
#
# Uso:
#   sudo ./demo_rsyslog_pipelines.sh [--auto <segundos>] [--keep] [--clean] [--help]
# ==============================================================================

set -uo pipefail

if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[0;36m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para ejecutar rsyslogd aislado.${C_RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Uso: sudo ./demo_rsyslog_pipelines.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${C_YELLOW}⏳ [MODO AUTO] Esperando ${AUTO_DELAY}s: ${mensaje}${C_RESET}"
        sleep "$AUTO_DELAY"
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
        if [ "$AUTO_MODE" = true ]; then
            sleep "$AUTO_DELAY"
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

DIR_LAB="/var/spool/rsyslog/lab_demo_rsyslog"
LOG_DIR="/var/log/lab_demo_rsyslog"
SRV_PID_FILE="${DIR_LAB}/rsyslog_srv.pid"
CLI_PID_FILE="${DIR_LAB}/rsyslog_cli.pid"

stop_pid_file() {
    local pf="$1"
    if [ -f "$pf" ]; then
        local p
        p=$(cat "$pf" 2>/dev/null || true)
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
            sleep 0.5
            kill -9 "$p" 2>/dev/null || true
        fi
        rm -f "$pf"
    fi
}

cleanup() {
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "\n${C_GREEN}[INFO] Se preservan instancias y archivos en ${DIR_LAB} y ${LOG_DIR} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_rsyslog_pipelines.sh\n"
        return
    fi
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo instancias aisladas de rsyslogd y limpiando rutas temporales...${C_RESET}"
    stop_pid_file "$CLI_PID_FILE"
    stop_pid_file "$SRV_PID_FILE"
    pkill -f "lab_demo_rsyslog/rsyslog_" 2>/dev/null || true
    rm -rf "$DIR_LAB" "$LOG_DIR"
    echo -e "${C_GREEN}✔ Limpieza completada sin procesos huérfanos.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi
trap cleanup EXIT INT TERM

if ! command -v rsyslogd &>/dev/null; then
    echo -e "${C_RED}[ERROR] rsyslogd no está instalado en este sistema. Instalá 'rsyslog' y 'rsyslog-gnutls'.${C_RESET}"
    exit 1
fi

mkdir -p "${DIR_LAB}/certs" "${DIR_LAB}/spool_srv" "${DIR_LAB}/spool_cli" "$LOG_DIR"
chmod -R 755 "$DIR_LAB" "$LOG_DIR"
chmod 700 "${DIR_LAB}/certs"
clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ⚙️  DEMOSTRACIÓN EN VIVO: RSYSLOG AVANZADO, TLS X.509 Y DISK-ASSISTED QUEUES${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"

# ==============================================================================
# PASO 1: DETECCIÓN DE MÓDULOS Y GENERACIÓN DE PKI EFÍMERA TLS
# ==============================================================================
step_banner "1" "Verificación de rsyslogd y Generación de PKI Efímera OpenSSL"
explain "Detectamos el driver TLS disponible en el sistema (gtls o ossl) y creamos una Autoridad Certificadora + certificado con SAN=DNS:localhost,IP:127.0.0.1 para autenticación mutua x509/name."

run_and_show "rsyslogd -v | head -n 4"

TLS_DRIVER=""
if find /usr/lib* /lib* -name "lmnsd_gtls.so" 2>/dev/null | grep -q .; then
    TLS_DRIVER="gtls"
elif find /usr/lib* /lib* -name "lmnsd_ossl.so" 2>/dev/null | grep -q .; then
    TLS_DRIVER="ossl"
fi
echo -e "${C_GREEN}✔ Driver TLS detectado: ${TLS_DRIVER:-NINGUNO (se usará TCP plano de respaldo)}${C_RESET}"

run_and_show "openssl req -x509 -newkey rsa:2048 -days 7 -nodes -keyout ${DIR_LAB}/certs/ca.key -out ${DIR_LAB}/certs/ca.crt -subj '/CN=LabRsyslogCA'"
run_and_show "openssl req -newkey rsa:2048 -nodes -keyout ${DIR_LAB}/certs/node.key -out ${DIR_LAB}/certs/node.csr -subj '/CN=localhost' && openssl x509 -req -in ${DIR_LAB}/certs/node.csr -CA ${DIR_LAB}/certs/ca.crt -CAkey ${DIR_LAB}/certs/ca.key -CAcreateserial -out ${DIR_LAB}/certs/node.crt -days 7 -extfile <(printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth,clientAuth')"

pause_step

# ==============================================================================
# PASO 2: CONFIGURACIÓN SERVIDOR RSYSLOG (RAINERSCRIPT) + VALIDACIÓN -N1
# ==============================================================================
step_banner "2" "Configuración Servidor rsyslog (RainerScript) y Validación -N1"
explain "Construimos el servidor receptor aislado en UDP :15514 y TCP/TLS :16514 con descarte de debug, plantillas MiFormato y FormatoJSON, y ruteo condicional por \$programname."

if [ -n "$TLS_DRIVER" ]; then
    TLS_SRV_GLOBAL="    DefaultNetstreamDriver=\"${TLS_DRIVER}\"
    DefaultNetstreamDriverCAFile=\"${DIR_LAB}/certs/ca.crt\"
    DefaultNetstreamDriverCertFile=\"${DIR_LAB}/certs/node.crt\"
    DefaultNetstreamDriverKeyFile=\"${DIR_LAB}/certs/node.key\""
    TLS_SRV_IMTCP="module(load=\"imtcp\" StreamDriver.Name=\"${TLS_DRIVER}\" StreamDriver.Mode=\"1\" StreamDriver.AuthMode=\"x509/name\" PermittedPeer=[\"localhost\",\"127.0.0.1\"])"
else
    TLS_SRV_GLOBAL=""
    TLS_SRV_IMTCP="module(load=\"imtcp\")"
fi

cat <<EOF > "${DIR_LAB}/rsyslog_server.conf"
global(
    workDirectory="${DIR_LAB}/spool_srv"
${TLS_SRV_GLOBAL}
)

module(load="imudp")
input(type="imudp" port="15514")

${TLS_SRV_IMTCP}
input(type="imtcp" port="16514")

template(name="MiFormato" type="string"
         string="%TIMESTAMP:::date-rfc3339% %HOSTNAME% %syslogtag%%msg%\n")

template(name="FormatoJSON" type="list") {
    constant(value="{")
    constant(value="\"timestamp\":\"")   property(name="timereported" dateFormat="rfc3339")
    constant(value="\",\"host\":\"")     property(name="hostname" format="json")
    constant(value="\",\"app\":\"")      property(name="programname" format="json")
    constant(value="\",\"severity\":\"") property(name="syslogseverity-text" format="json")
    constant(value="\",\"msg\":\"")      property(name="msg" format="json")
    constant(value="\"}\n")
}

# Regla equivalente a '*.debug ~' en sintaxis clásica
if (\$syslogseverity-text == "debug") then {
    stop
}

# Filtrar y enrutar mi_aplicacion en texto y JSON
if (\$programname == "mi_aplicacion") then {
    action(type="omfile" file="${LOG_DIR}/mi_aplicacion.log" template="MiFormato")
    action(type="omfile" file="${LOG_DIR}/mi_aplicacion.json" template="FormatoJSON")
    stop
}

action(type="omfile" file="${LOG_DIR}/mislogs.log" template="MiFormato")
EOF

run_and_show "rsyslogd -N1 -f ${DIR_LAB}/rsyslog_server.conf"
run_and_show "rsyslogd -n -f ${DIR_LAB}/rsyslog_server.conf -i NONE >/dev/null 2>&1 & echo \$! > ${SRV_PID_FILE}"
sleep 1
run_and_show "ps -p \$(cat ${SRV_PID_FILE}) -o pid,cmd"

pie_clase "¿Por qué siempre debés correr 'rsyslogd -N1' antes de hacer 'systemctl restart rsyslog' en producción?" \
          "Porque un error de sintaxis en /etc/rsyslog.d/*.conf impide que el demonio levante al reiniciar; -N1 valida el árbol de reglas completo en seco."
pause_step

# ==============================================================================
# PASO 3: PRUEBAS DE FILTRADO, DESCARTE DEBUG Y PLANTILLAS JSON
# ==============================================================================
step_banner "3" "Pruebas en Vivo de Filtrado (Descarte debug) y Formato JSON"
explain "Inyectamos eventos vía UDP :15514 con logger: un mensaje debug (que debe descartarse), un error de mi_aplicacion (ruteado a su archivo y JSON) y un evento general."

run_and_show "logger --udp -n 127.0.0.1 -P 15514 -p local0.debug -t mi_aplicacion 'DEBUG interno: variable x=42 (debe descartarse)'"
run_and_show "logger --udp -n 127.0.0.1 -P 15514 -p local0.err -t mi_aplicacion 'Error critico de pago tx=8841'"
run_and_show "logger --udp -n 127.0.0.1 -P 15514 -p local1.notice -t otro_servicio 'Backup diario completado'"
sleep 1

run_and_show "cat ${LOG_DIR}/mi_aplicacion.log"
run_and_show "jq . ${LOG_DIR}/mi_aplicacion.json 2>/dev/null || cat ${LOG_DIR}/mi_aplicacion.json"
run_and_show "cat ${LOG_DIR}/mislogs.log"

pause_step

# ==============================================================================
# PASO 4: CLIENTE RSYSLOG CON IMFILE + TLS + DISK-ASSISTED QUEUE
# ==============================================================================
step_banner "4" "Cliente rsyslog (imfile) + Transporte TLS + Disk-Assisted Queue"
explain "Levantamos una instancia cliente de rsyslogd leyendo un archivo de app con imfile y enviando al servidor por TCP+TLS :16514 con cola persistente en disco."

touch "${LOG_DIR}/app_origen.log"

if [ -n "$TLS_DRIVER" ]; then
    TLS_CLI_GLOBAL="    DefaultNetstreamDriver=\"${TLS_DRIVER}\"
    DefaultNetstreamDriverCAFile=\"${DIR_LAB}/certs/ca.crt\"
    DefaultNetstreamDriverCertFile=\"${DIR_LAB}/certs/node.crt\"
    DefaultNetstreamDriverKeyFile=\"${DIR_LAB}/certs/node.key\""
    TLS_CLI_ACTION="        StreamDriver=\"${TLS_DRIVER}\"
        StreamDriverMode=\"1\"
        StreamDriverAuthMode=\"x509/name\"
        StreamDriverPermittedPeers=\"localhost\""
else
    TLS_CLI_GLOBAL=""
    TLS_CLI_ACTION=""
fi

cat <<EOF > "${DIR_LAB}/rsyslog_client.conf"
global(
    workDirectory="${DIR_LAB}/spool_cli"
${TLS_CLI_GLOBAL}
)

module(load="imfile" PollingInterval="1")

input(
    type="imfile"
    File="${LOG_DIR}/app_origen.log"
    Tag="mi_aplicacion"
    Severity="err"
    Facility="local0"
    reopenOnTruncate="on"
)

if (\$programname == "mi_aplicacion") then {
    action(
        type="omfwd"
        target="127.0.0.1"
        port="16514"
        protocol="tcp"
${TLS_CLI_ACTION}
        queue.type="LinkedList"
        queue.filename="fwd_tls_queue"
        queue.maxdiskspace="50m"
        queue.saveonshutdown="on"
        action.resumeRetryCount="-1"
        action.resumeInterval="1"
    )
    stop
}
EOF

run_and_show "rsyslogd -N1 -f ${DIR_LAB}/rsyslog_client.conf"
run_and_show "rsyslogd -n -f ${DIR_LAB}/rsyslog_client.conf -i NONE >/dev/null 2>&1 & echo \$! > ${CLI_PID_FILE}"
sleep 1

if [ -n "$TLS_DRIVER" ]; then
    run_and_show "echo | openssl s_client -connect 127.0.0.1:16514 -CAfile ${DIR_LAB}/certs/ca.crt -cert ${DIR_LAB}/certs/node.crt -key ${DIR_LAB}/certs/node.key 2>/dev/null | grep -E 'subject=|issuer=|Verification:|Cipher|Protocol' | head -n 6"
fi

run_and_show "echo 'EVENTO_TLS_1: Transferencia inicial OK por imfile+TLS' >> ${LOG_DIR}/app_origen.log"
sleep 2
run_and_show "tail -n 3 ${LOG_DIR}/mi_aplicacion.log"

pause_step

# ==============================================================================
# PASO 5: CAOS EN VIVO -> CAÍDA DEL COLECTOR Y DRENAJE DE DISK-ASSISTED QUEUE
# ==============================================================================
step_banner "5" "Prueba de Resiliencia: Caída del Colector Central (0% Pérdida)"
explain "Matamos el servidor receptor rsyslogd mientras la app emite 5 transacciones críticas. Luego relanzamos el servidor y comprobamos que la cola del cliente drena los 5 eventos."

run_and_show "kill \$(cat ${SRV_PID_FILE}) && rm -f ${SRV_PID_FILE} && echo 'Colector central DETENIDO intencionalmente'"
sleep 1

for i in 1 2 3 4 5; do
    echo "EVENTO_CAIDA_${i}: Transaccion critica mientras el colector estaba CAIDO" >> "${LOG_DIR}/app_origen.log"
done
run_and_show "tail -n 5 ${LOG_DIR}/app_origen.log"
sleep 1
run_and_show "ls -la ${DIR_LAB}/spool_cli"

explain "Relanzamos el servidor receptor y esperamos 3 segundos para que action.resumeInterval drene la cola..."
run_and_show "rsyslogd -n -f ${DIR_LAB}/rsyslog_server.conf -i NONE >/dev/null 2>&1 & echo \$! > ${SRV_PID_FILE}"
sleep 3
run_and_show "grep 'EVENTO_CAIDA_' ${LOG_DIR}/mi_aplicacion.log"
COUNT_RECOVERED=$(grep -c 'EVENTO_CAIDA_' "${LOG_DIR}/mi_aplicacion.log" || true)
echo -e "${C_GREEN}✔ Eventos recuperados tras la caída del colector: ${COUNT_RECOVERED}/5${C_RESET}"

pie_clase "¿Qué sucede con el rendimiento de las aplicaciones si un cliente rsyslog usa TCP sin cola (queue.type) cuando el servidor central se cuelga?" \
          "Se llena el buffer TCP del kernel, rsyslog se bloquea y eventualmente bloquea el socket /dev/log, pudiendo congelar servicios locales como sshd o sudo. Las Disk-Assisted Queues evitan ese bloqueo."
echo -e "\n${C_BOLD}${C_GREEN}🎉 ¡Laboratorio 3.21 completado con éxito!${C_RESET}"
