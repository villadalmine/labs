#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EN CLASE: CLUSTER AWS MULTI-NODO (PROMETHEUS + GRAFANA + NTFY)
# - Levanta o reutiliza el cluster en AWS (3 nodos EC2 + EBS LVM RAID 1 + LUKS2)
# - Verifica telemetría en Prometheus (:9090), Grafana (:3000), Alertmanager (:9093)
# - Muestra en vivo cómo la caída de un disco RAID 1 o el cierre de LUKS2:
#     1. Cambia las métricas de 1 a 0 en 3 segundos ( vía Systemd Timers )
#     2. Mantiene el sitio web Nginx ONLINE (HTTP 200 - Zero Downtime)
#     3. Dispara alertas en el SRE Alert Hub Web (:9999) y push en vivo a ntfy.sh
# - Repara en caliente ambos nodos y verifica la notificación RESOLVED
# - ESTÁNDAR PEDAGÓGICO: Muestra SIEMPRE el comando exacto ejecutado antes
#   de imprimir la salida del sistema para que los alumnos entiendan qué se ejecutó.
#
# Uso:
#   ./demo_aws_clase.sh              -> Modo interactivo para clase (pausa con ENTER)
#   ./demo_aws_clase.sh --auto 3     -> Modo automático (espera 3s entre pasos)
#   ./demo_aws_clase.sh --destroy    -> Al finalizar destruye toda la infra en AWS
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AUTO_WAIT=0
DESTROY_AT_END=0
STOP_ON_BREAK=0
REPAIR_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-3}"
            shift 2
            ;;
        --destroy)
            DESTROY_AT_END=1
            shift
            ;;
        --break-only)
            STOP_ON_BREAK=1
            shift
            ;;
        --repair-only)
            REPAIR_ONLY=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[1;32m"
C_CYAN="\033[1;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[1;31m"
C_BLUE="\033[1;34m"

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar con el siguiente paso...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_DIM}⏳ [MODO AUTO] Continuando en ${AUTO_WAIT}s... (${msg})${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo ""
        read -rp "👉 ${msg} " _
    fi
}

banner() {
    echo -e "\n${C_CYAN}════════════════════════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_MAGENTA}  $1${C_RESET}"
    echo -e "${C_CYAN}════════════════════════════════════════════════════════════════════════════════════════${C_RESET}"
}

SSH_OPTS="-i ${SCRIPT_DIR}/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"

# ==============================================================================
# HELPERS PEDAGÓGICOS: MOSTRAR COMANDO EJECUTADO + SALIDA REAL
# ==============================================================================
run_cmd() {
    local label="$1"
    local cmd="$2"

    echo -e "\n${C_CYAN}┌─── [${label}] COMANDO A EJECUTAR ──────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_CYAN}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"
    local output
    output=$(eval "$cmd" 2>&1) || true
    if [ -z "$output" ]; then
        echo -e "${C_DIM}(Comando ejecutado exitosamente sin salida en stdout/stderr)${C_RESET}"
    else
        echo "$output"
    fi
    echo -e "${C_CYAN}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

run_cmd_stream() {
    local label="$1"
    local cmd="$2"

    echo -e "\n${C_CYAN}┌─── [${label}] COMANDO A EJECUTAR ──────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_CYAN}├─── SALIDA EN TIEMPO REAL ─────────────────────────────────────────────────────────┤${C_RESET}"
    eval "$cmd"
    echo -e "${C_CYAN}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

run_ssh() {
    local node_label="$1"
    local host_ip="$2"
    local remote_cmd="$3"

    echo -e "\n${C_CYAN}┌─── [${node_label}] COMANDO A EJECUTAR ──────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${remote_cmd}${C_RESET}"
    echo -e "${C_CYAN}├─── SALIDA REAL DEL NODO ──────────────────────────────────────────────────────────┤${C_RESET}"
    local output
    output=$(ssh $SSH_OPTS "ubuntu@${host_ip}" "${remote_cmd}" 2>&1) || true
    if [ -z "$output" ]; then
        echo -e "${C_DIM}(Comando ejecutado exitosamente sin salida en stdout/stderr)${C_RESET}"
    else
        echo "$output"
    fi
    echo -e "${C_CYAN}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

# ==============================================================================
# PASO 1: APROVISIONAMIENTO / VERIFICACIÓN DE TERRAFORM
# ==============================================================================
banner "🚀 PASO 1: APROVISIONAMIENTO / VERIFICACIÓN DEL CLUSTER EN AWS (TERRAFORM)"
if [ ! -d ".terraform" ]; then
    run_cmd_stream "Local Host" "terraform init"
fi

IP_CENTRAL=$(terraform output -raw prometheus_url 2>/dev/null | sed -E 's|http://([^:]+):.*|\1|' || true)
if [ -z "$IP_CENTRAL" ] || [[ "$IP_CENTRAL" == *"Warning"* ]]; then
    echo -e "${C_YELLOW}⚡ Desplegando cluster de 3 instancias EC2 en AWS...${C_RESET}"
    run_cmd_stream "Local Host" "terraform apply -auto-approve"
fi

IP_CENTRAL=$(terraform output -raw prometheus_url | sed -E 's|http://([^:]+):.*|\1|')
IP_WEB=$(terraform output -raw web_service_url | sed -E 's|http://||')
IP_LUKS=$(terraform output -raw ssh_srv_data_luks | awk -F'@' '{print $2}')
NTFY_URL=$(terraform output -raw ntfy_topic_url)
GRAFANA_URL=$(terraform output -raw grafana_url)
PROM_URL=$(terraform output -raw prometheus_url)
ALERTMANAGER_URL=$(terraform output -raw alertmanager_url)
HUB_URL=$(terraform output -raw alert_hub_web_url)

echo -e "\n${C_GREEN}✔ Infraestructura activa en AWS:${C_RESET}"
echo -e "  • ${C_BOLD}Grafana Dashboard :${C_RESET} ${C_CYAN}${GRAFANA_URL}${C_RESET}"
echo -e "  • ${C_BOLD}Prometheus UI     :${C_RESET} ${C_CYAN}${PROM_URL}${C_RESET}"
echo -e "  • ${C_BOLD}Alertmanager UI   :${C_RESET} ${C_CYAN}${ALERTMANAGER_URL}${C_RESET}"
echo -e "  • ${C_BOLD}SRE Alert Hub Web :${C_RESET} ${C_CYAN}${HUB_URL}${C_RESET}"
echo -e "  • ${C_BOLD}Canal Push ntfy.sh:${C_RESET} ${C_CYAN}${NTFY_URL}${C_RESET}"
echo -e "  • ${C_BOLD}Web Productiva LVM:${C_RESET} ${C_CYAN}http://${IP_WEB}${C_RESET}"

echo -e "\n${C_YELLOW}⏳ Esperando a que cloud-init finalice la configuración en los 3 nodos...${C_RESET}"
for host in "$IP_CENTRAL" "$IP_WEB" "$IP_LUKS"; do
    until ssh $SSH_OPTS "ubuntu@${host}" "cloud-init status --wait >/dev/null 2>&1" 2>/dev/null; do
        sleep 3
    done
done
echo -e "${C_GREEN}✔ Los 3 nodos completaron cloud-init exitosamente.${C_RESET}"

if [ "$REPAIR_ONLY" -eq 0 ]; then
pause_step "Abrí en el navegador Grafana, el SRE Alert Hub (:9999) y ntfy.sh. Presioná [ENTER] para verificar el estado inicial sano"

# ==============================================================================
# PASO 2: VERIFICACIÓN DEL ESTADO INICIAL SANO
# ==============================================================================
banner "🟢 PASO 2: VERIFICACIÓN DE ESTADO INICIAL SANO (3 NODOS UP, LVM=1, LUKS=1)"

echo -e "${C_BOLD}1. Estado de Nodos y Exporters en Prometheus Central:${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | \"   • Job: \" + .labels.job + \" (\" + .discoveredLabels.__address__ + \") -> \" + (.health | ascii_upcase)'"

echo -e "\n${C_BOLD}2. Estado del Espejo LVM RAID 1 en Worker 1:${C_RESET}"
run_ssh "Worker 1 - Web LVM (${IP_WEB})" "$IP_WEB" "sudo lvs -o lv_name,vg_name,attr,health_status,copy_percent vg_web/lv_html"

echo -e "\n${C_BOLD}3. Estado del Contenedor Cifrado LUKS2 en Worker 2:${C_RESET}"
run_ssh "Worker 2 - Datos LUKS (${IP_LUKS})" "$IP_LUKS" "sudo cryptsetup status datos_seguros | head -n 5"

echo -e "\n${C_BOLD}4. Consultando métricas de salud en la API de Prometheus:${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s 'http://localhost:9090/api/v1/query?query=node_lvm_mirror_health' | jq -r '.data.result[] | \"   • node_lvm_mirror_health = \" + .value[1] + \" (1 = SANO)\"'"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s 'http://localhost:9090/api/v1/query?query=node_luks_container_active' | jq -r '.data.result[] | \"   • node_luks_container_active = \" + .value[1] + \" (1 = SANO / ABIERTO)\"'"

LVM_VAL=$(ssh $SSH_OPTS "ubuntu@${IP_CENTRAL}" "curl -s 'http://localhost:9090/api/v1/query?query=node_lvm_mirror_health' | jq -r '.data.result[0].value[1]'")
LUKS_VAL=$(ssh $SSH_OPTS "ubuntu@${IP_CENTRAL}" "curl -s 'http://localhost:9090/api/v1/query?query=node_luks_container_active' | jq -r '.data.result[0].value[1]'")
echo -e "\n${C_GREEN}📊 Estado Inicial:${C_RESET} node_lvm_mirror_health = ${C_BOLD}${LVM_VAL}${C_RESET} | node_luks_container_active = ${C_BOLD}${LUKS_VAL}${C_RESET}"

pause_step "Presioná [ENTER] para INYECTAR LA FALLA DE DISCO EN LVM RAID 1 (dd sobre /dev/nvme1n1)"

# ==============================================================================
# PASO 3: CAOS 1 — DESTRUCCIÓN DE UN DISCO DEL ESPEJO LVM RAID 1
# ==============================================================================
banner "💥 PASO 3: CAOS 1 — DESTRUCCIÓN DE UN DISCO DEL ESPEJO LVM RAID 1 EN CALIENTE"

echo -e "${C_RED}⚡ Inyectando corrupción de bloques sobre el primer disco del RAID 1 en Worker 1:${C_RESET}"
run_ssh "Worker 1 - Web LVM (${IP_WEB})" "$IP_WEB" "sudo dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=10 conv=notrunc"

echo -e "\n${C_YELLOW}⏳ Esperando 6 segundos para que el timer de Systemd (3s), Prometheus (2s) y Alertmanager disparen la alerta...${C_RESET}"
sleep 6

echo -e "\n${C_BOLD}1. Verificando continuidad del servicio Web Nginx desde el exterior:${C_RESET}"
run_cmd "Local Host" "curl -i -s http://${IP_WEB}/ | head -n 5"

echo -e "\n${C_BOLD}2. Consultando métrica degradada en la API de Prometheus:${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s 'http://localhost:9090/api/v1/query?query=node_lvm_mirror_health' | jq -r '.data.result[] | \"   • node_lvm_mirror_health = \" + .value[1] + \" (0 = DEGRADADO / ALERTA FIRING)\"'"

echo -e "\n${C_BOLD}3. Consultando eventos activos en la API del SRE Alert Hub (${HUB_URL}):${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s http://localhost:9999/api/events | jq -r '.events[:2][] | \"   • [\" + .status + \"] \" + .time + \" -> \" + .summary'"

pause_step "Mirá el cartel ROJO en Grafana, en el Alert Hub (:9999) y la notificación en ${NTFY_URL}. Presioná [ENTER] para CERRAR LA BÓVEDA LUKS2"

# ==============================================================================
# PASO 4: CAOS 2 — BLOQUEO Y CIERRE DE EMERGENCIA DE LUKS2
# ==============================================================================
banner "🔐 PASO 4: CAOS 2 — BLOQUEO Y CIERRE DE EMERGENCIA DE LA BÓVEDA CIFRADA LUKS2"

echo -e "${C_RED}⚡ Desmontando filesystem seguro y cerrando mapper LUKS2 en Worker 2:${C_RESET}"
run_ssh "Worker 2 - Datos LUKS (${IP_LUKS})" "$IP_LUKS" "sudo umount /data/segura && sudo cryptsetup close datos_seguros"

echo -e "\n${C_YELLOW}⏳ Esperando 6 segundos para que el timer de Systemd y Prometheus detecten el cierre...${C_RESET}"
sleep 6

echo -e "\n${C_BOLD}1. Consultando métrica de LUKS en la API de Prometheus luego del cierre:${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s 'http://localhost:9090/api/v1/query?query=node_luks_container_active' | jq -r '.data.result[] | \"   • node_luks_container_active = \" + .value[1] + \" (0 = CERRADO / BLOQUEADO)\"'"

echo -e "\n${C_BOLD}2. Últimos eventos recibidos en el SRE Alert Hub (${HUB_URL}):${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s http://localhost:9999/api/events | jq -r '.events[:3][] | \"   • [\" + .status + \"] \" + .time + \" -> \" + .summary'"

if [ "$STOP_ON_BREAK" -eq 1 ]; then
    echo -e "\n${C_RED}${C_BOLD}🔥 CLUSTER EN ESTADO ROTO (ALERTAS FIRING EN VIVO)${C_RESET}"
    echo -e "  • ${C_BOLD}Grafana (en ROJO)   :${C_RESET} ${C_CYAN}${GRAFANA_URL}${C_RESET}"
    echo -e "  • ${C_BOLD}SRE Alert Hub (:9999):${C_RESET} ${C_CYAN}${HUB_URL}${C_RESET}"
    echo -e "  • ${C_BOLD}Alertmanager (:9093) :${C_RESET} ${C_CYAN}${ALERTMANAGER_URL}${C_RESET}"
    echo -e "  • ${C_BOLD}ntfy.sh Push         :${C_RESET} ${C_CYAN}${NTFY_URL}${C_RESET}"
    echo -e "  • ${C_BOLD}Web Nginx (200 OK)   :${C_RESET} ${C_CYAN}http://${IP_WEB}${C_RESET}\n"
    exit 0
fi

pause_step "Presioná [ENTER] para EJECUTAR LA REPARACIÓN EN CALIENTE (Hot-Repair de LVM RAID 1 + Reapertura LUKS2)"
fi

# ==============================================================================
# PASO 5: REPARACIÓN EN CALIENTE (HOT-REPAIR) Y AUTORRESOLUCIÓN
# ==============================================================================
banner "🛠️ PASO 5: REPARACIÓN EN CALIENTE (HOT-REPAIR) Y AUTORRESOLUCIÓN DE ALERTAS"

echo -e "${C_GREEN}🔧 1. Reconstruyendo espejo LVM RAID 1 en Worker 1 (vgreduce + pvcreate + vgextend + lvconvert):${C_RESET}"
run_ssh "Worker 1 - Web LVM (${IP_WEB})" "$IP_WEB" "sudo vgreduce -y --removemissing --force vg_web && sudo pvcreate -y -ff /dev/nvme1n1 && sudo vgextend vg_web /dev/nvme1n1 && sudo lvconvert -y --repair vg_web/lv_html"

echo -e "\n${C_GREEN}🔓 2. Reabriendo contenedor LUKS2 con llave criptográfica y remontando en Worker 2:${C_RESET}"
run_ssh "Worker 2 - Datos LUKS (${IP_LUKS})" "$IP_LUKS" "sudo cryptsetup open --key-file /root/luks.key /dev/nvme1n1 datos_seguros && sudo mount /dev/mapper/datos_seguros /data/segura"

echo -e "\n${C_YELLOW}⏳ Esperando 6 segundos para propagación de métricas y disparo de alertas RESOLVED...${C_RESET}"
sleep 6

echo -e "\n${C_BOLD}3. Consultando métricas recuperadas en la API de Prometheus:${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s 'http://localhost:9090/api/v1/query?query=node_lvm_mirror_health' | jq -r '.data.result[] | \"   • node_lvm_mirror_health = \" + .value[1] + \" (1 = SANO / RESOLVED)\"'"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s 'http://localhost:9090/api/v1/query?query=node_luks_container_active' | jq -r '.data.result[] | \"   • node_luks_container_active = \" + .value[1] + \" (1 = SANO / ABIERTO / RESOLVED)\"'"

echo -e "\n${C_BOLD}4. Historial completo de eventos en SRE Alert Hub (${HUB_URL}) y ntfy.sh (${NTFY_URL}):${C_RESET}"
run_ssh "Prometheus Central (${IP_CENTRAL})" "$IP_CENTRAL" "curl -s http://localhost:9999/api/events | jq -r '.events[:6][] | \"   • [\" + .status + \"] \" + .time + \" -> \" + .summary'"

# ==============================================================================
# PASO 6: DESTRUCCIÓN O CIERRE
# ==============================================================================
if [ "$DESTROY_AT_END" -eq 1 ]; then
    banner "🧹 PASO 6: DESTRUYENDO INFRAESTRUCTURA EN AWS (--destroy)"
    run_cmd_stream "Local Host" "terraform destroy -auto-approve"
else
    echo -e "\n${C_GREEN}✨ Demo completada. El cluster sigue activo para explorar en el navegador.${C_RESET}"
    echo -e "   Para destruir todo al terminar la clase: ${C_BOLD}./demo_aws_clase.sh --destroy${C_RESET} o ${C_BOLD}terraform destroy -auto-approve${C_RESET}\n"
fi
