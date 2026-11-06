#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio Anacron y at
# Referencia: linux/administrator/automatizacion/anacron_at_tareas_asincronas.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de laboratorio de Anacron y at...${C_RESET}"

for dir in /tmp/lab_anacron /tmp/lab_demo_anacron_at; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        echo -e "  ${C_GREEN}✔ Directorio eliminado: ${dir}${C_RESET}"
    fi
done

if command -v atq &>/dev/null && command -v atrm &>/dev/null; then
    for jid in $(atq 2>/dev/null | awk '{print $1}'); do
        atrm "$jid" 2>/dev/null || true
    done
    echo -e "  ${C_GREEN}✔ Cola de trabajos 'at' limpiada.${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
