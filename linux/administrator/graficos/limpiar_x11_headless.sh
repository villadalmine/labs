#!/usr/bin/env bash
# ==============================================================================
# LIMPIEZA DE EMERGENCIA / MANUAL: Lab 3.27 (X11 Headless con Xvfb)
# ==============================================================================
set -uo pipefail

pkill -f "xclock -geometry 220x220\+40\+40" 2>/dev/null || true
pkill -f "Xvfb :99" 2>/dev/null || true
rm -rf /tmp/lab_x11_headless

echo "✅ Limpieza del Lab 3.27 (Xvfb :99 y /tmp/lab_x11_headless) completada."
