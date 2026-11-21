#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Journald y Troubleshooting Forense (Lab 3.20)
# Referencia: linux/administrator/logs/journald_journalctl_troubleshooting.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio Journald Troubleshooting (Lab 3.20)...${C_RESET}"

pkill -f "http.server 18080" 2>/dev/null || true
systemctl stop lab-web-prod.service lab-sshd-audit.service 2>/dev/null || true
rm -f /etc/systemd/system/lab-web-prod.service /etc/systemd/system/lab-sshd-audit.service /etc/systemd/journald.conf.d/99-lab-demo.conf
systemctl daemon-reload 2>/dev/null || true
systemctl reset-failed lab-web-prod.service lab-sshd-audit.service 2>/dev/null || true
systemctl restart systemd-journald 2>/dev/null || true

if [ -d "/tmp/lab_demo_journald" ]; then
    rm -rf "/tmp/lab_demo_journald"
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_journald${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
