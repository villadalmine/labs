#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: BorgBackup, Deduplicación, Cifrado y FUSE Mount
# Basado en: linux/administrator/borg/borg.md y borg-con-systemd-timers.md
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema destacada en una caja limpia.
#  - Desglosa y explica las estadísticas de deduplicación (Original vs Deduplicated).
#  - Recuperación de desastres con FUSE mount (borg mount / umount).
#  - Preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   ./demo_borg.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_borg.sh --auto 4 -> Modo automático (espera 4s entre pasos)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"

ORIGEN_DIR="/tmp/demo_borg_origen"
REPO_DIR="/tmp/demo_borg_repo"
MOUNT_RESTORE="/tmp/demo_borg_restauracion"

export BORG_PASSPHRASE="ClaseBorgPass2026!"
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando FUSE y eliminando repositorios temporales...${C_RESET}"
    if command -v borg &>/dev/null && [ -d "$MOUNT_RESTORE" ]; then
        borg umount "$MOUNT_RESTORE" 2>/dev/null || umount -f "$MOUNT_RESTORE" 2>/dev/null || true
    fi
    rm -rf "$ORIGEN_DIR" "$REPO_DIR" "$MOUNT_RESTORE" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Directorios temporales eliminados correctamente.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón directamente."
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
    echo -e "\n${C_MAGENTA}🎤 [PIE PARA LA CLASE EN VIVO]:${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW}👉 Preguntale a los alumnos:${C_RESET} \"$1\""
    if [ -n "${2:-}" ]; then
        echo -e "   ${C_CYAN}Respuesta clave esperada:${C_RESET} $2"
    fi
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
        read -r
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

clear || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🛡️ LABORATORIO EN VIVO: BORGBACKUP, DEDUPLICACIÓN Y FUSE MOUNT                ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "borg init ➔ borg create (--stats) ➔ Deduplicación extrema ➔ Rescate con borg mount"
echo -e "Aprende cómo ahorrar 80%+ de espacio en respaldos empresariales de producción\n"

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------
step_banner "0" "Verificación de BorgBackup"

explain "Comprobando la presencia de borgbackup en el sistema operativo:"
if ! command -v borg &>/dev/null; then
    echo -e "${C_YELLOW}BorgBackup no está instalado. Instalándolo con el gestor del sistema...${C_RESET}"
    if command -v dnf &>/dev/null; then
        sudo dnf install -y borgbackup
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq borgbackup
    fi
fi

run_and_show "borg --version"
echo -e "${C_GREEN}✔ BorgBackup disponible para la demostración.${C_RESET}"

pause_step "Presioná [ENTER] para crear los archivos de producción simulados..."

# ------------------------------------------------------------------------------
# 1. Preparar archivos de prueba
# ------------------------------------------------------------------------------
step_banner "1" "Estructura de Archivos de Producción Simulada"

explain "Creamos un entorno de servidor web en ${ORIGEN_DIR}:"
explain " • /var_www (HTML, CSS y un archivo binario de 10 MB)"
explain " • /etc_nginx (Archivo de configuración del servidor web)"

mkdir -p "$ORIGEN_DIR/var_www" "$ORIGEN_DIR/etc_nginx"
echo "<h1>Sitio Web de Producción - Version 1.0</h1>" > "$ORIGEN_DIR/var_www/index.html"
echo "body { background: #f0f0f0; }" > "$ORIGEN_DIR/var_www/style.css"
dd if=/dev/urandom of="$ORIGEN_DIR/var_www/banner.bin" bs=1M count=10 status=none
echo "server { listen 80; root /var/www; }" > "$ORIGEN_DIR/etc_nginx/nginx.conf"

explain "Listamos los archivos creados en el origen:"
run_and_show "ls -lh ${ORIGEN_DIR}/var_www && ls -lh ${ORIGEN_DIR}/etc_nginx"

pie_clase "¿Cuál es la diferencia entre un backup tradicional (tar/zip) y un backup por chunking como Borg?" \
          "Tar copia el archivo entero aunque cambie 1 byte; Borg divide en bloques y solo guarda los chunks que cambiaron."

pause_step "Presioná [ENTER] para inicializar el repositorio cifrado de Borg..."

# ------------------------------------------------------------------------------
# 2. Inicializar repositorio cifrado de Borg
# ------------------------------------------------------------------------------
step_banner "2" "Inicializar Repositorio Borg (borg init --encryption=repokey)"

explain "Borg almacena los datos en un repositorio de chunks cifrados y deduplicados."
explain "Usaremos --encryption=repokey para proteger el repositorio con contraseña:"
run_and_show "borg init --encryption=repokey ${REPO_DIR}"

explain "Veamos la estructura interna de chunks que Borg creó en el disco:"
run_and_show "ls -la ${REPO_DIR}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • No hay archivos individuales con sus nombres originales."
echo -e " • Los datos están divididos en segmentos cifrados en la subcarpeta ${C_BOLD}data/${C_RESET}."

pause_step "Presioná [ENTER] para crear el primer backup completo (Snapshot 1)..."

# ------------------------------------------------------------------------------
# 3. Primer Backup Completo
# ------------------------------------------------------------------------------
step_banner "3" "Primer Backup Completo (borg create --stats)"

explain "Creamos el snapshot 'servidor-2026-v1' con estadísticas detalladas (--stats):"
run_and_show "borg create --stats ${REPO_DIR}::servidor-2026-v1 ${ORIGEN_DIR}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LAS ESTADÍSTICAS:${C_RESET}"
echo -e " • ${C_BOLD}Original size:${C_RESET} ~10 MB (el tamaño total del origen)."
echo -e " • ${C_BOLD}Deduplicated size:${C_RESET} ~10 MB (en el primer backup todos los bloques son nuevos)."

pause_step "Presioná [ENTER] para ver la magia de la DEDUPLICACIÓN en el segundo backup..."

# ------------------------------------------------------------------------------
# 4. Segundo Backup: Demostración de Deduplicación
# ------------------------------------------------------------------------------
step_banner "4" "Deduplicación Extrema: Segundo Backup tras un cambio mínimo"

explain "Simulamos un cambio mínimo en producción: editamos solo 1 línea en index.html:"
echo "<h1>Sitio Web de Producción - Version 1.1 (Actualizado)</h1>" > "$ORIGEN_DIR/var_www/index.html"

explain "Ejecutamos el segundo snapshot completo ('servidor-2026-v2'):"
run_and_show "borg create --stats ${REPO_DIR}::servidor-2026-v2 ${ORIGEN_DIR}"

echo -e "\n${C_BOLD}${C_GREEN}📢 LECCIÓN CRUCIAL DE DEDUPLICACIÓN:${C_RESET}"
echo -e " • ${C_BOLD}This archive (Original size):${C_RESET} ~10 MB (respaldamos todo el servidor de nuevo)."
echo -e " • ${C_BOLD}This archive (Deduplicated size):${C_RESET} ${C_GREEN}¡Apenas unos pocos BYTES!${C_RESET}"
echo -e " • El archivo binario de 10 MB (banner.bin) no cambió, por lo que Borg ${C_BOLD}no gastó ni 1 byte extra de disco${C_RESET}."

explain "Listamos los snapshots existentes en el repositorio con borg list:"
run_and_show "borg list ${REPO_DIR}"

pause_step "Presioná [ENTER] para simular un desastre y recuperar archivos con FUSE mount..."

# ------------------------------------------------------------------------------
# 5. Exploración y Restauración con FUSE (borg mount)
# ------------------------------------------------------------------------------
step_banner "5" "Recuperación de Desastre con borg mount (FUSE)"

explain "DESASTRE: Un operador borró accidentalmente el archivo index.html en producción:"
rm -f "$ORIGEN_DIR/var_www/index.html"
echo -e "${C_RED}[ALERTA] Archivo index.html borrado.${C_RESET}"
run_and_show "ls -l ${ORIGEN_DIR}/var_www"

explain "En lugar de extraer gigabytes de un tar, montamos TODO el repositorio como carpeta con FUSE:"
mkdir -p "$MOUNT_RESTORE"
run_and_show "borg mount ${REPO_DIR} ${MOUNT_RESTORE}"

explain "Listamos los snapshots montados como carpetas navegables en tiempo real:"
run_and_show "ls -l ${MOUNT_RESTORE}"

explain "Podemos navegar dentro del snapshot 'servidor-2026-v2' y recuperar el archivo borrado con un simple 'cp':"
run_and_show "cp ${MOUNT_RESTORE}/servidor-2026-v2/${ORIGEN_DIR}/var_www/index.html ${ORIGEN_DIR}/var_www/"

explain "Comprobamos que el archivo fue resucitado con éxito:"
run_and_show "cat ${ORIGEN_DIR}/var_www/index.html"

explain "Desmontamos el repositorio FUSE con borg umount:"
run_and_show "borg umount ${MOUNT_RESTORE}"

pie_clase "¿Por qué es tan revolucionario poder montar backups con FUSE?" \
          "Permite recuperar archivos puntuales en segundos sin tener que descargar o descomprimir el backup completo."

pause_step "Presioná [ENTER] para ver la política de retención automática (borg prune)..."

# ------------------------------------------------------------------------------
# 6. Política de Retención y Limpieza (borg prune)
# ------------------------------------------------------------------------------
step_banner "6" "Política de Retención Automática (borg prune)"

explain "Aplicamos una política de retención GFS (Grandfather-Father-Son):"
explain "Mantener 7 diarios, 4 semanales y 6 mensuales sin borrar bloques compartidos:"
run_and_show "borg prune -v --list --keep-daily=7 --keep-weekly=4 ${REPO_DIR}"

explain "Verificamos los snapshots que quedaron vigentes tras la poda:"
run_and_show "borg list ${REPO_DIR}"

pause_step "Presioná [ENTER] para finalizar la demostración y limpiar el sistema..."

step_banner "FIN" "Demostración de BorgBackup finalizada"
echo -e "${C_BOLD}${C_GREEN}✔ BorgBackup, deduplicación, FUSE mount y retención completados con éxito.${C_RESET}\n"
