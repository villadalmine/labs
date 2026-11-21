#!/usr/bin/env bash
# ==============================================================================
# LIMPIEZA DE EMERGENCIA / MANUAL: Lab 3.28 (Acceso Gráfico Remoto)
# ==============================================================================
set -uo pipefail

pkill -f "lab_gui_remoto/sshd_config" 2>/dev/null || true
pkill -f "15901:127.0.0.1:25901" 2>/dev/null || true
pkill -f "lab_gui_remoto/rfb_sim.py" 2>/dev/null || true
pkill -f "Xvfb :98" 2>/dev/null || true

if command -v xauth >/dev/null 2>&1; then
    xauth remove localhost:50 2>/dev/null || true
fi

rm -rf /tmp/lab_gui_remoto

echo "✅ Limpieza del Lab 3.28 (sshd :22230, túneles, Xvfb :98 y /tmp/lab_gui_remoto) completada."
