#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Fundamentos de Logs (Lab 3.19)
# Referencia: linux/administrator/logs/logs_fundamentos_varlog_dmesg.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio de Fundamentos de Logs (Lab 3.19)...${C_RESET}"

pkill -f "lab_demo_logs_fund/app_activa.log" 2>/dev/null || true

if [ -d "/tmp/lab_demo_logs_fund" ]; then
    rm -rf "/tmp/lab_demo_logs_fund"
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_logs_fund${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
