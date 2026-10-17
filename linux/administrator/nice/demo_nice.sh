#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Prioridad y consumo de CPU con nice, renice y taskset
# Basado en: linux/administrator/nice/nice.md
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto a ejecutar.
#  - Ejecuta y muestra la salida real destacada en un cuadro visual.
#  - No mezcla salidas asíncronas de los procesos en segundo plano.
#  - Desglosa y explica los campos clave (PID, NI, %CPU, PSR).
#  - Proporciona preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   ./demo_nice.sh          -> Modo interactivo (pausa con [ENTER] en cada paso)
#   ./demo_nice.sh --auto 4 -> Modo automático (espera 4 segundos entre pasos)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

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
BIN_WORKER="${SCRIPT_DIR}/cpu_worker"
SRC_WORKER="${SCRIPT_DIR}/cpu_worker.c"

# Lista de PIDs activos para limpieza garantizada
ACTIVE_PIDS=()

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo workers en segundo plano...${C_RESET}"
    if [ ${#ACTIVE_PIDS[@]} -gt 0 ]; then
        kill -TERM "${ACTIVE_PIDS[@]}" 2>/dev/null || true
        wait "${ACTIVE_PIDS[@]}" 2>/dev/null || true
        ACTIVE_PIDS=()
    fi
    pkill -9 -f "cpu_worker" 2>/dev/null || true
    rm -f /tmp/worker_*.log 2>/dev/null || true
    echo -e "${C_GREEN}✔ Todos los workers detenidos. Entorno limpio.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración y ayuda para sesiones TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón directamente."
    echo -e "  - ${C_YELLOW}Scroll con TECLADO:${C_RESET} Presioná ${C_BOLD}Ctrl+b${C_RESET} y luego ${C_BOLD}[${C_RESET} (salís con ${C_BOLD}q${C_RESET})."
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
fi

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
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "${AUTO_WAIT:-0}" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM:-\033[2m}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
    fi
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
        read -r
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

sample_instant_top() {
    local pids="$1"
    local delay="${2:-1.5}"
    echo -e "\n${C_BOLD}${C_GREEN}[top] Consumo INSTANTÁNEO real en ventana de ${delay}s (medición de deltas):${C_RESET}"
    top -b -n 2 -d "$delay" -w 512 -p "$pids" 2>/dev/null | awk '
        /^top - /{ iter++ }
        iter == 2 && (/^[[:space:]]*PID/ || $1 ~ /^[0-9]+$/) { print }
    '
    echo -e "\n${C_BOLD}${C_GREEN}[ps] Tabla de procesos (PID, Core/PSR, NI, %CPU acumulado, COMM):${C_RESET}"
    ps -o pid,psr,ni,%cpu,comm -p "$pids" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 0. Verificaciones previas y compilación
# ------------------------------------------------------------------------------
clear || true
step_banner "0" "Preparación del entorno y verificación de CPUs"

explain "Revisando CPUs lógicas disponibles en el sistema y compilando el worker."
NUM_CPUS=$(nproc)
echo -e "Número de CPUs lógicas detectadas: ${C_BOLD}${NUM_CPUS}${C_RESET}"

if [ "$NUM_CPUS" -lt 2 ]; then
    echo -e "${C_RED}[AVISO] Tenés solo 1 CPU lógica. La sección 5 (multinúcleo) requerirá al menos 2 CPUs.${C_RESET}"
    CPU_A=0
    CPU_B=0
else
    CPU_A=0
    CPU_B=1
fi

echo -e "Usaremos para las pruebas mononúcleo: CPU_A = ${C_BOLD}${CPU_A}${C_RESET}"

# Compilar cpu_worker si no existe
if [ ! -f "$BIN_WORKER" ]; then
    if [ ! -f "$SRC_WORKER" ]; then
        echo -e "${C_RED}[ERROR] No se encontró ${SRC_WORKER}.${C_RESET}"
        exit 1
    fi
    explain "Compilamos el código en C cpu_worker.c:"
    run_and_show "gcc -Wall -Wextra '${SRC_WORKER}' -o '${BIN_WORKER}'"
    echo -e "${C_GREEN}[OK] Binario compilado exitosamente.${C_RESET}"
fi

pie_clase "¿Cuál es el rango de valores de nice en Linux y cuál da más prioridad?" \
          "De -20 (máxima prioridad) a +19 (mínima prioridad). Por defecto los procesos nacen en 0."

pause_step "Presioná [ENTER] para comenzar la primera demostración (Reparto Parejo)..."

# ------------------------------------------------------------------------------
# 1. Caso Base: Reparto Parejo (~50% / ~50%) con el mismo Nice
# ------------------------------------------------------------------------------
step_banner "1" "Reparto equitativo con mismo nice (nice 10 vs nice 10 en CPU ${CPU_A})"

explain "Iniciamos dos workers con idéntica prioridad (nice 10), ambos atados a la CPU ${CPU_A}."
explain "Al tener el mismo peso en el scheduler CFS, les reparte el tiempo a mitades (~50% cada uno)."

# Redirigimos la salida a logs para no ensuciar la terminal de forma asíncrona
taskset -c "$CPU_A" nice -n 10 "$BIN_WORKER" > /tmp/worker_A.log 2>&1 &
PID_A=$!

taskset -c "$CPU_A" nice -n 10 "$BIN_WORKER" > /tmp/worker_B.log 2>&1 &
PID_B=$!

ACTIVE_PIDS=("$PID_A" "$PID_B")
echo -e "Workers iniciados en segundo plano:"
echo -e " • ${C_YELLOW}Worker A:${C_RESET} PID = ${C_BOLD}${PID_A}${C_RESET} (nice 10, CPU ${CPU_A})"
echo -e " • ${C_YELLOW}Worker B:${C_RESET} PID = ${C_BOLD}${PID_B}${C_RESET} (nice 10, CPU ${CPU_A})"

sample_instant_top "$PID_A,$PID_B" 1.5

pie_clase "Observen el %CPU en la tabla: ¿por qué ambos rondan el ~50% si el núcleo está al 100%?" \
          "Porque ambos tienen el mismo peso CFS (peso=110 para nice 10). El scheduler divide el núcleo exactamente a la mitad."

pause_step "Presioná [ENTER] para enviar señal SIGUSR1 y comprobar el trabajo real (vueltas de cómputo)..."

explain "Enviamos SIGUSR1 a ambos workers para que registren sus contadores internos:"
run_and_show "kill -USR1 $PID_A $PID_B"
sleep 0.5

echo -e "\n${C_BOLD}Contadores reales computados por cada proceso:${C_RESET}"
echo -e "${C_CYAN}Worker A (PID ${PID_A}):${C_RESET} $(tail -n 1 /tmp/worker_A.log)"
echo -e "${C_CYAN}Worker B (PID ${PID_B}):${C_RESET} $(tail -n 1 /tmp/worker_B.log)"

explain "Notá que ambos contadores avanzan a la misma velocidad."

pause_step "Presioná [ENTER] para detener estos workers y pasar a la competencia desigual..."

run_and_show "kill -TERM $PID_A $PID_B"
wait "$PID_A" "$PID_B" 2>/dev/null || true
ACTIVE_PIDS=()

# ------------------------------------------------------------------------------
# 2. Competencia Desigual: Nice bajo vs Nice alto (Nice 5 vs Nice 19)
# ------------------------------------------------------------------------------
step_banner "2" "Competencia dispar en misma CPU (nice 5 vs nice 19)"

explain "Linux CFS asigna tiempos según una escala logarítmica de pesos matemáticos:"
explain " - Nice 5  -> Peso en kernel: 335  (le corresponde ~95.7% del CPU)"
explain " - Nice 19 -> Peso en kernel: 15   (le corresponde ~4.3% del CPU)"
explain "Iniciamos ambos en la misma CPU ${CPU_A}."

taskset -c "$CPU_A" nice -n 5 "$BIN_WORKER" > /tmp/worker_nice5.log 2>&1 &
PID_NICE5=$!

taskset -c "$CPU_A" nice -n 19 "$BIN_WORKER" > /tmp/worker_nice19.log 2>&1 &
PID_NICE19=$!

ACTIVE_PIDS=("$PID_NICE5" "$PID_NICE19")
echo -e "Workers iniciados:"
echo -e " • ${C_YELLOW}Worker Nice 5:${C_RESET}  PID = ${C_BOLD}${PID_NICE5}${C_RESET} (CPU ${CPU_A})"
echo -e " • ${C_YELLOW}Worker Nice 19:${C_RESET} PID = ${C_BOLD}${PID_NICE19}${C_RESET} (CPU ${CPU_A})"

sample_instant_top "$PID_NICE5,$PID_NICE19" 1.5

pie_clase "¿El proceso con nice 19 se muere de hambre (starvation) o sigue avanzando?" \
          "No se muere de hambre: CFS nunca deja morir de hambre a un proceso; le da un ~4.3% mínimo garantizado."

pause_step "Presioná [ENTER] para enviar SIGUSR1 y comprobar la disparidad en los contadores..."

explain "Enviamos SIGUSR1 a ambos workers:"
run_and_show "kill -USR1 $PID_NICE5 $PID_NICE19"
sleep 0.5

echo -e "\n${C_BOLD}Contadores computados:${C_RESET}"
echo -e "${C_CYAN}Worker Nice 5  (PID ${PID_NICE5}):${C_RESET}  $(tail -n 1 /tmp/worker_nice5.log)"
echo -e "${C_CYAN}Worker Nice 19 (PID ${PID_NICE19}):${C_RESET} $(tail -n 1 /tmp/worker_nice19.log)"

explain "¡Mirá la diferencia abismal! El worker con nice 5 procesó ~22 veces más vueltas que el de nice 19."

pause_step "Presioná [ENTER] para aplicar renice en caliente sobre el worker desfavorecido (PID $PID_NICE19)..."

# ------------------------------------------------------------------------------
# 3. Modificación Dinámica con renice (19 -> 5)
# ------------------------------------------------------------------------------
step_banner "3" "Modificación de prioridad en caliente con renice (PID $PID_NICE19)"

explain "El worker PID $PID_NICE19 está rezagado con nice 19."
explain "Subiremos su prioridad cambiándole el valor nice a 5 con 'sudo renice'."
explain "Se requiere root/sudo porque disminuir el valor nice (dar más prioridad) está restringido por CAP_SYS_NICE."

run_and_show "sudo renice -n 5 -p $PID_NICE19"

echo -e "\n${C_BOLD}${C_YELLOW}📢 LECCIÓN CLAVE PARA LA CLASE: 'ps' vs 'top' y el promedio histórico${C_RESET}"
explain "1) 'top' mide la ventana INSTANTÁNEA en los últimos segundos."
explain "   Observá cómo top ya refleja el 50/50 de forma inmediata:"
sample_instant_top "$PID_NICE5,$PID_NICE19" 1.5

explain "2) En cambio, 'ps' calcula el PROMEDIO HISTÓRICO desde que nació el proceso."
explain "   Como el PID $PID_NICE19 estuvo corriendo al 4%, el promedio de ps irá convergiendo gradualmente con el tiempo."

pause_step "Presioná [ENTER] para medir la velocidad de los contadores ahora que ambos tienen nice 5..."

echo -e "\n${C_CYAN}Midiendo avance en tiempo real:${C_RESET}"
kill -USR1 "$PID_NICE5" "$PID_NICE19"
sleep 2.0
kill -USR1 "$PID_NICE5" "$PID_NICE19"
sleep 0.5

echo -e "\n${C_BOLD}Últimas lecturas de contadores:${C_RESET}"
echo -e "${C_CYAN}Worker A (PID ${PID_NICE5}):${C_RESET}  $(tail -n 2 /tmp/worker_nice5.log | tr '\n' ' | ')"
echo -e "\n${C_CYAN}Worker B (PID ${PID_NICE19}):${C_RESET} $(tail -n 2 /tmp/worker_nice19.log | tr '\n' ' | ')"

explain "Notá cómo en ese intervalo de 2 segundos ambos sumaron exactamente la misma cantidad de vueltas (~50/50 real)."

pause_step "Presioná [ENTER] para detener ambos workers y pasar a prioridades negativas (-5 vs +5)..."

run_and_show "kill -TERM $PID_NICE5 $PID_NICE19"
wait "$PID_NICE5" "$PID_NICE19" 2>/dev/null || true
ACTIVE_PIDS=()

# ------------------------------------------------------------------------------
# 4. Prioridad Alta: Nice Negativo (-5 vs 5)
# ------------------------------------------------------------------------------
step_banner "4" "Prioridad Alta: Nice Negativo (-5 vs 5)"

explain "Los valores negativos (-1 a -20) son para tareas de máxima urgencia del sistema."
explain "Pesos CFS en el Kernel:"
explain " - Nice -5 -> Peso: 3121 (~90.3%)"
explain " - Nice  5 -> Peso:  335 (~9.7%)"

explain "Iniciamos ambos workers en la CPU ${CPU_A} con nice 5 por defecto:"
taskset -c "$CPU_A" nice -n 5 "$BIN_WORKER" > /tmp/worker_minus5.log 2>&1 &
PID_MINUS5=$!

taskset -c "$CPU_A" nice -n 5 "$BIN_WORKER" > /tmp/worker_plus5.log 2>&1 &
PID_PLUS5=$!

ACTIVE_PIDS=("$PID_MINUS5" "$PID_PLUS5")

echo -e "Workers lanzados:"
echo -e " • PID ${PID_MINUS5} (será promovido a nice -5)"
echo -e " • PID ${PID_PLUS5} (permanecerá en nice +5)"

explain "Elevamos el worker PID ${PID_MINUS5} a nice -5 con sudo:"
run_and_show "sudo renice -n -5 -p $PID_MINUS5"

sample_instant_top "$PID_MINUS5,$PID_PLUS5" 1.5

pie_clase "¿Qué procesos del sistema suelen usar nice negativo en producción?" \
          "Demonios críticos como monitoreo en tiempo real, drivers de audio, bases de datos prioritarias o watchdog."

pause_step "Presioná [ENTER] para ver el cómputo real con SIGUSR1..."

run_and_show "kill -USR1 $PID_MINUS5 $PID_PLUS5"
sleep 0.5
echo -e "\n${C_BOLD}Contadores de bucle procesados:${C_RESET}"
echo -e "${C_CYAN}Worker Nice -5 (PID ${PID_MINUS5}):${C_RESET} $(tail -n 1 /tmp/worker_minus5.log)"
echo -e "${C_CYAN}Worker Nice +5 (PID ${PID_PLUS5}):${C_RESET} $(tail -n 1 /tmp/worker_plus5.log)"

explain "El proceso con nice -5 se apropia de más del 90% del tiempo de procesamiento."

pause_step "Presioná [ENTER] para detener estos workers y pasar a la prueba multinúcleo..."

run_and_show "kill -TERM $PID_MINUS5 $PID_PLUS5"
wait "$PID_MINUS5" "$PID_PLUS5" 2>/dev/null || true
ACTIVE_PIDS=()

# ------------------------------------------------------------------------------
# 5. Multinúcleo y Afinidad con taskset
# ------------------------------------------------------------------------------
step_banner "5" "Multinúcleo y Afinidad (taskset vs nice)"

if [ "$NUM_CPUS" -lt 2 ]; then
    explain "Omitiendo prueba de 2 CPUs porque el sistema solo tiene 1 CPU lógica."
else
    explain "Lección crucial: Nice SOLO causa disputa si los procesos compiten por el MISMO núcleo."
    explain "Si enviamos un worker a CPU ${CPU_A} y otro a CPU ${CPU_B}, ¡ambos obtienen el 100% de su respectivo núcleo!"

    taskset -c "$CPU_A" nice -n 10 "$BIN_WORKER" > /tmp/worker_cpu0.log 2>&1 &
    PID_CPU_A=$!

    taskset -c "$CPU_B" nice -n 10 "$BIN_WORKER" > /tmp/worker_cpu1.log 2>&1 &
    PID_CPU_B=$!

    ACTIVE_PIDS=("$PID_CPU_A" "$PID_CPU_B")

    explain "Verificamos la afinidad fijada con taskset -pc:"
    run_and_show "taskset -pc $PID_CPU_A && taskset -pc $PID_CPU_B"

    sample_instant_top "$PID_CPU_A,$PID_CPU_B" 1.5

    explain "Fijate en la columna %CPU y PSR: ambos procesos tienen ~100% de CPU porque están en núcleos separados."

    pie_clase "¿De qué sirve optimizar nice si tu servidor tiene 16 cores y los procesos están en núcleos distintos?" \
             "De nada: nice solo tiene impacto cuando hay saturación o contención en el mismo núcleo físico/lógico."

    pause_step "Presioná [ENTER] para terminar la demostración y limpiar el sistema..."

    run_and_show "kill -TERM $PID_CPU_A $PID_CPU_B"
    wait "$PID_CPU_A" "$PID_CPU_B" 2>/dev/null || true
    ACTIVE_PIDS=()
fi

step_banner "FIN" "Demostración de Nice, Renice y Taskset finalizada"
echo -e "${C_BOLD}${C_GREEN}✔ Todos los conceptos fueron demostrados con salidas reales en pantalla.${C_RESET}\n"
