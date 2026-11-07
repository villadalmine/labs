#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Planificación Clásica con Cron y Crontab en Linux
# Laboratorio: linux/administrator/automatizacion/cron_crontab_planificacion.md
#
# Basado en el temario oficial de Automatización y Planificación en Linux (Clase 8)
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema en una caja formateada.
#  - Analiza /etc/crontab (SHELL, PATH, MAILTO) y los 5 campos de tiempo.
#  - Demuestra todos los patrones: exactos, pasos (/), rangos (-), listas (,) y macros (@).
#  - Reproduce el fallo real de PATH restringido en cron y su remediación.
#  - Limpieza garantizada al finalizar (trap cleanup) restaurando cualquier crontab previo.
#
# Uso:
#   sudo ./demo_cron_crontab.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               Preserva los archivos de prueba en /tmp/lab_demo_cron
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
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para inspeccionar servicios y /etc/cron.d.${C_RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false
CLEAN_ONLY=false

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
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Uso: sudo ./demo_cron_crontab.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
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

DIR_LAB="/tmp/lab_demo_cron"
BACKUP_CRON="${DIR_LAB}/root_crontab.bak"
HAD_CRONTAB=false
mkdir -p "${DIR_LAB}/bin" "${DIR_LAB}/custom_bin" "${DIR_LAB}/logs"

if command -v crontab &>/dev/null && crontab -l > "$BACKUP_CRON" 2>/dev/null; then
    HAD_CRONTAB=true
fi

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Restaurando estado original de cron...${C_RESET}"
    rm -f /etc/cron.d/lab_demo_automatizacion 2>/dev/null || true
    if command -v crontab &>/dev/null; then
        if [ "$HAD_CRONTAB" = true ] && [ -f "$BACKUP_CRON" ]; then
            crontab "$BACKUP_CRON" 2>/dev/null || true
        else
            crontab -r 2>/dev/null || true
        fi
    fi
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los archivos de laboratorio en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./demo_cron_crontab.sh --clean\n"
    else
        rm -rf "$DIR_LAB" /tmp/lab_cron
        echo -e "${C_GREEN}✔ Archivos temporales limpiados correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}
if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi
trap cleanup EXIT INT TERM

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ⏰ DEMOSTRACIÓN EN VIVO: PLANIFICACIÓN CLÁSICA CON CRON Y CRONTAB             ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Anatomía de /etc/crontab, los 5 campos, operadores (/, -, ,), macros (@) y PATH\n"

# ==============================================================================
# PASO 1: VERIFICACIÓN DEL SERVICIO CORE CRON
# ==============================================================================
step_banner "1" "Verificación del Demonio Core: cron / crond"

explain "Comprobamos la presencia del binario crontab y el servicio del sistema (cron en Debian/Ubuntu, crond en RHEL/Rocky/Fedora):"
if ! command -v crontab &>/dev/null; then
    echo -e "${C_YELLOW}Instalando paquete cron/cronie si hay repositorio disponible...${C_RESET}"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq cron 2>/dev/null || true
    elif command -v dnf &>/dev/null; then
        dnf install -y -q cronie 2>/dev/null || true
    fi
fi

if systemctl list-unit-files 2>/dev/null | grep -q "cron\.service"; then
    systemctl start cron.service 2>/dev/null || true
    run_and_show "systemctl status cron.service --no-pager | head -n 12"
elif systemctl list-unit-files 2>/dev/null | grep -q "crond\.service"; then
    systemctl start crond.service 2>/dev/null || true
    run_and_show "systemctl status crond.service --no-pager | head -n 12"
else
    explain "En este contenedor/entorno ligero inspeccionamos o simulamos la estructura estándar de Vixie Cron / Cronie:"
    mkdir -p /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly
fi

pie_clase "¿Cada cuánto tiempo despierta el demonio cron para verificar si hay tareas pendientes?" \
          "Despierta exactamente una vez por minuto (cada 60 segundos) para evaluar las tablas en memoria."

pause_step "Presioná [ENTER] para inspeccionar el motor de configuración global /etc/crontab..."

# ==============================================================================
# PASO 2: EL MOTOR DE CONFIGURACIÓN GLOBAL (/etc/crontab)
# ==============================================================================
step_banner "2" "El Motor de Configuración Global: /etc/crontab y Variables de Entorno"

if [ ! -f /etc/crontab ]; then
    cat << 'EOF' > /etc/crontab
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name  command to be executed
EOF
fi

explain "Inspeccionamos /etc/crontab y los directorios modulares de cron en /etc:"
run_and_show "cat /etc/crontab"
run_and_show "ls -ld /etc/cron*"

pie_clase "¿Para qué sirven las tres variables SHELL, PATH y MAILTO en /etc/crontab?" \
          "SHELL define el intérprete (ej. /bin/bash), PATH define las rutas donde buscar comandos ejecutables, y MAILTO define el usuario local que recibirá por correo el stdout/stderr de las tareas."

pause_step "Presioná [ENTER] para analizar la anatomía de los 5 campos y los operadores..."

# ==============================================================================
# PASO 3: ANATOMÍA DE LOS 5 CAMPOS, OPERADORES (/, -, ,) Y MACROS (@)
# ==============================================================================
step_banner "3" "Patrones de Ejecución: Frecuencias Regulares, Fechas, Listas y Macros (@)"

explain "Creamos un script de respaldo simulado y configuramos todos los patrones del temario oficial:"
cat << 'EOF' > "${DIR_LAB}/bin/backup_simulado.sh"
#!/usr/bin/env bash
MODO="${1:-estandar}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ejecución exitosa de backup_simulado.sh (Modo: ${MODO})" >> /tmp/lab_demo_cron/logs/cron_ejecuciones.log
EOF
chmod +x "${DIR_LAB}/bin/backup_simulado.sh"

cat << 'EOF' > "${DIR_LAB}/tabla_crontab_ejemplo.cron"
# =========================================================================
# TABLA DEMOSTRATIVA DE PATRONES CRONTAB (SLIDES 5, 7, 8 y 9 DEL TEMARIO)
# =========================================================================
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=""

# 1. Ejecución cada minuto (para validación en vivo durante el laboratorio)
* * * * * /tmp/lab_demo_cron/bin/backup_simulado.sh cada_minuto

# 2. Diariamente a una hora exacta (04:00 AM)
0 4 * * * /tmp/lab_demo_cron/bin/backup_simulado.sh diario_4am

# 3. Intervalos divisibles con operador barra (/) -> Cada 5 minutos y cada 5 horas
*/5 * * * * /tmp/lab_demo_cron/bin/backup_simulado.sh cada_5_min
0 */5 * * * /tmp/lab_demo_cron/bin/backup_simulado.sh cada_5_horas

# 4. Rangos continuos con operador guion (-) -> Minuto 0 de 09:00 a 18:00
0 9-18 * * * /tmp/lab_demo_cron/bin/backup_simulado.sh rango_9_a_18

# 5. Día específico del mes (Día 1 a las 05:00 AM) y Día de la semana (Viernes)
0 5 1 * * /tmp/lab_demo_cron/bin/backup_simulado.sh dia_1_mes
0 0 * * Fri /tmp/lab_demo_cron/bin/backup_simulado.sh viernes_medianoche

# 6. Listas discontinuas con operador coma (,) -> Solo en Mayo (5) y Octubre (10)
0 0 * 5,10 * /tmp/lab_demo_cron/bin/backup_simulado.sh mayo_y_octubre

# 7. Macros y Atajos de Tiempo (@yearly, @monthly, @daily, @hourly, @reboot)
@yearly /tmp/lab_demo_cron/bin/backup_simulado.sh mantenimiento_anual
@reboot /tmp/lab_demo_cron/bin/backup_simulado.sh borra_temporales_arranque
EOF

run_and_show "cat ${DIR_LAB}/tabla_crontab_ejemplo.cron"

pie_clase "¿Por qué para ejecutar una tarea cada 5 meses usamos '0 0 * 5,10 *' con coma en lugar de '*/5'?" \
          "Porque el año tiene 12 meses (no divisible exactamente por 5 sin salto desigual entre Octubre y Enero). Listar los meses explícitos separados por coma (5,10) garantiza precisión absoluta."

pause_step "Presioná [ENTER] para gestionar la cola del usuario con crontab (-l, -e, -r)..."

# ==============================================================================
# PASO 4: GESTIÓN DE USUARIOS INDEPENDIENTES (crontab -l, -e, -r)
# ==============================================================================
step_banner "4" "Gestión de Crontab por Usuario y Advertencia Operativa (-e vs -r)"

if command -v crontab &>/dev/null; then
    explain "Cargamos la tabla en el crontab activo y la listamos con 'crontab -l':"
    run_and_show "crontab ${DIR_LAB}/tabla_crontab_ejemplo.cron && crontab -l"
else
    explain "Instalamos la tabla en /etc/cron.d/lab_demo_automatizacion para su inspección:"
    sed 's|^\(\*\|0\|\*/5\|@yearly\|@reboot\)\([^/]*\)\(/tmp/.*\)|\1\2 root \3|' "${DIR_LAB}/tabla_crontab_ejemplo.cron" > /etc/cron.d/lab_demo_automatizacion
    run_and_show "cat /etc/cron.d/lab_demo_automatizacion"
fi

pie_clase "¿Por qué la opción 'crontab -r' es peligrosa en el teclado estándar al querer escribir 'crontab -e'?" \
          "Porque la tecla R está pegada a la tecla E en el teclado QWERTY, y 'crontab -r' borra inmediatamente todas las tareas programadas sin pedir confirmación (salvo que se use 'crontab -i -r')."

pause_step "Presioná [ENTER] para demostrar el problema real del PATH en scripts de Cron..."

# ==============================================================================
# PASO 5: TROUBLESHOOTING EN VIVO: EL FALLO CLÁSICO DE PATH EN CRON
# ==============================================================================
step_banner "5" "Troubleshooting de Producción: Por qué los scripts fallan en Cron por el PATH"

explain "Creamos una herramienta personalizada en ${DIR_LAB}/custom_bin/auditor_secreto:"
cat << 'EOF' > "${DIR_LAB}/custom_bin/auditor_secreto"
#!/usr/bin/env bash
echo "✅ Binario auditor_secreto ejecutado correctamente desde $(command -v auditor_secreto)"
EOF
chmod +x "${DIR_LAB}/custom_bin/auditor_secreto"

explain "1. Simulamos la ejecución con el entorno minimalista predeterminado de Cron (PATH=/usr/bin:/bin):"
run_and_show "env -i SHELL=/bin/sh PATH=/usr/bin:/bin auditor_secreto"

explain "2. Ahora definimos explícitamente el PATH enriquecido (como se debe hacer en el crontab o cabecera del script):"
run_and_show "env -i SHELL=/bin/bash PATH=${DIR_LAB}/custom_bin:/usr/local/bin:/usr/bin:/bin auditor_secreto"

explain "3. Ejecutamos nuestro script de backup simulado y verificamos el registro de auditoría en logs:"
"${DIR_LAB}/bin/backup_simulado.sh" "prueba_en_vivo"
run_and_show "cat ${DIR_LAB}/logs/cron_ejecuciones.log"

pie_clase "Si un script funciona perfecto cuando lo ejecutás manualmente por SSH pero no hace nada en cron, ¿cuál es el primer factor a revisar?" \
          "Las variables de entorno (especialmente PATH, que en cron es minimalista y no lee ~/.bashrc), las rutas relativas de archivos y los permisos de ejecución (chmod +x)."

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ✔ LABORATORIO DE CRON Y CRONTAB COMPLETADO CON ÉXITO                          ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado /etc/crontab, los 5 campos, operadores (/, -, ,), macros (@) y el manejo de PATH.\n"
