#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio 3.25 (Seguridad del Kernel y eBPF)
# Referencia: linux/administrator/kernel/seguridad_ataques_kernel_ebpf.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de Lab 3.25 (Seguridad Kernel y eBPF)...${C_RESET}"

sysctl -w kernel.kptr_restrict=2 >/dev/null 2>&1 || true
sysctl -w kernel.dmesg_restrict=1 >/dev/null 2>&1 || true
sysctl -w kernel.randomize_va_space=2 >/dev/null 2>&1 || true
sysctl -w fs.protected_symlinks=1 >/dev/null 2>&1 || true

if [ -d /tmp/lab_demo_sec_ebpf ]; then
    rm -rf /tmp/lab_demo_sec_ebpf
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_sec_ebpf${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
