#!/usr/bin/env bash
# ==============================================================================
# limpiar_ai_sre.sh - Saneamiento idempotente del laboratorio AI SRE
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

LAB_DIR="/tmp/ai_sre_lab"
PORT_WEB=8080

echo -e "${YELLOW}🧹 Iniciando limpieza del laboratorio AI SRE...${NC}"

# Detener procesos creados durante el lab
pkill -f "python3 -m http.server ${PORT_WEB}" 2>/dev/null || true
pkill -f "ai_sre_agent.py" 2>/dev/null || true

# Limpiar directorio de laboratorio si existe
if [ -d "${LAB_DIR}" ]; then
    rm -rf "${LAB_DIR}"
    echo -e "${GREEN}✓ Directorio temporal ${LAB_DIR} eliminado.${NC}"
fi

# Purgar reportes generados
rm -rf /tmp/ai_sre_reports 2>/dev/null || true

echo -e "${GREEN}${BOLD}✅ Saneamiento completado exitosamente. Entorno limpio.${NC}"
