#!/usr/bin/env bash
# ==============================================================================
# LIMPIEZA DE EMERGENCIA / MANUAL: Lab 3.30 (Podman Pod DOOM en navegador)
# Uso:
#   ./limpiar_doom_podman_browser.sh        # Borra Pod y volumen (conserva imagen en caché)
#   ./limpiar_doom_podman_browser.sh --rmi  # Borra también localhost/lab-graficos-doom:latest
# ==============================================================================
set -uo pipefail

POD_NAME="lab-doom-graficos"
VOL_NAME="lab-doom-x11"
IMAGE_NAME="localhost/lab-graficos-doom:latest"

podman pod rm -f "${POD_NAME}" 2>/dev/null || true
podman volume rm -f "${VOL_NAME}" 2>/dev/null || true

if [[ "${1:-}" == "--rmi" || "${1:-}" == "--all" ]]; then
    podman rmi -f "${IMAGE_NAME}" 2>/dev/null || true
    echo "✅ Limpieza completa del Lab 3.30 (Pod, volumen e imagen ${IMAGE_NAME}) finalizada."
else
    echo "✅ Limpieza del Lab 3.30 (Pod ${POD_NAME} y volumen ${VOL_NAME}) finalizada. Imagen en caché conservada (0 MB RAM)."
fi
