#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Systemd Timers vs Cron y Sincronización NTP (Chrony)
# Laboratorio: linux/administrator/automatizacion/systemd_timers_vs_cron_chrony.md
#
# Basado en el temario oficial de Automatización y Planificación en Linux (Clase 8)
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema en una caja formateada.
#  - Fase 1: La Regla de Oro -> Auditoría NTP con timedatectl y chronyc.
#  - Fase 2: Equivalencias Crontab -> OnCalendar con systemd-analyze calendar.
#  - Fase 3: Desacoplamiento .timer + .service con Persistent=true, After= y cgroups.
#  - Fase 4: Reemplazo de 'at' con systemd-run transitorio y logs en journalctl.
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   sudo ./demo_systemd_timers_chrony.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               Preserva las unidades creadas para inspección manual
#   --help               Muestra este mensaje de ayuda
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
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para gestionar unidades de systemd.${C_RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false

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
        --help|-h)
            echo "Uso: sudo ./demo_systemd_timers_chrony.sh [--auto <segundos>] [--keep] [--help]"
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

cleanup() {
    if [ "$KEEP_FILES" = true ]; then
        echo -e "\n${C_GREEN}[INFO] Se preservan las unidades lab-mantenimiento.{timer,service} por opción --keep.${C_RESET}"
    else
        echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo y eliminando unidades de prueba de Systemd...${C_RESET}"
        systemctl stop lab-mantenimiento.timer lab-mantenimiento.service lab-tarea-efimera.timer lab-tarea-efimera.service 2>/dev/null || true
        systemctl disable lab-mantenimiento.timer 2>/dev/null || true
        rm -f /etc/systemd/system/lab-mantenimiento.timer /etc/systemd/system/lab-mantenimiento.service /usr/local/bin/lab-mantenimiento-enterprise.sh
        systemctl daemon-reload 2>/dev/null || true
        echo -e "${C_GREEN}✔ Unidades temporales de Systemd limpiadas correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ⚙️  DEMOSTRACIÓN EN VIVO: SYSTEMD TIMERS VS CRON Y SINCRONIZACIÓN CHRONY (NTP)${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Auditoría NTP (Chrony), systemd-analyze calendar, .timer/.service y journalctl\n"

# ==============================================================================
# PASO 1: LA REGLA DE ORO DEL SYSADMIN -> CAPA BASE CHRONY (NTP) Y TIMEDATECTL
# ==============================================================================
step_banner "1" "La Regla de Oro: Sincronización de Tiempo Exacta con Chrony (NTP)"

explain "Ninguna herramienta de automatización funcionará bien si el reloj interno está desfasado."
explain "Auditamos primero el reloj del sistema, zona horaria y sincronización NTP con timedatectl y chronyc:"
run_and_show "timedatectl status"

if command -v chronyc &>/dev/null; then
    systemctl start chronyd 2>/dev/null || chronyd -x 2>/dev/null || true
    run_and_show "chronyc tracking"
    run_and_show "chronyc sources"
fi

pie_clase "¿Por qué Chrony (NTP) es considerado 'el habilitador invisible' de toda automatización en Linux?" \
          "Porque garantiza que el reloj del kernel no sufra deriva (clock drift), asegurando que los triggers de Cron y Systemd Timers se disparen en el segundo exacto y los logs tengan marcas de tiempo coherentes."

pause_step "Presioná [ENTER] para validar expresiones de calendario con systemd-analyze calendar..."

# ==============================================================================
# PASO 2: TRADUCCIÓN CRONTAB -> SYSTEMD ONCALENDAR Y VALIDACIÓN MATEMÁTICA
# ==============================================================================
step_banner "2" "Simulación y Validación de Calendarios con systemd-analyze calendar"

explain "Traducimos los patrones de crontab del temario a sintaxis OnCalendar y calculamos las próximas 3 ejecuciones:"
run_and_show "systemd-analyze calendar --iterations=3 '*-*-* 04:00:00'"
run_and_show "systemd-analyze calendar --iterations=3 '*:0/5:00'"
run_and_show "systemd-analyze calendar --iterations=3 '*-*-* 09..18:00:00'"
run_and_show "systemd-analyze calendar --iterations=3 'Fri *-*-* 00:00:00'"
run_and_show "systemd-analyze calendar --iterations=3 '*-05,10-* 00:00:00'"

pie_clase "¿Qué ventaja aporta 'systemd-analyze calendar' frente a editar un archivo crontab tradicional?" \
          "Permite comprobar matemáticamente antes de activar la tarea si la sintaxis es válida y en qué fechas y horas exactas se dispararán las próximas ejecuciones."

pause_step "Presioná [ENTER] para crear las unidades desacopladas .service y .timer..."

# ==============================================================================
# PASO 3: DESACOPLAMIENTO LÓGICO (.service + .timer) CON PERSISTENT Y CGROUPS
# ==============================================================================
step_banner "3" "Desacoplamiento Lógico: lab-mantenimiento.service y lab-mantenimiento.timer"

explain "1. Creamos el script ejecutable /usr/local/bin/lab-mantenimiento-enterprise.sh:"
cat << 'EOF' > /usr/local/bin/lab-mantenimiento-enterprise.sh
#!/usr/bin/env bash
set -euo pipefail
echo "=== [INICIO] Auditoría y Mantenimiento Automatizado Enterprise ==="
echo "Timestamp UTC    : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Espacio en /tmp  : $(df -h /tmp | awk 'NR==2 {print $4 " libres (" $5 " usado)"}')"
echo "Load Average     : $(cat /proc/loadavg)"
echo "=== [FIN] Ejecución exitosa (Status 0) ==="
EOF
chmod +x /usr/local/bin/lab-mantenimiento-enterprise.sh

explain "2. Creamos la unidad .service (define el QUÉ, dependencias de red After= y límites Cgroups CPUQuota/MemoryMax):"
cat << 'EOF' > /etc/systemd/system/lab-mantenimiento.service
[Unit]
Description=Servicio de Mantenimiento y Auditoría Enterprise (Lab 2.6)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/lab-mantenimiento-enterprise.sh
CPUQuota=25%
MemoryMax=128M
Nice=10
EOF
run_and_show "cat /etc/systemd/system/lab-mantenimiento.service"

explain "3. Creamos la unidad .timer (define el CUÁNDO con OnCalendar y Persistent=true estilo Anacron):"
cat << 'EOF' > /etc/systemd/system/lab-mantenimiento.timer
[Unit]
Description=Temporizador para Mantenimiento Enterprise (Reemplazo de Cron + Anacron)

[Timer]
OnCalendar=*:0/1
AccuracySec=1s
Persistent=true
Unit=lab-mantenimiento.service

[Install]
WantedBy=timers.target
EOF
run_and_show "cat /etc/systemd/system/lab-mantenimiento.timer"

pie_clase "¿Cuáles son las tres grandes ventajas operativas de Systemd Timers sobre Cron según el temario?" \
          "1) Visibilidad nativa en journalctl, 2) Dependencias condicionales (ej. esperar a que la red o un disco estén activos), y 3) Precisión de microsegundos y control de recursos (CPU/RAM) con cgroups."

pause_step "Presioná [ENTER] para activar el timer y auditar su ejecución en journalctl..."

# ==============================================================================
# PASO 4: ACTIVACIÓN, LISTADO DE TIMERS Y LOGS EN JOURNALCTL
# ==============================================================================
step_banner "4" "Activación del Timer y Auditoría Centralizada en journalctl"

explain "Recargamos systemd, probamos el servicio de forma inmediata y habilitamos el timer:"
run_and_show "systemctl daemon-reload && systemctl start lab-mantenimiento.service && systemctl enable --now lab-mantenimiento.timer"

explain "Consultamos el estado del timer y la tabla de próximas ejecuciones con 'systemctl list-timers':"
run_and_show "systemctl list-timers lab-mantenimiento.timer --no-pager"

explain "Inspeccionamos los logs estructurados capturados automáticamente en journalctl:"
run_and_show "journalctl -u lab-mantenimiento.service -n 15 --no-pager"

pie_clase "¿Cómo soluciona Systemd Timers el problema de los sistemas intermitentes que antes requería instalar Anacron?" \
          "Simplemente añadiendo 'Persistent=true' en la sección [Timer]. Systemd almacena en disco cuándo corrió por última vez y, si el equipo estuvo apagado, lanza la tarea apenas arranca."

pause_step "Presioná [ENTER] para ver cómo Systemd también reemplaza al comando 'at' con systemd-run..."

# ==============================================================================
# PASO 5: EJECUCIÓN ÚNICA EFÍMERA CON SYSTEMD-RUN (ALTERNATIVA MODERNA A 'AT')
# ==============================================================================
step_banner "5" "Timers Transitorios Efímeros con systemd-run (Alternativa Moderna a 'at')"

explain "Programamos una tarea única efímera que se ejecutará en 2 segundos sin dejar archivos residuales:"
run_and_show "systemd-run --unit=lab-tarea-efimera --on-active=2s --timer-property=AccuracySec=100ms /bin/bash -c 'echo \"[SYSTEMD-RUN] Tarea única ad-hoc completada exitosamente en \$(date -Iseconds)\"'"

sleep 3
explain "Consultamos el registro que dejó nuestra tarea efímera en journalctl:"
run_and_show "journalctl -u lab-tarea-efimera.service -n 10 --no-pager"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ✔ LABORATORIO DE SYSTEMD TIMERS Y CHRONY COMPLETADO CON ÉXITO                 ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado la Regla de Oro (Chrony NTP), systemd-analyze calendar, .timer/.service y journalctl.\n"
