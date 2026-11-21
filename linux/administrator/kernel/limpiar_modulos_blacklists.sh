#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio 1.7 (/boot, Módulos LKM y Blacklists)
# Referencia: linux/administrator/kernel/modulos_lkm_blacklists_boot.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de Lab 1.7 (Módulos y Blacklists)...${C_RESET}"

if [ -f /etc/modprobe.d/99-lab-blacklist-demo.conf ]; then
    rm -f /etc/modprobe.d/99-lab-blacklist-demo.conf
    echo -e "  ${C_GREEN}✔ Regla eliminada: /etc/modprobe.d/99-lab-blacklist-demo.conf${C_RESET}"
fi

if lsmod 2>/dev/null | grep -q '^dummy\b'; then
    modprobe -r dummy 2>/dev/null && echo -e "  ${C_GREEN}✔ Módulo temporal descargado: dummy${C_RESET}" || true
fi

if [ -d /tmp/lab_demo_modulos ]; then
    rm -rf /tmp/lab_demo_modulos
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_modulos${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
