#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Ciclo de Vida de Procesos y Estados Zombie (defunct)
# Basado en: linux/administrator/procesos/proceso_zombie.md
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto a ejecutar.
#  - Ejecuta y muestra la salida real destacada en un cuadro visual.
#  - Desglosa y explica los campos clave (PID, PPID, STAT=Z, /proc).
#  - Proporciona preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   ./demo_zombie.sh          -> Modo interactivo (pausa con [ENTER] en cada paso)
#   ./demo_zombie.sh --auto 4 -> Modo automático (espera 4 segundos entre pasos)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

# Colores ANSI enriquecidos para proyector y terminal
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"
C_BG_DARK="\033[48;5;235m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_ZOMBIE="${SCRIPT_DIR}/zombie_maker"
SRC_ZOMBIE="${SCRIPT_DIR}/zombie_maker.c"

# PIDs activos para limpieza en trap
PID_SUBREAPER=""
PID_PADRE=""
PID_HIJO=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Verificando y limpiando procesos de prueba...${C_RESET}"
    if [ -n "$PID_HIJO" ]; then kill -9 "$PID_HIJO" 2>/dev/null || true; fi
    if [ -n "$PID_PADRE" ]; then kill -9 "$PID_PADRE" 2>/dev/null || true; fi
    if [ -n "$PID_SUBREAPER" ]; then kill -9 "$PID_SUBREAPER" 2>/dev/null || true; fi
    pkill -9 -f "zombie_maker" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Sistema limpio. Ningún proceso zombie residual en ejecución.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Detección de TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón libremente."
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
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
            read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
    fi
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para ejecutar el comando y ver su salida...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
        read -r
    fi
}

# Ejecuta un comando, imprime qué comando corrió y muestra su salida formateada en una caja
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

# ==============================================================================
# INICIO DE LA DEMOSTRACIÓN
# ==============================================================================

clear || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🧟 LABORATORIO EN VIVO: EL CICLO DE VIDA DE PROCESOS Y EL ESTADO ZOMBIE       ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Este script guía la demostración en vivo mostrando siempre el comando ejecutado,"
echo -e "su salida real formateada, la explicación técnica y preguntas disparadoras para el grupo."

# ------------------------------------------------------------------------------
# 0. Verificación y Compilación de zombie_maker.c
# ------------------------------------------------------------------------------
step_banner "0" "Preparación y Compilación del Generador de Procesos"

explain "Para estudiar un zombie necesitamos tres procesos estructurados:"
explain " 1. Un Subreaper (proceso abuelo que adopta descendientes huérfanos con prctl)."
explain " 2. Un Padre (hace fork pero NUNCA llama a wait())."
explain " 3. Un Hijo (duerme unos segundos, termina con _exit(0) y se vuelve zombie)."

if [ ! -f "$SRC_ZOMBIE" ]; then
    echo -e "${C_RED}[ERROR] No se encontró el código fuente ${SRC_ZOMBIE}${C_RESET}"
    exit 1
fi

explain "Compilamos el código en C con gcc:"
run_and_show "gcc -Wall -Wextra '${SRC_ZOMBIE}' -o '${BIN_ZOMBIE}'"

if [ ! -f "$BIN_ZOMBIE" ]; then
    echo -e "${C_RED}[ERROR] Falló la compilación del binario.${C_RESET}"
    exit 1
fi

echo -e "${C_GREEN}✔ Binario '${BIN_ZOMBIE}' listo para la demostración.${C_RESET}"

pie_clase "¿Quién recuerda qué llamada al sistema crea un proceso y cuál recoge su código de salida?" \
          "fork() crea una copia del proceso y wait()/waitpid() recoge su código de terminación."

pause_step "Presioná [ENTER] para iniciar el árbol de procesos..."

# ------------------------------------------------------------------------------
# 1. Lanzar la jerarquía de procesos
# ------------------------------------------------------------------------------
step_banner "1" "Lanzar el programa y observar el hijo vivo (Estado S)"

explain "Iniciamos '${BIN_ZOMBIE} 15' en segundo plano (el hijo dormirá 15 segundos)."
explain "Redirigimos la salida a un archivo temporal para capturar los PIDs de forma exacta."

TMP_OUT=$(mktemp)
"${BIN_ZOMBIE}" 15 > "$TMP_OUT" 2>&1 &
MAIN_PID=$!
sleep 0.8

PID_SUBREAPER=$(grep -oE "Subreaper PID: [0-9]+" "$TMP_OUT" | awk '{print $3}' | head -n 1)
PID_PADRE=$(grep -oE "Padre original PID: [0-9]+" "$TMP_OUT" | awk '{print $4}' | head -n 1)
PID_HIJO=$(grep -oE "Hijo PID: [0-9]+" "$TMP_OUT" | awk '{print $3}' | head -n 1)
rm -f "$TMP_OUT"

if [ -z "$PID_SUBREAPER" ] || [ -z "$PID_PADRE" ] || [ -z "$PID_HIJO" ]; then
    echo -e "${C_RED}[ERROR] No se pudieron detectar los 3 PIDs. Abortando.${C_RESET}"
    exit 1
fi

echo -e "\n${C_BOLD}Jerarquía de PIDs detectada:${C_RESET}"
echo -e " • ${C_YELLOW}Subreaper (Abuelo):${C_RESET} PID = ${C_BOLD}${PID_SUBREAPER}${C_RESET}"
echo -e " • ${C_YELLOW}Padre Original:${C_RESET}     PID = ${C_BOLD}${PID_PADRE}${C_RESET} (PPID = ${PID_SUBREAPER})"
echo -e " • ${C_YELLOW}Hijo:${C_RESET}               PID = ${C_BOLD}${PID_HIJO}${C_RESET} (PPID = ${PID_PADRE})"

explain "Consultamos el estado de los procesos con 'ps':"
run_and_show "ps -o pid,ppid,stat,cmd -p ${PID_SUBREAPER},${PID_PADRE},${PID_HIJO}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " - El Hijo (${PID_HIJO}) tiene estado ${C_BOLD}S / S+${C_RESET} (Interruptible Sleep, durmiendo en sleep())."
echo -e " - Su PPID es ${PID_PADRE} (su padre biológico)."
echo -e " - El proceso está completamente vivo y operativo."

pie_clase "¿Qué pasa si un proceso termina su ejecución pero su padre no hace wait()?" \
          "El proceso se convierte en ZOMBIE (defunct). El kernel retiene sus metadatos."

pause_step "Presioná [ENTER] para esperar a que el hijo termine y se transforme en zombie..."

# ------------------------------------------------------------------------------
# 2. El Hijo muere y se convierte en Zombie (STAT = Z)
# ------------------------------------------------------------------------------
step_banner "2" "El Hijo termina y nace el estado Zombie (<defunct>)"

echo -e "${C_YELLOW}⏳ Esperando que el hijo agote sus segundos de sleep...${C_RESET}"
# Esperamos hasta que el estado del hijo sea Z
for ((i=1; i<=20; i++)); do
    STAT_HIJO=$(ps -o stat= -p "$PID_HIJO" 2>/dev/null || echo "")
    if [[ "$STAT_HIJO" == *"Z"* ]]; then
        break
    fi
    sleep 1
    echo -n "."
done
echo -e "\n${C_GREEN}¡El hijo finalizó su código con _exit(0)!${C_RESET}"

explain "Consultamos nuevamente el proceso hijo con 'ps':"
run_and_show "ps -o pid,ppid,stat,cmd -p ${PID_HIJO}"

explain "Veamos también la estructura en forma de árbol (--forest):"
run_and_show "ps -o pid,ppid,stat,cmd --forest -p ${PID_SUBREAPER},${PID_PADRE},${PID_HIJO}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " 1) Columna ${C_BOLD}STAT = Z / Z+${C_RESET}: Indica estado Zombie."
echo -e " 2) Columna ${C_BOLD}CMD = [zombie_maker] <defunct>${C_RESET}: El kernel marca que el proceso ya 'defeció' (murió)."
echo -e " 3) Columna ${C_BOLD}PPID = ${PID_PADRE}${C_RESET}: Sigue apuntando al padre, porque este aún no leyó el código de salida."

pie_clase "¿Un proceso zombie está consumiendo memoria RAM o gastando CPU en este momento?" \
          "¡No! El kernel ya liberó todo su espacio de direcciones (memoria). No gasta ciclos de CPU."

pause_step "Presioná [ENTER] para comprobar en /proc qué recursos gasta realmente..."

# ------------------------------------------------------------------------------
# 3. Radiografía Forense en /proc (Memoria y CPU)
# ------------------------------------------------------------------------------
step_banner "3" "Radiografía Forense en /proc: ¿Consume Memoria o CPU?"

explain "Inspeccionamos el archivo /proc/${PID_HIJO}/status provisto por el kernel:"
run_and_show "cat /proc/${PID_HIJO}/status | grep -E '^(Name|State|Tgid|Pid|PPid|VmSize|VmRSS|Threads):'"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA EN /PROC:${C_RESET}"
echo -e " • ${C_BOLD}State: Z (zombie)${C_RESET} -> Confirmado por el planificador del kernel."
echo -e " • ${C_BOLD}VmSize: 0 kB / VmRSS: 0 kB${C_RESET} -> ¡NO TIENE MEMORIA ASIGNADA! Las páginas de RAM se liberaron."
echo -e " • ${C_BOLD}Threads: 0${C_RESET} -> No tiene ningún hilo de ejecución. No se planifica en la CPU."

explain "Consultemos el límite máximo de PIDs en este sistema:"
run_and_show "cat /proc/sys/kernel/pid_max"

echo -e "\n${C_BOLD}${C_RED}⚠️ EL PELIGRO REAL EN PRODUCCIÓN:${C_RESET}"
echo -e "Un zombie NO satura la memoria ni la CPU. Pero ${C_BOLD}OCUPA UN NÚMERO DE PID${C_RESET} en la tabla de procesos."
echo -e "Si un bug en un software (ej: servidor web, worker) genera miles de zombies sin hacer wait(),"
echo -e "se produce ${C_BOLD}PID Exhaustion${C_RESET}: el kernel no puede crear NINGÚN nuevo proceso ('fork: Resource temporarily unavailable')."

pie_clase "Si un zombie no gasta RAM ni CPU pero molesta... ¿podemos matarlo con 'kill -9'?" \
          "¡La respuesta es NO! Vamos a demostrarlo en vivo en el siguiente paso."

pause_step "Presioná [ENTER] para intentar matar al zombie con kill -9..."

# ------------------------------------------------------------------------------
# 4. El Gran Mito de Sysadmin: Intentar kill -9 al Zombie
# ------------------------------------------------------------------------------
step_banner "4" "Desmontando el Mito: Intentar matar al Zombie con 'kill -9'"

explain "Intentamos enviar la señal SIGKILL (la más destructiva de Linux) directamente al PID zombie:"
run_and_show "kill -9 ${PID_HIJO}"

explain "Comprobamos inmediatamente si el proceso murió o sigue ahí:"
run_and_show "ps -o pid,ppid,stat,cmd -p ${PID_HIJO}"

echo -e "\n${C_BOLD}${C_RED}❌ RESULTADO: ¡EL ZOMBIE SIGUE VIVO CON STAT=Z!${C_RESET}"
echo -e "\n${C_CYAN}🔍 EXPLICACIÓN PARA LA CLASE:${C_RESET}"
echo -e " • ${C_BOLD}'No se puede matar a lo que ya está muerto'${C_RESET}."
echo -e " • Una señal POSIX (incluyendo SIGKILL) es un mensaje que el kernel encola para que un HILO activo"
echo -e "   lo despache cuando sea planificado."
echo -e " • Como el zombie tiene ${C_BOLD}Threads: 0${C_RESET}, la señal se descarta instantáneamente."

pie_clase "Si no podemos matar al zombie con kill -9... ¿a quién tenemos que matar?" \
          "¡Al proceso PADRE! Al morir el padre, el kernel reasigna el hijo a un nuevo proceso."

pause_step "Presioná [ENTER] para matar al padre y ver la adopción por el Subreaper..."

# ------------------------------------------------------------------------------
# 5. Matar al Padre: Adopción por el Subreaper
# ------------------------------------------------------------------------------
step_banner "5" "Matar al Padre Original y Observar la Adopción por el Subreaper"

explain "Terminamos al padre irresponsable que no hizo wait() enviándole SIGKILL:"
run_and_show "kill -9 ${PID_PADRE}"

explain "Consultamos qué pasó con el zombie PID ${PID_HIJO}:"
run_and_show "ps -o pid,ppid,stat,cmd -p ${PID_HIJO}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • El proceso sigue siendo zombie (${C_BOLD}STAT=Z${C_RESET})."
echo -e " • ¡Pero mirá la columna ${C_BOLD}PPID${C_RESET}! Ya no es ${PID_PADRE}."
echo -e " • Ahora su nuevo padre adoptivo es ${C_BOLD}PPID = ${PID_SUBREAPER}${C_RESET} (el Subreaper)."

echo -e "\n${C_BOLD}${C_YELLOW}💡 ¿Qué es un SUBREAPER (PR_SET_CHILD_SUBREAPER)?${C_RESET}"
echo -e "Históricamente en UNIX, cualquier proceso huérfano era adoptado directamente por el PID 1 (init)."
echo -e "Desde Linux 3.4, un proceso intermedio puede declarar 'yo adopto a mis descendientes huérfanos'."
echo -e "Esto lo usan ${C_BOLD}systemd --user${C_RESET}, ${C_BOLD}tmux${C_RESET}, ${C_BOLD}Docker (containerd)${C_RESET} y ${C_BOLD}Kubernetes${C_RESET} para evitar que"
echo -e "procesos huérfanos dentro de un contenedor o sesión salgan al sistema principal."

pie_clase "Como nuestro Subreaper tampoco hace wait(), retiene al zombie adoptado. ¿Qué pasará si matamos al Subreaper?" \
          "Al no haber más subreapers intermedios, el zombie caerá en el proceso 1 (systemd/init)."

pause_step "Presioná [ENTER] para matar al Subreaper y ver cómo systemd limpia el zombie..."

# ------------------------------------------------------------------------------
# 6. La Cosecha Final: Matar al Subreaper y Adopción por PID 1
# ------------------------------------------------------------------------------
step_banner "6" "La Cosecha Final: Adopción por PID 1 (systemd/init) y Limpieza Automática"

explain "Matamos al Subreaper con SIGKILL:"
run_and_show "kill -9 ${PID_SUBREAPER}"

explain "Buscamos de inmediato si el PID ${PID_HIJO} sigue existiendo en el sistema:"
run_and_show "ps -o pid,ppid,stat,cmd -p ${PID_HIJO}"

explain "Verificamos si queda algún rastro del programa 'zombie_maker':"
run_and_show "pgrep -af zombie_maker"

echo -e "\n${C_BOLD}${C_GREEN}✔ RESULTADO: ¡EL ZOMBIE DESAPARECIÓ POR COMPLETO!${C_RESET}"
echo -e "\n${C_CYAN}🔍 EXPLICACIÓN TÉCNICA:${C_RESET}"
echo -e " 1. Al morir el subreaper, el zombie fue heredado automáticamente por ${C_BOLD}PID 1 (systemd / init)${C_RESET}."
echo -e " 2. El proceso 1 tiene un bucle de eventos que atiende la señal ${C_BOLD}SIGCHLD${C_RESET} ejecutando:"
echo -e "    ${C_GREEN}waitpid(-1, NULL, WNOHANG)${C_RESET}"
echo -e " 3. Al llamar a waitpid(), el kernel entrega el código de salida y ${C_BOLD}elimina de inmediato la entrada en la tabla de procesos${C_RESET}."

pause_step "Presioná [ENTER] para ver el resumen de comandos útiles para el Administrador de Sistemas..."

# ------------------------------------------------------------------------------
# 7. Comandos de Diagnóstico Rápido para SysAdmins
# ------------------------------------------------------------------------------
step_banner "7" "Caja de Herramientas del SysAdmin: Detección y Acción en Servidores Reales"

explain "Comandos esenciales para diagnosticar zombies en un servidor de producción:"

echo -e "\n${C_BOLD}1. Contar cuántos zombies hay en el sistema:${C_RESET}"
echo -e "${C_GREEN}$ ps -eo stat | grep -c Z${C_RESET}"
run_and_show "ps -eo stat | grep -c Z"

echo -e "\n${C_BOLD}2. Listar todos los zombies con sus PIDs y nombres:${C_RESET}"
echo -e "${C_GREEN}$ ps -eo stat,pid,ppid,comm | grep -w Z${C_RESET}"

echo -e "\n${C_BOLD}3. Descubrir quién es el padre culpable de un zombie determinado:${C_RESET}"
echo -e "${C_GREEN}$ ps -o ppid= -p <PID_ZOMBIE>${C_RESET}"

echo -e "\n${C_BOLD}4. La regla de oro para eliminar zombies en producción:${C_RESET}"
echo -e " - No intentes 'kill -9 <zombie>' (es inútil)."
echo -e " - Intentá primero reiniciar suavemente el servicio padre: ${C_CYAN}systemctl reload/restart <servicio>${C_RESET}"
echo -e " - Si no responde, terminá al padre: ${C_CYAN}kill -15 <PID_PADRE>${C_RESET} (o ${C_CYAN}kill -9${C_RESET} como último recurso)."
echo -e " - El proceso init/systemd adoptará a los zombies huérfanos y los limpiará en milisegundos."

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN FINALIZADA CON ÉXITO!                                         ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}\n"
