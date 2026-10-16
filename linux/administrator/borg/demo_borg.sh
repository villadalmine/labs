#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: BorgBackup, Deduplicación, Cifrado y FUSE Mount
# Basado en: linux/administrator/borg.md y borg-con-systemd-timers.md
# Uso:
#   ./demo_borg.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_borg.sh --auto 5 -> Modo automático (espera 5s entre pasos)
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

ORIGEN_DIR="/tmp/demo_borg_origen"
REPO_DIR="/tmp/demo_borg_repo"
MOUNT_RESTORE="/tmp/demo_borg_restauracion"

export BORG_PASSPHRASE="ClaseBorgPass2026!"
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

cleanup() {
    echo -e "\n${C_YELLOW}[!] Limpiando recursos de la prueba Borg...${C_RESET}"
    if command -v borg &>/dev/null && [ -d "$MOUNT_RESTORE" ]; then
        borg umount "$MOUNT_RESTORE" 2>/dev/null || umount -f "$MOUNT_RESTORE" 2>/dev/null || true
    fi
    rm -rf "$ORIGEN_DIR" "$REPO_DIR" "$MOUNT_RESTORE" 2>/dev/null || true
    echo -e "${C_GREEN}[OK] Directorios temporales eliminados.${C_RESET}"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Configuración amigable para TMUX
# ------------------------------------------------------------------------------
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
    echo -e "\n${C_MAGENTA}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW} PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}======================================================================${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💬 EXPLICACIÓN:${C_RESET} $1"
}

command_info() {
    echo -e "${C_BOLD}${C_GREEN}$ ${1}${C_RESET}"
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_YELLOW}👉 ${msg}${C_RESET}"
        read -r
    fi
}

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------
step_banner "0" "Verificación de BorgBackup"

if ! command -v borg &>/dev/null; then
    echo -e "${C_RED}[ERROR] BorgBackup no está instalado.${C_RESET}"
    echo "Instalalo con: sudo apt update && sudo apt install -y borgbackup"
    exit 1
fi
echo -e "${C_GREEN}[OK] BorgBackup está disponible ($(borg --version)).${C_RESET}"

pause_step "Presioná [ENTER] para crear los archivos de producción simulados..."

# ------------------------------------------------------------------------------
# 1. Preparar archivos de prueba
# ------------------------------------------------------------------------------
step_banner "1" "Estructura de archivos de producción simulada"

explain "Creamos datos simulados de un servidor web en $ORIGEN_DIR:"
explain " - /var/www (HTML, CSS y una imagen de 10MB)"
explain " - /etc/nginx (Archivos de configuración del servidor)"

mkdir -p "$ORIGEN_DIR/var_www" "$ORIGEN_DIR/etc_nginx"
echo "<h1>Sitio Web de Producción - Version 1.0</h1>" > "$ORIGEN_DIR/var_www/index.html"
echo "body { background: #f0f0f0; }" > "$ORIGEN_DIR/var_www/style.css"
dd if=/dev/urandom of="$ORIGEN_DIR/var_www/banner.bin" bs=1M count=10 status=none

echo "server { listen 80; root /var/www; }" > "$ORIGEN_DIR/etc_nginx/nginx.conf"

echo -e "\n${C_BOLD}Archivos generados en el origen:${C_RESET}"
ls -lh "$ORIGEN_DIR/var_www"
ls -lh "$ORIGEN_DIR/etc_nginx"

pause_step "Presioná [ENTER] para inicializar el repositorio cifrado de Borg..."

# ------------------------------------------------------------------------------
# 2. Inicializar repositorio cifrado de Borg
# ------------------------------------------------------------------------------
step_banner "2" "Inicializar Repositorio Borg (borg init --encryption=repokey)"

explain "Borg no copia archivos como un zip; los divide en bloques únicos (chunks), los comprime y los cifra."
explain "--encryption=repokey guarda la clave dentro del repositorio pero protegida con contraseña."
explain "Usaremos BORG_PASSPHRASE='$BORG_PASSPHRASE' en memoria."

command_info "borg init --encryption=repokey $REPO_DIR"
borg init --encryption=repokey "$REPO_DIR"

echo -e "${C_GREEN}[OK] Repositorio Borg creado en $REPO_DIR${C_RESET}"
echo -e "Estructura interna del repositorio de chunks cifrados:"
ls -l "$REPO_DIR"

pause_step "Presioná [ENTER] para crear el primer backup completo (Snapshot 1)..."

# ------------------------------------------------------------------------------
# 3. Primer Backup Completo
# ------------------------------------------------------------------------------
step_banner "3" "Primer Backup Completo (borg create --stats)"

explain "Creamos el archivo 'servidor-2026-v1' conteniendo $ORIGEN_DIR:"
command_info "borg create --stats $REPO_DIR::servidor-2026-v1 $ORIGEN_DIR"
borg create --stats "$REPO_DIR::servidor-2026-v1" "$ORIGEN_DIR"

explain "Observá las estadísticas: Original size vs Deduplicated size."
explain "En este primer snapshot, todos los bloques son nuevos."

pause_step "Presioná [ENTER] para ver la magia de la DEDUPLICACIÓN en el segundo backup..."

# ------------------------------------------------------------------------------
# 4. Segundo Backup: Demostración de Deduplicación
# ------------------------------------------------------------------------------
step_banner "4" "Deduplicación Extrema: Segundo Backup tras un cambio mínimo"

explain "Simulamos un cambio menor en producción: modificamos solo 1 línea en index.html."
echo "<h1>Sitio Web de Producción - Version 1.1 (Actualizado)</h1>" > "$ORIGEN_DIR/var_www/index.html"

explain "Ejecutamos el segundo backup completo ('servidor-2026-v2'):"
command_info "borg create --stats $REPO_DIR::servidor-2026-v2 $ORIGEN_DIR"
borg create --stats "$REPO_DIR::servidor-2026-v2" "$ORIGEN_DIR"

echo -e "\n${C_BOLD}${C_GREEN}📢 CONCLUSIÓN DIDÁCTICA DE LA DEDUPLICACIÓN:${C_RESET}"
explain "Fijate en 'This archive' vs 'All archives':"
explain "Aunque respaldamos los 10MB completos de nuevo, 'Deduplicated size' del nuevo archivo fue de apenas unos pocos BYTES."
explain "¡El archivo de 10MB (banner.bin) tardó 0 segundos en procesarse y consumió 0 bytes adicionales de almacenamiento!"

pause_step "Presioná [ENTER] para simular un desastre y recuperar archivos montando el repositorio..."

# ------------------------------------------------------------------------------
# 5. Exploración y Restauración con FUSE (borg mount)
# ------------------------------------------------------------------------------
step_banner "5" "Recuperación de Desastre con borg mount (FUSE)"

explain "Simulamos que un usuario o administrador borró accidentalmente el archivo index.html en producción:"
rm -f "$ORIGEN_DIR/var_www/index.html"
echo -e "${C_RED}[ALERTA] Archivo index.html borrado del servidor.${C_RESET}"
ls -l "$ORIGEN_DIR/var_www"

explain "Borg permite montar TODO el repositorio como una carpeta normal del sistema de archivos con FUSE."
mkdir -p "$MOUNT_RESTORE"

command_info "borg mount $REPO_DIR $MOUNT_RESTORE"
borg mount "$REPO_DIR" "$MOUNT_RESTORE"

echo -e "\n${C_BOLD}Snapshots montados como carpetas navegables en $MOUNT_RESTORE:${C_RESET}"
ls -l "$MOUNT_RESTORE"

explain "Podemos explorar el contenido del snapshot v1 o v2 y recuperar exactamente el archivo borrado con un simple 'cp':"
command_info "cp $MOUNT_RESTORE/servidor-2026-v2/$ORIGEN_DIR/var_www/index.html $ORIGEN_DIR/var_www/"
cp "$MOUNT_RESTORE/servidor-2026-v2/$ORIGEN_DIR/var_www/index.html" "$ORIGEN_DIR/var_www/"

echo -e "\n${C_BOLD}Verificación del archivo restaurado:${C_RESET}"
cat "$ORIGEN_DIR/var_www/index.html"

command_info "borg umount $MOUNT_RESTORE"
borg umount "$MOUNT_RESTORE"
explain "Repositorio desmontado correctamente."

pause_step "Presioná [ENTER] para ver la política de retención y limpieza (borg prune)..."

# ------------------------------------------------------------------------------
# 6. Política de Retención y Limpieza (borg prune)
# ------------------------------------------------------------------------------
step_banner "6" "Política de Retención Automática (borg prune)"

explain "Con el paso de los meses, los backups se acumulan. 'borg prune' aplica reglas GFS (Grandfather-Father-Son):"
explain "Por ejemplo: mantener 7 diarios, 4 semanales y 6 mensuales."
command_info "borg prune -v --list --keep-daily=7 --keep-weekly=4 $REPO_DIR"
borg prune -v --list --keep-daily=7 --keep-weekly=4 "$REPO_DIR"

explain "Borg borra los snapshots obsoletos, pero NUNCA borra los chunks que sigan siendo referenciados por otros snapshots activos."

pause_step "Presioná [ENTER] para revisar la automatización con systemd timers y finalizar..."

# ------------------------------------------------------------------------------
# 7. Resumen de Automatización con systemd timers
# ------------------------------------------------------------------------------
step_banner "7" "Automatización segura con systemd timers"

explain "En un entorno real, automatizamos Borg sin contraseñas en texto plano:"
echo -e "  1. ${C_BOLD}/etc/borg/credenciales${C_RESET} -> Guarda BORG_PASSPHRASE con permisos 600 (solo root)."
echo -e "  2. ${C_BOLD}/usr/local/bin/backup-diario.sh${C_RESET} -> Script que ejecuta 'borg create' y 'borg prune'."
echo -e "  3. ${C_BOLD}/etc/systemd/system/borg-backup.service${C_RESET} -> Inyecta credenciales con EnvironmentFile=."
echo -e "  4. ${C_BOLD}/etc/systemd/system/borg-backup.timer${C_RESET} -> Dispara el backup automáticamente a las 3 AM."

step_banner "FIN" "Demostración de BorgBackup finalizada con éxito"
echo -e "${C_GREEN}¡Todos los conceptos de Borg, deduplicación, FUSE mount y retención demostrados!${C_RESET}\n"
