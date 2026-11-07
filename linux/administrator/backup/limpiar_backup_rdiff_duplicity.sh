#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio rdiff-backup y Duplicity
# Referencia: linux/administrator/backup/backup_rdiff_duplicity.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

LAB_DIR="/tmp/lab_rdiff_duplicity"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de rdiff-backup y Duplicity...${C_RESET}"

if [ -d "$LAB_DIR" ]; then
    rm -rf "$LAB_DIR"
    echo -e "  ${C_GREEN}✔ Directorio eliminado: ${LAB_DIR}${C_RESET}"
else
    echo -e "  ${C_GREEN}✔ El directorio ${LAB_DIR} ya estaba limpio.${C_RESET}"
fi

rm -f /tmp/clientes_recuperado.txt 2>/dev/null || true

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
