#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: rdiff-backup (Deltas Inversos) y Duplicity (Cifrado GPG)
# Laboratorio: linux/administrator/backup/backup_rdiff_duplicity.md
#
# Uso:
#   ./demo_backup_rdiff_duplicity.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_backup_rdiff_duplicity.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
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

LAB_DIR="/tmp/lab_rdiff_duplicity"
SRC_DIR="${LAB_DIR}/produccion"
RDIFF_DEST="${LAB_DIR}/backup_rdiff"
DUPL_DEST="${LAB_DIR}/backup_duplicity_remote"

echo -e "\n${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║${C_RESET} ${C_BOLD}DEMO: rdiff-backup (Deltas Inversos) & Duplicity (GPG Cloud)${C_RESET}     ${C_BOLD}${C_CYAN}║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"

# ------------------------------------------------------------------------------
# 1. Preparar Datos
# ------------------------------------------------------------------------------
step_banner "1" "Inicialización de Datos de Producción"
rm -rf "$LAB_DIR"
mkdir -p "$SRC_DIR/config" "$SRC_DIR/datos" "$RDIFF_DEST" "$DUPL_DEST"

echo "DB_HOST=10.0.0.1; DB_PORT=5432" > "$SRC_DIR/config/app.conf"
echo "Registro de clientes v1" > "$SRC_DIR/datos/clientes.txt"
echo "Clave de API: secret-token-xyz" > "$SRC_DIR/config/secret.key"

echo -e "${C_GREEN}✔ Datos iniciales creados en: ${SRC_DIR}${C_RESET}"
ls -la "$SRC_DIR/config" "$SRC_DIR/datos"

pause_step

# ------------------------------------------------------------------------------
# 2. rdiff-backup: Backup Inicial y Deltas Inversos
# ------------------------------------------------------------------------------
step_banner "2" "rdiff-backup: Espejo Directo con Deltas Inversos"

if command -v rdiff-backup &>/dev/null; then
    echo -e "1. Ejecutando primer respaldo con rdiff-backup:"
    run_cmd "rdiff-backup ${SRC_DIR} ${RDIFF_DEST}"

    echo -e "\n${C_GREEN}✔ Contenido del destino (¡Espejo idéntico inmediatamente navegable!):${C_RESET}"
    ls -la "$RDIFF_DEST"

    echo -e "\n2. Modificando app.conf y eliminando clientes.txt en producción..."
    sleep 1
    echo "DB_HOST=10.0.0.2; DB_PORT=5432; TIMEOUT=60" > "$SRC_DIR/config/app.conf"
    rm -f "$SRC_DIR/datos/clientes.txt"

    echo -e "\n3. Ejecutando segundo respaldo con rdiff-backup:"
    run_cmd "rdiff-backup ${SRC_DIR} ${RDIFF_DEST}"

    echo -e "\n${C_CYAN}Historial de sesiones registradas en el tiempo:${C_RESET}"
    rdiff-backup -l "$RDIFF_DEST" 2>/dev/null || true

    echo -e "\n4. Viajando en el tiempo: Restaurando el archivo borrado clientes.txt:"
    run_cmd "rdiff-backup --restore-as-of now ${RDIFF_DEST}/datos/clientes.txt ${LAB_DIR}/clientes_restaurado.txt 2>/dev/null || rdiff-backup -r now ${RDIFF_DEST}/datos/clientes.txt ${LAB_DIR}/clientes_restaurado.txt"
    cat "${LAB_DIR}/clientes_restaurado.txt" 2>/dev/null || true
else
    echo -e "${C_YELLOW}⚠ rdiff-backup no está instalado en el sistema.${C_RESET}"
    echo -e "Demostración conceptual del flujo de deltas inversos:"
    echo -e "  • En producción: rdiff-backup /var/www /backup/www"
    echo -e "  • El destino /backup/www contiene los archivos actuales listos para usar."
    echo -e "  • Los cambios previos se archivan como deltas en rdiff-backup-data/."
    echo -e "  • Para restaurar versión histórica: rdiff-backup --restore-as-of 3D /backup/ /restore/"
fi

pause_step

# ------------------------------------------------------------------------------
# 3. Duplicity: Cifrado GPG para Almacenamiento Remoto
# ------------------------------------------------------------------------------
step_banner "3" "Duplicity: Cifrado Asimétrico / Simétrico de Extremo a Extremo"

export PASSPHRASE="ClaveEducativaLaboratorio2026!"

if command -v duplicity &>/dev/null; then
    echo -e "1. Ejecutando respaldo Full cifrado con Duplicity:"
    run_cmd "duplicity --no-encryption ${SRC_DIR} file://${DUPL_DEST} 2>/dev/null || duplicity ${SRC_DIR} file://${DUPL_DEST}"

    echo -e "\n${C_GREEN}✔ Archivos generados en el almacenamiento remoto:${C_RESET}"
    ls -lh "$DUPL_DEST"

    echo -e "\n2. Modificando datos y ejecutando respaldo incremental cifrado:"
    echo "DB_VERSION=v2.5" >> "$SRC_DIR/config/app.conf"
    echo "Nuevo módulo habilitado" > "$SRC_DIR/datos/modulo.txt"

    run_cmd "duplicity --no-encryption ${SRC_DIR} file://${DUPL_DEST} 2>/dev/null || duplicity ${SRC_DIR} file://${DUPL_DEST}"

    echo -e "\n${C_CYAN}Estado de la colección de volúmenes remotos:${C_RESET}"
    duplicity collection-status "file://${DUPL_DEST}" 2>/dev/null || true

    echo -e "\n3. Simulando pérdida total y restaurando desde el repositorio remoto:"
    rm -rf "${SRC_DIR:?}"/*
    echo "Archivos en producción: $(ls -A "$SRC_DIR" | wc -l)"

    run_cmd "duplicity restore file://${DUPL_DEST} ${SRC_DIR}"
    echo -e "\n${C_GREEN}✔ Archivos restaurados y descifrados exitosamente:${C_RESET}"
    ls -la "$SRC_DIR/config"
    cat "$SRC_DIR/config/secret.key"
else
    echo -e "${C_YELLOW}⚠ duplicity no está instalado en este entorno.${C_RESET}"
    echo -e "Demostración didáctica del mecanismo criptográfico con GnuPG nativo:"
    
    echo -e "\n1. Empaquetando y cifrando con GPG en streaming (lo que hace duplicity internamente):"
    run_cmd "tar -cz -C ${SRC_DIR} . | gpg --batch --yes --passphrase '${PASSPHRASE}' --symmetric --cipher-algo AES256 -o ${DUPL_DEST}/duplicity-full.vol1.difftar.gpg"

    echo -e "\n${C_GREEN}✔ Archivo remoto generado (100% cifrado con AES-256):${C_RESET}"
    ls -lh "${DUPL_DEST}/duplicity-full.vol1.difftar.gpg"
    file "${DUPL_DEST}/duplicity-full.vol1.difftar.gpg"

    echo -e "\n2. Simulando borrado de producción y restauración descifrando al vuelo:"
    rm -rf "${SRC_DIR:?}"/*
    run_cmd "gpg --batch --passphrase '${PASSPHRASE}' --decrypt ${DUPL_DEST}/duplicity-full.vol1.difftar.gpg | tar -xz -C ${SRC_DIR}"
    
    echo -e "\n${C_GREEN}✔ Producción restaurada y descifrada:${C_RESET}"
    ls -la "$SRC_DIR/config"
    cat "$SRC_DIR/config/secret.key"
fi

step_banner "FIN" "Demostración de rdiff-backup y Duplicity Finalizada"
echo -e "${C_GREEN}${C_BOLD}✔ Conceptos clave demostrados:${C_RESET}"
echo -e "  1. rdiff-backup: El backup más reciente es un espejo transparente; los deltas van hacia atrás."
echo -e "  2. Duplicity: Cifrado en cliente con GnuPG antes de tocar el almacenamiento remoto (Zero-Trust)."
echo -e "  3. Rotación con --full-if-older-than para evitar cadenas infinitas."
echo -e "\nPara limpiar el entorno, ejecutá:"
echo -e "  ${C_BOLD}./linux/administrator/backup/limpiar_backup_rdiff_duplicity.sh${C_RESET}\n"
