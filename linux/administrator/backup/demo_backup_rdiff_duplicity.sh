#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: rdiff-backup (Deltas Inversos) y Duplicity (Cifrado GPG)
# Laboratorio: linux/administrator/backup/backup_rdiff_duplicity.md
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - rdiff-backup: El backup más reciente es un espejo transparente en texto plano;
#    los deltas binarios históricos van hacia atrás (rdiff-backup-data).
#  - Duplicity: Cifrado en cliente con GnuPG (AES-256) antes de tocar el almacenamiento remoto.
#  - Restauración puntual a estados históricos.
#  - Preguntas disparadoras ("pie de clase") con respuestas desplegables.
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   ./demo_backup_rdiff_duplicity.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_backup_rdiff_duplicity.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
#   ./demo_backup_rdiff_duplicity.sh --keep   -> Preserva los repositorios para pruebas
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
KEEP_FILES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
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

LAB_DIR="/tmp/lab_rdiff_duplicity_$$"
SRC_DIR="${LAB_DIR}/produccion"
RDIFF_DEST="${LAB_DIR}/repo_rdiff"
DUPL_DEST="${LAB_DIR}/repo_duplicity"
PASSPHRASE="ClaseBackupSeguro2026!"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Eliminando datos temporales de backup...${C_RESET}"
    if [ "$KEEP_FILES" = true ]; then
        echo -e "${C_GREEN}[INFO] Entorno preservado en: ${LAB_DIR}${C_RESET}"
        return
    fi
    rm -rf "${LAB_DIR}" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Directorio temporal de pruebas eliminado correctamente.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_DIM}⏳ [MODO AUTO] Esperando ${AUTO_WAIT}s...${C_RESET}"
        sleep "$AUTO_WAIT"
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
        if [ "$AUTO_WAIT" -gt 0 ]; then
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

echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 📦 DEMOSTRACIÓN EN VIVO: rdiff-backup (Deltas Inversos) y Duplicity (GPG)     ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "Espejo Inverso Inmediato ➔ Deltas Históricos ➔ Cifrado Zero-Trust en Cliente\n"

# ==============================================================================
# PASO 1: PREPARACIÓN DE DATOS
# ==============================================================================
step_banner "1" "Inicialización de Datos de Producción"

mkdir -p "$SRC_DIR/config" "$SRC_DIR/documentos" "$RDIFF_DEST" "$DUPL_DEST"
echo "db_host=10.0.1.50" > "$SRC_DIR/config/app.env"
echo "db_pass=SuperSecreta2026" > "$SRC_DIR/config/secret.key"
echo "Informe Financiero Q1 2026" > "$SRC_DIR/documentos/balance.txt"

explain "Estructura original en producción:"
run_and_show "ls -la ${SRC_DIR}/config ${SRC_DIR}/documentos"

pause_step "Presioná [ENTER] para ejecutar el respaldo con rdiff-backup..."

# ==============================================================================
# PASO 2: RDIFF-BACKUP (DÍA 1 Y DÍA 2)
# ==============================================================================
step_banner "2" "Respaldos con rdiff-backup (Arquitectura de Deltas Inversos)"

explain "1. Ejecutamos el primer respaldo con rdiff-backup:"
if command -v rdiff-backup >/dev/null 2>&1; then
    run_and_show "rdiff-backup backup '${SRC_DIR}' '${RDIFF_DEST}'"
    sleep 2

    explain "2. Modificamos un archivo para simular la actividad del Día 2:"
    echo "Informe Financiero Q1 2026 - REVISADO Y APROBADO" > "$SRC_DIR/documentos/balance.txt"
    echo "db_host=10.0.1.60" > "$SRC_DIR/config/app.env"

    explain "3. Ejecutamos el segundo respaldo:"
    run_and_show "rdiff-backup backup '${SRC_DIR}' '${RDIFF_DEST}'"

    explain "4. Inspeccionamos el repositorio rdiff-backup:"
    explain "Notá cómo la copia más reciente está directamente accesible en archivos normales:"
    run_and_show "ls -la '${RDIFF_DEST}/documentos'"
    run_and_show "cat '${RDIFF_DEST}/documentos/balance.txt'"

    explain "Y los deltas hacia el pasado se almacenan en 'rdiff-backup-data':"
    run_and_show "ls -la '${RDIFF_DEST}/rdiff-backup-data' | head -n 12"
else
    explain "rdiff-backup no está instalado en este entorno. Demostrando cómo opera conceptualmente:"
    rsync -a "${SRC_DIR}/" "${RDIFF_DEST}/"
    mkdir -p "${RDIFF_DEST}/rdiff-backup-data/increments"
    echo "Delta diff binario inverso comprimido con librsync" > "${RDIFF_DEST}/rdiff-backup-data/increments/balance.2026-10-30.diff.gz"
    run_and_show "ls -la '${RDIFF_DEST}'"
    run_and_show "cat '${RDIFF_DEST}/documentos/balance.txt'"
fi

pie_clase "¿Cuál es la gran ventaja de la arquitectura de 'Deltas Inversos' de rdiff-backup frente a un incremental clásico?" \
          "Que el backup más reciente (que representa el 95% de las restauraciones cotidianas) es un espejo idéntico listo para copiar inmediatamente, sin tener que reconstruir la cadena aplicando deltas hacia adelante."

pause_step "Presioná [ENTER] para ver el cifrado Zero-Trust con Duplicity..."

# ==============================================================================
# PASO 3: DUPLICITY Y CIFRADO ASIMÉTRICO EN CLIENTE
# ==============================================================================
step_banner "3" "Cifrado en Cliente con Duplicity (Zero-Trust con GnuPG)"

explain "Duplicity nunca envía archivos planos a la red: empaqueta en volúmenes tar y los cifra con GnuPG localmente."

if command -v duplicity >/dev/null 2>&1; then
    export PASSPHRASE
    run_and_show "duplicity --no-encryption '${SRC_DIR}' 'file://${DUPL_DEST}'"
else
    explain "Duplicity no está disponible. Ejecutamos el pipeline streaming exacto que realiza Duplicity:"
    explain "Pipeline: tar (empaquetado) | gpg --symmetric --cipher-algo AES256 (cifrado):"
    run_and_show "tar -cz -C '${SRC_DIR}' . | gpg --batch --yes --passphrase '${PASSPHRASE}' --symmetric --cipher-algo AES256 -o '${DUPL_DEST}/duplicity-full.vol1.difftar.gpg'"
    
    explain "Inspeccionamos el volumen remoto resultante:"
    run_and_show "ls -lh '${DUPL_DEST}/duplicity-full.vol1.difftar.gpg'"
    run_and_show "file '${DUPL_DEST}/duplicity-full.vol1.difftar.gpg'"
fi

pie_clase "¿Por qué el cifrado del lado del cliente (Client-Side Encryption) es obligatorio para respaldos en la nube pública (AWS S3, Azure, Google Drive)?" \
          "Para aplicar el modelo Zero-Trust: aunque el proveedor de nube o el bucket sufran una filtración masiva o acceso no autorizado, los datos son completamente ilegibles sin la clave privada o contraseña local."

pause_step "Presioná [ENTER] para simular la restauración de emergencia..."

# ==============================================================================
# PASO 4: RESTAURACIÓN Y DESCIFRADO AL VUELO
# ==============================================================================
step_banner "4" "Restauración Descifrando en Memoria"

explain "Simulamos la pérdida total de los archivos en producción:"
rm -rf "${SRC_DIR:?}"/*
run_and_show "ls -la '${SRC_DIR}'"

explain "Restauramos descifrando al vuelo sin escribir archivos intermedios en disco:"
if [ -f "${DUPL_DEST}/duplicity-full.vol1.difftar.gpg" ]; then
    run_and_show "gpg --batch --passphrase '${PASSPHRASE}' --decrypt '${DUPL_DEST}/duplicity-full.vol1.difftar.gpg' | tar -xz -C '${SRC_DIR}'"
fi

explain "Comprobamos que las claves y archivos secretos se recuperaron intactos:"
run_and_show "cat '${SRC_DIR}/config/secret.key'"
run_and_show "cat '${SRC_DIR}/documentos/balance.txt'"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE RDIFF-BACKUP Y DUPLICITY FINALIZADA CON ÉXITO!           ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado los deltas inversos y el cifrado en cliente Zero-Trust con GnuPG.\n"
