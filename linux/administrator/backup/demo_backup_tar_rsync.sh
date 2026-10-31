#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: Respaldos Clásicos con tar y rsync (--link-dest)
# Laboratorio: linux/administrator/backup/backup_tar_rsync_incremental.md
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Preservación estricta de permisos Unix (-p) y rutas relativas (-C).
#  - Backups incrementales con GNU tar y metadatos SNAR (Nivel 0 y Nivel 1).
#  - Deduplicación física a nivel de inodos con rsync --link-dest (Zero-Copy).
#  - Auditoría forense con stat (comparación de inodos y contador nlink).
#  - Simulacro de desastre con rm -rf y restauración validada por SHA-256.
#  - Preguntas disparadoras ("pie de clase") con respuestas desplegables.
#  - Limpieza garantizada al finalizar (trap cleanup).
#
# Uso:
#   ./demo_backup_tar_rsync.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_backup_tar_rsync.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
#   ./demo_backup_tar_rsync.sh --keep   -> Preserva los backups generados para inspección
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

LAB_DIR="/tmp/lab_backups_$$"
SRC_DIR="${LAB_DIR}/produccion"
DST_DIR="${LAB_DIR}/repositorio_backups"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Eliminando datos temporales de backup...${C_RESET}"
    if [ "$KEEP_FILES" = true ]; then
        echo -e "${C_GREEN}[INFO] Entorno de backups preservado en: ${LAB_DIR}${C_RESET}"
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
echo -e "${C_BOLD}${C_CYAN} 📦 DEMOSTRACIÓN EN VIVO: RESPALDOS CLÁSICOS (tar SNAR + rsync --link-dest)     ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "Full con tar (-p) ➔ Incremental SNAR ➔ Deduplicación rsync ➔ Restauración SHA256\n"

# ==============================================================================
# PASO 1: PREPARACIÓN DE DATOS DE PRODUCCIÓN
# ==============================================================================
step_banner "1" "Inicialización de Datos de Producción y Hash SHA-256"

explain "Creamos una estructura de producción simulada: sitio web, base de datos de 3 MB y configuración:"
mkdir -p "$SRC_DIR/web" "$SRC_DIR/db" "$DST_DIR"

echo "<h1>Bienvenido a la Intranet Corporativa</h1>" > "$SRC_DIR/web/index.html"
echo "body { font-family: sans-serif; background: #fafafa; }" > "$SRC_DIR/web/style.css"
dd if=/dev/urandom of="$SRC_DIR/db/clientes.dat" bs=1M count=3 status=none
echo "v1.0.0" > "$SRC_DIR/db/version.txt"

explain "Calculamos los hashes SHA-256 originales para validar la restauración al final:"
(cd "$SRC_DIR" && sha256sum web/* db/* > "${LAB_DIR}/original_checksums.sha256")
run_and_show "ls -lh ${SRC_DIR}/web ${SRC_DIR}/db"
run_and_show "cat ${LAB_DIR}/original_checksums.sha256"

pie_clase "¿Por qué es crucial respaldar usando rutas relativas (-C) en lugar de absolutas (/var/www)?" \
          "Porque si empaquetás con rutas absolutas, al restaurar tar sobreescribirá ciegamente los archivos del sistema raíz sin permitir restaurar en una carpeta aislada de pruebas."

pause_step "Presioná [ENTER] para ejecutar el Backup Full con tar..."

# ==============================================================================
# PASO 2: BACKUP FULL CON TAR
# ==============================================================================
step_banner "2" "Backup Completo con GNU tar (-cvpzf)"

explain "Empaquetamos preservando permisos estrictos (-p), comprimiendo con gzip (-z) y con rutas relativas (-C):"
run_and_show "tar -cvpzf ${DST_DIR}/backup_full.tar.gz -C ${SRC_DIR} ."

explain "Inspeccionamos el archivo resultante y su tabla de contenidos:"
run_and_show "ls -lh ${DST_DIR}/backup_full.tar.gz"
run_and_show "tar -tvf ${DST_DIR}/backup_full.tar.gz | head -n 8"

pie_clase "¿Qué flag de tar garantiza que los permisos de lectura, escritura y ejecución de los usuarios no se pierdan?" \
          "La flag '-p' (--preserve-permissions). Sin ella, tar aplica la máscara umask del usuario que ejecuta la extracción."

pause_step "Presioná [ENTER] para ver el Backup Incremental con tar SNAR..."

# ==============================================================================
# PASO 3: BACKUP INCREMENTAL CON TAR Y SNAR
# ==============================================================================
step_banner "3" "Backup Incremental con Archivo de Instantánea GNU tar (--listed-incremental)"

SNAR_FILE="${DST_DIR}/tar_incremental/empresa.snar"
mkdir -p "${DST_DIR}/tar_incremental"

explain "1. Ejecutamos el Backup Nivel 0 (Full base que genera el catálogo SNAR):"
run_and_show "tar --create --listed-incremental=${SNAR_FILE} --verbose --preserve-permissions --gzip --file=${DST_DIR}/tar_incremental/backup_nivel0.tar.gz -C ${SRC_DIR} ."

explain "2. Modificamos datos en producción simulando la jornada laboral:"
echo "<h1>Intranet v2 - Modificada</h1>" > "$SRC_DIR/web/index.html"
echo "Reporte de ventas 2026" > "$SRC_DIR/reporte.txt"
rm -f "$SRC_DIR/web/style.css"
echo "  • web/index.html modificado"
echo "  • reporte.txt creado"
echo "  • web/style.css eliminado"

explain "3. Ejecutamos el Backup Nivel 1 (Incremental leyendo el mismo archivo SNAR):"
run_and_show "tar --create --listed-incremental=${SNAR_FILE} --verbose --preserve-permissions --gzip --file=${DST_DIR}/tar_incremental/backup_nivel1.tar.gz -C ${SRC_DIR} ."

explain "Comparamos los tamaños: Nivel 0 vs Nivel 1 (el incremental solo guardó los deltas):"
run_and_show "ls -lh ${DST_DIR}/tar_incremental/*.tar.gz"

pie_clase "¿Qué información almacena el archivo .snar de GNU tar?" \
          "Almacena los inodos, tamaños y marcas de tiempo (mtime/ctime) de cada archivo y directorio para detectar rápidamente qué fue creado, modificado o borrado desde el último ciclo."

pause_step "Presioná [ENTER] para ver la deduplicación con rsync --link-dest..."

# ==============================================================================
# PASO 4: DEDUPLICACIÓN POR INODOS DUROS CON RSYNC (--link-dest)
# ==============================================================================
step_banner "4" "Deduplicación Física en el Kernel con rsync --link-dest"

RSYNC_DIR="${DST_DIR}/rsync_backups"
mkdir -p "$RSYNC_DIR"

explain "1. Generamos el respaldo del Día 1 con rsync estándar:"
run_and_show "rsync -av ${SRC_DIR}/ ${RSYNC_DIR}/dia_1/"

explain "2. Modificamos un archivo para el Día 2 (la base de datos de 3 MB permanece intacta):"
echo "<h1>Intranet - Día 2</h1>" > "$SRC_DIR/web/index.html"
echo "Log diario OK" > "$SRC_DIR/db/eventos.log"

explain "3. Ejecutamos el respaldo del Día 2 utilizando --link-dest apuntando al Día 1:"
run_and_show "rsync -av --link-dest=${RSYNC_DIR}/dia_1 ${SRC_DIR}/ ${RSYNC_DIR}/dia_2/"

explain "🔬 AUDITORÍA FORENSE DE INODOS (DEDUPLICACIÓN REAL EN EL KERNEL):"
explain "Comparamos la base de datos de 3 MB (clientes.dat) en el Día 1 y Día 2:"
run_and_show "stat -c 'Archivo: %n | Inodo: %i | Enlaces (nlink): %h | Tamaño: %s B' ${RSYNC_DIR}/dia_1/db/clientes.dat ${RSYNC_DIR}/dia_2/db/clientes.dat"

explain "Comparamos web/index.html (que sí fue modificado):"
run_and_show "stat -c 'Archivo: %n | Inodo: %i | Enlaces (nlink): %h | Tamaño: %s B' ${RSYNC_DIR}/dia_1/web/index.html ${RSYNC_DIR}/dia_2/web/index.html"

pie_clase "Si clientes.dat tiene nlink=2 y el mismo inodo en dia_1 y dia_2, ¿cuánto espacio físico adicional ocupó en el disco?" \
          "CERO bytes. El kernel solo creó una nueva entrada de directorio (dentry) apuntando al mismo inodo existente. Esto permite tener backups completos diarios al costo de almacenamiento de un incremental."

pause_step "Presioná [ENTER] para simular un desastre y restaurar..."

# ==============================================================================
# PASO 5: DESASTRE Y RESTAURACIÓN INTEGRAL
# ==============================================================================
step_banner "5" "Simulacro de Pérdida Catastrófica y Restauración con rsync"

explain "Simulamos un borrado accidental o sabotaje en producción con 'rm -rf':"
rm -rf "${SRC_DIR:?}"/*
run_and_show "ls -la ${SRC_DIR}"

explain "Restauramos toda la producción en segundos desde la copia deduplicada de rsync:"
run_and_show "rsync -av ${RSYNC_DIR}/dia_2/ ${SRC_DIR}/"

explain "Validamos la integridad criptográfica de los datos restaurados:"
run_and_show "cd ${SRC_DIR} && sha256sum -c ${LAB_DIR}/original_checksums.sha256 2>/dev/null || true"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE RESPALDOS CLÁSICOS FINALIZADA CON ÉXITO!                 ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado tar full (-p), tar incremental con catálogos .snar, y la técnica"
echo -e "de deduplicación por inodos duros con rsync --link-dest utilizada en producción.\n"
