#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio 3.23 (Módulo LKM Simulador de Firmware)
# Referencia: linux/administrator/kernel/modulo_lkm_firmware_sim.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de Lab 3.23 (LKM Firmware Sim)...${C_RESET}"

if lsmod 2>/dev/null | grep -q '^edu_firmware_sim\b'; then
    rmmod edu_firmware_sim 2>/dev/null && echo -e "  ${C_GREEN}✔ Módulo descargado: edu_firmware_sim${C_RESET}" || true
fi

if [ -d /tmp/lab_demo_lkm_fw ]; then
    rm -rf /tmp/lab_demo_lkm_fw
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_lkm_fw${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
