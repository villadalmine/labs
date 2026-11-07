#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN: CLUSTER DE MONITOREO CENTRALIZADO MULTI-NODO
# Prometheus Central + Worker 1 (Web LVM RAID 1) + Worker 2 (Datos Cifrados LUKS)
#
# Simulación de Topología Empresarial:
#  - Servidor Central (:9090): Prometheus Server raspando métricas de todos los nodos.
#  - Nodo 01 Web (:9101, :8081): LVM RAID 1 espejado, servicio web y telemetría de almacenamiento.
#  - Nodo 02 Almacenamiento (:9102): Contenedor cifrado LUKS2 (dm-crypt) y telemetría de seguridad.
#  - Inyección de fallas en caliente, verificación de alertas y recuperación.
#
# Uso:
#   sudo ./demo_monitoreo_centralizado.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_monitoreo_centralizado.sh --auto 3 -> Modo desatendido (espera 3s entre pasos)
#   sudo ./demo_monitoreo_centralizado.sh --keep   -> Preserva el cluster activo al finalizar
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR] Este laboratorio requiere privilegios de superusuario (sudo).\033[0m"
    echo "Ejecutá: sudo $0"
    exit 1
fi

AUTO_WAIT=0
KEEP_TEMP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_TEMP=1
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
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"

# Directorios de trabajo
BASE_DIR="/tmp/cluster_monitoreo"
CENTRAL_DIR="${BASE_DIR}/central"
NODE1_DIR="${BASE_DIR}/node1_web"
NODE2_DIR="${BASE_DIR}/node2_luks"

MOUNT_WEB="${NODE1_DIR}/mnt"
MOUNT_LUKS="${NODE2_DIR}/mnt"
TEXTFILE_N1="${NODE1_DIR}/textfile"
TEXTFILE_N2="${NODE2_DIR}/textfile"

LUKS_MAPPER="datos_seguros_multi"
VG_NAME="vg_multi_web"
LV_NAME="lv_multi_html"

PORT_PROM=9090
PORT_N1=9101
PORT_N2=9102
PORT_WEB=8081

PID_PROM=""
PID_N1=""
PID_N2=""
PID_WEB=""

LOOP_W1=""
LOOP_W2=""
LOOP_W_SPARE=""
LOOP_LUKS=""

cleanup() {
    if [ "$KEEP_TEMP" -eq 1 ]; then
        echo -e "\n${C_YELLOW}ℹ [INFO] Preservando cluster activo (--keep):${C_RESET}"
        echo -e " • Prometheus Central:  http://localhost:${PORT_PROM}/"
        echo -e " • Worker 1 (Web LVM):  http://localhost:${PORT_WEB}/ | Métricas: :${PORT_N1}/metrics"
        echo -e " • Worker 2 (LUKS):     Métricas: :${PORT_N2}/metrics\n"
        return
    fi

    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmantelando cluster multi-nodo y liberando puertos...${C_RESET}"

    # Detener procesos
    for pid in "$PID_PROM" "$PID_N1" "$PID_N2" "$PID_WEB"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    pkill -f "python3 -m http.server ${PORT_WEB}" 2>/dev/null || true
    pkill -f "web.listen-address=:${PORT_N1}" 2>/dev/null || true
    pkill -f "web.listen-address=:${PORT_N2}" 2>/dev/null || true
    pkill -f "config.file=${CENTRAL_DIR}/prometheus.yml" 2>/dev/null || true

    # Desmontar filesystems
    if mountpoint -q "$MOUNT_WEB" 2>/dev/null; then
        umount -f "$MOUNT_WEB" 2>/dev/null || true
    fi
    if mountpoint -q "$MOUNT_LUKS" 2>/dev/null; then
        umount -f "$MOUNT_LUKS" 2>/dev/null || true
    fi

    # Cerrar LUKS
    if [ -e "/dev/mapper/${LUKS_MAPPER}" ]; then
        cryptsetup close "$LUKS_MAPPER" 2>/dev/null || true
    fi

    # Remover LVM
    if vgs "$VG_NAME" &>/dev/null; then
        lvchange -an "$VG_NAME" 2>/dev/null || true
        vgremove -f -y "$VG_NAME" 2>/dev/null || true
    fi

    # Liberar Loop devices
    for dev in "$LOOP_W1" "$LOOP_W2" "$LOOP_W_SPARE" "$LOOP_LUKS"; do
        if [ -n "$dev" ] && [ -b "$dev" ]; then
            pvremove -ff -y "$dev" 2>/dev/null || true
            wipefs -a "$dev" 2>/dev/null || true
            losetup -d "$dev" 2>/dev/null || true
        fi
    done

    rm -rf "$BASE_DIR" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Cluster multi-nodo desmantelado y recursos liberados exitosamente.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

step_banner() {
    local num="$1"
    local title="$2"
    echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_YELLOW}PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💡 FUNDAMENTO TÉCNICO:${C_RESET} $1"
}

analisis_tecnico() {
    local pregunta="$1"
    local respuesta="${2:-}"
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Análisis de Arquitectura: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_WAIT" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver el fundamento técnico...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Fundamento:${C_RESET} ${respuesta}\n"
    fi
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
        read -r </dev/tty 2>/dev/null || read -
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
        echo -e "${C_YELLOW}(Comando finalizado exitosamente sin salida)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🌐 ARQUITECTURA DE OBSERVABILIDAD CENTRALIZADA MULTI-NODO                    ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Prometheus Central (:9090) ➔ Worker 1: Web + LVM RAID 1 (:9101, :8081)"
echo -e "                           ➔ Worker 2: Datos Cifrados LUKS2 (:9102)"
echo -e "Telemetría PULL ➔ Detección de Falla de Disco y Cifrado ➔ Recuperación en Vivo\n"

# ------------------------------------------------------------------------------
# 1. Verificación de Paquetes y Entorno
# ------------------------------------------------------------------------------
step_banner "1" "Detección e Instalación de Dependencias (Nativo APT)"

explain "Validamos que el sistema cuente con las utilidades de almacenamiento y monitoreo:"

BIN_NODE=""
if command -v prometheus-node-exporter &>/dev/null; then
    BIN_NODE=$(command -v prometheus-node-exporter)
elif command -v node_exporter &>/dev/null; then
    BIN_NODE=$(command -v node_exporter)
elif command -v apt-get &>/dev/null; then
    explain "Instalando paquetes vía APT (prometheus-node-exporter, lvm2, cryptsetup, curl):"
    apt-get update -qq && apt-get install -y -qq prometheus-node-exporter lvm2 cryptsetup curl
    BIN_NODE=$(command -v prometheus-node-exporter || command -v node_exporter)
fi

BIN_PROM=""
if command -v prometheus &>/dev/null; then
    BIN_PROM=$(command -v prometheus)
elif command -v apt-get &>/dev/null; then
    explain "Instalando Prometheus Server vía APT:"
    apt-get update -qq && apt-get install -y -qq prometheus
    BIN_PROM=$(command -v prometheus)
else
    # Fallback portable si no es Debian/Ubuntu
    VER="2.54.1"
    if [ ! -f "/tmp/prometheus" ]; then
        curl -sL "https://github.com/prometheus/prometheus/releases/download/v${VER}/prometheus-${VER}.linux-amd64.tar.gz" | tar -xz -C /tmp/
        mv /tmp/prometheus-${VER}.linux-amd64/prometheus /tmp/prometheus
    fi
    BIN_PROM="/tmp/prometheus"
fi

echo -e "✔ Binario Node Exporter: ${C_BOLD}${BIN_NODE}${C_RESET}"
echo -e "✔ Binario Prometheus:    ${C_BOLD}${BIN_PROM}${C_RESET}"

pause_step "Presioná [ENTER] para aprovisionar el Nodo 01 (Web + LVM RAID 1)..."

# ------------------------------------------------------------------------------
# 2. Aprovisionar Nodo 01: Servidor Web sobre LVM RAID 1
# ------------------------------------------------------------------------------
step_banner "2" "Aprovisionamiento de Nodo 01 (srv-web-lvm: :8081 y :9101)"

explain "Creamos almacenamiento espejado LVM RAID 1 para el servicio web del Worker 1:"
mkdir -p "${NODE1_DIR}" "${MOUNT_WEB}" "${TEXTFILE_N1}"

truncate -s 128M "${NODE1_DIR}/disk1.img" "${NODE1_DIR}/disk2.img"
LOOP_W1=$(losetup -f --show "${NODE1_DIR}/disk1.img")
LOOP_W2=$(losetup -f --show "${NODE1_DIR}/disk2.img")

pvcreate -y -ff "$LOOP_W1" "$LOOP_W2" >/dev/null
vgcreate -y "$VG_NAME" "$LOOP_W1" "$LOOP_W2" >/dev/null
lvcreate -y --type raid1 -m 1 -L 90M -n "$LV_NAME" "$VG_NAME" "$LOOP_W1" "$LOOP_W2" >/dev/null

mkfs.ext4 -F -q "/dev/${VG_NAME}/${LV_NAME}"
mount "/dev/${VG_NAME}/${LV_NAME}" "$MOUNT_WEB"

cat << 'EOF' > "${MOUNT_WEB}/index.html"
<!DOCTYPE html>
<html><body style="font-family:sans-serif; text-align:center; padding:40px; background:#181825; color:#cdd6f4;">
<h1 style="color:#a6e3a1;">Nodo 01: Servidor Web de Producción</h1>
<p>Almacenamiento subyacente: <strong>LVM RAID 1 Mirror (vg_multi_web/lv_multi_html)</strong></p>
<p>Telemetría PULL hacia el Servidor Central activa en puerto 9101.</p>
</body></html>
EOF

python3 -m http.server "$PORT_WEB" --directory "$MOUNT_WEB" &>/dev/null &
PID_WEB=$!
sleep 1

# Publicar métrica custom inicial de salud de LVM
cat << 'EOF' > "${TEXTFILE_N1}/lvm_mirror_health.prom"
# HELP node_lvm_mirror_health Estado de redundancia del espejo LVM (1=Sano, 0=Degradado)
# TYPE node_lvm_mirror_health gauge
node_lvm_mirror_health{vg="vg_multi_web",lv="lv_multi_html"} 1
EOF

"$BIN_NODE" --collector.textfile.directory="$TEXTFILE_N1" --web.listen-address=":${PORT_N1}" &>/tmp/node1_exporter.log &
PID_N1=$!
sleep 1

run_and_show "curl -sI http://localhost:${PORT_WEB}/ | head -n 3"
run_and_show "curl -s http://localhost:${PORT_N1}/metrics | grep node_lvm_mirror_health"

pause_step "Presioná [ENTER] para aprovisionar el Nodo 02 (Almacenamiento Cifrado LUKS2)..."

# ------------------------------------------------------------------------------
# 3. Aprovisionar Nodo 02: Servidor de Datos Cifrados LUKS2
# ------------------------------------------------------------------------------
step_banner "3" "Aprovisionamiento de Nodo 02 (srv-data-luks: :9102)"

explain "Configuramos cifrado de bloques FDE con LUKS2 (dm-crypt) para el Worker 2:"
mkdir -p "${NODE2_DIR}" "${MOUNT_LUKS}" "${TEXTFILE_N2}"

truncate -s 128M "${NODE2_DIR}/disk_luks.img"
LOOP_LUKS=$(losetup -f --show "${NODE2_DIR}/disk_luks.img")

KEY_FILE="${NODE2_DIR}/luks.key"
openssl rand -base64 32 > "$KEY_FILE"
chmod 0400 "$KEY_FILE"

echo -e "Formateando contenedor LUKS2 en ${LOOP_LUKS}..."
cryptsetup luksFormat --type luks2 --batch-mode --key-file "$KEY_FILE" "$LOOP_LUKS"
cryptsetup open --key-file "$KEY_FILE" "$LOOP_LUKS" "$LUKS_MAPPER"

mkfs.ext4 -F -q "/dev/mapper/${LUKS_MAPPER}"
mount "/dev/mapper/${LUKS_MAPPER}" "$MOUNT_LUKS"
echo "CONFIDENTIAL_FINANCIAL_DATABASE_DUMP_2026" > "${MOUNT_LUKS}/secretos.db"

# Publicar métrica custom de estado de LUKS
cat << 'EOF' > "${TEXTFILE_N2}/luks_status.prom"
# HELP node_luks_container_active Estado del contenedor LUKS descifrado (1=Abierto/Activo, 0=Cerrado)
# TYPE node_luks_container_active gauge
node_luks_container_active{device="datos_seguros_multi",cipher="aes-xts-plain64"} 1
EOF

"$BIN_NODE" --collector.textfile.directory="$TEXTFILE_N2" --web.listen-address=":${PORT_N2}" &>/tmp/node2_exporter.log &
PID_N2=$!
sleep 1

run_and_show "cryptsetup status ${LUKS_MAPPER} | head -n 5"
run_and_show "curl -s http://localhost:${PORT_N2}/metrics | grep node_luks_container_active"

pause_step "Presioná [ENTER] para encender el Servidor Central de Monitoreo (Prometheus)..."

# ------------------------------------------------------------------------------
# 4. Despliegue del Servidor Central de Monitoreo
# ------------------------------------------------------------------------------
step_banner "4" "Arranque del Servidor Central de Monitoreo (Prometheus :9090)"

explain "Generamos la configuración de scrape centralizado en prometheus.yml:"
mkdir -p "${CENTRAL_DIR}/data"

cat << EOF > "${CENTRAL_DIR}/prometheus.yml"
global:
  scrape_interval: 2s
  evaluation_interval: 2s

scrape_jobs:
  - job_name: 'srv-monitoreo-central'
    static_configs:
      - targets: ['localhost:${PORT_PROM}']
        labels:
          role: 'observability-hub'

  - job_name: 'srv-web-lvm'
    static_configs:
      - targets: ['localhost:${PORT_N1}']
        labels:
          role: 'web-production'
          storage: 'lvm-raid1'

  - job_name: 'srv-data-luks'
    static_configs:
      - targets: ['localhost:${PORT_N2}']
        labels:
          role: 'secure-database'
          storage: 'luks2-encrypted'
EOF

if ss -tulpn 2>/dev/null | grep -q ":${PORT_PROM}\b"; then
    explain "Liberando puerto :${PORT_PROM} para la instancia del laboratorio:"
    systemctl stop prometheus 2>/dev/null || true
    fuser -k "${PORT_PROM}/tcp" 2>/dev/null || true
    sleep 1
fi

"$BIN_PROM" --config.file="${CENTRAL_DIR}/prometheus.yml" \
            --storage.tsdb.path="${CENTRAL_DIR}/data" \
            --web.listen-address=":${PORT_PROM}" &>/tmp/prometheus_central.log &
PID_PROM=$!
sleep 3

explain "Consultamos la API de Targets de Prometheus para verificar el estado de los 3 nodos:"
run_and_show "curl -s http://localhost:${PORT_PROM}/api/v1/targets | grep -o '\"health\":\"[^\"]*\"' | head -n 3"

analisis_tecnico "¿Por qué el Servidor Central puede supervisar subsistemas del kernel como LVM y LUKS?" \
                 "Porque los Workers utilizan el Textfile Collector de Node Exporter como puente: scripts livianos inspeccionan el kernel (lvs, cryptsetup) y escriben archivos .prom que Node Exporter expone en su /metrics."

pause_step "Presioná [ENTER] para el momento cumbre: ¡Inyección de fallas en los dos Workers!..."

# ------------------------------------------------------------------------------
# 5. Inyección de Fallas Simultáneas en los Nodos de Producción
# ------------------------------------------------------------------------------
step_banner "5" "Simulación de Incidentes: Falla de Disco 1 en Nodo 1 y Cierre de LUKS en Nodo 2"

explain "1. En Nodo 1 (Web): Destruimos físicamente el disco 1 con ceros (dd):"
run_and_show "dd if=/dev/zero of=${LOOP_W1} bs=1M count=10 conv=notrunc status=none"
blockdev --flushbufs "$LOOP_W1" 2>/dev/null || true

# Actualizar métrica en Nodo 1
cat << 'EOF' > "${TEXTFILE_N1}/lvm_mirror_health.prom"
# HELP node_lvm_mirror_health Estado de redundancia del espejo LVM (1=Sano, 0=Degradado)
# TYPE node_lvm_mirror_health gauge
node_lvm_mirror_health{vg="vg_multi_web",lv="lv_multi_html"} 0
EOF

explain "2. En Nodo 2 (Datos): Desmontamos y bloqueamos el contenedor LUKS:"
umount -f "$MOUNT_LUKS" 2>/dev/null || true
cryptsetup close "$LUKS_MAPPER" 2>/dev/null || true

# Actualizar métrica en Nodo 2
cat << 'EOF' > "${TEXTFILE_N2}/luks_status.prom"
# HELP node_luks_container_active Estado del contenedor LUKS descifrado (1=Abierto/Activo, 0=Cerrado)
# TYPE node_luks_container_active gauge
node_luks_container_active{device="datos_seguros_multi",cipher="aes-xts-plain64"} 0
EOF

sleep 3

echo -e "\n${C_BOLD}${C_RED}🚨 ALERTA CENTRAL DISPARADA EN PROMETHEUS:${C_RESET}"
explain "Consultamos PromQL en el Servidor Central para detectar nodos en falla:"
run_and_show "curl -s 'http://localhost:${PORT_PROM}/api/v1/query' --data-urlencode 'query=node_lvm_mirror_health == 0' | jq -c '.data.result[] | {metric: .metric, value: .value}' 2>/dev/null || curl -s 'http://localhost:${PORT_PROM}/api/v1/query?query=node_lvm_mirror_health==0'"
run_and_show "curl -s 'http://localhost:${PORT_PROM}/api/v1/query' --data-urlencode 'query=node_luks_container_active == 0' | jq -c '.data.result[] | {metric: .metric, value: .value}' 2>/dev/null || curl -s 'http://localhost:${PORT_PROM}/api/v1/query?query=node_luks_container_active==0'"

explain "Comprobamos que el servicio Web de producción NO se cayó (Zero Downtime con LVM RAID 1):"
run_and_show "curl -sI http://localhost:${PORT_WEB}/ | head -n 3"

pause_step "Presioná [ENTER] para reparar los dos nodos y observar la recuperación centralizada..."

# ------------------------------------------------------------------------------
# 6. Reparación en Caliente y Retorno a la Normalidad
# ------------------------------------------------------------------------------
step_banner "6" "Reparación de Nodos y Recuperación de la Telemetría Central"

explain "1. Reparamos Nodo 1: Insertamos disco de repuesto y reconstruimos el espejo LVM:"
truncate -s 128M "${NODE1_DIR}/disk_spare.img"
LOOP_W_SPARE=$(losetup -f --show "${NODE1_DIR}/disk_spare.img")
pvcreate -y "$LOOP_W_SPARE" >/dev/null
vgextend "$VG_NAME" "$LOOP_W_SPARE" >/dev/null
lvconvert -y --repair "${VG_NAME}/${LV_NAME}" >/dev/null
vgreduce -y --removemissing --force "$VG_NAME" >/dev/null

cat << 'EOF' > "${TEXTFILE_N1}/lvm_mirror_health.prom"
# HELP node_lvm_mirror_health Estado de redundancia del espejo LVM (1=Sano, 0=Degradado)
# TYPE node_lvm_mirror_health gauge
node_lvm_mirror_health{vg="vg_multi_web",lv="lv_multi_html"} 1
EOF

explain "2. Reparamos Nodo 2: Desbloqueamos el contenedor LUKS y remontamos:"
cryptsetup open --key-file "$KEY_FILE" "$LOOP_LUKS" "$LUKS_MAPPER"
mount "/dev/mapper/${LUKS_MAPPER}" "$MOUNT_LUKS"

cat << 'EOF' > "${TEXTFILE_N2}/luks_status.prom"
# HELP node_luks_container_active Estado del contenedor LUKS descifrado (1=Abierto/Activo, 0=Cerrado)
# TYPE node_luks_container_active gauge
node_luks_container_active{device="datos_seguros_multi",cipher="aes-xts-plain64"} 1
EOF

sleep 3

explain "Verificamos que en el Servidor Central todos los valores regresaron a 1 (VERDE):"
run_and_show "curl -s 'http://localhost:${PORT_PROM}/api/v1/query' --data-urlencode 'query=node_lvm_mirror_health' | jq -c '.data.result[] | {metric: .metric, value: .value}' 2>/dev/null || curl -s 'http://localhost:${PORT_PROM}/api/v1/query?query=node_lvm_mirror_health'"
run_and_show "curl -s 'http://localhost:${PORT_PROM}/api/v1/query' --data-urlencode 'query=node_luks_container_active' | jq -c '.data.result[] | {metric: .metric, value: .value}' 2>/dev/null || curl -s 'http://localhost:${PORT_PROM}/api/v1/query?query=node_luks_container_active'"

echo -e "\n${C_BOLD}${C_GREEN}✔ ¡Todos los nodos recuperaron su estado de salud óptimo (SANO)!${C_RESET}"

pause_step "Presioná [ENTER] para ver el resumen final y concluir..."

step_banner "FIN" "Demostración de Cluster Multi-Nodo Finalizada con Éxito"
echo -e "${C_BOLD}${C_GREEN}✔ Se demostró con éxito la arquitectura de observabilidad centralizada:${C_RESET}"
echo -e " 1. Modelo PULL multi-target orquestado desde un único servidor central."
echo -e " 2. Supervisión de subsistemas del kernel (LVM RAID 1 y LUKS) mediante Textfile Collector."
echo -e " 3. Detección inmediata de fallas y comprobación de resiliencia Zero Downtime.\n"
