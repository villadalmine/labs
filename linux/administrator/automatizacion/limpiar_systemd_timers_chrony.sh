#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio Systemd Timers vs Cron y Chrony
# Referencia: linux/administrator/automatizacion/systemd_timers_vs_cron_chrony.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando unidades de laboratorio de Systemd Timers...${C_RESET}"

systemctl stop lab-mantenimiento.timer lab-mantenimiento.service lab-tarea-efimera.timer lab-tarea-efimera.service 2>/dev/null || true
systemctl disable lab-mantenimiento.timer 2>/dev/null || true

rm -f /etc/systemd/system/lab-mantenimiento.timer \
      /etc/systemd/system/lab-mantenimiento.service \
      /usr/local/bin/lab-mantenimiento-enterprise.sh

systemctl daemon-reload 2>/dev/null || true
systemctl reset-failed 2>/dev/null || true

echo -e "  ${C_GREEN}✔ Unidades lab-mantenimiento.{timer,service} y lab-tarea-efimera eliminadas.${C_RESET}"
echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
