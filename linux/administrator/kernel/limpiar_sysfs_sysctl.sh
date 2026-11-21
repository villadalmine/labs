#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio 1.8 (sysfs, procfs y sysctl)
# Referencia: linux/administrator/kernel/sysfs_proc_sysctl_tuning.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de Lab 1.8 (sysfs y sysctl)...${C_RESET}"

if [ -f /etc/sysctl.d/99-lab-sysctl-demo.conf ]; then
    rm -f /etc/sysctl.d/99-lab-sysctl-demo.conf
    echo -e "  ${C_GREEN}✔ Archivo eliminado: /etc/sysctl.d/99-lab-sysctl-demo.conf${C_RESET}"
fi

if [ -f /tmp/lab_demo_sysctl/backup_values.txt ]; then
    while IFS='=' read -r k v; do
        if [ -n "$k" ] && [ -n "$v" ]; then
            sysctl -w "${k}=${v}" >/dev/null 2>&1 && echo -e "  ${C_GREEN}✔ Restaurado ${k}=${v}${C_RESET}" || true
        fi
    done < /tmp/lab_demo_sysctl/backup_values.txt
fi

if command -v ip &>/dev/null && ip netns list 2>/dev/null | grep -q "^lab_sysctl_ns\b"; then
    ip netns del lab_sysctl_ns 2>/dev/null && echo -e "  ${C_GREEN}✔ Network namespace eliminado: lab_sysctl_ns${C_RESET}" || true
fi

if [ -d /tmp/lab_demo_sysctl ]; then
    rm -rf /tmp/lab_demo_sysctl
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_sysctl${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
