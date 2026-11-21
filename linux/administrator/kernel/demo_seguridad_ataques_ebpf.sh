#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Seguridad del Kernel, Ataques Defensivos y eBPF en Vivo
# Laboratorio: linux/administrator/kernel/seguridad_ataques_kernel_ebpf.md (Lab 3.25)
#
# - Simulación 1: Info-Leak (/proc/kallsyms, dmesg) + Prueba empírica ASLR (0 vs 2).
# - Simulación 2: Symlink Race (TOCTOU) en directorio sticky bloqueado por fs.protected_symlinks.
# - Simulación 3: Forense de Kernel Taint (/proc/sys/kernel/tainted), lsmod vs /sys/module y lockdown.
# - Simulación 4: Contención SYN Cookies / rp_filter y agotamiento de PIDs (ulimit -u).
# - Parte B (eBPF): bpftool + tracepoint execve + Mini-IDS en vivo con bpftrace.
# - Restaura TODOS los valores sysctl modificados en cleanup().
#
# Uso:
#   sudo ./demo_seguridad_ataques_ebpf.sh [--auto <segundos>] [--keep] [--clean] [--help]
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

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                AUTO_DELAY="$2"
                shift 2
            else
                AUTO_DELAY=3
                shift
            fi
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
            echo "Uso: sudo ./demo_seguridad_ataques_ebpf.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

DIR_LAB="/tmp/lab_demo_sec_ebpf"
ORIG_KPTR=""
ORIG_DMESG=""
ORIG_ASLR=""
ORIG_SYMLINK=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Restaurando parámetros de seguridad sysctl y eliminando temporales...${C_RESET}"
    [ -n "$ORIG_KPTR" ] && sysctl -w "kernel.kptr_restrict=${ORIG_KPTR}" >/dev/null 2>&1 || true
    [ -n "$ORIG_DMESG" ] && sysctl -w "kernel.dmesg_restrict=${ORIG_DMESG}" >/dev/null 2>&1 || true
    [ -n "$ORIG_ASLR" ] && sysctl -w "kernel.randomize_va_space=${ORIG_ASLR}" >/dev/null 2>&1 || true
    [ -n "$ORIG_SYMLINK" ] && sysctl -w "fs.protected_symlinks=${ORIG_SYMLINK}" >/dev/null 2>&1 || true

    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan archivos de prueba en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_seguridad_ataques_ebpf.sh\n"
    else
        rm -rf "$DIR_LAB" 2>/dev/null || true
        echo -e "${C_GREEN}✔ Sysctl restaurados y carpeta temporal eliminada.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para probar sysctl, tracefs y eBPF.${C_RESET}"
    exit 1
fi

trap cleanup EXIT INT TERM

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

rm -rf "$DIR_LAB"
mkdir -p "$DIR_LAB"
chmod 755 "$DIR_LAB"

ORIG_KPTR=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || true)
ORIG_DMESG=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || true)
ORIG_ASLR=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null || true)
ORIG_SYMLINK=$(cat /proc/sys/fs/protected_symlinks 2>/dev/null || true)

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🛡️  DEMOSTRACIÓN EN VIVO: ATAQUES DEFENSIVOS AL KERNEL, HARDENING Y eBPF     ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "4 simulaciones de ataques + mitigación y trazado/Mini-IDS eBPF en vivo\n"

# ==============================================================================
# PASO 1: ATAQUE/MITIGACIÓN 1 — INFO-LEAK DE KERNEL Y ASLR (0 VS 2)
# ==============================================================================
step_banner "1" "Simulación 1: Info-Leak (/proc/kallsyms, dmesg) y Prueba Empírica de ASLR"

explain "Comprobamos si un usuario sin privilegios ('nobody') puede leer punteros de memoria del kernel en /proc/kallsyms o logs:"
if [ -w /proc/sys/kernel/kptr_restrict ]; then
    sysctl -w kernel.kptr_restrict=0 >/dev/null 2>&1 || true
    run_and_show "echo '[VULNERABLE] kptr_restrict=0:' && su -s /bin/sh nobody -c 'head -n 3 /proc/kallsyms'"
    sysctl -w kernel.kptr_restrict=2 >/dev/null 2>&1 || true
    run_and_show "echo '[ENDURECIDO] kptr_restrict=2:' && su -s /bin/sh nobody -c 'head -n 3 /proc/kallsyms'"

    sysctl -w kernel.dmesg_restrict=0 >/dev/null 2>&1 || true
    run_and_show "echo '[VULNERABLE] dmesg_restrict=0:' && su -s /bin/sh nobody -c 'dmesg | head -n 2'"
    sysctl -w kernel.dmesg_restrict=1 >/dev/null 2>&1 || true
    run_and_show "echo '[ENDURECIDO] dmesg_restrict=1:' && su -s /bin/sh nobody -c 'dmesg | head -n 2'"
else
    run_and_show "sysctl kernel.kptr_restrict kernel.dmesg_restrict"
fi

if command -v gcc &>/dev/null; then
    explain "Compilamos un binario educativo (aslr_probe.c) para ver direcciones de Stack y Heap con ASLR apagado vs encendido:"
    cat <<'EOF' > "${DIR_LAB}/aslr_probe.c"
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    int stack_var = 42;
    void *heap_ptr = malloc(64);
    printf("main=%p | stack=%p | heap=%p\n", (void*)main, (void*)&stack_var, heap_ptr);
    free(heap_ptr);
    return 0;
}
EOF
    run_and_show "gcc -O2 -fPIE -pie \"${DIR_LAB}/aslr_probe.c\" -o \"${DIR_LAB}/aslr_probe\""
    if [ -w /proc/sys/kernel/randomize_va_space ]; then
        sysctl -w kernel.randomize_va_space=0 >/dev/null 2>&1 || true
        run_and_show "echo '[SIN ASLR - randomize_va_space=0] Direcciones fijas predecibles:' && \"${DIR_LAB}/aslr_probe\" && \"${DIR_LAB}/aslr_probe\""
        sysctl -w kernel.randomize_va_space=2 >/dev/null 2>&1 || true
        run_and_show "echo '[CON ASLR - randomize_va_space=2] Direcciones aleatorizadas en cada corrida:' && \"${DIR_LAB}/aslr_probe\" && \"${DIR_LAB}/aslr_probe\""
    else
        run_and_show "setarch \$(uname -m) -R \"${DIR_LAB}/aslr_probe\" && setarch \$(uname -m) -R \"${DIR_LAB}/aslr_probe\" && \"${DIR_LAB}/aslr_probe\" && \"${DIR_LAB}/aslr_probe\""
    fi
fi

pie_clase "¿Por qué kptr_restrict=2 y dmesg_restrict=1 complementan a KASLR?" \
          "Porque KASLR aleatoriza dónde carga el kernel en RAM, pero si un usuario local lee punteros reales en /proc/kallsyms o en mensajes de error de dmesg, recupera el mapa exacto y anula la protección."

pause_step "Presioná [ENTER] para probar la Simulación 2: Symlink Race (TOCTOU) en /tmp..."

# ==============================================================================
# PASO 2: ATAQUE/MITIGACIÓN 2 — SYMLINK RACE (TOCTOU) EN STICKY DIR
# ==============================================================================
step_banner "2" "Simulación 2: Symlink Race (TOCTOU) en Directorio Sticky (/tmp)"

mkdir -p "${DIR_LAB}/sticky_dir"
chmod 1777 "${DIR_LAB}/sticky_dir"
echo "SECRETO_DE_ROOT" > "${DIR_LAB}/root_target.txt"
chmod 644 "${DIR_LAB}/root_target.txt"
su -s /bin/sh nobody -c "ln -sf ${DIR_LAB}/root_target.txt ${DIR_LAB}/sticky_dir/evil_link"

explain "Creamos un enlace simbólico propiedad de 'nobody' dentro de un directorio sticky (1777) apuntando a un archivo de root:"
run_and_show "ls -ld \"${DIR_LAB}/sticky_dir\" && ls -l \"${DIR_LAB}/sticky_dir/evil_link\""

if [ -w /proc/sys/fs/protected_symlinks ]; then
    sysctl -w fs.protected_symlinks=0 >/dev/null 2>&1 || true
    run_and_show "echo '[VULNERABLE] fs.protected_symlinks=0 (root sigue el enlace trampa):' && cat \"${DIR_LAB}/sticky_dir/evil_link\""
    sysctl -w fs.protected_symlinks=1 >/dev/null 2>&1 || true
    run_and_show "echo '[PROTEGIDO] fs.protected_symlinks=1 (VFS bloquea TOCTOU):' && cat \"${DIR_LAB}/sticky_dir/evil_link\""
else
    run_and_show "sysctl fs.protected_symlinks fs.protected_hardlinks"
fi

pie_clase "¿Qué bloquea exactamente fs.protected_symlinks=1?" \
          "Impide seguir symlinks ubicados en directorios world-writable sticky (como /tmp) cuando el dueño del enlace no coincide con el dueño del directorio ni con el usuario que abre el archivo."

pause_step "Presioná [ENTER] para ejecutar la Simulación 3: Forense de Rootkits LKM y Taint..."

# ==============================================================================
# PASO 3: SIMULACIÓN 3 — AUDITORÍA FORENSE DE LKM, TAINT Y LOCKDOWN
# ==============================================================================
step_banner "3" "Simulación 3: Forense de Módulos (lsmod vs /sys/module), Taint y Lockdown"

explain "Decodificamos las banderas reales de /proc/sys/kernel/tainted y el modo de Kernel Lockdown:"
run_and_show "python3 - <<'PY'
t = int(open('/proc/sys/kernel/tainted').read().strip())
flags = [(0,'P:Proprietary'),(1,'F:Force'),(4,'R:UnsupportedHW'),(12,'O:OutOfTree'),(13,'E:Unsigned')]
active = [name for bit,name in flags if t & (1<<bit)]
print(f'tainted={t} -> flags={active if active else [\"0 (Limpio/GPL)\"]}')
PY"
run_and_show "cat /sys/kernel/security/lockdown 2>/dev/null || echo 'lockdown no expuesto'"
run_and_show "sysctl kernel.modules_disabled 2>/dev/null || true"

explain "Cruce forense rápido entre módulos declarados en /proc/modules (lsmod) y directorios reales en /sys/module/:"
run_and_show "lsmod | tail -n +2 | wc -l | xargs -I{} echo 'Módulos en lsmod: {}' && ls -d /sys/module/*/initstate 2>/dev/null | wc -l | xargs -I{} echo 'Módulos cargables con initstate en /sys/module: {}'"

pie_clase "¿Qué ocurre cuando activás 'sysctl -w kernel.modules_disabled=1' después del arranque?" \
          "Cierra de forma irreversible hasta el siguiente reinicio la carga y descarga de cualquier LKM nuevo, neutralizando rootkits basados en módulos cargables."

pause_step "Presioná [ENTER] para ejecutar la Simulación 4: Contención DoS / PIDs y Parte B (eBPF)..."

# ==============================================================================
# PASO 4: SIMULACIÓN 4 — SYN COOKIES, RP_FILTER Y CONTENCIÓN DE PIDS
# ==============================================================================
step_banner "4" "Simulación 4: Endurecimiento Anti-DoS (SYN Cookies, rp_filter y Límite PIDs)"

run_and_show "sysctl net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter 2>/dev/null || true"

explain "Demostramos contención segura de agotamiento de procesos (fork bomb defensivo) como usuario sin privilegios 'nobody' con ulimit -u = 6:"
run_and_show "su -s /bin/bash nobody -c 'ulimit -u 6; for i in \$(seq 1 15); do (sleep 1) & done 2>&1; wait' | head -n 10"

pause_step "Presioná [ENTER] para pasar a la Parte B: Observabilidad y Mini-IDS eBPF en vivo..."

# ==============================================================================
# PASO 5: PARTE B — eBPF EN VIVO CON BPFTOOL Y BPFTRACE MINI-IDS
# ==============================================================================
step_banner "5" "Parte B: eBPF Verificado en Ring 0 (bpftool + bpftrace Mini-IDS)"

# Asegurar debugfs / tracefs montados si estamos en VM minimalista
if [ -d /sys/kernel/tracing ] && ! mountpoint -q /sys/kernel/tracing 2>/dev/null; then
    mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true
fi
if [ -d /sys/kernel/debug ] && ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
    mount -t debugfs nodev /sys/kernel/debug 2>/dev/null || true
fi

explain "Verificamos la presencia de BTF (/sys/kernel/btf/vmlinux) para portabilidad CO-RE y listamos programas eBPF cargados:"
run_and_show "ls -lh /sys/kernel/btf/vmlinux 2>/dev/null || echo 'BTF no disponible en este entorno'"
if command -v bpftool &>/dev/null; then
    run_and_show "bpftool prog list 2>&1 | head -n 15"
    run_and_show "bpftool map list 2>&1 | head -n 12"
else
    run_and_show "echo 'bpftool no instalado en este entorno (en Ubuntu: linux-tools-common / bpftool)'"
fi

if command -v bpftrace &>/dev/null && [ -d /sys/kernel/tracing/events/syscalls ]; then
    explain "Ejecutamos un trazador eBPF en vivo sobre 'tracepoint:syscalls:sys_enter_execve' durante 5 segundos:"
    EXEC_OUT="${DIR_LAB}/ebpf_execve.log"
    echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR ────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf(\"eBPF execve -> pid=%d comm=%s file=%s\\\\n\", pid, comm, str(args->filename)); }' &${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"
    timeout 8 bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("eBPF execve -> pid=%d comm=%s file=%s\n", pid, comm, str(args->filename)); }' >"$EXEC_OUT" 2>&1 &
    EXEC_PID=$!
    for _ in $(seq 1 20); do
        grep -q 'Attaching' "$EXEC_OUT" 2>/dev/null && break
        sleep 0.3
    done
    /bin/uname -r >/dev/null
    /bin/true
    sleep 0.5
    kill "$EXEC_PID" 2>/dev/null || true
    wait "$EXEC_PID" 2>/dev/null || true
    head -n 12 "$EXEC_OUT"
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"

    explain "Ahora lanzamos nuestro Mini-IDS eBPF vigilando accesos al archivo señuelo ${DIR_LAB}/vault_secret.key:"
    echo "TOP_SECRET_API_KEY=demo_ebpf_ids" > "${DIR_LAB}/vault_secret.key"
    chmod 600 "${DIR_LAB}/vault_secret.key"

    IDS_OUT="${DIR_LAB}/ebpf_ids.log"
    SECRET_PATH="${DIR_LAB}/vault_secret.key"
    cat <<EOF > "${DIR_LAB}/mini_ids.bt"
tracepoint:syscalls:sys_enter_openat
/str(args->filename) == "${SECRET_PATH}"/
{
    printf("[ALERTA eBPF IDS] pid=%d uid=%d comm=%s intento abrir %s\n", pid, uid, comm, str(args->filename));
}
EOF
    run_and_show "cat ${DIR_LAB}/mini_ids.bt"

    echo -e "\n${C_BOLD}${C_BLUE}┌─── DEMO MINI-IDS eBPF EN VIVO ────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ bpftrace ${DIR_LAB}/mini_ids.bt &  (mientras un proceso simula abrir el secreto)${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── ALERTA REAL EMITIDA POR EL KERNEL VIA eBPF ────────────────────────────────────┤${C_RESET}"
    timeout 8 bpftrace "${DIR_LAB}/mini_ids.bt" >"$IDS_OUT" 2>&1 &
    BPF_PID=$!
    for _ in $(seq 1 20); do
        grep -q 'Attaching' "$IDS_OUT" 2>/dev/null && break
        sleep 0.3
    done
    cat "$SECRET_PATH" >/dev/null 2>&1 || true
    sleep 0.5
    kill "$BPF_PID" 2>/dev/null || true
    wait "$BPF_PID" 2>/dev/null || true
    cat "$IDS_OUT"
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
else
    explain "bpftrace o /sys/kernel/tracing no está disponible en este entorno (ej. contenedor restringido sin CAP_BPF)."
    run_and_show "echo 'Sintaxis Mini-IDS: bpftrace -e '\''tracepoint:syscalls:sys_enter_openat /str(args->filename) == \"/tmp/vault_secret.key\"/ { printf(\"[ALERTA eBPF IDS] pid=%d comm=%s\\n\", pid, comm); }'\'''"
fi

pie_clase "¿Por qué en producción moderna herramientas como Falco, Tetragon o Cilium prefieren eBPF sobre módulos LKM?" \
          "Porque el eBPF Verifier garantiza antes de ejecutar que el programa no tiene bucles infinitos ni accesos de memoria inválidos (evitando Kernel Panics) y CO-RE (BTF) evita recompilar por cada kernel."

echo -e "\n${C_BOLD}${C_GREEN}✔ Lab 3.25 completado con éxito.${C_RESET}"
