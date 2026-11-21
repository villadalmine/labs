#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: rsyslog Avanzado (Lab 3.21)
# Referencia: linux/administrator/logs/rsyslog_filtrado_plantillas_tls_colas.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio rsyslog Avanzado (Lab 3.21)...${C_RESET}"

DIR_LAB="/var/spool/rsyslog/lab_demo_rsyslog"
LOG_DIR="/var/log/lab_demo_rsyslog"
for pf in "${DIR_LAB}/rsyslog_cli.pid" "${DIR_LAB}/rsyslog_srv.pid" "/tmp/lab_demo_rsyslog/rsyslog_cli.pid" "/tmp/lab_demo_rsyslog/rsyslog_srv.pid"; do
    if [ -f "$pf" ]; then
        p=$(cat "$pf" 2>/dev/null || true)
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
            sleep 0.3
            kill -9 "$p" 2>/dev/null || true
        fi
    fi
done
pkill -f "lab_demo_rsyslog/rsyslog_" 2>/dev/null || true

for d in "$DIR_LAB" "$LOG_DIR" "/tmp/lab_demo_rsyslog"; do
    if [ -d "$d" ]; then
        rm -rf "$d"
        echo -e "  ${C_GREEN}✔ Directorio eliminado: ${d}${C_RESET}"
    fi
done

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
