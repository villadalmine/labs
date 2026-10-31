#!/usr/bin/env bash
# ==============================================================================
# demo_ai_sre.sh - Demostración Interactiva de AI SRE y Autorremediación
#
# Simula un incidente real en Linux (caída de servicio y acumulación de inodos)
# e invoca al agente de IA para realizar diagnóstico forense y autorremediación.
# ==============================================================================
set -euo pipefail

# --- Colores ANSI ---
BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SCRIPT="${SCRIPT_DIR}/scripts/ai_sre_agent.py"
LAB_DIR="/tmp/ai_sre_lab"
PORT_WEB=8080
PORT_METRICS=9100

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║          🧪 DEMOSTRACIÓN PRÁCTICA: AI SRE & AGENTES AUTÓNOMOS               ║"
echo "║     Diagnóstico Causal, Protocolo MCP y Remediación en Caliente en Linux    ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. Preparación del Entorno
echo -e "${YELLOW}▶ [PASO 1/5] Preparando entorno de prueba en ${LAB_DIR}...${NC}"
mkdir -p "${LAB_DIR}/web"
mkdir -p "${LAB_DIR}/metrics"
mkdir -p "${LAB_DIR}/tmp_storage"

echo "<h1>Servicio Web Corporativo - Estado Operativo Normal</h1>" > "${LAB_DIR}/web/index.html"

# Iniciar servidor web de prueba en segundo plano
if ! pgrep -f "python3 -m http.server ${PORT_WEB}" >/dev/null 2>&1; then
    (cd "${LAB_DIR}/web" && nohup python3 -m http.server "${PORT_WEB}" >/dev/null 2>&1 &)
    echo -e "${GREEN}✓ Servidor web de producción iniciado en puerto :${PORT_WEB}.${NC}"
else
    echo -e "${GREEN}✓ Servidor web ya activo en puerto :${PORT_WEB}.${NC}"
fi

# Generar archivo de métricas simulado para Node Exporter / Agente
cat << 'EOF' > "${LAB_DIR}/metrics/system.prom"
# HELP lvm_mirror_health Estado de salud del arreglo RAID 1 (1 = Ok, 0 = Degradado)
# TYPE lvm_mirror_health gauge
lvm_mirror_health 1
# HELP web_service_status Estado del servicio web (1 = Up, 0 = Down)
# TYPE web_service_status gauge
web_service_status 1
EOF

# Iniciar Node Exporter si existe el binario o un mock HTTP
if [ -f "/tmp/node_exporter" ]; then
    if ! pgrep -f "node_exporter" >/dev/null 2>&1; then
        nohup /tmp/node_exporter --collector.textfile.directory="${LAB_DIR}/metrics" --web.listen-address=":${PORT_METRICS}" >/dev/null 2>&1 &
        echo -e "${GREEN}✓ Node Exporter activo en puerto :${PORT_METRICS}.${NC}"
    fi
fi

sleep 1

# 2. Inyección de Falla Controlada
echo -e "\n${RED}${BOLD}▶ [PASO 2/5] Inyectando Falla Controlada (Caída de Servicio Web)...${NC}"
pkill -f "python3 -m http.server ${PORT_WEB}" 2>/dev/null || true
echo -e "${RED}⚠️  El proceso web fue detenido intencionalmente. Los clientes reciben 'Connection Refused'.${NC}"

# Actualizar métrica a estado degradado
sed -i 's/web_service_status 1/web_service_status 0/g' "${LAB_DIR}/metrics/system.prom" 2>/dev/null || true

# 3. Invocación de Fase 1: Triage y Diagnóstico Forense
echo -e "\n${CYAN}${BOLD}▶ [PASO 3/5] Invocando AI SRE Agent en modo Triage Forense...${NC}"
python3 "${AGENT_SCRIPT}" --triage

# 4. Invocación de Fase 2: Formulación del Plan con Guardrails
echo -e "\n${CYAN}${BOLD}▶ [PASO 4/5] Generando Plan de Remediación con Validación de Seguridad...${NC}"
python3 "${AGENT_SCRIPT}" --plan

# 5. Invocación de Fase 3: Ejecución de Remediación
echo -e "\n${GREEN}${BOLD}▶ [PASO 5/5] Ejecutando Remediación Automática (Self-Healing)...${NC}"
python3 "${AGENT_SCRIPT}" --remediate --auto

# 6. Verificación Final de Disponibilidad
echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}✓ VERIFICACIÓN FINAL DE DISPONIBILIDAD:${NC}"
if curl -s "http://127.0.0.1:${PORT_WEB}" | grep -q "Servicio Web Corporativo"; then
    echo -e "  ${GREEN}✅ Servicio Web restaurado exitosamente en http://127.0.0.1:${PORT_WEB}${NC}"
else
    echo -e "  ${YELLOW}⚠️ Servicio en proceso de reanudación.${NC}"
fi

echo -e "\n${CYAN}💡 Demostración completada. Ejecute './limpiar_ai_sre.sh' para purgar procesos y archivos temporales.${NC}"
