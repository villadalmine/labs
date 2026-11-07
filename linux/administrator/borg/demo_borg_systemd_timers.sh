#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: BorgBackup Automatizado con Systemd Timers
# Guías: linux/administrator/borg/borg-con-systemd-timers.md
#        linux/administrator/backup/borg-con-systemd-timers.md
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Protección de BORG_PASSPHRASE en /etc/borg/credenciales_demo con chmod 600.
#  - Demostración de por qué las credenciales con permisos abiertos (644) exponen
#    el repositorio y cómo EnvironmentFile las inyecta sin exponerlas en 'ps aux'.
#  - Creación de script automatizado (borg create + borg prune).
#  - Despliegue real de borg-demo-backup.service (Type=oneshot) y .timer.
#  - Ejecución en vivo con systemctl start y auditoría en journalctl.
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   sudo ./demo_borg_systemd_timers.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_borg_systemd_timers.sh --auto 2 -> Modo desatendido (espera 2s)
#   sudo ./demo_borg_systemd_timers.sh --keep   -> Preserva las unidades para inspección
#   sudo ./demo_borg_systemd_timers.sh --clean  -> Limpia unidades y repositorios de prueba
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este script requiere privilegios de superusuario (sudo) para registrar unidades en /etc/systemd/system.\033[0m"
    echo "Ejecutá: sudo $0 $*"
    exit 1
fi

AUTO_MODE=false
AUTO_WAIT=0
KEEP_FILES=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            AUTO_WAIT="${2:-2}"
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
            echo "Uso: sudo ./demo_borg_systemd_timers.sh [--auto <segundos>] [--keep] [--clean|--limpiar]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

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

WORK_DIR="/tmp/demo_borg_timers_$$"
ORIGEN_DIR="${WORK_DIR}/datos_produccion"
REPO_DIR="${WORK_DIR}/repo_borg"
CRED_DIR="/etc/borg_demo_$$"
CRED_FILE="${CRED_DIR}/credenciales"
BACKUP_SCRIPT="/usr/local/bin/borg-backup-diario-demo.sh"
SERVICE_UNIT="/etc/systemd/system/borg-demo-backup.service"
TIMER_UNIT="/etc/systemd/system/borg-demo-backup.timer"

cleanup() {
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "\n${C_GREEN}[INFO] Unidades y repositorio preservados (--keep):${C_RESET}"
        echo -e "  • Repositorio : ${REPO_DIR}"
        echo -e "  • Credenciales: ${CRED_FILE}"
        echo -e "  • Unidades    : ${SERVICE_UNIT} / ${TIMER_UNIT}"
        echo -e "Para limpiar luego ejecutá: sudo ./demo_borg_systemd_timers.sh --clean\n"
        return
    fi
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo timer y eliminando unidades y repositorios temporales...${C_RESET}"
    systemctl stop borg-demo-backup.timer borg-demo-backup.service 2>/dev/null || true
    systemctl disable borg-demo-backup.timer 2>/dev/null || true
    rm -f "$SERVICE_UNIT" "$TIMER_UNIT" "$BACKUP_SCRIPT" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    rm -rf "$WORK_DIR" "$CRED_DIR" /tmp/demo_borg_timers_* /etc/borg_demo_* 2>/dev/null || true
    echo -e "${C_GREEN}✔ Unidades Systemd y repositorio temporal de Borg eliminados correctamente.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi
trap cleanup EXIT INT TERM

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${C_YELLOW}⏳ [MODO AUTO] Esperando ${AUTO_WAIT}s: ${msg}${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
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
            sleep "$AUTO_WAIT"
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

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🛡️  DEMO EN VIVO: BACKUP AUTOMATIZADO CON BORGBACKUP + SYSTEMD TIMERS          ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "EnvironmentFile (chmod 600) ➔ Script Borg + Prune ➔ .service/.timer ➔ journalctl\n"

# ==============================================================================
# PASO 1: PROTEGER LA CONTRASEÑA CON ENVIRONMENTFILE Y PERMISOS 600
# ==============================================================================
step_banner "1" "Fase 1: Protección de BORG_PASSPHRASE y Permisos Estrictos (chmod 600)"

if ! command -v borg &>/dev/null; then
    echo -e "${C_YELLOW}Instalando borgbackup...${C_RESET}"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq borgbackup
    elif command -v dnf &>/dev/null; then
        dnf install -y -q borgbackup
    fi
fi

explain "Nunca debemos escribir BORG_PASSPHRASE dentro de un script ni en un crontab."
explain "Creamos un archivo de credenciales dedicado y verificamos qué pasa si queda con permisos abiertos (644) vs cerrados (600):"

run_and_show "mkdir -p ${CRED_DIR} ${ORIGEN_DIR} ${REPO_DIR} && echo 'BORG_PASSPHRASE=SuperSecretoBorgSystemd2026!' > ${CRED_FILE}"
run_and_show "chmod 644 ${CRED_FILE} && ls -l ${CRED_FILE}"
echo -e "${C_RED}✖ RIESGO DE SEGURIDAD:${C_RESET} Con permisos 644 (-rw-r--r--), cualquier usuario local puede hacer 'cat ${CRED_FILE}' y robar la llave del backup."

explain "Blindamos el archivo con chown root:root y chmod 600 (solo root puede leerlo):"
run_and_show "chown root:root ${CRED_FILE} && chmod 600 ${CRED_FILE} && ls -l ${CRED_FILE}"

explain "Inicializamos el repositorio cifrado de Borg leyendo la credencial de forma segura:"
run_and_show "set -a && source ${CRED_FILE} && set +a && borg init --encryption=repokey ${REPO_DIR} && ls -la ${REPO_DIR}"

pie_clase "¿Por qué usamos 'EnvironmentFile=' en la unidad Systemd en lugar de pasar la contraseña como argumento en la línea de comandos?" \
          "Porque cualquier argumento en la línea de comandos es visible para todos los usuarios del servidor ejecutando 'ps aux' o leyendo /proc/<PID>/cmdline. EnvironmentFile inyecta la variable directamente en el entorno privado del proceso."

pause_step "Presioná [ENTER] para crear el script automatizado de backup y rotación (prune)..."

# ==============================================================================
# PASO 2: CREAR DATOS DE PRUEBA Y EL SCRIPT DE BACKUP + PRUNE
# ==============================================================================
step_banner "2" "Fase 2: Script de Backup Automatizado (borg create + borg prune)"

explain "Creamos archivos de producción simulados en ${ORIGEN_DIR}:"
run_and_show "echo 'Base de datos de clientes activa' > ${ORIGEN_DIR}/clientes.sql && echo 'Configuracion crítica Nginx' > ${ORIGEN_DIR}/nginx.conf && ls -lh ${ORIGEN_DIR}"

explain "Creamos el script ejecutable ${BACKUP_SCRIPT} (observá que NO contiene ninguna contraseña en su código):"
cat << EOF > "$BACKUP_SCRIPT"
#!/usr/bin/env bash
set -euo pipefail

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
REPO="${REPO_DIR}"

echo "[BORG-SYSTEMD] Iniciando backup hacia \$REPO..."
borg create --stats "\$REPO::backup-{now:%Y-%m-%d_%H:%M:%S}" "${ORIGEN_DIR}"

echo "[BORG-SYSTEMD] Aplicando política de retención GFS (borg prune)..."
borg prune -v --list --keep-daily=7 --keep-weekly=4 --keep-monthly=6 "\$REPO"
echo "[BORG-SYSTEMD] Operación completada con éxito."
EOF

run_and_show "chmod +x ${BACKUP_SCRIPT} && cat ${BACKUP_SCRIPT}"

pause_step "Presioná [ENTER] para crear y activar las unidades .service y .timer en Systemd..."

# ==============================================================================
# PASO 3: CREACIÓN DE LAS UNIDADES .SERVICE Y .TIMER EN SYSTEMD
# ==============================================================================
step_banner "3" "Fase 3: Unidades borg-demo-backup.service y borg-demo-backup.timer"

explain "Creamos la unidad de servicio (${SERVICE_UNIT}) con Type=oneshot, EnvironmentFile y prioridad de I/O idle:"
cat << EOF > "$SERVICE_UNIT"
[Unit]
Description=Backup diario automatizado con BorgBackup (Demo)
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=${CRED_FILE}
ExecStart=${BACKUP_SCRIPT}
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
EOF

run_and_show "cat ${SERVICE_UNIT}"

explain "Creamos la unidad temporizadora (${TIMER_UNIT}) con OnCalendar y Persistent=true:"
cat << EOF > "$TIMER_UNIT"
[Unit]
Description=Temporizador para el backup diario con BorgBackup (Demo)

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=borg-demo-backup.service

[Install]
WantedBy=timers.target
EOF

run_and_show "cat ${TIMER_UNIT}"

pie_clase "¿Para qué sirven las directivas 'IOSchedulingClass=idle' y 'CPUSchedulingPolicy=idle' en el archivo .service?" \
          "Aseguran que el proceso de cifrado y compresión de Borg solo utilice disco y CPU cuando ningún otro servicio crítico de producción (como la base de datos o el servidor web) los necesite."

pause_step "Presioná [ENTER] para recargar Systemd, disparar el servicio y auditar journalctl..."

# ==============================================================================
# PASO 4: ACTIVACIÓN DEL TIMER, DISPARO EN VIVO Y AUDITORÍA EN JOURNALCTL
# ==============================================================================
step_banner "4" "Fase 4: Activación del Timer, Ejecución Manual y Auditoría en journalctl"

explain "Recargamos el demonio de Systemd y habilitamos el temporizador:"
run_and_show "systemctl daemon-reload && systemctl enable --now borg-demo-backup.timer"
run_and_show "systemctl list-timers --all | grep -E 'NEXT|borg-demo-backup'"

explain "Disparamos una ejecución inmediata del servicio para verificar todo el flujo en vivo:"
run_and_show "systemctl start borg-demo-backup.service"

explain "Auditamos los logs estructurados capturados por journalctl:"
run_and_show "journalctl -u borg-demo-backup.service -n 25 --no-pager"

explain "Verificamos directamente en el repositorio de Borg que el snapshot fue creado y cifrado:"
run_and_show "set -a && source ${CRED_FILE} && set +a && borg list ${REPO_DIR}"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE BORGBACKUP + SYSTEMD TIMERS COMPLETADA CON ÉXITO!         ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
