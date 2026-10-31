#!/usr/bin/env bash
# ==============================================================================
# TUI MONITOR: Panel de Control en Terminal para Clase en Vivo
# Lee telemetría de Node Exporter (:9100) y estado de LVM RAID 1 en tiempo real
# ==============================================================================

set -uo pipefail

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_CYAN="\033[0;36m"
C_BLUE="\033[1;34m"
C_DIM="\033[2m"

VG_NAME="${VG_NAME:-vg_web}"
LV_NAME="${LV_NAME:-lv_html}"
WEB_PORT="${WEB_PORT:-8080}"
NODE_PORT="${NODE_PORT:-9100}"
INTERVAL="${1:-1}"

trap "echo -e '\n${C_RESET}Panel TUI finalizado.'; exit 0" INT TERM

clear 2>/dev/null || true

while true; do
    # 1. Obtener estado de LVM RAID 1
    LVM_HEALTH="DESCONOCIDO"
    LVM_ATTR="------"
    LVM_COLOR="$C_YELLOW"
    
    if command -v lvs &>/dev/null && lvs "${VG_NAME}/${LV_NAME}" &>/dev/null; then
        LVM_STATUS=$(lvs --noheadings -o health_status "${VG_NAME}/${LV_NAME}" 2>/dev/null | tr -d ' ' || true)
        LVM_ATTR=$(lvs --noheadings -o lv_attr "${VG_NAME}/${LV_NAME}" 2>/dev/null | tr -d ' ' || true)
        
        if [ -z "$LVM_STATUS" ] && [[ ! "$LVM_ATTR" =~ ^....p ]]; then
            LVM_HEALTH="🟢 SANO (Mirror Óptimo)"
            LVM_COLOR="$C_GREEN"
        else
            LVM_HEALTH="🔴 DEGRADADO (Fallo de Disco)"
            LVM_COLOR="$C_RED"
        fi
    else
        LVM_HEALTH="⚪ NO MONTADO"
        LVM_COLOR="$C_DIM"
    fi

    # 2. Consultar servicio Web
    WEB_STATUS="🔴 CAÍDO"
    WEB_CODE="---"
    HTTP_REQ="0"
    if curl -s -m 1 "http://localhost:${WEB_PORT}/" >/dev/null 2>&1; then
        WEB_STATUS="🟢 EN LÍNEA (200 OK)"
        WEB_CODE="200"
    fi
    if [ -f /tmp/web_requests.count ]; then
        HTTP_REQ=$(cat /tmp/web_requests.count 2>/dev/null || echo 0)
    fi

    # 3. Consultar Node Exporter (:9100)
    NODE_STATUS="🔴 DESCONECTADO"
    MEM_AVAIL="---"
    FS_AVAIL="---"
    
    METRICS=$(curl -s -m 1 "http://localhost:${NODE_PORT}/metrics" 2>/dev/null || true)
    if [ -n "$METRICS" ]; then
        NODE_STATUS="🟢 ACTIVO (PULL OK)"
        
        # Extraer memoria disponible en MB
        MEM_BYTES=$(echo "$METRICS" | grep -E '^node_memory_MemAvailable_bytes ' | awk '{print $2}' || true)
        if [ -n "$MEM_BYTES" ]; then
            MEM_AVAIL=$(awk -v b="$MEM_BYTES" 'BEGIN {printf "%.0f MB", b/1024/1024}')
        fi

        # Extraer espacio libre en ext4
        FS_BYTES=$(echo "$METRICS" | grep -E 'node_filesystem_avail_bytes\{.*mountpoint="/var/www/html_lab".*\}' | awk '{print $2}' || true)
        if [ -n "$FS_BYTES" ]; then
            FS_AVAIL=$(awk -v b="$FS_BYTES" 'BEGIN {printf "%.0f MB", b/1024/1024}')
        fi
    fi

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Renderizar interfaz gráfica en terminal
    tput cup 0 0 2>/dev/null || clear 2>/dev/null || true
    echo -e "${C_BOLD}${C_BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET} ${C_BOLD}${C_CYAN}📊 TUI DASHBOARD: SERVIDOR WEB SOBRE LVM RAID 1 + NODE EXPORTER${C_RESET}             ${C_BOLD}${C_BLUE}║${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET} ${C_DIM}Hora: ${TIMESTAMP}  |  Refresco: cada ${INTERVAL}s  |  Salir: [Ctrl+C]${C_RESET}              ${C_BOLD}${C_BLUE}║${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET} ${C_BOLD}${C_YELLOW}1. ESTADO DE ALMACENAMIENTO (LVM RAID 1 / dm-raid):${C_RESET}                         ${C_BOLD}${C_BLUE}║${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET}    • Volumen Lógico:   /dev/${VG_NAME}/${LV_NAME} (Espejo de 2 vías)               ${C_BOLD}${C_BLUE}║${C_RESET}"
    printf "${C_BOLD}${C_BLUE}║${C_RESET}    • Salud del Espejo: %-52b ${C_BOLD}${C_BLUE}║${C_RESET}\n" "${LVM_COLOR}${LVM_HEALTH}${C_RESET} (Attr: ${LVM_ATTR})"
    echo -e "${C_BOLD}${C_BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET} ${C_BOLD}${C_YELLOW}2. SERVIDOR WEB EN PRODUCCIÓN (Puerto ${WEB_PORT}):${C_RESET}                                   ${C_BOLD}${C_BLUE}║${C_RESET}"
    printf "${C_BOLD}${C_BLUE}║${C_RESET}    • Estado HTTP:      %-54b ${C_BOLD}${C_BLUE}║${C_RESET}\n" "${WEB_STATUS}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET}    • Tráfico Servido:  ${C_BOLD}${HTTP_REQ}${C_RESET} peticiones recibidas                              ${C_BOLD}${C_BLUE}║${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET} ${C_BOLD}${C_YELLOW}3. AGENTE NODE EXPORTER (Puerto ${NODE_PORT} - Modelo PULL):${C_RESET}                         ${C_BOLD}${C_BLUE}║${C_RESET}"
    printf "${C_BOLD}${C_BLUE}║${C_RESET}    • Endpoint /metrics:%-54b ${C_BOLD}${C_BLUE}║${C_RESET}\n" "${NODE_STATUS}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET}    • RAM Disponible:   ${MEM_AVAIL}                                               ${C_BOLD}${C_BLUE}║${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}║${C_RESET}    • Espacio Web Libre:${FS_AVAIL}                                               ${C_BOLD}${C_BLUE}║${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo -e "${C_DIM}💡  Cuando rompas el disco 1 con dd, mirá cómo cambia${C_RESET}"
    echo -e "${C_DIM}   la fila de Almacenamiento a ROJO pero el Servidor Web SIGUE EN VERDE.${C_RESET}"

    sleep "$INTERVAL"
done
