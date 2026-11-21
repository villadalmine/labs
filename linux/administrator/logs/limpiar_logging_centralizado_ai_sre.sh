#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Logging Centralizado y AI SRE (Lab 3.22)
# Referencia: linux/administrator/logs/logging_centralizado_estructurado_ai_sre.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio Logging Centralizado y AI SRE (Lab 3.22)...${C_RESET}"

for pf in "/var/spool/rsyslog/lab_demo_central/rsyslog_central.pid" "/tmp/lab_demo_central/rsyslog_central.pid"; do
    if [ -f "$pf" ]; then
        p=$(cat "$pf" 2>/dev/null || true)
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
            sleep 0.3
            kill -9 "$p" 2>/dev/null || true
        fi
    fi
done
pkill -f "lab_demo_central/rsyslog_central.conf" 2>/dev/null || true

for d in "/var/spool/rsyslog/lab_demo_central" "/var/log/lab_demo_central" "/tmp/lab_demo_central"; do
    if [ -d "$d" ]; then
        rm -rf "$d"
        echo -e "  ${C_GREEN}✔ Directorio eliminado: ${d}${C_RESET}"
    fi
done

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
