#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Fundamentos de Logs en Linux
# Laboratorio: linux/administrator/logs/logs_fundamentos_varlog_dmesg.md (Lab 3.19)
#
# Cubre:
#  - Anatomía de /var/log (texto vs binarios wtmp/btmp/lastlog, Debian vs RHEL)
#  - Severities (0-7), Facilities (0-23) y cálculo <PRI> con logger y systemd-cat
#  - Kernel Ring Buffer con dmesg (-T, --level=err,warn, dmesg_restrict)
#  - Rescate forense de inodo abierto borrado (lsof +L1 / /proc/PID/fd)
#  - Rotación y compresión real con logrotate (copytruncate + delaycompress)
#
# Uso:
#   sudo ./demo_logs_fundamentos.sh [--auto <segundos>] [--keep] [--clean] [--help]
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
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para inspeccionar /var/log, dmesg y journalctl.${C_RESET}"
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
            echo "Uso: sudo ./demo_logs_fundamentos.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
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

DIR_LAB="/tmp/lab_demo_logs_fund"
WRITER_PID=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Liberando procesos y archivos temporales del Lab 3.19...${C_RESET}"
    if [ -n "$WRITER_PID" ] && kill -0 "$WRITER_PID" 2>/dev/null; then
        kill "$WRITER_PID" 2>/dev/null || true
        wait "$WRITER_PID" 2>/dev/null || true
    fi
    pkill -f "lab_demo_logs_fund/app_activa.log" 2>/dev/null || true
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los archivos en ${DIR_LAB} por opción --keep.${C_RESET}"
    else
        rm -rf "$DIR_LAB"
        echo -e "${C_GREEN}✔ Directorio temporal ${DIR_LAB} eliminado.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Limpieza completada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi
trap cleanup EXIT INT TERM

mkdir -p "$DIR_LAB"
chmod 755 "$DIR_LAB"
clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 📜 DEMOSTRACIÓN EN VIVO: FUNDAMENTOS DE LOGS (/var/log, dmesg y logrotate)${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"

# ==============================================================================
# PASO 1: RADIOGRAFÍA DE /var/log (TEXTO vs BINARIOS)
# ==============================================================================
step_banner "1" "Anatomía del Directorio /var/log: Texto Plano vs Binarios de Sesión"
explain "En Linux, /var/log concentra registros de texto plano (syslog/messages, auth.log/secure) y archivos binarios de sesión (wtmp, btmp, lastlog) más el diario binario en /var/log/journal."

run_and_show "ls -lht /var/log | head -n 18"
run_and_show "for f in /var/log/syslog /var/log/messages /var/log/auth.log /var/log/secure /var/log/wtmp /var/log/btmp /var/log/lastlog; do [ -e \"\$f\" ] && ls -lh \"\$f\"; done || echo 'Revisar /var/log/journal'"
run_and_show "last -n 5"

pie_clase "¿Por qué nunca debés usar 'cat /var/log/wtmp' o 'cat /var/log/btmp' y qué herramientas los leen?" \
          "Porque son archivos binarios estructurados (structs utmp/wtmp). Se consultan con 'last' (exitosos en wtmp) y 'sudo lastb' (intentos fallidos en btmp)."
pause_step

# ==============================================================================
# PASO 2: SEVERITIES, FACILITIES Y CÁLCULO <PRI> CON LOGGER Y SYSTEMD-CAT
# ==============================================================================
step_banner "2" "Severities (0-7), Facilities (0-23) y Cálculo PRI con logger y systemd-cat"
explain "Syslog clasifica eventos por Facility (origen) y Severity (gravedad: 0=emerg .. 7=debug). La prioridad numérica en red vale PRI = (Facility * 8) + Severity."

TAG_APP="lab319-app-$$"
run_and_show "logger -p local0.info -t ${TAG_APP} 'Servicio inicializado correctamente'"
run_and_show "logger -p local0.warning -t ${TAG_APP} 'Latencia de cola superando 800ms'"
run_and_show "logger -p local0.err -t ${TAG_APP} 'Fallo de conexion contra replica SQL'"
run_and_show "echo 'Evento critico capturado desde stdout via pipe' | systemd-cat -t ${TAG_APP} -p crit"

sleep 1
run_and_show "journalctl -t ${TAG_APP} --no-pager -o verbose | grep -E 'MESSAGE=|PRIORITY=|SYSLOG_FACILITY=|SYSLOG_IDENTIFIER=' | head -n 20"
run_and_show "python3 -c 'print(\"Verificacion PRI local0(16) + err(3):\", (16*8)+3, \"| auth(4) + err(3):\", (4*8)+3)'"

pie_clase "Si ves el código <132> en un paquete Syslog crudo por red, ¿a qué Facility y Severity corresponde?" \
          "132 / 8 = 16 (cociente -> local0) y 132 % 8 = 4 (residuo -> warning). Es decir: local0.warning."
pause_step

# ==============================================================================
# PASO 3: KERNEL RING BUFFER Y DMESG
# ==============================================================================
step_banner "3" "Inspección del Kernel Ring Buffer con dmesg"
explain "El kernel escribe en un buffer circular en RAM (/dev/kmsg) desde el primer milisegundo del arranque. dmesg -T muestra marcas de tiempo humanas y --level filtra por gravedad."

run_and_show "cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo 'Parametro no visible en este entorno'"
DMESG_CHECK=$(dmesg -T 2>&1 | tail -n 5 || true)
if echo "$DMESG_CHECK" | grep -qi "Operation not permitted"; then
    run_and_show "dmesg -T 2>&1 || true"
    explain "En contenedores sin CAP_SYSLOG el kernel bloquea /dev/kmsg por seguridad (aislamiento del host). En un servidor real o VM verás la salida directa; simulamos un extracto real de hardware/USB para practicar el filtrado."
    cat <<'EOF' > "${DIR_LAB}/dmesg_sample.txt"
[jue nov 21 09:10:01 2026] e1000: enp0s3 NIC Link is Up 1000 Mbps Full Duplex
[jue nov 21 09:11:14 2026] usb 1-1: new high-speed USB device number 4 using xhci_hcd
[jue nov 21 09:11:15 2026] usb 1-1: device descriptor read/64, error -71 (USB device not recognized)
[jue nov 21 09:12:02 2026] nvme0n1: I/O error, dev nvme0n1, sector 8192 op 0x1:(WRITE)
EOF
    run_and_show "grep -i 'USB' ${DIR_LAB}/dmesg_sample.txt | grep -i 'error'"
else
    run_and_show "dmesg -T | tail -n 12"
    run_and_show "dmesg --level=err,warn -T | tail -n 10"
fi

pie_clase "¿Por qué ejecutar 'dmesg -c' en un servidor en producción es una pésima práctica durante un incidente?" \
          "Porque -c (--clear) vacía el ring buffer del kernel tras imprimirlo, destruyendo evidencia forense si el mensaje no alcanzó a persistirse en disco."
pause_step

# ==============================================================================
# PASO 4: EL DRAMA DEL DISCO LLENO POR INODO ABIERTO (lsof +L1)
# ==============================================================================
step_banner "4" "Incidente Real: Borré el Log con 'rm' pero el Disco Sigue Ocupado"
explain "Si borrás un archivo de log con 'rm' mientras un demonio sigue escribiendo en él, el nombre desaparece del directorio pero los bloques siguen ocupados hasta que el proceso cierre el File Descriptor."

python3 -c "
import time
with open('${DIR_LAB}/app_activa.log', 'w', buffering=1) as f:
    for i in range(200):
        f.write(f'seq={i} ' + 'A'*8192 + '\n')
        time.sleep(0.2)
" &
WRITER_PID=$!
sleep 1

run_and_show "ls -lh ${DIR_LAB}/app_activa.log"
run_and_show "rm -f ${DIR_LAB}/app_activa.log && ls -la ${DIR_LAB}/"
if command -v lsof &>/dev/null; then
    run_and_show "lsof +L1 ${DIR_LAB}/ 2>/dev/null || lsof -p ${WRITER_PID} | grep deleted"
else
    run_and_show "ls -l /proc/${WRITER_PID}/fd"
fi
explain "Observá el estado '(deleted)' en el File Descriptor del proceso ${WRITER_PID}. El espacio no se libera hasta vaciarlo vía /proc/${WRITER_PID}/fd/<N> o reiniciar el proceso. Terminamos el proceso de prueba ahora."
kill "$WRITER_PID" 2>/dev/null || true
wait "$WRITER_PID" 2>/dev/null || true
WRITER_PID=""

pie_clase "¿Cómo vaciás un log gigante en caliente sin reiniciar el servicio ni romper su descriptor de archivo?" \
          "Ejecutando ': > /ruta/al/archivo.log' (o 'truncate -s 0 /ruta/al/archivo.log'), manteniendo intacto el inodo, o delegando en 'logrotate' con 'copytruncate'."
pause_step

# ==============================================================================
# PASO 5: ROTACIÓN Y COMPRESIÓN REAL CON LOGROTATE
# ==============================================================================
step_banner "5" "Ciclo de Vida Automatizado: Rotación y Compresión con logrotate"
explain "logrotate evita que /var/log llene el disco rotando, comprimiendo y purgando logs antiguos. Lo probaremos con un archivo de estado aislado (-s) sin tocar /etc/logrotate.d."

cat <<EOF > "${DIR_LAB}/logrotate.conf"
${DIR_LAB}/servicio.log {
    su root root
    size 1k
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

run_and_show "cat ${DIR_LAB}/logrotate.conf"
for i in $(seq 1 40); do
    echo "2026-11-21T10:00:00Z INFO transaccion_ok id=${i} payload=demostracion_logrotate" >> "${DIR_LAB}/servicio.log"
done
run_and_show "ls -lh ${DIR_LAB}/servicio.log"
run_and_show "logrotate -d -s ${DIR_LAB}/state ${DIR_LAB}/logrotate.conf | tail -n 15"
run_and_show "logrotate -f -s ${DIR_LAB}/state ${DIR_LAB}/logrotate.conf"

for i in $(seq 41 80); do
    echo "2026-11-21T10:01:00Z INFO transaccion_ok id=${i} payload=demostracion_logrotate_2" >> "${DIR_LAB}/servicio.log"
done
run_and_show "logrotate -f -s ${DIR_LAB}/state ${DIR_LAB}/logrotate.conf"
run_and_show "ls -lh ${DIR_LAB}/servicio.log*"

pie_clase "¿Qué hace la directiva 'delaycompress' y por qué es buena práctica junto a 'create'?" \
          "Pospone la compresión gzip del archivo recién rotado (.1) hasta el siguiente ciclo (.2.gz), dando margen por si el demonio tarda unos segundos en reabrir su nuevo log tras SIGHUP."
echo -e "\n${C_BOLD}${C_GREEN}🎉 ¡Laboratorio 3.19 completado con éxito!${C_RESET}"
