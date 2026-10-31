#!/usr/bin/env bash
# ==============================================================================
# Script de Limpieza Completa: Cluster de Monitoreo Centralizado Multi-Nodo
# Desmantela procesos de Prometheus, Node Exporters, Web Server, contenedores
# LUKS, volúmenes LVM y loop devices temporales.
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Se requieren privilegios de superusuario (sudo).\033[0m"
    exit 1
fi

echo -e "\033[1;33m🧹 [LIMPIEZA] Desmantelando cluster multi-nodo...\033[0m"

# Detener procesos
pkill -f "python3 -m http.server 8081" 2>/dev/null || true
pkill -f "web.listen-address=:9101" 2>/dev/null || true
pkill -f "web.listen-address=:9102" 2>/dev/null || true
pkill -f "config.file=/tmp/cluster_monitoreo/central/prometheus.yml" 2>/dev/null || true

# Desmontar filesystems
umount -f /tmp/cluster_monitoreo/node1_web/mnt 2>/dev/null || true
umount -f /tmp/cluster_monitoreo/node2_luks/mnt 2>/dev/null || true

# Cerrar LUKS
if [ -e "/dev/mapper/datos_seguros_multi" ]; then
    cryptsetup close datos_seguros_multi 2>/dev/null || true
fi

# Remover LVM
if vgs "vg_multi_web" &>/dev/null; then
    lvchange -an "vg_multi_web" 2>/dev/null || true
    vgremove -f -y "vg_multi_web" 2>/dev/null || true
fi

# Desasociar loop devices asociados a cluster_monitoreo
for loop in $(losetup -a | grep "/tmp/cluster_monitoreo" | cut -d: -f1); do
    pvremove -ff -y "$loop" 2>/dev/null || true
    wipefs -a "$loop" 2>/dev/null || true
    losetup -d "$loop" 2>/dev/null || true
done

rm -rf /tmp/cluster_monitoreo 2>/dev/null || true
rm -f /tmp/node1_exporter.log /tmp/node2_exporter.log /tmp/prometheus_central.log 2>/dev/null || true

echo -e "\033[0;32m✔ Recursos del cluster multi-nodo liberados exitosamente.\033[0m\n"
