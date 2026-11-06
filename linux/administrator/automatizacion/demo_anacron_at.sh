#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Anacron (Sistemas Intermitentes) y at (Ejecución Efímera)
# Laboratorio: linux/administrator/automatizacion/anacron_at_tareas_asincronas.md
#
# Basado en el temario oficial de Automatización y Planificación en Linux (Clase 8)
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema en una caja formateada.
#  - Explica por qué Cron pierde tareas si una laptop está apagada a las 04:00 AM.
#  - Analiza /etc/anacrontab (period, delay, job-identifier, command) y /var/spool/anacron.
#  - Simula una tarea vencida hace 5 días y demuestra su recuperación y actualización de fecha.
#  - Demuestra la cola efímera de 'at' (at, atq, at -c, atrm y batch).
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   sudo ./demo_anacron_at.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               Preserva los archivos de prueba en /tmp/lab_demo_anacron_at
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
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para gestionar anacron y atd.${C_RESET}"
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
            echo "Uso: sudo ./demo_anacron_at.sh [--auto <segundos>] [--keep] [--help]"
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

DIR_LAB="/tmp/lab_demo_anacron_at"
mkdir -p "${DIR_LAB}/spool" "${DIR_LAB}/logs" "${DIR_LAB}/atjobs"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Purgando colas de prueba de anacron y at...${C_RESET}"
    if command -v atq &>/dev/null && command -v atrm &>/dev/null; then
        for jid in $(atq 2>/dev/null | awk '{print $1}'); do
            atrm "$jid" 2>/dev/null || true
        done
    fi
    if [ "$KEEP_FILES" = true ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los archivos en ${DIR_LAB} por opción --keep.${C_RESET}"
    else
        rm -rf "$DIR_LAB"
        echo -e "${C_GREEN}✔ Archivos temporales limpiados correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 💻 DEMOSTRACIÓN EN VIVO: ANACRON (INTERMITENTES) Y AT (EJECUCIÓN EFÍMERA)     ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Rescate de tareas perdidas en laptops con Anacron y trabajos únicos ad-hoc con at\n"

# ==============================================================================
# PASO 1: EL PROBLEMA DE CRON EN EQUIPOS QUE SE APAGAN Y LA SOLUCIÓN ANACRON
# ==============================================================================
step_banner "1" "Anacron: Anatomía de /etc/anacrontab para Sistemas Intermitentes"

if ! command -v anacron &>/dev/null || ! command -v at &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq anacron at 2>/dev/null || true
    elif command -v dnf &>/dev/null; then
        dnf install -y -q cronie-anacron at 2>/dev/null || true
    fi
fi

cat << 'EOF' > "${DIR_LAB}/anacrontab_ejemplo"
# /etc/anacrontab: configuration file for anacron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
RANDOM_DELAY=45
START_HOURS_RANGE=3-22

# period in days   delay in minutes   job-identifier        command
1                  5                  cron.daily            nice run-parts --report /etc/cron.daily
7                  10                 cron.weekly           nice run-parts --report /etc/cron.weekly
@monthly           15                 cron.monthly          nice run-parts --report /etc/cron.monthly
1                  0                  backup_laptop_diario  echo "[$(date '+%F %T')] Backup de workstation recuperado tras encendido" >> /tmp/lab_demo_anacron_at/logs/anacron_recuperado.log
EOF

explain "Inspeccionamos la estructura de 4 columnas de anacrontab (period, delay, job-identifier, command):"
run_and_show "cat ${DIR_LAB}/anacrontab_ejemplo"

pie_clase "¿Por qué cron falla en una laptop personal si programás un backup a las 04:00 AM y cómo lo resuelve anacron?" \
          "Cron asume operación 24/7; si a las 04:00 AM la laptop está apagada, la tarea se pierde. Anacron no mira la hora exacta sino cuántos días pasaron desde el último sello en /var/spool/anacron, ejecutando la tarea minutos después de encender el equipo."

pause_step "Presioná [ENTER] para simular un apagado de 5 días y ver cómo Anacron recupera la tarea..."

# ==============================================================================
# PASO 2: SIMULACIÓN FORENSE DE /var/spool/anacron Y RECUPERACIÓN
# ==============================================================================
step_banner "2" "Simulación Forense de Sellos de Tiempo en /var/spool/anacron"

FECHA_HACE_5_DIAS=$(date -d "5 days ago" '+%Y%m%d')
FECHA_HOY=$(date '+%Y%m%d')
echo "$FECHA_HACE_5_DIAS" > "${DIR_LAB}/spool/backup_laptop_diario"

explain "1. Simulamos en el spool que el último backup de la laptop corrió hace 5 días (${FECHA_HACE_5_DIAS}):"
run_and_show "cat ${DIR_LAB}/spool/backup_laptop_diario"

explain "2. Al encender el equipo hoy (${FECHA_HOY}), Anacron compara: (${FECHA_HOY} - ${FECHA_HACE_5_DIAS}) >= 1 día (period=1):"
if command -v anacron &>/dev/null; then
    run_and_show "anacron -t ${DIR_LAB}/anacrontab_ejemplo -S ${DIR_LAB}/spool -n backup_laptop_diario"
else
    echo "[$(date '+%F %T')] Backup de workstation recuperado tras encendido" >> "${DIR_LAB}/logs/anacron_recuperado.log"
    echo "$FECHA_HOY" > "${DIR_LAB}/spool/backup_laptop_diario"
    run_and_show "echo 'Anacron verificó retraso >= 1 día, ejecutó backup_laptop_diario y actualizó el timestamp.'"
fi

explain "3. Verificamos el log de la tarea recuperada y el nuevo sello de tiempo actualizado a HOY (${FECHA_HOY}):"
run_and_show "cat ${DIR_LAB}/logs/anacron_recuperado.log"
run_and_show "cat ${DIR_LAB}/spool/backup_laptop_diario"

pie_clase "¿Para qué sirve la columna 'delay in minutes' (ej. 5, 10, 15 minutos) en /etc/anacrontab?" \
          "Evita una tormenta de I/O de disco y CPU en el instante exacto en que el usuario enciende su laptop, escalonando las tareas pendientes."

pause_step "Presioná [ENTER] para explorar la ejecución efímera con el comando at..."

# ==============================================================================
# PASO 3: EL COMANDO AT: EJECUCIÓN ÚNICA EFÍMERA (SIN BASURA EN CRONTAB)
# ==============================================================================
step_banner "3" "El Comando at: Encolado de Trabajos Únicos Ad-Hoc (at, atq, at -c, atrm)"

explain "El problema de usar crontab para una tarea que solo debe ocurrir UNA vez en la vida es que deja código residual peligroso."
explain "La solución es el comando 'at', que encola el trabajo para una fecha/hora futura y se auto-elimina al terminar:"

if command -v at &>/dev/null && systemctl start atd.service 2>/dev/null; then
    run_and_show "echo 'echo Reinicio programado de ventana de mantenimiento > ${DIR_LAB}/logs/at_job.log' | at 2:00 AM tomorrow"
    run_and_show "echo 'echo Auditoria unica en 30 minutos >> ${DIR_LAB}/logs/at_job.log' | at now + 30 minutes"
    
    explain "Listamos la cola de trabajos pendientes con 'atq' (at queue):"
    run_and_show "atq"
    
    FIRST_JOB=$(atq | head -n 1 | awk '{print $1}')
    if [ -n "$FIRST_JOB" ]; then
        explain "Inspeccionamos con 'at -c ${FIRST_JOB}' cómo 'at' capturó automáticamente el entorno actual y directorio de trabajo:"
        run_and_show "at -c ${FIRST_JOB} | tail -n 18"
        
        explain "Cancelamos y eliminamos el trabajo de la cola con 'atrm ${FIRST_JOB}':"
        run_and_show "atrm ${FIRST_JOB} && atq"
    fi
else
    explain "Demostración de la cola de trabajos efímeros de 'at' (sintaxis del temario Slide 10):"
    cat << EOF > "${DIR_LAB}/atjobs/job_00001.sh"
#!/bin/sh
# atrun uid=0 gid=0
# mail root 0
umask 22
PWD=$(pwd); export PWD
PATH=${PATH}; export PATH
cd ${DIR_LAB} || {
	 echo 'Execution directory inaccessible' >&2
	 exit 1
}
echo "Ejecutando ventana de mantenimiento única programada con: echo 'reboot' | at 2:00 AM tomorrow"
EOF
    run_and_show "echo 'echo \"reboot\" | at 2:00 AM tomorrow'"
    echo -e "${C_DIM}warning: commands will be executed using /bin/sh\njob 1 at $(date -d 'tomorrow 02:00' '+%a %b %e %H:%M:%S %Y')${C_RESET}"
    
    explain "Consultando la cola activa con 'atq' e inspeccionando el entorno capturado con 'at -c 1':"
    echo -e "${C_GREEN}$ atq${C_RESET}\n1\t$(date -d 'tomorrow 02:00' '+%a %b %e %H:%M:%S %Y') a root"
    run_and_show "cat ${DIR_LAB}/atjobs/job_00001.sh"
fi

pie_clase "¿Cuándo deberías elegir 'at' en lugar de 'crontab -e'?" \
          "Siempre que la tarea sea de ejecución única (ad-hoc), como reiniciar un servidor a las 2:00 AM mañana, aplicar un cambio puntual fuera de horario o correr un proceso pesado con 'batch'."

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ✔ LABORATORIO DE ANACRON Y AT COMPLETADO CON ÉXITO                            ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado Anacron (/etc/anacrontab y /var/spool/anacron) y la suite at (at, atq, atrm).\n"
