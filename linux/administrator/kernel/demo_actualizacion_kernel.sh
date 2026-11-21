#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Plan de Actualización Continua del Kernel en 8 Pasos
# Laboratorio: linux/administrator/kernel/actualizacion_kernel_rollback_livepatch.md (Lab 2.7)
#
# Plan profesional de actualización continua del Kernel Linux en 8 pasos:
#  - Audita kernel activo vs kernels instalados en disco y espacio en /boot.
#  - Genera un respaldo pre-update completo (configs kernel, sysctl, modprobe, cmdline).
#  - Revisa compatibilidad DKMS, módulos externos y soporte de Livepatch (/sys/kernel/livepatch).
#  - Inspecciona estrategia de Rollback (GRUB2/BLS vs OSTree/bootc).
#  - Ejecuta un Smoke-Test real post-update (dmesg, systemd, kernel, red).
#  - Genera plantillas de automatización segura (unattended-upgrades, dnf-automatic, systemd timer).
#  - 100% seguro: NO reinicia el equipo ni instala/desinstala paquetes reales.
#
# Uso:
#   sudo ./demo_actualizacion_kernel.sh [--auto <segundos>] [--keep] [--clean] [--help]
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
            echo "Uso: sudo ./demo_actualizacion_kernel.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

DIR_LAB="/tmp/lab_demo_kernel_update"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Limpiando espacio de trabajo del Lab 2.7...${C_RESET}"
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan respaldos y plantillas en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_actualizacion_kernel.sh\n"
    else
        rm -rf "$DIR_LAB" 2>/dev/null || true
        echo -e "${C_GREEN}✔ Directorio temporal eliminado correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para auditar /boot, dmesg y logs del kernel.${C_RESET}"
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

mkdir -p "${DIR_LAB}/pre_update_backup" "${DIR_LAB}/automation_examples"

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🔄 DEMOSTRACIÓN EN VIVO: ACTUALIZACIÓN SEGURA DE KERNEL, ROLLBACK & LIVEPATCH ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Runbook de 8 pasos: inventario, pre-backup, DKMS, rollback, smoke-test y timers\n"

# ==============================================================================
# PASO 1: INVENTARIO DE KERNEL ACTIVO VS INSTALADOS Y ESPACIO EN /boot
# ==============================================================================
step_banner "1" "Paso 1 y 3 del Runbook: Inventario Activo vs Paquetes y Espacio en /boot"

explain "Identificamos la distribución, el kernel activo en RAM y los paquetes de kernel instalados en disco:"
run_and_show "grep -E '^(PRETTY_NAME|ID)=' /etc/os-release && uname -r"
run_and_show "df -h /boot / 2>/dev/null | uniq"

if command -v dpkg-query &>/dev/null; then
    run_and_show "dpkg-query -W -f='\${Status}\t\${Package}\t\${Version}\n' 'linux-image-*' 2>/dev/null | grep '^install ok installed' || echo 'Sin paquetes linux-image-* en este rootfs'"
elif command -v rpm &>/dev/null; then
    run_and_show "rpm -q kernel kernel-core kernel-modules 2>/dev/null | head -n 12 || true"
fi

if [ -f /var/run/reboot-required ]; then
    run_and_show "cat /var/run/reboot-required && cat /var/run/reboot-required.pkgs 2>/dev/null || true"
else
    explain "Comprobamos si existe la bandera /var/run/reboot-required (Debian/Ubuntu) indicando reinicio pendiente:"
    run_and_show "echo 'No existe /var/run/reboot-required (o no es familia Debian/Ubuntu)'"
fi

pie_clase "¿Por qué conviene revisar 'df -h /boot' antes de actualizar el kernel?" \
          "Porque /boot suele ser una partición pequeña (500 MB–1 GB); si se llena mientras se genera un nuevo initramfs, la actualización queda truncada y el sistema puede fallar al reiniciar."

pause_step "Presioná [ENTER] para generar el paquete de respaldo pre-update..."

# ==============================================================================
# PASO 2: BACKUP PRE-UPDATE DE CONFIGURACIÓN Y ESTADO DEL KERNEL
# ==============================================================================
step_banner "2" "Paso 2 del Runbook: Respaldo Forense Pre-Actualización"

explain "Antes de actualizar, capturamos la foto exacta de parámetros, módulos, cmdline y reglas en ${DIR_LAB}/pre_update_backup:"
uname -a > "${DIR_LAB}/pre_update_backup/uname.txt"
cat /proc/cmdline > "${DIR_LAB}/pre_update_backup/cmdline.txt"
lsmod > "${DIR_LAB}/pre_update_backup/lsmod.txt"
sysctl -a 2>/dev/null > "${DIR_LAB}/pre_update_backup/sysctl_all.txt" || true
ls -la /boot > "${DIR_LAB}/pre_update_backup/boot_listing.txt" 2>/dev/null || true
cp -r /etc/modprobe.d "${DIR_LAB}/pre_update_backup/" 2>/dev/null || true
cp -r /etc/sysctl.d "${DIR_LAB}/pre_update_backup/" 2>/dev/null || true

run_and_show "ls -lh ${DIR_LAB}/pre_update_backup/"
run_and_show "cat ${DIR_LAB}/pre_update_backup/cmdline.txt"

pie_clase "¿Qué archivos deberías respaldar o snapshotear antes de aplicar una actualización de kernel en producción?" \
          "Snapshot del volumen raíz/boot (LVM/Btrfs/EBS), copia de /etc/modprobe.d, /etc/sysctl.d, configuración de GRUB y el estado previo (uname, lsmod, sysctl -a)."

pause_step "Presioná [ENTER] para auditar compatibilidad DKMS y soporte de Livepatching..."

# ==============================================================================
# PASO 3: DKMS, TAINT Y LIVEPATCHING (/sys/kernel/livepatch)
# ==============================================================================
step_banner "3" "Paso 3 y 6 del Runbook: DKMS, Taint y Livepatching en Caliente"

explain "Verificamos si existen módulos out-of-tree compilados por DKMS que dependan de linux-headers:"
if command -v dkms &>/dev/null; then
    run_and_show "dkms status"
else
    run_and_show "echo 'dkms no está instalado (no hay módulos externos DKMS activos o se usan kmods nativos)'"
fi

explain "Consultamos el estado de taint (/proc/sys/kernel/tainted) y parches en vivo en /sys/kernel/livepatch:"
run_and_show "cat /proc/sys/kernel/tainted && ls -la /sys/kernel/livepatch/ 2>/dev/null || echo 'Directorio /sys/kernel/livepatch vacío o sin livepatches cargados'"

pie_clase "¿Un Livepatch (kpatch / Canonical Livepatch) reemplaza por completo el reinicio de cambio de versión mayor de kernel?" \
          "No; el Livepatch aplica parches binarios críticos de CVE en RAM en vivo para evitar downtime inmediato, pero las nuevas funcionalidades o cambios de ABI siguen requiriendo reinicio (o kexec) en ventana planificada."

pause_step "Presioná [ENTER] para inspeccionar mecanismos de Rollback (GRUB2/BLS vs OSTree)..."

# ==============================================================================
# PASO 4: ROLLBACK EN DISTROS CLÁSICAS VS INMUTABLES
# ==============================================================================
step_banner "4" "Paso 4 del Runbook: Retención de Kernels y Mecanismos de Rollback"

explain "Inspeccionamos la configuración de retención de kernels y entradas de arranque disponibles:"
run_and_show "grep -H 'installonly_limit' /etc/dnf/dnf.conf 2>/dev/null || grep -H 'GRUB_DEFAULT' /etc/default/grub 2>/dev/null || echo 'Configuración GRUB/DNF estándar no presente en este entorno mínimo'"

if command -v rpm-ostree &>/dev/null && [ -d /ostree ]; then
    explain "Detectado sistema inmutable OSTree: mostramos los despliegues atómicos A/B listos para rollback:"
    run_and_show "rpm-ostree status 2>/dev/null | head -n 20"
else
    run_and_show "ls -la /boot/loader/entries/ 2>/dev/null || ls -la /boot/grub*/grub.cfg 2>/dev/null || echo 'Entorno sin bootloader directo en /boot'"
fi

pie_clase "¿Qué ventaja aporta un sistema inmutable OSTree/bootc frente a apt/dnf ante un corte de energía durante un update de kernel?" \
          "Que el nuevo despliegue y su kernel se preparan en un árbol paralelo inmutable sin tocar el sistema en ejecución; si falla antes de terminar, el sistema sigue arrancando intacto."

pause_step "Presioná [ENTER] para ejecutar el Smoke-Test post-update y ver plantillas de automatización..."

# ==============================================================================
# PASO 5: SMOKE-TEST POST-REBOOT Y AUTOMATIZACIÓN SEGURA (PASOS 7 Y 8)
# ==============================================================================
step_banner "5" "Pasos 7 y 8 del Runbook: Smoke-Test Automatizado y Timers Seguros"

cat <<'EOF' > "${DIR_LAB}/post_reboot_smoke_test.sh"
#!/usr/bin/env bash
set -uo pipefail
echo "=== [1] Kernel activo ==="
uname -r
echo "=== [2] Errores críticos en ring buffer (dmesg) ==="
ERR_CNT=$(dmesg -l err,crit,alert,emerg 2>/dev/null | wc -l || echo 0)
echo "Líneas err/crit/alert/emerg: ${ERR_CNT}"
echo "=== [3] Unidades systemd fallidas ==="
if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    systemctl --failed --no-pager || true
else
    echo "Systemd no es PID 1 en este entorno (contenedor/sandbox)."
fi
echo "=== [4] Salud de red loopback ==="
ip -br addr show lo 2>/dev/null || echo "iproute2 no disponible"
echo "=== SMOKE-TEST FINALIZADO ==="
EOF
chmod +x "${DIR_LAB}/post_reboot_smoke_test.sh"

explain "Ejecutamos el script automatizado de verificación post-reinicio:"
run_and_show "${DIR_LAB}/post_reboot_smoke_test.sh"

explain "Generamos ejemplos reales de automatización moderna (Systemd Timer + unattended-upgrades) en ${DIR_LAB}/automation_examples/:"
cat <<'EOF' > "${DIR_LAB}/automation_examples/kernel-security-check.timer"
[Unit]
Description=Auditoría semanal de parches de seguridad de kernel pendientes

[Timer]
OnCalendar=Mon *-*-* 03:00:00
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat <<'EOF' > "${DIR_LAB}/automation_examples/50unattended-upgrades.snippet"
// Recomendación SRE en Debian/Ubuntu: instalar seguridad automáticamente,
// pero NO reiniciar nodos críticos de producción sin drenar tráfico primero.
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
EOF

run_and_show "ls -la ${DIR_LAB}/automation_examples/ && cat ${DIR_LAB}/automation_examples/kernel-security-check.timer"

pie_clase "¿Por qué se desaconseja activar el reinicio automático ciego (Automatic-Reboot true) en servidores críticos de producción?" \
          "Porque reiniciar todos los nodos a la vez o sin drenar conexiones activas/bases de datos causa indisponibilidad total; el reinicio debe coordinarse en ventanas o mediante rolling-reboots."

echo -e "\n${C_BOLD}${C_GREEN}✔ Lab 2.7 completado con éxito.${C_RESET}"
