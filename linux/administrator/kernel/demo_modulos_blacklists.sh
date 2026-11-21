#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Anatomía de /boot, Módulos LKM y Blacklists
# Laboratorio: linux/administrator/kernel/modulos_lkm_blacklists_boot.md (Lab 1.7)
#
# Recorrido práctico de /boot, Módulos LKM y Blacklists:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Lista los kernels en /boot (clásico + BLS + OSTree) y compara con uname -r.
#  - Lista todos los módulos en blacklist (/etc/modprobe.d + modprobe --showconfig).
#  - Demuestra carga/descarga segura con el módulo inocuo 'dummy'.
#  - Demuestra la diferencia real entre 'blacklist' e 'install /bin/false'.
#  - Genera plantilla segura para bloqueo de almacenamiento USB (sin romper usbhid).
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   sudo ./demo_modulos_blacklists.sh [--auto <segundos>] [--keep] [--clean] [--help]
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
            echo "Uso: sudo ./demo_modulos_blacklists.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

DIR_LAB="/tmp/lab_demo_modulos"
DEMO_BLACKLIST_CONF="/etc/modprobe.d/99-lab-blacklist-demo.conf"
DUMMY_WAS_LOADED=false

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Restaurando estado original de módulos y /etc/modprobe.d...${C_RESET}"
    rm -f "$DEMO_BLACKLIST_CONF" 2>/dev/null || true

    if [ "$DUMMY_WAS_LOADED" = false ] && lsmod 2>/dev/null | grep -q '^dummy\b'; then
        modprobe -r dummy 2>/dev/null || rmmod dummy 2>/dev/null || true
    fi

    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los archivos de ejemplo en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_modulos_blacklists.sh\n"
    else
        rm -rf "$DIR_LAB" 2>/dev/null || true
        echo -e "${C_GREEN}✔ Archivos temporales y regla de prueba eliminados correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para probar modprobe y /etc/modprobe.d.${C_RESET}"
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

mkdir -p "$DIR_LAB"
if lsmod 2>/dev/null | grep -q '^dummy\b'; then
    DUMMY_WAS_LOADED=true
fi

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🐧 DEMOSTRACIÓN EN VIVO: /boot, MÓDULOS LKM (modprobe) Y BLACKLISTS           ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Cubre: listar kernels en /boot, listar blacklists, troubleshooting y bloqueo USB\n"

# ==============================================================================
# PASO 1: IDENTIFICAR EL KERNEL ACTIVO Y LISTAR KERNELS EN /boot (EJERCICIO 1)
# ==============================================================================
step_banner "1" "Auditoría del Kernel en Memoria y Listado de Kernels en /boot"

explain "Primero verificamos qué versión de kernel está ejecutándose ahora en RAM y con qué parámetros arrancó:"
run_and_show "uname -a"
run_and_show "cat /proc/cmdline"

explain "Auditoría de /boot: listamos todas las imágenes de kernel e initramfs presentes en /boot (incluyendo entradas BLS u OSTree si existen):"
run_and_show "ls -lh /boot/ 2>/dev/null | head -n 25"
run_and_show "ls -lh /boot/vmlinuz* /boot/initr* 2>/dev/null || echo 'Sin vmlinuz directo en /boot (puede usar /boot/ostree o contenedor sin /boot montado)'"
run_and_show "ls -la /boot/loader/entries/ 2>/dev/null && grep -H '^title\|^linux' /boot/loader/entries/*.conf 2>/dev/null | head -n 12 || true"

pie_clase "¿Por qué una distribución Linux suele conservar 2 o 3 versiones de kernel en /boot?" \
          "Para permitir un rollback inmediato desde el menú de arranque (GRUB/BLS) si una actualización reciente falla o rompe un controlador."

pause_step "Presioná [ENTER] para inspeccionar módulos LKM activos en Ring 0..."

# ==============================================================================
# PASO 2: INSPECCIÓN DE MÓDULOS ACTIVOS Y HARDWARE ASOCIADO
# ==============================================================================
step_banner "2" "Inspección de Módulos Cargados (lsmod, modinfo y lspci -k)"

explain "lsmod lista los módulos cargados actualmente en Ring 0, su tamaño en memoria y dependencias:"
run_and_show "lsmod | head -n 15"
run_and_show "echo \"Total módulos activos: $(lsmod | tail -n +2 | wc -l)\" && ls -d /lib/modules/$(uname -r)/kernel/* 2>/dev/null"

explain "Con modinfo inspeccionamos la metadata de un módulo en disco (.ko) sin necesidad de cargarlo:"
run_and_show "modinfo dummy 2>/dev/null | head -n 15 || modinfo loop 2>/dev/null | head -n 15"

if command -v lspci &>/dev/null; then
    explain "lspci -k cruza cada dispositivo PCI físico/virtual con el driver del kernel que lo gobierna:"
    run_and_show "lspci -k | head -n 18"
fi

pie_clase "¿Cuál es la diferencia operativa entre usar insmod y usar modprobe?" \
          "insmod inserta un archivo .ko puntual sin resolver dependencias ni leer /etc/modprobe.d; modprobe resuelve dependencias con modules.dep.bin y aplica reglas de configuración y blacklists."

pause_step "Presioná [ENTER] para auditar todos los módulos en lista negra (blacklist)..."

# ==============================================================================
# PASO 3: LISTAR TODOS LOS MÓDULOS EN BLACKLIST
# ==============================================================================
step_banner "3" "Auditoría Real de Módulos en Lista Negra (Blacklist)"

explain "Las listas negras pueden venir de archivos del administrador (/etc/modprobe.d) o de paquetes de la distro (/usr/lib/modprobe.d):"
run_and_show "ls -la /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null"

explain "Buscamos tanto directivas 'blacklist' como bloqueos duros 'install ... /bin/false':"
run_and_show "grep -rnE '^\s*(blacklist|install)\s+' /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null | head -n 25"

explain "El comando definitivo para ver la verdad efectiva que usará el sistema es 'modprobe --showconfig':"
run_and_show "modprobe --showconfig | grep -E '^(blacklist|install)' | sort -u | head -n 25"

pie_clase "¿Por qué 'grep blacklist /etc/modprobe.d/blacklist.conf' puede dar una visión incompleta?" \
          "Porque las distros reparten archivos *.conf entre /etc/modprobe.d y /usr/lib/modprobe.d, y muchos bloqueos efectivos usan la directiva 'install <mod> /bin/false'."

pause_step "Presioná [ENTER] para practicar carga, descarga y blacklist en vivo con el módulo inocuo 'dummy'..."

# ==============================================================================
# PASO 4: FLUJO DE TROUBLESHOOTING Y BLACKLIST VS INSTALL /BIN/FALSE
# ==============================================================================
step_banner "4" "Flujo de Troubleshooting y Diferencia Real: blacklist vs install /bin/false"

CAN_LOAD_MOD=false
if modinfo dummy &>/dev/null; then
    if modprobe dummy 2>/dev/null; then
        CAN_LOAD_MOD=true
    fi
fi

if [ "$CAN_LOAD_MOD" = true ]; then
    explain "Cargamos el módulo inocuo 'dummy' en Ring 0 y verificamos en lsmod y logs del kernel (dmesg):"
    run_and_show "lsmod | grep '^dummy\b'"
    run_and_show "dmesg | tail -n 5"

    explain "Simulamos que este módulo presenta incompatibilidad: lo descargamos en caliente con modprobe -r:"
    run_and_show "modprobe -r dummy && lsmod | grep '^dummy\b' || echo 'Módulo dummy descargado limpiamente.'"

    explain "Ahora probamos qué pasa cuando escribimos SOLO 'blacklist dummy' en ${DEMO_BLACKLIST_CONF}:"
    cat <<'EOF' > "$DEMO_BLACKLIST_CONF"
# Prueba temporal del Lab 1.7
blacklist dummy
EOF
    run_and_show "cat ${DEMO_BLACKLIST_CONF}"
    run_and_show "modprobe -n -v --use-blacklist dummy"
    explain "¡Observación clave! Si alguien ejecuta 'modprobe dummy' directamente (o como dependencia), 'blacklist' solo NO lo frena:"
    run_and_show "modprobe dummy && lsmod | grep '^dummy\b'"
    modprobe -r dummy 2>/dev/null || true

    explain "Agregamos ahora el bloqueo duro 'install dummy /bin/false' y comprobamos:"
    cat <<'EOF' > "$DEMO_BLACKLIST_CONF"
# Bloqueo estricto del Lab 1.7
blacklist dummy
install dummy /bin/false
EOF
    run_and_show "cat ${DEMO_BLACKLIST_CONF}"
    run_and_show "modprobe -n -v dummy"
    run_and_show "modprobe dummy; echo \"Código de salida al intentar cargar: \$?\""
else
    explain "Entorno sin módulo 'dummy' o sin capacidad CAP_SYS_MODULE (ej. contenedor sin privilegios de kernel)."
    explain "Mostramos igualmente la verificación en seco (dry-run) con /etc/modprobe.d temporal:"
    cat <<'EOF' > "$DEMO_BLACKLIST_CONF"
blacklist dummy
install dummy /bin/false
EOF
    run_and_show "cat ${DEMO_BLACKLIST_CONF}"
    run_and_show "modprobe --showconfig | grep 'dummy'"
fi

pie_clase "¿En qué se diferencia 'blacklist modulo' de 'install modulo /bin/false'?" \
          "'blacklist' solo evita la autocarga por alias de hardware (udev), mientras que 'install modulo /bin/false' bloquea también la carga manual y por dependencias de otros módulos."

pause_step "Presioná [ENTER] para practicar el bloqueo seguro de almacenamiento USB..."

# ==============================================================================
# PASO 5: CASO PRÁCTICO — BLOQUEO SEGURO DE MÓDULOS USB Y HARDENING CIS
# ==============================================================================
step_banner "5" "Caso Práctico: Bloqueo Seguro de Almacenamiento USB (Sin Romper Teclado)"

explain "Generamos la plantilla segura en ${DIR_LAB}/99-usb-storage-hardening.conf.example (sin bloquear el USB del host en vivo):"
cat <<'EOF' > "${DIR_LAB}/99-usb-storage-hardening.conf.example"
# /etc/modprobe.d/99-usb-storage-hardening.conf
# Bloquea dispositivos de almacenamiento masivo USB al arranque y en caliente.
# IMPORTANTE: NO incluir 'usbhid' ni 'xhci_hcd' si usás teclado/ratón USB.
blacklist usb-storage
install usb-storage /bin/false

blacklist uas
install uas /bin/false
EOF
run_and_show "cat ${DIR_LAB}/99-usb-storage-hardening.conf.example"

explain "Auditamos qué módulos USB están cargados hoy en el sistema para distinguir almacenamiento (usb-storage/uas) de HID (usbhid):"
run_and_show "lsmod | grep -iE 'usb|uas|hid|xhci|ehci' | head -n 15 || true"

explain "Recordatorio de producción: si el módulo se carga antes de montar '/', hay que actualizar initramfs:"
run_and_show "echo 'Debian/Ubuntu : sudo update-initramfs -u -k all' && echo 'RHEL/Fedora   : sudo dracut -f --regenerate-all' && echo 'Dependencias  : sudo depmod -a'"

pie_clase "Si te piden bloquear almacenamiento USB en un servidor físico con teclado USB, ¿qué módulo NUNCA debés agregar a la blacklist?" \
          "Nunca debés bloquear 'usbhid' (ni los controladores raíz 'xhci_hcd'/'usbcore'); solo debés bloquear 'usb-storage' y 'uas' (y actualizar initramfs)."

echo -e "\n${C_BOLD}${C_GREEN}✔ Lab 1.7 completado con éxito.${C_RESET}"
