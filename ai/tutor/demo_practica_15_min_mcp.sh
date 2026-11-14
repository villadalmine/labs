#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN Y PRUEBA: Práctica de 15 minutos — tu primer servidor MCP
# Guía: ai/tutor/PRACTICA_15_MIN_MCP.md
#
# Recorre los mismos pasos que la guía y comprueba cada resultado:
#  1. Levanta el MCP de los labs con hub.py y lo verifica.
#  2. Le habla a mano por HTTP: initialize, tools/list y tools/call.
#  3. Muestra el comando para conectar un agente (Claude Code).
#  4. Reto 1: servidor con herramientas ocultas (--exclude-tools).
#  5. Reto 2: servidor protegido con token (MCP_HTTP_TOKEN).
#  - Limpieza garantizada al finalizar (trap cleanup).
#  - Sale con código 0 si todo dio OK y 1 si algo falló (sirve como test).
#
# Uso (desde la raíz del repo):
#   ./ai/tutor/demo_practica_15_min_mcp.sh          -> Modo interactivo (pausa con [ENTER])
#   ./ai/tutor/demo_practica_15_min_mcp.sh --auto 0 -> Modo desatendido (para probar o en CI)
#   ./ai/tutor/demo_practica_15_min_mcp.sh --clean  -> Solo baja los servidores que hayan quedado
# Requisitos: python3, curl. Puertos libres: 8091 y 8095.
# ==============================================================================

set -uo pipefail

AUTO_MODE=false
AUTO_WAIT=0
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto) AUTO_MODE=true; AUTO_WAIT="${2:-2}"; shift 2 ;;
        --clean|--limpiar) CLEAN_ONLY=true; shift ;;
        --help|-h)
            echo "Uso: ./ai/tutor/demo_practica_15_min_mcp.sh [--auto <segundos>] [--clean|--limpiar]"
            exit 0 ;;
        *) echo "Opción desconocida: $1 (ver --help)"; exit 2 ;;
    esac
done

C_RESET="\033[0m"; C_BOLD="\033[1m"; C_GREEN="\033[0;32m"; C_RED="\033[0;31m"
C_YELLOW="\033[1;33m"; C_CYAN="\033[0;36m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HUB="$REPO_ROOT/ai/tutor/hub/hub.py"
SERVER="$REPO_ROOT/ai/tutor/mcp/labs_mcp_server.py"
URL="http://127.0.0.1:8091/mcp"
URL_RETO="http://127.0.0.1:8095/mcp"
TOKEN="clase123"
RETO_PID=""
FALLAS=0

cleanup() {
    [ -n "$RETO_PID" ] && kill "$RETO_PID" 2>/dev/null
    python3 "$HUB" down labs >/dev/null 2>&1 || true
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    pkill -f "labs_mcp_server.py --transport http --port 8095" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Servidores de la práctica detenidos.${C_RESET}"
    exit 0
fi
trap cleanup EXIT INT TERM

paso() {
    echo -e "\n${C_BOLD}${C_CYAN}━━ $1 ━━${C_RESET}"
}
pausa() {
    if [ "$AUTO_MODE" = true ]; then sleep "$AUTO_WAIT"; else read -r -p "   [ENTER] para seguir..." _; fi
}
ok()    { echo -e "   ${C_GREEN}✔ $1${C_RESET}"; }
falla() { echo -e "   ${C_RED}✘ $1${C_RESET}"; FALLAS=$((FALLAS + 1)); }

# Llamada JSON-RPC por HTTP. $1 url, $2 cuerpo JSON, $3 cabecera extra opcional.
rpc() {
    local extra=()
    [ -n "${3:-}" ] && extra=(-H "$3")
    curl -s -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
         "${extra[@]}" "$1" -d "$2"
}
codigo_http() {
    local extra=()
    [ -n "${3:-}" ] && extra=(-H "$3")
    curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" \
         -H "Accept: application/json, text/event-stream" "${extra[@]}" "$1" -d "$2"
}
# Lee JSON por stdin y evalúa una expresión de Python sobre él (variable d).
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
esperar_puerto() {
    for _ in $(seq 1 50); do
        curl -s -o /dev/null "http://127.0.0.1:$1/healthz" && return 0
        sleep 0.2
    done
    return 1
}

echo -e "${C_BOLD}${C_YELLOW}Práctica de 15 minutos: tu primer servidor MCP${C_RESET}"
for bin in python3 curl; do
    command -v "$bin" >/dev/null || { echo -e "${C_RED}Falta $bin.${C_RESET}"; exit 1; }
done

# ------------------------------------------------------------------------------
paso "1. Levantar el servidor (hub.py up labs)"
python3 "$HUB" up labs
if python3 "$HUB" verify labs | grep -q " OK "; then ok "el MCP de labs responde en $URL"; else falla "hub.py verify labs no dio OK"; fi
pausa

# ------------------------------------------------------------------------------
paso "2.1 Presentarse: initialize"
R=$(rpc "$URL" '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"yo","version":"1"}}}')
NOMBRE=$(echo "$R" | jq_py 'd["result"]["serverInfo"]["name"]' 2>/dev/null)
[ "$NOMBRE" = "linux-labs-tutor" ] && ok "el servidor se presenta como: $NOMBRE" || falla "initialize no devolvió serverInfo"
pausa

paso "2.2 Pedir la lista de herramientas: tools/list"
R=$(rpc "$URL" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
echo "$R" | jq_py '"\n".join("     - " + t["name"] for t in d["result"]["tools"])' 2>/dev/null
N=$(echo "$R" | jq_py 'len(d["result"]["tools"])' 2>/dev/null)
[ "${N:-0}" -ge 6 ] && ok "$N herramientas disponibles" || falla "tools/list devolvió ${N:-0} herramientas"
pausa

paso "2.3 Llamar a una herramienta: tools/call search_curriculum(query=RAID)"
R=$(rpc "$URL" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_curriculum","arguments":{"query":"RAID"}}}')
TEXTO=$(echo "$R" | jq_py 'd["result"]["content"][0]["text"]' 2>/dev/null)
echo "$TEXTO" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("     encontrados:", d["total_found"]); [print("     -", l["id"]) for l in d["labs"][:3]]' 2>/dev/null
echo "$TEXTO" | grep -q '"lab-3.8-raid-mdadm"' && ok "la búsqueda trae lab-3.8-raid-mdadm" || falla "search_curriculum no encontró lab-3.8-raid-mdadm"
pausa

# ------------------------------------------------------------------------------
paso "3. Conectar un agente"
CMD=$(python3 "$HUB" config claude-code | grep -m1 'claude mcp add')
echo "     $CMD"
[[ "$CMD" == *"$URL"* ]] && ok "hub.py config claude-code da el comando para conectar el agente" || falla "hub.py config claude-code no dio el comando esperado"
echo "     (con un agente instalado: pegá ese comando y preguntale por los labs de RAID)"
pausa
python3 "$HUB" down labs >/dev/null

# ------------------------------------------------------------------------------
paso "4. Reto 1: esconder herramientas (--exclude-tools)"
python3 "$SERVER" --transport http --port 8095 --exclude-tools get_progressive_hint,read_lab_guide >/dev/null 2>&1 &
RETO_PID=$!
if esperar_puerto 8095; then
    N=$(rpc "$URL_RETO" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq_py 'len(d["result"]["tools"])' 2>/dev/null)
    echo "     herramientas visibles: ${N:-?}"
    R=$(rpc "$URL_RETO" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_progressive_hint","arguments":{"lab_id":"lab-3.8-raid-mdadm","hint_level":1}}}')
    BLOQ=$(echo "$R" | jq_py 'd["result"].get("isError")' 2>/dev/null)
    [ "${N:-0}" -eq 5 ] && [ "$BLOQ" = "True" ] && ok "quedan 5 herramientas y llamar a una oculta falla" \
        || falla "esperaba 5 herramientas y la oculta bloqueada (vi ${N:-?} y isError=$BLOQ)"
else
    falla "el servidor del reto 1 no arrancó en el puerto 8095"
fi
kill "$RETO_PID" 2>/dev/null; wait "$RETO_PID" 2>/dev/null; RETO_PID=""
pausa

# ------------------------------------------------------------------------------
paso "5. Reto 2: ponerle llave (MCP_HTTP_TOKEN)"
MCP_HTTP_TOKEN="$TOKEN" python3 "$SERVER" --transport http --port 8095 >/dev/null 2>&1 &
RETO_PID=$!
if esperar_puerto 8095; then
    SIN=$(codigo_http "$URL_RETO" '{"jsonrpc":"2.0","id":1,"method":"ping"}')
    CON=$(codigo_http "$URL_RETO" '{"jsonrpc":"2.0","id":1,"method":"ping"}' "Authorization: Bearer $TOKEN")
    echo "     sin token: HTTP $SIN | con token: HTTP $CON"
    [ "$SIN" = "401" ] && [ "$CON" = "200" ] && ok "sin token se rechaza (401) y con token entra (200)" \
        || falla "esperaba 401 y 200"
else
    falla "el servidor del reto 2 no arrancó en el puerto 8095"
fi

# ------------------------------------------------------------------------------
echo
if [ "$FALLAS" -eq 0 ]; then
    echo -e "${C_BOLD}${C_GREEN}TODO OK: la práctica funciona en esta máquina.${C_RESET}"
    exit 0
fi
echo -e "${C_BOLD}${C_RED}$FALLAS paso(s) fallaron: revisá los ✘ de arriba.${C_RESET}"
exit 1
