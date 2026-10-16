#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Prioridad y consumo de CPU con nice, renice y taskset
# Basado en: linux/administrator/nice.md
# Uso:
#   ./demo_nice.sh          -> Modo interactivo (pausa con [ENTER] en cada paso)
#   ./demo_nice.sh --auto 5 -> Modo automático (espera 5 segundos entre pasos)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_WORKER="${SCRIPT_DIR}/cpu_worker"
SRC_WORKER="${SCRIPT_DIR}/cpu_worker.c"

# Lista de PIDs activos para limpieza garantizada
ACTIVE_PIDS=()

cleanup() {
    echo -e "\n${C_YELLOW}[!] Limpiando procesos en segundo plano...${C_RESET}"
    if [ ${#ACTIVE_PIDS[@]} -gt 0 ]; then
        kill -TERM "${ACTIVE_PIDS[@]}" 2>/dev/null || true
        wait "${ACTIVE_PIDS[@]}" 2>/dev/null || true
        ACTIVE_PIDS=()
    fi
    echo -e "${C_GREEN}[OK] Todos los workers detenidos. Entorno limpio.${C_RESET}"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Configuración y ayuda para sesiones TMUX
# ------------------------------------------------------------------------------
if [ -n "${TMUX:-}" ]; then
    # Habilita el scroll con la rueda del ratón en tmux
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón directamente."
    echo -e "  - ${C_YELLOW}Scroll con TECLADO:${C_RESET} Presioná ${C_BOLD}Ctrl+b${C_RESET} y luego ${C_BOLD}[${C_RESET} (usá flechas/RePág/AvPág; salís con ${C_BOLD}q${C_RESET})."
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
fi

step_banner() {
    local num="$1"
    local title="$2"
    echo -e "\n${C_MAGENTA}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW} PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}======================================================================${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💬 EXPLICACIÓN:${C_RESET} $1"
}

command_info() {
    echo -e "${C_BOLD}${C_GREEN}$ ${1}${C_RESET}"
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_YELLOW}👉 ${msg}${C_RESET}"
        read -r
    fi
}

sample_ps() {
    local pids="$1"
    local iterations="${2:-2}"
    echo -e "\n${C_BOLD}[ps] Promedio acumulado desde el inicio del proceso (%CPU promedio de vida):${C_RESET}"
    for ((i=1; i<=iterations; i++)); do
        ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$pids"
        sleep 1.2
    done
}

sample_instant_top() {
    local pids="$1"
    local delay="${2:-1.5}"
    echo -e "\n${C_BOLD}${C_GREEN}[top] Consumo INSTANTÁNEO real en ventana de ${delay}s (sin arrastrar el pasado):${C_RESET}"
    # La iteración 1 de top es acumulativa; la iteración 2 mide el delta instantáneo
    top -b -n 2 -d "$delay" -p "$pids" 2>/dev/null | awk '
        /^top - /{ iter++ }
        iter == 2 && (/^[[:space:]]*PID/ || /cpu_worker/) { print }
    '
}

# ------------------------------------------------------------------------------
# 0. Verificaciones previas y compilación
# ------------------------------------------------------------------------------
step_banner "0" "Preparación del entorno y verificación de CPUs"

explain "Revisando CPUs lógicas disponibles en el sistema y permisos."
NUM_CPUS=$(nproc)
echo -e "Número de CPUs lógicas detectadas: ${C_BOLD}${NUM_CPUS}${C_RESET}"

if [ "$NUM_CPUS" -lt 2 ]; then
    echo -e "${C_RED}[AVISO] Tenés solo 1 CPU lógica. La sección 5 (multinúcleo con CPU_B) requerirá al menos 2 CPUs.${C_RESET}"
    CPU_A=0
    CPU_B=0
else
    CPU_A=0
    CPU_B=1
fi

echo -e "Usaremos: CPU_A=${C_BOLD}${CPU_A}${C_RESET} y CPU_B=${C_BOLD}${CPU_B}${C_RESET}"

# Compilar cpu_worker si no existe
if [ ! -f "$BIN_WORKER" ]; then
    if [ ! -f "$SRC_WORKER" ]; then
        echo -e "${C_RED}[ERROR] No se encontró ${SRC_WORKER}.${C_RESET}"
        exit 1
    fi
    echo -e "Compilando ${SRC_WORKER}..."
    command_info "gcc -Wall -Wextra ${SRC_WORKER} -o ${BIN_WORKER}"
    gcc -Wall -Wextra "$SRC_WORKER" -o "$BIN_WORKER"
    echo -e "${C_GREEN}[OK] Binario compilado exitosamente.${C_RESET}"
fi

pause_step "Presioná [ENTER] para comenzar la clase y la primera demostración..."

# ------------------------------------------------------------------------------
# 1. Caso Base: Reparto Parejo (~50% / ~50%) con el mismo Nice
# ------------------------------------------------------------------------------
step_banner "1" "Reparto equitativo con mismo nice (nice 10 vs nice 10 en CPU ${CPU_A})"

explain "Iniciamos dos workers con idéntica prioridad (nice 10), ambos atados a la CPU ${CPU_A}."
explain "Al tener el mismo peso (peso=110), el planificador CFS les reparte el tiempo a mitades (~50% c/u)."

command_info "taskset -c $CPU_A nice -n 10 $BIN_WORKER & (Worker A)"
taskset -c "$CPU_A" nice -n 10 "$BIN_WORKER" &
PID_A=$!

command_info "taskset -c $CPU_A nice -n 10 $BIN_WORKER & (Worker B)"
taskset -c "$CPU_A" nice -n 10 "$BIN_WORKER" &
PID_B=$!

ACTIVE_PIDS=("$PID_A" "$PID_B")
echo -e "Workers iniciados: Worker A (PID=${C_BOLD}$PID_A${C_RESET}), Worker B (PID=${C_BOLD}$PID_B${C_RESET})"

sample_instant_top "$PID_A,$PID_B" 1.5

pause_step "Presioná [ENTER] para enviar señal SIGUSR1 y consultar los contadores de ambos..."

echo -e "\nEnviando SIGUSR1 para comparar el trabajo computacional real (vueltas de bucle):"
command_info "kill -USR1 $PID_A $PID_B"
kill -USR1 "$PID_A" "$PID_B"
sleep 0.5

explain "Ambos contadores tienen valores muy similares porque recibieron la misma cantidad de CPU."

pause_step "Presioná [ENTER] para detener estos workers y pasar al siguiente paso..."

command_info "kill -TERM $PID_A $PID_B"
kill -TERM "$PID_A" "$PID_B"
wait "$PID_A" "$PID_B" 2>/dev/null || true
ACTIVE_PIDS=()

# ------------------------------------------------------------------------------
# 2. Competencia Desigual: Nice bajo vs Nice alto (Nice 5 vs Nice 19)
# ------------------------------------------------------------------------------
step_banner "2" "Competencia dispar en misma CPU (nice 5 vs nice 19)"

explain "Linux CFS asigna tiempos según pesos matemáticos:"
explain " - Nice 5  -> Peso en kernel: 335  (le toca ~95.7%)"
explain " - Nice 19 -> Peso en kernel: 15   (le toca ~4.3%)"
explain "Iniciamos ambos en la misma CPU ${CPU_A}."

command_info "taskset -c $CPU_A nice -n 5 $BIN_WORKER & (Worker Nice 5)"
taskset -c "$CPU_A" nice -n 5 "$BIN_WORKER" &
PID_NICE5=$!

command_info "taskset -c $CPU_A nice -n 19 $BIN_WORKER & (Worker Nice 19)"
taskset -c "$CPU_A" nice -n 19 "$BIN_WORKER" &
PID_NICE19=$!

ACTIVE_PIDS=("$PID_NICE5" "$PID_NICE19")
echo -e "Workers iniciados: Nice 5 (PID=${C_BOLD}$PID_NICE5${C_RESET}), Nice 19 (PID=${C_BOLD}$PID_NICE19${C_RESET})"

sample_instant_top "$PID_NICE5,$PID_NICE19" 1.5

pause_step "Presioná [ENTER] para enviar SIGUSR1 y ver la disparidad de los contadores..."

echo -e "\nEnviando SIGUSR1 a ambos workers:"
command_info "kill -USR1 $PID_NICE5 $PID_NICE19"
kill -USR1 "$PID_NICE5" "$PID_NICE19"
sleep 0.5

explain "¡Mirá la enorme diferencia! El worker con nice 5 avanzó unas 20 a 24 veces más vueltas que el de nice 19."
explain "IMPORTANTE: No los detenemos; ahora modificaremos el worker PID $PID_NICE19 en caliente."

pause_step "Presioná [ENTER] para aplicar renice en caliente sobre PID $PID_NICE19..."

# ------------------------------------------------------------------------------
# 3. Modificación Dinámica con renice (19 -> 5)
# ------------------------------------------------------------------------------
step_banner "3" "Modificación de prioridad en caliente con renice (PID $PID_NICE19)"

explain "El worker PID $PID_NICE19 sigue ejecutándose con nice 19."
explain "Subiremos su prioridad cambiándole el valor nice a 5 con 'sudo renice'."
explain "(Se requiere sudo porque disminuir el nice / aumentar prioridad lo restringe el kernel a root/CAP_SYS_NICE)."

command_info "sudo renice -n 5 -p $PID_NICE19"
sudo renice -n 5 -p "$PID_NICE19"

echo -e "\n${C_BOLD}${C_YELLOW}📢 LECCIÓN CLAVE PARA LA CLASE: 'ps' vs 'top' y el promedio histórico${C_RESET}"
explain "1) 'ps' calcula el PROMEDIO HISTÓRICO desde que nació el proceso."
explain "   Como el PID $PID_NICE19 estuvo corriendo al 4%, el promedio de ps no cambia de golpe a 50%;"
explain "   irá convergiendo gradualmente con el paso de los minutos (4% -> 5% -> 6%...):"
sample_ps "$PID_NICE5,$PID_NICE19" 2

explain "2) En cambio, 'top' mide la ventana INSTANTÁNEA en los últimos segundos."
explain "   Observá cómo top ya refleja el 50/50 de forma inmediata:"
sample_instant_top "$PID_NICE5,$PID_NICE19" 1.5

pause_step "Presioná [ENTER] para medir la velocidad de los contadores en dos momentos..."

echo -e "\n${C_CYAN}Midiendo avance de vueltas del bucle (Contadores con SIGUSR1):${C_RESET}"
echo -e "Muestra 1:"
kill -USR1 "$PID_NICE5" "$PID_NICE19"
sleep 2.0
echo -e "\nMuestra 2 (2 segundos después):"
kill -USR1 "$PID_NICE5" "$PID_NICE19"
sleep 0.5

explain "Notá cómo en esos 2 segundos ambos sumaron exactamente la misma cantidad de vueltas (~50/50 real)."

pause_step "Presioná [ENTER] para detener ambos workers y pasar a la prueba de prioridades negativas..."

command_info "kill -TERM $PID_NICE5 $PID_NICE19"
kill -TERM "$PID_NICE5" "$PID_NICE19"
wait "$PID_NICE5" "$PID_NICE19" 2>/dev/null || true
ACTIVE_PIDS=()

# ------------------------------------------------------------------------------
# 4. Prioridad Alta: Nice Negativo (-5 vs 5)
# ------------------------------------------------------------------------------
step_banner "4" "Prioridad Alta: Nice Negativo (-5 vs 5)"

explain "Los valores negativos (-1 a -20) son para máxima prioridad."
explain "Pesos CFS en el Kernel:"
explain " - Nice -5 -> Peso: 3121 (~90.3%)"
explain " - Nice  5 -> Peso:  335 (~9.7%)"

command_info "taskset -c $CPU_A nice -n 5 $BIN_WORKER & (Worker Nice -5 futuro)"
taskset -c "$CPU_A" nice -n 5 "$BIN_WORKER" &
PID_MINUS5=$!

command_info "taskset -c $CPU_A nice -n 5 $BIN_WORKER & (Worker Nice +5)"
taskset -c "$CPU_A" nice -n 5 "$BIN_WORKER" &
PID_PLUS5=$!

ACTIVE_PIDS=("$PID_MINUS5" "$PID_PLUS5")

echo -e "\nAplicando nice -5 al worker $PID_MINUS5 con sudo:"
command_info "sudo renice -n -5 -p $PID_MINUS5"
sudo renice -n -5 -p "$PID_MINUS5"

sample_instant_top "$PID_MINUS5,$PID_PLUS5" 1.5

pause_step "Presioná [ENTER] para ver los contadores con SIGUSR1..."
command_info "kill -USR1 $PID_MINUS5 $PID_PLUS5"
kill -USR1 "$PID_MINUS5" "$PID_PLUS5"
sleep 0.5

explain "El proceso con nice -5 se apropia de más del 90% del tiempo de esa CPU."

pause_step "Presioná [ENTER] para detener estos workers y pasar a la prueba multinúcleo..."
command_info "kill -TERM $PID_MINUS5 $PID_PLUS5"
kill -TERM "$PID_MINUS5" "$PID_PLUS5"
wait "$PID_MINUS5" "$PID_PLUS5" 2>/dev/null || true
ACTIVE_PIDS=()

# ------------------------------------------------------------------------------
# 5. Multinúcleo y Afinidad con taskset
# ------------------------------------------------------------------------------
step_banner "5" "Multinúcleo y Afinidad (taskset vs nice)"

if [ "$NUM_CPUS" -lt 2 ]; then
    explain "Omitiendo prueba de 2 CPUs porque el sistema solo tiene 1 CPU lógica."
else
    explain "Demostración fundamental: Nice SOLO causa disputa si los procesos compiten por el mismo núcleo."
    explain "Si enviamos un worker a CPU $CPU_A y otro a CPU $CPU_B, ¡ambos obtienen casi el 100% de su respectivo núcleo!"

    command_info "taskset -c $CPU_A nice -n 10 $BIN_WORKER & (En CPU $CPU_A)"
    taskset -c "$CPU_A" nice -n 10 "$BIN_WORKER" &
    PID_CPU_A=$!

    command_info "taskset -c $CPU_B nice -n 10 $BIN_WORKER & (En CPU $CPU_B)"
    taskset -c "$CPU_B" nice -n 10 "$BIN_WORKER" &
    PID_CPU_B=$!

    ACTIVE_PIDS=("$PID_CPU_A" "$PID_CPU_B")

    echo -e "\nAfinidad fijada:"
    taskset -pc "$PID_CPU_A"
    taskset -pc "$PID_CPU_B"

    sample_instant_top "$PID_CPU_A,$PID_CPU_B" 1.5

    explain "Fijate: cada uno está en un núcleo diferente. Ambos se acercan al 100% de su propio núcleo."

    pause_step "Presioná [ENTER] para ver un proceso con afinidad libre (0,1) y migración..."

    command_info "taskset -c $CPU_A,$CPU_B nice -n 10 $BIN_WORKER & (Worker Migrante)"
    taskset -c "$CPU_A,$CPU_B" nice -n 10 "$BIN_WORKER" &
    PID_MIGRANTE=$!
    ACTIVE_PIDS+=("$PID_MIGRANTE")

    taskset -pc "$PID_MIGRANTE"
    sample_instant_top "$PID_MIGRANTE" 1.5

    explain "El worker migrante puede ejecutarse en cualquiera de los dos núcleos permitidos según decida el scheduler."

    pause_step "Presioná [ENTER] para terminar la demostración y limpiar procesos..."
    command_info "kill -TERM $PID_CPU_A $PID_CPU_B $PID_MIGRANTE"
    kill -TERM "$PID_CPU_A" "$PID_CPU_B" "$PID_MIGRANTE"
    wait "$PID_CPU_A" "$PID_CPU_B" "$PID_MIGRANTE" 2>/dev/null || true
    ACTIVE_PIDS=()
fi

step_banner "FIN" "Demostración completada con éxito"
echo -e "${C_GREEN}¡Listo! Todos los conceptos de nice, renice, CFS y taskset fueron demostrados.${C_RESET}\n"
