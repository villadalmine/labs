#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio Cron y Crontab
# Referencia: linux/administrator/automatizacion/cron_crontab_planificacion.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio de Cron y Crontab...${C_RESET}"

rm -f /etc/cron.d/lab_demo_automatizacion 2>/dev/null || true

for dir in /tmp/lab_cron /tmp/lab_demo_cron; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        echo -e "  ${C_GREEN}✔ Directorio eliminado: ${dir}${C_RESET}"
    fi
done

if command -v crontab &>/dev/null; then
    if crontab -l 2>/dev/null | grep -q "lab_cron\|lab_demo_cron"; then
        crontab -l 2>/dev/null | grep -v "lab_cron\|lab_demo_cron" | crontab - 2>/dev/null || crontab -r 2>/dev/null || true
        echo -e "  ${C_GREEN}✔ Entradas de prueba removidas del crontab activo.${C_RESET}"
    fi
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
