#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio 2.7 (Actualización del Kernel, Rollback y Livepatch)
# Referencia: linux/administrator/kernel/actualizacion_kernel_rollback_livepatch.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de Lab 2.7 (Actualización de Kernel)...${C_RESET}"

if [ -d /tmp/lab_demo_kernel_update ]; then
    rm -rf /tmp/lab_demo_kernel_update
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_kernel_update${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
