#!/usr/bin/env bash
# ==============================================================================
# limpiar_monitoreo_clasico.sh - Saneamiento idempotente del monitoreo clásico
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

LAB_DIR="/tmp/classic_monitoring"

echo -e "${YELLOW}🧹 Iniciando saneamiento de monitoreo clásico...${NC}"

# 1. Terminar procesos en segundo plano
pkill -f "statsd_collectd_mini.py" 2>/dev/null || true

# 2. Purgar archivos temporales y CSVs
if [ -d "${LAB_DIR}" ]; then
    rm -rf "${LAB_DIR}"
    echo -e "${GREEN}✓ Directorio ${LAB_DIR} purgado.${NC}"
fi

echo -e "${GREEN}${BOLD}✅ Saneamiento completado. Entorno limpio.${NC}"
