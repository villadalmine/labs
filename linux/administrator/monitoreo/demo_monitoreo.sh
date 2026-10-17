#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Monitoreo Liviano y Métricas en Linux
# Node Exporter + Textfile Collector + Salud de Mirror + Tráfico + Backups
#
# Uso:
#   sudo ./demo_monitoreo.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No detener Node Exporter ni limpiar al finalizar
# ==============================================================================

# Si se ejecuta en tmux, activar scroll con la rueda del ratón
if [ -n "$TMUX" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

# Paleta de colores didáctica
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
RESET='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Este script requiere privilegios de superusuario (sudo).${RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_RUNNING=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

pause_step() {
    local mensaje="${1:-Presiona [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${YELLOW}[MODO AUTOMÁTICO] Esperando ${AUTO_DELAY}s: ${mensaje}${RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${YELLOW}>>> ${mensaje}${RESET}"
        read -r
    fi
}

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
NODE_PID=""
LOOP_DEV1=""
LOOP_DEV2=""
VG_NAME="vg_demo_monitoreo"
LV_NAME="lv_mirror"

cleanup() {
    echo -e "\n${YELLOW}=== Limpieza de recursos del laboratorio ===${RESET}"
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${GREEN}[INFO] Se mantiene Node Exporter corriendo por opción --keep.${RESET}"
        echo -e "${CYAN}Consulta las métricas en: http://localhost:9100/metrics${RESET}"
        return
    fi

    # Detener Node Exporter si lo levantamos nosotros directamente
    if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
        echo "Deteniendo proceso Node Exporter (PID: $NODE_PID)..."
        kill "$NODE_PID" 2>/dev/null || true
    fi

    # Limpiar LVM si fue creado
    if vgs "$VG_NAME" &>/dev/null; then
        echo "Desmontando y eliminando volumen LVM de prueba..."
        lvremove -y "/dev/${VG_NAME}/${LV_NAME}" 2>/dev/null || true
        vgremove -y "$VG_NAME" 2>/dev/null || true
    fi

    if [ -n "$LOOP_DEV1" ]; then
        pvremove -y "$LOOP_DEV1" 2>/dev/null || true
        losetup -d "$LOOP_DEV1" 2>/dev/null || true
        rm -f /tmp/disk_mon_1.img
    fi

    if [ -n "$LOOP_DEV2" ]; then
        pvremove -y "$LOOP_DEV2" 2>/dev/null || true
        losetup -d "$LOOP_DEV2" 2>/dev/null || true
        rm -f /tmp/disk_mon_2.img
    fi

    rm -f /tmp/simular_falla_mirror
    rm -f /tmp/lab_http_requests.count
    rm -rf /tmp/mock_backup_dir

    echo -e "${GREEN}[OK] Laboratorio limpio correctamente.${RESET}"
}

trap cleanup EXIT INT TERM

clear
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${BOLD}${CYAN}   LABORATORIO EDUCATIVO: MONITOREO Y MÉTRICAS EN LINUX (DE 0 A 100)   ${RESET}"
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${CYAN}Conceptos clave: Modelo PULL vs PUSH | Prometheus Node Exporter | Textfile${RESET}"
echo -e "${CYAN}Métricas reales: Salud de Mirror RAID 1 | Tráfico Web | Sesiones | Backups${RESET}"
echo -e "${PURPLE}------------------------------------------------------------------------${RESET}"

# ==============================================================================
# PASO 1: TEORÍA BÁSICA Y DIFERENCIA PULL VS PUSH
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 1] Entendiendo el Monitoreo: Diagnóstico vs Monitoreo Continuo${RESET}"
echo -e "Herramientas que ya conoces: ${YELLOW}vmstat, iostat, sar${RESET}."
echo -e "  * Son para ${BOLD}diagnóstico puntual en vivo${RESET} cuando tú estás frente a la terminal."
echo -e "  * ${RED}Problema:${RESET} No te avisan si a las 3 AM un disco falló o el backup no corrió."
echo -e "\nEl monitoreo continuo requiere ${BOLD}Métricas${RESET}:"
echo -e "  1. ${GREEN}Gauge (Indicador):${RESET} Sube y baja (RAM usada, sesiones SSH activas)."
echo -e "  2. ${GREEN}Counter (Contador):${RESET} Solo se incrementa (total de peticiones HTTP)."
echo -e "  3. ${GREEN}Estado Booleano:${RESET} 1 (Saludable/OK) o 0 (Falla/Degradado)."
echo -e "\nModelos de arquitectura:"
echo -e "  * ${YELLOW}PULL (Sondeo):${RESET} El monitor central pregunta por HTTP GET: '¿Cuáles son tus números?'"
echo -e "  * ${YELLOW}PUSH (Empuje):${RESET} El script o tarea envía sus métricas al terminar (ideal para backups)."

pause_step "Avanzar para preparar Node Exporter y el Textfile Collector..."

# ==============================================================================
# PASO 2: PREPARAR NODE EXPORTER Y EL TEXTFILE COLLECTOR
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 2] Configuración de Node Exporter y Textfile Collector${RESET}"
mkdir -p "$TEXTFILE_DIR"
chmod 775 "$TEXTFILE_DIR"
echo -e "Directorio Textfile Collector listo: ${GREEN}${TEXTFILE_DIR}${RESET}"

# Verificar si node_exporter está instalado en el sistema
if command -v node_exporter &>/dev/null || command -v prometheus-node-exporter &>/dev/null; then
    BIN_NODE=$(command -v node_exporter || command -v prometheus-node-exporter)
    echo -e "Se detectó Node Exporter instalado en: ${GREEN}${BIN_NODE}${RESET}"
else
    echo -e "${YELLOW}Descargando Node Exporter oficial (binario Go estático, ultraliviano <15MB)...${RESET}"
    VER="1.8.2"
    TAR_FILE="/tmp/node_exporter-${VER}.linux-amd64.tar.gz"
    if [ ! -f "$TAR_FILE" ]; then
        curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz" -o "$TAR_FILE"
    fi
    tar -xzf "$TAR_FILE" -C /tmp/
    BIN_NODE="/tmp/node_exporter-${VER}.linux-amd64/node_exporter"
    chmod +x "$BIN_NODE"
fi

# Iniciar Node Exporter en segundo plano si no está corriendo el servicio systemd
if systemctl is-active prometheus-node-exporter &>/dev/null; then
    echo -e "Node Exporter ya está corriendo como servicio de systemd."
    # Asegurar que tenga el flag de textfile directory
    if ! grep -q "collector.textfile.directory" /etc/default/prometheus-node-exporter 2>/dev/null; then
        echo 'ARGS="--collector.textfile.directory=/var/lib/node_exporter/textfile_collector"' > /etc/default/prometheus-node-exporter
        systemctl restart prometheus-node-exporter
    fi
else
    # Iniciar binario en segundo plano apuntando al textfile collector
    "$BIN_NODE" --collector.textfile.directory="$TEXTFILE_DIR" --web.listen-address=":9100" &>/tmp/node_exporter.log &
    NODE_PID=$!
    sleep 2
    echo -e "Node Exporter levantado en segundo plano con PID: ${GREEN}${NODE_PID}${RESET}"
fi

# Validar que responde
if curl -s http://localhost:9100/metrics | head -n 5 >/dev/null; then
    echo -e "${GREEN}✓ Node Exporter respondiendo correctamente en http://localhost:9100/metrics${RESET}"
else
    echo -e "${RED}[ERROR] Node Exporter no respondió en el puerto 9100.${RESET}"
fi

pause_step "Avanzar para configurar las métricas de Almacenamiento (Mirror RAID 1)..."

# ==============================================================================
# PASO 3: MÉTRICA DE SALUD DE ALMACENAMIENTO (MIRROR RAID 1)
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 3] Creando Métrica de Almacenamiento Espejado (LVM RAID 1)${RESET}"
echo -e "Creando un arreglo LVM RAID 1 de demostración con discos virtuales loop..."

dd if=/dev/zero of=/tmp/disk_mon_1.img bs=1M count=100 status=none
dd if=/dev/zero of=/tmp/disk_mon_2.img bs=1M count=100 status=none
LOOP_DEV1=$(losetup -f --show /tmp/disk_mon_1.img)
LOOP_DEV2=$(losetup -f --show /tmp/disk_mon_2.img)

pvcreate -y "$LOOP_DEV1" "$LOOP_DEV2" >/dev/null
vgcreate -y "$VG_NAME" "$LOOP_DEV1" "$LOOP_DEV2" >/dev/null
# Crear LV RAID 1 espejado
lvcreate -y --type raid1 -m 1 -L 60M -n "$LV_NAME" "$VG_NAME" >/dev/null
mkfs.ext4 -q "/dev/${VG_NAME}/${LV_NAME}"

echo -e "Arreglo LVM RAID 1 creado con éxito: ${GREEN}/dev/${VG_NAME}/${LV_NAME}${RESET}"
lvs -a -o lv_name,vg_name,copy_percent,health_status "$VG_NAME"

# Escribir métrica de estado
cat <<EOF > "${TEXTFILE_DIR}/storage_mirror.prom"
# HELP lvm_mirror_health Estado de salud del arreglo de disco espejado (1 = OK, 0 = Degradado)
# TYPE lvm_mirror_health gauge
lvm_mirror_health{vg="${VG_NAME}",lv="${LV_NAME}"} 1
EOF

echo -e "\nMétrica generada en: ${CYAN}${TEXTFILE_DIR}/storage_mirror.prom${RESET}"
echo -e "${BOLD}Muestra expuesta en Node Exporter:${RESET}"
curl -s http://localhost:9100/metrics | grep lvm_mirror_health

pause_step "Avanzar para configurar las métricas de Tráfico Web y Sesiones..."

# ==============================================================================
# PASO 4: MÉTRICAS DE TRÁFICO WEB Y SESIONES ACTIVAS
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 4] Métricas de Tráfico Web (Counter) y Sesiones (Gauge)${RESET}"

SESIONES_SSH=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | grep -v Recv-Q | wc -l || echo 1)
[ "$SESIONES_SSH" -eq 0 ] && SESIONES_SSH=1
echo "150" > /tmp/lab_http_requests.count

cat <<EOF > "${TEXTFILE_DIR}/sistema_trafico.prom"
# HELP server_active_ssh_sessions Conexiones TCP establecidas en puerto SSH (22)
# TYPE server_active_ssh_sessions gauge
server_active_ssh_sessions ${SESIONES_SSH}

# HELP http_incoming_requests_total Contador total acumulativo de peticiones web recibidas
# TYPE http_incoming_requests_total counter
http_incoming_requests_total 150
EOF

echo -e "${BOLD}Métricas expuestas en Node Exporter:${RESET}"
curl -s http://localhost:9100/metrics | grep -E "(server_active_ssh_sessions|http_incoming_requests_total)"

pause_step "Avanzar para configurar la métrica de Respaldos (PUSH de Backup)..."

# ==============================================================================
# PASO 5: MÉTRICAS DE BACKUP (MODELO PUSH REAL)
# ==============================================================================
echo -e "\n${BOLD}${BLUE}[PASO 5] Monitoreo de Respaldos: Timestamp, Exit Code y Tamaño${RESET}"
echo -e "Ejecutando script de respaldo simulado..."

mkdir -p /tmp/mock_backup_dir
TAR_BACKUP="/tmp/mock_backup_dir/backup_demo.tar.gz"
START_T=$(date +%s)
tar -czf "$TAR_BACKUP" /etc/hosts /etc/issue 2>/dev/null
SIZE_BYTES=$(stat -c%s "$TAR_BACKUP")
END_T=$(date +%s)

cat <<EOF > "${TEXTFILE_DIR}/backup_status.prom"
# HELP backup_last_run_timestamp_seconds Fecha unix del ultimo backup ejecutado
# TYPE backup_last_run_timestamp_seconds gauge
backup_last_run_timestamp_seconds{job="wordpress_db"} ${END_T}

# HELP backup_last_status Codigo de estado del ultimo backup (1 = OK/Exitoso, 0 = Fallo)
# TYPE backup_last_status gauge
backup_last_status{job="wordpress_db"} 1

# HELP backup_last_size_bytes Tamano en bytes del ultimo archivo de backup generado
# TYPE backup_last_size_bytes gauge
backup_last_size_bytes{job="wordpress_db"} ${SIZE_BYTES}

# HELP backup_duration_seconds Duracion en segundos de la operacion de backup
# TYPE backup_duration_seconds gauge
backup_duration_seconds{job="wordpress_db"} 1
EOF

echo -e "✓ Backup completado (${SIZE_BYTES} bytes). Métricas emitidas vía PUSH local."
curl -s http://localhost:9100/metrics | grep -E "backup_last_"

pause_step "Avanzar a la Fase de Pruebas en Vivo (Simulación de Fallas y Tráfico)..."

# ==============================================================================
# PASO 6: SIMULACIÓN EN VIVO (TRÁFICO, FALLA DE MIRROR Y FALLA DE BACKUP)
# ==============================================================================
echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}"
echo -e "${BOLD}${CYAN}          DEMOSTRACIÓN EN VIVO: ¿CÓMO REACCIONAN LAS MÉTRICAS?          ${RESET}"
echo -e "${BOLD}${PURPLE}========================================================================${RESET}"

echo -e "\n${BOLD}1) Inyectando 85 nuevas peticiones HTTP al contador...${RESET}"
NUEVO_TOTAL=$(( 150 + 85 ))
cat <<EOF > "${TEXTFILE_DIR}/sistema_trafico.prom.$$"
# HELP server_active_ssh_sessions Conexiones TCP establecidas en puerto SSH (22)
# TYPE server_active_ssh_sessions gauge
server_active_ssh_sessions ${SESIONES_SSH}

# HELP http_incoming_requests_total Contador total acumulativo de peticiones web recibidas
# TYPE http_incoming_requests_total counter
http_incoming_requests_total ${NUEVO_TOTAL}
EOF
mv "${TEXTFILE_DIR}/sistema_trafico.prom.$$" "${TEXTFILE_DIR}/sistema_trafico.prom"
echo -e "Resultado en métricas: ${GREEN}$(curl -s http://localhost:9100/metrics | grep ^http_incoming_requests_total)${RESET}"

pause_step "Ahora simularemos una falla de disco en el espejo LVM RAID 1..."

echo -e "\n${BOLD}2) Simulando falla física de una pata del espejo LVM RAID 1...${RESET}"
echo -e "${RED}[FALLA INYECTADA] Marcando disco como fallido / degradado...${RESET}"
cat <<EOF > "${TEXTFILE_DIR}/storage_mirror.prom.$$"
# HELP lvm_mirror_health Estado de salud del arreglo de disco espejado (1 = OK, 0 = Degradado)
# TYPE lvm_mirror_health gauge
lvm_mirror_health{vg="${VG_NAME}",lv="${LV_NAME}"} 0
EOF
mv "${TEXTFILE_DIR}/storage_mirror.prom.$$" "${TEXTFILE_DIR}/storage_mirror.prom"

echo -e "${BOLD}Lectura inmediata desde Node Exporter:${RESET}"
echo -e "${RED}$(curl -s http://localhost:9100/metrics | grep ^lvm_mirror_health)${RESET}"
echo -e "${YELLOW}--> Interpretación: El valor 0 activa inmediatamente las alertas de PagerDuty/Slack.${RESET}"

pause_step "Ahora simularemos un backup que falló por disco lleno o red caída..."

echo -e "\n${BOLD}3) Simulando ejecución de backup con error catastrófico...${RESET}"
NOW_T=$(date +%s)
cat <<EOF > "${TEXTFILE_DIR}/backup_status.prom"
# HELP backup_last_run_timestamp_seconds Fecha unix del ultimo backup ejecutado
# TYPE backup_last_run_timestamp_seconds gauge
backup_last_run_timestamp_seconds{job="wordpress_db"} ${NOW_T}

# HELP backup_last_status Codigo de estado del ultimo backup (1 = OK/Exitoso, 0 = Fallo)
# TYPE backup_last_status gauge
backup_last_status{job="wordpress_db"} 0

# HELP backup_last_size_bytes Tamano en bytes del ultimo archivo de backup generado
# TYPE backup_last_size_bytes gauge
backup_last_size_bytes{job="wordpress_db"} 0
EOF

echo -e "${BOLD}Lectura del estado del backup:${RESET}"
echo -e "${RED}$(curl -s http://localhost:9100/metrics | grep -E 'backup_last_(status|size_bytes)')${RESET}"
echo -e "${YELLOW}--> Interpretación: status=0 y size=0 alertan que hoy el servidor está sin copia de seguridad.${RESET}"

pause_step "Avanzar para ver el Mini-Dashboard Consolidado..."

# ==============================================================================
# PASO 7: MINI-DASHBOARD CONSOLIDADO EN TERMINAL
# ==============================================================================
echo -e "\n${BOLD}${CYAN}========================================================================${RESET}"
echo -e "${BOLD}${CYAN}             RESUMEN DEL ESTADO DE MONITOREO DEL SERVIDOR               ${RESET}"
echo -e "${BOLD}${CYAN}========================================================================${RESET}"

printf "${BOLD}%-35s %-15s %-25s${RESET}\n" "MÉTRICA MONITOREADA" "VALOR ACTUAL" "ESTADO EDUCATIVO"
printf "%-35s %-15s %-25s\n" "---------------------------------" "------------" "-------------------------"

MIRROR_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^lvm_mirror_health" | awk '{print $2}')
if [ "$MIRROR_VAL" = "1" ]; then
    printf "%-35s %-15s ${GREEN}%-25s${RESET}\n" "Salud Espejo LVM (RAID 1)" "$MIRROR_VAL" "✓ ÓPTIMO (Redundante)"
else
    printf "%-35s %-15s ${RED}%-25s${RESET}\n" "Salud Espejo LVM (RAID 1)" "$MIRROR_VAL" "✗ DEGRADADO (Alerta)"
fi

HTTP_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^http_incoming_requests_total" | awk '{print $2}')
printf "%-35s %-15s ${CYAN}%-25s${RESET}\n" "Peticiones Web Totales" "$HTTP_VAL" "Contador acumulativo"

SSH_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^server_active_ssh_sessions" | awk '{print $2}')
printf "%-35s %-15s ${BLUE}%-25s${RESET}\n" "Sesiones SSH Activas" "$SSH_VAL" "Conexiones activas"

BACKUP_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^backup_last_status" | awk '{print $2}')
BACKUP_SIZE=$(curl -s http://localhost:9100/metrics | grep -E "^backup_last_size_bytes" | awk '{print $2}')
if [ "$BACKUP_VAL" = "1" ]; then
    printf "%-35s %-15s ${GREEN}%-25s${RESET}\n" "Último Backup Status" "$BACKUP_VAL ($BACKUP_SIZE B)" "✓ EXITOSO"
else
    printf "%-35s %-15s ${RED}%-25s${RESET}\n" "Último Backup Status" "$BACKUP_VAL ($BACKUP_SIZE B)" "✗ FALLIDO (Alerta)"
fi

echo -e "\n${BOLD}${GREEN}¡Demostración completada con éxito!${RESET}"
echo -e "Puedes consultar todas las métricas en crudo con:"
echo -e "  ${YELLOW}curl -s http://localhost:9100/metrics | grep -v '^#'${RESET}"
echo -e "${PURPLE}========================================================================${RESET}"
