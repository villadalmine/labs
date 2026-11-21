#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE LIMPIEZA: Laboratorio 3.24 (Compilación de Kernel e initramfs QEMU)
# Referencia: linux/administrator/kernel/compilacion_kernel_initramfs.md
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"

echo -e "\n${C_BOLD}${C_YELLOW}🧹 Limpiando entorno de Lab 3.24 (Compilación e initramfs QEMU)...${C_RESET}"

umount /tmp/lab_demo_kernel_initramfs/mnt_root 2>/dev/null || true

if [ -d /tmp/lab_demo_kernel_initramfs ]; then
    rm -rf /tmp/lab_demo_kernel_initramfs
    echo -e "  ${C_GREEN}✔ Directorio eliminado: /tmp/lab_demo_kernel_initramfs${C_RESET}"
fi

echo -e "\n${C_BOLD}${C_GREEN}✔ Limpieza completada con éxito.${C_RESET}\n"
