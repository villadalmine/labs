#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Compilación e Inyección de Módulo LKM (Simulación Firmware)
# Laboratorio: linux/administrator/kernel/modulo_lkm_firmware_sim.md (Lab 3.23)
#
# - Compila src/edu_firmware_sim.c en /tmp/lab_demo_lkm_fw (sin ensuciar Git).
# - Muestra metadata con modinfo (vermagic, licencia, module_param).
# - Carga el módulo con fw_version="1.0.0", lee /proc/edu_firmware_sim,
#   /sys/module/edu_firmware_sim/parameters/ y logs del kernel (dmesg/syslog).
# - Simula un hot-update de firmware (rmmod + insmod fw_version="2.0.0-patched").
# - Analiza /proc/sys/kernel/tainted y limpia el módulo al finalizar.
#
# Uso:
#   sudo ./demo_lkm_firmware_sim.sh [--auto <segundos>] [--keep] [--clean] [--help]
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
            echo "Uso: sudo ./demo_lkm_firmware_sim.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
DIR_LAB="/tmp/lab_demo_lkm_fw"
MOD_NAME="edu_firmware_sim"
KVER="$(uname -r)"
KDIR="${KDIR:-/lib/modules/${KVER}/build}"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Descargando módulo ${MOD_NAME} y limpiando temporales...${C_RESET}"
    if lsmod 2>/dev/null | grep -q "^${MOD_NAME}\b"; then
        rmmod "$MOD_NAME" 2>/dev/null || true
    fi
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan artefactos de compilación en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_lkm_firmware_sim.sh\n"
    else
        rm -rf "$DIR_LAB" 2>/dev/null || true
        echo -e "${C_GREEN}✔ Módulo descargado y carpeta temporal eliminada.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para ejecutar insmod/rmmod y leer dmesg.${C_RESET}"
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
cp "${SRC_DIR}/edu_firmware_sim.c" "${SRC_DIR}/Makefile" "$DIR_LAB/"

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🔧 DEMOSTRACIÓN EN VIVO: COMPILAR E INYECTAR MÓDULO LKM (FIRMWARE SIMULATOR) ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Kbuild out-of-tree, module_param, /proc, /sys/module, dmesg/syslog y hot-update\n"

# ==============================================================================
# PASO 1: INSPECCIONAR EL CÓDIGO FUENTE Y VERIFICAR HEADERS
# ==============================================================================
step_banner "1" "Anatomía del Módulo en C (edu_firmware_sim.c) y Kernel Headers"

explain "Observamos el código C y Makefile copiados a ${DIR_LAB} (mantenemos el repositorio limpio):"
run_and_show "head -n 45 ${DIR_LAB}/edu_firmware_sim.c"
run_and_show "cat ${DIR_LAB}/Makefile"
run_and_show "ls -ld \"${KDIR}\" 2>&1 || echo 'Faltan cabeceras del kernel (instalar linux-headers-$(uname -r) o kernel-devel)'"

if [ ! -d "$KDIR" ]; then
    echo -e "${C_RED}[ERROR] No se encontraron cabeceras del kernel en ${KDIR}. Instalá linux-headers-${KVER} o kernel-devel.${C_RESET}"
    exit 1
fi

pie_clase "¿Por qué un módulo del kernel usa pr_info() en lugar de printf() y no define main()?" \
          "Porque corre en Ring 0 dentro del propio kernel sin libc ni consola estándar; los hooks module_init/module_exit reemplazan a main() y pr_info() escribe al ring buffer del núcleo."

pause_step "Presioná [ENTER] para compilar edu_firmware_sim.ko con Kbuild..."

# ==============================================================================
# PASO 2: COMPILACIÓN KBUILD Y METADATA CON MODINFO
# ==============================================================================
step_banner "2" "Compilación Out-of-Tree con Kbuild y Análisis con modinfo"

explain "Compilamos el código contra ${KDIR} para generar el objeto de kernel .ko:"
run_and_show "make -C \"${DIR_LAB}\" KDIR=\"${KDIR}\""
run_and_show "ls -lh ${DIR_LAB}/edu_firmware_sim.ko && file ${DIR_LAB}/edu_firmware_sim.ko"
run_and_show "modinfo ${DIR_LAB}/edu_firmware_sim.ko"

if [ ! -f "${DIR_LAB}/edu_firmware_sim.ko" ]; then
    echo -e "${C_RED}[ERROR] Falló la compilación de edu_firmware_sim.ko.${C_RESET}"
    exit 1
fi

pie_clase "¿Para qué sirve el campo 'vermagic' que muestra modinfo?" \
          "Asegura que la versión del kernel y las opciones ABI (SMP, preempt) con que se compiló el .ko coincidan con el kernel en memoria, evitando corrupción de estructuras internas."

pause_step "Presioná [ENTER] para cargar el módulo simulando Firmware v1.0.0..."

# ==============================================================================
# PASO 3: FASE 1 — CARGA DEL MÓDULO (FIRMWARE v1.0.0) Y LOGS
# ==============================================================================
step_banner "3" "Fase 1: Inyección en Ring 0 (Firmware v1.0.0) + Logs + /proc + /sys"

TAINT_BEFORE=$(cat /proc/sys/kernel/tainted 2>/dev/null || echo "0")
explain "Estado inicial de /proc/sys/kernel/tainted antes de cargar nuestro módulo externo: ${TAINT_BEFORE}"

explain "Insertamos el módulo con insmod pasando los parámetros iniciales de firmware:"
if ! insmod "${DIR_LAB}/edu_firmware_sim.ko" fw_version="1.0.0" device_name="edu-virt-nic0" reload_count=1 2>"${DIR_LAB}/insmod.err"; then
    echo -e "${C_RED}[AVISO] insmod falló:$(cat "${DIR_LAB}/insmod.err")${C_RESET}"
    echo -e "${C_YELLOW}Nota: Si estás en un contenedor sin CAP_SYS_MODULE o con UEFI Secure Boot Lockdown estricto, el kernel bloquea módulos sin firma.${C_RESET}"
    exit 1
fi

run_and_show "lsmod | grep '^${MOD_NAME}\b'"
run_and_show "cat /proc/${MOD_NAME}"
run_and_show "ls -la /sys/module/${MOD_NAME}/parameters/ && head -n 5 /sys/module/${MOD_NAME}/parameters/*"
run_and_show "dmesg | grep '${MOD_NAME}' | tail -n 5"

if command -v journalctl &>/dev/null && [ -d /run/systemd/system ]; then
    run_and_show "journalctl -k -n 5 --no-pager | grep '${MOD_NAME}' || true"
fi

TAINT_AFTER=$(cat /proc/sys/kernel/tainted 2>/dev/null || echo "0")
run_and_show "echo \"Kernel Taint antes: ${TAINT_BEFORE} -> después de cargar módulo out-of-tree sin firma: ${TAINT_AFTER}\""

pie_clase "¿Por qué cambió el número en /proc/sys/kernel/tainted al insertar edu_firmware_sim.ko?" \
          "Porque el módulo se compiló fuera del árbol oficial (bit O = 4096) y sin firma criptográfica de la distro (bit E = 8192), informando a herramientas de soporte que hay código externo en Ring 0."

pause_step "Presioná [ENTER] para simular un Hot-Update de Firmware (v1.0.0 -> v2.0.0-patched)..."

# ==============================================================================
# PASO 4: FASE 2 — HOT-UPDATE DE FIRMWARE (v1.0.0 -> v2.0.0-patched)
# ==============================================================================
step_banner "4" "Fase 2: Simulación de Update de Firmware en Caliente (rmmod + insmod)"

explain "Descargamos la versión anterior del controlador (rmmod) y cargamos el firmware parcheado v2.0.0-patched:"
run_and_show "rmmod ${MOD_NAME}"
run_and_show "insmod \"${DIR_LAB}/edu_firmware_sim.ko\" fw_version=\"2.0.0-patched\" device_name=\"edu-virt-nic0\" reload_count=2"

explain "Comprobamos que /proc, /sys y el log del kernel reflejan inmediatamente la versión v2.0.0-patched:"
run_and_show "cat /proc/${MOD_NAME}"
run_and_show "cat /sys/module/${MOD_NAME}/parameters/fw_version"
run_and_show "dmesg | grep '${MOD_NAME}' | tail -n 6"

pause_step "Presioná [ENTER] para descargar limpiamente el módulo y comprobar remove_proc_entry..."

# ==============================================================================
# PASO 5: FASE 3 — DESCARGA LIMPIA
# ==============================================================================
step_banner "5" "Fase 3: Descarga Limpia y Verificación de Logs de Salida"

run_and_show "rmmod ${MOD_NAME}"
run_and_show "lsmod | grep '^${MOD_NAME}\b' || echo 'Módulo descargado correctamente.'"
run_and_show "test ! -e /proc/${MOD_NAME} && echo '/proc/${MOD_NAME} fue removido limpiamente en module_exit()'"
run_and_show "dmesg | grep '${MOD_NAME}' | tail -n 8"

echo -e "\n${C_BOLD}${C_GREEN}✔ Lab 3.23 completado con éxito.${C_RESET}"
