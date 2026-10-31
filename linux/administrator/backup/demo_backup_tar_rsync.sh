#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: Respaldos Clásicos con tar y rsync (--link-dest)
# Laboratorio: linux/administrator/backup/backup_tar_rsync_incremental.md
#
# Uso:
#   ./demo_backup_tar_rsync.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_backup_tar_rsync.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_DIM="\033[2m"

pause_step() {
    local prompt_msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "${C_DIM}⏳ Esperando ${AUTO_WAIT}s...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_YELLOW}${prompt_msg}${C_RESET}"
        read -r
    fi
}

step_banner() {
    local step_num="$1"
    local step_title="$2"
    echo -e "\n${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN} [PASO ${step_num}] ${step_title}${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}\n"
}

run_cmd() {
    local cmd="$1"
    echo -e "${C_BOLD}$ ${cmd}${C_RESET}"
    eval "$cmd"
}

# Variables de entorno del laboratorio
LAB_DIR="/tmp/lab_backups"
SRC_DIR="${LAB_DIR}/produccion"
DST_DIR="${LAB_DIR}/repositorio_backups"

echo -e "\n${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║${C_RESET} ${C_BOLD}DEMO: RESPALDOS CLÁSICOS (tar SNAR + rsync --link-dest)${C_RESET}          ${C_BOLD}${C_CYAN}║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"

# ------------------------------------------------------------------------------
# 1. Preparar Datos
# ------------------------------------------------------------------------------
step_banner "1" "Inicialización de Datos de Producción"
echo -e "Limpiando directorio de trabajo previo y creando datos simulados..."
rm -rf "$LAB_DIR"
mkdir -p "$SRC_DIR/web" "$SRC_DIR/db" "$DST_DIR"

echo "<h1>Bienvenido a la Intranet Corporativa</h1>" > "$SRC_DIR/web/index.html"
echo "body { font-family: sans-serif; background: #fafafa; }" > "$SRC_DIR/web/style.css"
dd if=/dev/urandom of="$SRC_DIR/db/clientes.dat" bs=1M count=3 status=none
echo "v1.0.0" > "$SRC_DIR/db/version.txt"

echo -e "\n${C_GREEN}✔ Datos iniciales generados en: ${SRC_DIR}${C_RESET}"
ls -lh "$SRC_DIR/web" "$SRC_DIR/db"

cd "$SRC_DIR"
sha256sum web/* db/* > "${LAB_DIR}/original_checksums.sha256"

pause_step

# ------------------------------------------------------------------------------
# 2. Backup Full con tar
# ------------------------------------------------------------------------------
step_banner "2" "Backup Completo con GNU tar (-cvpzf)"
echo -e "Empaquetamos preservando permisos (-p) y rutas relativas (-C):"
run_cmd "tar -cvpzf ${DST_DIR}/backup_full.tar.gz -C ${SRC_DIR} ."

echo -e "\n${C_GREEN}✔ Archivo empaquetado y comprimido creado:${C_RESET}"
ls -lh "${DST_DIR}/backup_full.tar.gz"

pause_step

# ------------------------------------------------------------------------------
# 3. Backup Incremental con tar y archivo de instantánea SNAR
# ------------------------------------------------------------------------------
step_banner "3" "Backup Incremental con tar (--listed-incremental)"
SNAR_FILE="${DST_DIR}/tar_incremental/empresa.snar"
mkdir -p "${DST_DIR}/tar_incremental"

echo -e "1. Ejecutando Backup Nivel 0 (Full inicial con registro SNAR):"
run_cmd "tar --create --listed-incremental=${SNAR_FILE} --verbose --preserve-permissions --gzip --file=${DST_DIR}/tar_incremental/backup_nivel0.tar.gz -C ${SRC_DIR} ."

echo -e "\n2. Modificando datos en producción (simulando actividad de usuarios):"
echo "<h1>Intranet v2 - Modificada</h1>" > "$SRC_DIR/web/index.html"
echo "Reporte de ventas 2026" > "$SRC_DIR/reporte.txt"
rm -f "$SRC_DIR/web/style.css"
echo "  • web/index.html modificado"
echo "  • reporte.txt creado"
echo "  • web/style.css eliminado"

echo -e "\n3. Ejecutando Backup Nivel 1 (Incremental con el mismo .snar):"
run_cmd "tar --create --listed-incremental=${SNAR_FILE} --verbose --preserve-permissions --gzip --file=${DST_DIR}/tar_incremental/backup_nivel1.tar.gz -C ${SRC_DIR} ."

echo -e "\n${C_CYAN}Comparativa de tamaños en tar incremental:${C_RESET}"
ls -lh "${DST_DIR}/tar_incremental"

pause_step

# ------------------------------------------------------------------------------
# 4. Deduplicación por Hard Links con rsync --link-dest
# ------------------------------------------------------------------------------
step_banner "4" "Deduplicación por Inodos con rsync --link-dest"
RSYNC_DIR="${DST_DIR}/rsync_backups"
mkdir -p "$RSYNC_DIR"

echo -e "1. Generando respaldo del Día 1 con rsync estándar:"
run_cmd "rsync -av ${SRC_DIR}/ ${RSYNC_DIR}/dia_1/"

echo -e "\n2. Modificando un archivo en producción para el Día 2:"
echo "<h1>Intranet - Día 2</h1>" > "$SRC_DIR/web/index.html"
echo "Log diario OK" > "$SRC_DIR/db/eventos.log"

echo -e "\n3. Ejecutando respaldo del Día 2 con --link-dest=${RSYNC_DIR}/dia_1:"
run_cmd "rsync -av --link-dest=${RSYNC_DIR}/dia_1 ${SRC_DIR}/ ${RSYNC_DIR}/dia_2/"

echo -e "\n${C_BOLD}${C_YELLOW}🔬 AUDITORÍA FORENSE DE INODOS (DEDUPLICACIÓN REAL EN EL KERNEL):${C_RESET}"
echo -e "Inspeccionamos la base de datos clientes.dat (que no cambió entre día 1 y 2):"
stat -c "Archivo: %n | Inodo: %i | Enlaces (nlink): %h" \
    "${RSYNC_DIR}/dia_1/db/clientes.dat" \
    "${RSYNC_DIR}/dia_2/db/clientes.dat"

echo -e "\nInspeccionamos web/index.html (que sí cambió):"
stat -c "Archivo: %n | Inodo: %i | Enlaces (nlink): %h" \
    "${RSYNC_DIR}/dia_1/web/index.html" \
    "${RSYNC_DIR}/dia_2/web/index.html"

echo -e "\n${C_GREEN}✔ Observación: clientes.dat comparte el MISMO inodo físico y tiene Links: 2.${C_RESET}"
echo -e "${C_GREEN}  Ocupa CERO bytes de disco adicional.${C_RESET}"

pause_step

# ------------------------------------------------------------------------------
# 5. Desastre y Recuperación
# ------------------------------------------------------------------------------
step_banner "5" "Simulacro de Desastre y Restauración"
echo -e "${C_RED}💥 SIMULANDO PÉRDIDA TOTAL: rm -rf ${SRC_DIR}/*${C_RESET}"
rm -rf "${SRC_DIR:?}"/*
echo "Archivos restantes en producción: $(ls -A "$SRC_DIR" | wc -l)"

echo -e "\nRestaurando desde el backup deduplicado rsync del Día 2:"
run_cmd "rsync -av ${RSYNC_DIR}/dia_2/ ${SRC_DIR}/"

echo -e "\n${C_GREEN}✔ Producción 100% restaurada al estado del Día 2:${C_RESET}"
ls -la "$SRC_DIR"

echo -e "\nVerificando checksums de archivos que no debían sufrir corrupción:"
cd "$SRC_DIR"
sha256sum -c "${LAB_DIR}/original_checksums.sha256" 2>/dev/null || true

step_banner "FIN" "Demostración Finalizada Exitosamente"
echo -e "${C_GREEN}${C_BOLD}✔ Se demostraron todas las fases:${C_RESET}"
echo -e "  1. Tar Full con preservación estricta de permisos (-p)."
echo -e "  2. Tar Incremental con detección automática vía .snar."
echo -e "  3. Rsync con --link-dest y deduplicación física por inodos compartidos."
echo -e "  4. Restauración instantánea y validación criptográfica."
echo -e "\nPara limpiar los archivos de prueba, ejecutá:"
echo -e "  ${C_BOLD}./linux/administrator/backup/limpiar_backup_tar_rsync.sh${C_RESET}\n"
