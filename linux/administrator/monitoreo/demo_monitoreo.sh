#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Monitoreo Liviano y Métricas en Linux
# Node Exporter + Textfile Collector + Salud de Mirror + Tráfico + Backups
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema destacada en una caja limpia.
#  - Explica modelos PULL vs PUSH y formato Prometheus (HELP, TYPE, Gauge, Counter).
#  - Inyección de fallas en vivo y reacción inmediata en las métricas.
#  - Preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   sudo ./demo_monitoreo.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No detener Node Exporter ni limpiar al finalizar
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este script requiere privilegios de superusuario (sudo).\033[0m"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false

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

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"

pause_step() {
    local mensaje="${1:-Presiona [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${C_YELLOW}⏳ [MODO AUTO] Esperando ${AUTO_DELAY}s: ${mensaje}${C_RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${mensaje}${C_RESET}"
        read -r
    fi
}

step_banner() {
    local num="$1"
    local title="$2"
    echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_YELLOW}PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💡 EXPLICACIÓN TEÓRICA:${C_RESET} $1"
}

pie_clase() {
    echo -e "\n${C_MAGENTA}🎤 [PIE PARA LA CLASE EN VIVO]:${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW}👉 Preguntale a los alumnos:${C_RESET} \"$1\""
    if [ -n "${2:-}" ]; then
        echo -e "   ${C_CYAN}Respuesta clave esperada:${C_RESET} $2"
    fi
}

run_and_show() {
    local cmd="$1"
    echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR ────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"
    
    local output
    output=$(eval "$cmd" 2>&1) || true
    
    if [ -z "$output" ]; then
        echo -e "${C_YELLOW}(El comando finalizó exitosamente sin imprimir texto en stdout/stderr)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
NODE_PID=""
LOOP_DEV1=""
LOOP_DEV2=""
VG_NAME="vg_demo_monitoreo"
LV_NAME="lv_mirror"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo servicios y limpiando recursos...${C_RESET}"
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${C_GREEN}[INFO] Se mantiene Node Exporter activo por opción --keep.${C_RESET}"
        echo -e "Métricas disponibles en: http://localhost:9100/metrics"
        return
    fi

    if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
        kill "$NODE_PID" 2>/dev/null || true
    fi

    if vgs "$VG_NAME" &>/dev/null; then
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
    echo -e "${C_GREEN}✔ Entorno de monitoreo limpio y liberado.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

clear || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 📊 LABORATORIO EN VIVO: MONITOREO CONTINUO Y MÉTRICAS EN LINUX                ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Prometheus Node Exporter ➔ Textfile Collector ➔ Mirror RAID ➔ Tráfico ➔ Backups"
echo -e "Aprende la diferencia entre diagnóstico forense puntual y telemetría de producción\n"

# ==============================================================================
# PASO 1: TEORÍA BÁSICA: DIAGNÓSTICO VS MONITOREO
# ==============================================================================
step_banner "1" "Diagnóstico Puntual vs Monitoreo Continuo (PULL vs PUSH)"

explain "Herramientas que ya conocés: vmstat, iostat, sar, top, ps."
explain " • Son excelentes para DIAGNÓSTICO EN VIVO mientras estás conectado por SSH."
explain " • Limitación: No alertan automáticamente a las 3 AM si un disco falló o un backup colapsó."

explain "El monitoreo continuo se basa en MÉTRICAS estandarizadas:"
explain " 1. Gauge: Valor que sube y baja (temperatura, RAM en uso, sesiones activas)."
explain " 2. Counter: Contador que solo se incrementa (total de peticiones HTTP, bytes transmitidos)."
explain " 3. Estado Booleano: 1 (OK / Saludable) o 0 (Falla / Degradado)."

pie_clase "¿Cuál es la diferencia entre el modelo PULL (Prometheus) y el modelo PUSH (Pushgateway/Logs)?" \
          "En PULL el servidor central sondea cada N segundos; en PUSH la tarea emite sus métricas al terminar."

pause_step "Presioná [ENTER] para inicializar Node Exporter y el Textfile Collector..."

# ==============================================================================
# PASO 2: PREPARAR NODE EXPORTER Y EL TEXTFILE COLLECTOR
# ==============================================================================
step_banner "2" "Configuración de Node Exporter y Textfile Collector"

explain "Creamos el directorio del Textfile Collector (/var/lib/node_exporter/textfile_collector):"
mkdir -p "$TEXTFILE_DIR"
chmod 775 "$TEXTFILE_DIR"
echo -e "Directorio Textfile Collector listo: ${C_GREEN}${TEXTFILE_DIR}${C_RESET}"

if command -v node_exporter &>/dev/null || command -v prometheus-node-exporter &>/dev/null; then
    BIN_NODE=$(command -v node_exporter || command -v prometheus-node-exporter)
    echo -e "Node Exporter detectado en: ${C_GREEN}${BIN_NODE}${C_RESET}"
else
    explain "Descargando binario oficial de Node Exporter (Go estático ultraliviano <15 MB):"
    VER="1.8.2"
    TAR_FILE="/tmp/node_exporter-${VER}.linux-amd64.tar.gz"
    if [ ! -f "$TAR_FILE" ]; then
        curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz" -o "$TAR_FILE"
    fi
    tar -xzf "$TAR_FILE" -C /tmp/
    BIN_NODE="/tmp/node_exporter-${VER}.linux-amd64/node_exporter"
    chmod +x "$BIN_NODE"
fi

if systemctl is-active prometheus-node-exporter &>/dev/null; then
    echo -e "Node Exporter ya está activo como servicio systemd."
else
    explain "Lanzamos Node Exporter en segundo plano apuntando al Textfile Collector:"
    "$BIN_NODE" --collector.textfile.directory="$TEXTFILE_DIR" --web.listen-address=":9100" &>/tmp/node_exporter.log &
    NODE_PID=$!
    sleep 2
    echo -e "Node Exporter ejecutándose en segundo plano (PID: ${C_BOLD}${NODE_PID}${C_RESET})"
fi

explain "Comprobamos que Node Exporter responde por HTTP GET en el puerto 9100:"
run_and_show "curl -s http://localhost:9100/metrics | head -n 12"

pause_step "Presioná [ENTER] para configurar métricas de Almacenamiento (LVM RAID 1)..."

# ==============================================================================
# PASO 3: MÉTRICA DE SALUD DE ALMACENAMIENTO (MIRROR RAID 1)
# ==============================================================================
step_banner "3" "Métricas de Salud de Almacenamiento (LVM RAID 1)"

explain "Creamos un arreglo LVM RAID 1 espejado de prueba con dos loop devices:"
dd if=/dev/zero of=/tmp/disk_mon_1.img bs=1M count=100 status=none
dd if=/dev/zero of=/tmp/disk_mon_2.img bs=1M count=100 status=none
LOOP_DEV1=$(losetup -f --show /tmp/disk_mon_1.img)
LOOP_DEV2=$(losetup -f --show /tmp/disk_mon_2.img)

pvcreate -y "$LOOP_DEV1" "$LOOP_DEV2" >/dev/null
vgcreate -y "$VG_NAME" "$LOOP_DEV1" "$LOOP_DEV2" >/dev/null
lvcreate -y --type raid1 -m 1 -L 60M -n "$LV_NAME" "$VG_NAME" >/dev/null
mkfs.ext4 -F -q "/dev/${VG_NAME}/${LV_NAME}"

explain "Inspeccionamos el estado de salud del espejo RAID 1 con lvs:"
run_and_show "lvs -a -o lv_name,vg_name,copy_percent,health_status ${VG_NAME}"

explain "Generamos la métrica en formato Prometheus en el Textfile Collector:"
cat <<EOF > "${TEXTFILE_DIR}/storage_mirror.prom"
# HELP lvm_mirror_health Estado de salud del arreglo de disco espejado (1 = OK, 0 = Degradado)
# TYPE lvm_mirror_health gauge
lvm_mirror_health{vg="${VG_NAME}",lv="${LV_NAME}"} 1
EOF

explain "Consultamos cómo Node Exporter expone inmediatamente la nueva métrica:"
run_and_show "curl -s http://localhost:9100/metrics | grep -A 2 lvm_mirror_health"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • ${C_BOLD}# HELP${C_RESET} -> Documentación de la métrica para Grafana / Prometheus."
echo -e " • ${C_BOLD}# TYPE${C_RESET} -> Declara el tipo (gauge: sube o baja)."
echo -e " • ${C_BOLD}Valor: 1${C_RESET} -> Indica que el espejo está saludable y sincronizado al 100%."

pause_step "Presioná [ENTER] para configurar métricas de Tráfico Web y Sesiones SSH..."

# ==============================================================================
# PASO 4: MÉTRICAS DE TRÁFICO WEB (COUNTER) Y SESIONES (GAUGE)
# ==============================================================================
step_banner "4" "Métricas de Tráfico Web (Counter) y Conexiones SSH (Gauge)"

explain "Recolectamos las conexiones SSH activas con ss y fijamos un contador de tráfico:"
SESIONES_SSH=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | grep -v Recv-Q | wc -l || echo 1)
[ "$SESIONES_SSH" -eq 0 ] && SESIONES_SSH=1

cat <<EOF > "${TEXTFILE_DIR}/sistema_trafico.prom"
# HELP server_active_ssh_sessions Conexiones TCP establecidas en puerto SSH (22)
# TYPE server_active_ssh_sessions gauge
server_active_ssh_sessions ${SESIONES_SSH}

# HELP http_incoming_requests_total Contador total acumulativo de peticiones web recibidas
# TYPE http_incoming_requests_total counter
http_incoming_requests_total 150
EOF

explain "Verificamos las métricas de tráfico en el endpoint HTTP:"
run_and_show "curl -s http://localhost:9100/metrics | grep -E '(server_active_ssh_sessions|http_incoming_requests_total)'"

pie_clase "¿Por qué un contador HTTP (counter) nunca debe decrementar su valor?" \
          "Porque Prometheus calcula la tasa de peticiones por segundo usando rate() sobre la derivada del contador."

pause_step "Presioná [ENTER] para configurar el monitoreo de Backups..."

# ==============================================================================
# PASO 5: MÉTRICAS DE BACKUP (MODELO PUSH LOCAL)
# ==============================================================================
step_banner "5" "Monitoreo de Respaldos: Timestamp, Exit Code y Tamaño"

explain "Simulamos la ejecución de un backup diario y emitimos sus métricas al terminar:"
mkdir -p /tmp/mock_backup_dir
TAR_BACKUP="/tmp/mock_backup_dir/backup_demo.tar.gz"
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
EOF

explain "Consultamos las métricas de backup expuestas:"
run_and_show "curl -s http://localhost:9100/metrics | grep -E 'backup_last_'"

pause_step "Presioná [ENTER] para iniciar la fase de Simulación de Fallas y Tráfico en Vivo..."

# ==============================================================================
# PASO 6: SIMULACIÓN EN VIVO: FALLA DE DISCO Y FALLA DE BACKUP
# ==============================================================================
step_banner "6" "Simulación en Vivo: Inyección de Tráfico y Fallas Reales"

explain "1) Inyectamos 85 peticiones HTTP nuevas en caliente (el total pasa de 150 a 235):"
NUEVO_TOTAL=235
cat <<EOF > "${TEXTFILE_DIR}/sistema_trafico.prom.$$"
# HELP server_active_ssh_sessions Conexiones TCP establecidas en puerto SSH (22)
# TYPE server_active_ssh_sessions gauge
server_active_ssh_sessions ${SESIONES_SSH}

# HELP http_incoming_requests_total Contador total acumulativo de peticiones web recibidas
# TYPE http_incoming_requests_total counter
http_incoming_requests_total ${NUEVO_TOTAL}
EOF
mv "${TEXTFILE_DIR}/sistema_trafico.prom.$$" "${TEXTFILE_DIR}/sistema_trafico.prom"

explain "Leemos el contador actualizado:"
run_and_show "curl -s http://localhost:9100/metrics | grep ^http_incoming_requests_total"

pause_step "Presioná [ENTER] para inyectar una rotura física en el disco RAID 1..."

explain "2) INYECCIÓN DE FALLA: Simulamos disco degradado en el arreglo RAID 1 (salud pasa de 1 a 0):"
cat <<EOF > "${TEXTFILE_DIR}/storage_mirror.prom.$$"
# HELP lvm_mirror_health Estado de salud del arreglo de disco espejado (1 = OK, 0 = Degradado)
# TYPE lvm_mirror_health gauge
lvm_mirror_health{vg="${VG_NAME}",lv="${LV_NAME}"} 0
EOF
mv "${TEXTFILE_DIR}/storage_mirror.prom.$$" "${TEXTFILE_DIR}/storage_mirror.prom"

explain "Lectura inmediata de la telemetría en Node Exporter:"
run_and_show "curl -s http://localhost:9100/metrics | grep ^lvm_mirror_health"

echo -e "\n${C_BOLD}${C_RED}🚨 ALERTA GENERADA:${C_RESET} El valor 0 dispara de inmediato la notificación en PagerDuty / Slack."

pause_step "Presioná [ENTER] para simular un backup fallido por falta de espacio o red..."

explain "3) INYECCIÓN DE FALLA: El backup falló (status=0 y size=0 bytes):"
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

explain "Comprobamos el estado del backup en las métricas:"
run_and_show "curl -s http://localhost:9100/metrics | grep -E 'backup_last_(status|size_bytes)'"

echo -e "\n${C_BOLD}${C_RED}🚨 ALERTA DE BACKUP:${C_RESET} El monitor detecta status=0 e informa que el servidor carece de copia hoy."

pause_step "Presioná [ENTER] para ver el Mini-Dashboard Consolidado en terminal..."

# ==============================================================================
# PASO 7: MINI-DASHBOARD CONSOLIDADO EN TERMINAL
# ==============================================================================
step_banner "7" "Mini-Dashboard de Estado en Terminal"

printf "${C_BOLD}%-35s %-15s %-25s${C_RESET}\n" "MÉTRICA MONITOREADA" "VALOR ACTUAL" "ESTADO EDUCATIVO"
printf "%-35s %-15s %-25s\n" "---------------------------------" "------------" "-------------------------"

MIRROR_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^lvm_mirror_health" | awk '{print $2}')
if [ "$MIRROR_VAL" = "1" ]; then
    printf "%-35s %-15s ${C_GREEN}%-25s${C_RESET}\n" "Salud Espejo LVM (RAID 1)" "$MIRROR_VAL" "✓ ÓPTIMO (Redundante)"
else
    printf "%-35s %-15s ${C_RED}%-25s${C_RESET}\n" "Salud Espejo LVM (RAID 1)" "$MIRROR_VAL" "✗ DEGRADADO (Alerta)"
fi

HTTP_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^http_incoming_requests_total" | awk '{print $2}')
printf "%-35s %-15s ${C_CYAN}%-25s${C_RESET}\n" "Peticiones Web Totales" "$HTTP_VAL" "Contador acumulativo"

SSH_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^server_active_ssh_sessions" | awk '{print $2}')
printf "%-35s %-15s ${C_BLUE}%-25s${C_RESET}\n" "Sesiones SSH Activas" "$SSH_VAL" "Conexiones activas"

BACKUP_VAL=$(curl -s http://localhost:9100/metrics | grep -E "^backup_last_status" | awk '{print $2}')
BACKUP_SIZE=$(curl -s http://localhost:9100/metrics | grep -E "^backup_last_size_bytes" | awk '{print $2}')
if [ "$BACKUP_VAL" = "1" ]; then
    printf "%-35s %-15s ${C_GREEN}%-25s${C_RESET}\n" "Último Backup Status" "$BACKUP_VAL ($BACKUP_SIZE B)" "✓ EXITOSO"
else
    printf "%-35s %-15s ${C_RED}%-25s${C_RESET}\n" "Último Backup Status" "$BACKUP_VAL ($BACKUP_SIZE B)" "✗ FALLIDO (Alerta)"
fi

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE MONITOREO Y MÉTRICAS FINALIZADA CON ÉXITO!               ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}\n"
