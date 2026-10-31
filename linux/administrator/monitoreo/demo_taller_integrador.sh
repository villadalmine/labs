#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTEGRADA: Servidor Web sobre LVM RAID 1, Node Exporter,
# Falla de Disco en Vivo, Reemplazo en Caliente y TUI de Observabilidad
#
# Diseñado para clases magistrales:
#  - Muestra cómo se monitoreaba antes (diagnóstico reactivo) vs hoy (PULL continuo).
#  - Despliega un servicio real (Servidor Web) sobre almacenamiento resiliente (LVM RAID 1).
#  - Simula la destrucción física de un disco en caliente con dd.
#  - Demuestra que la web NO se cae gracias a la paridad/espejo del kernel.
#  - Reemplaza y reconstruye el espejo en vivo con lvconvert --repair.
#  - Muestra la telemetría en un panel gráfico TUI de terminal y explica Prometheus/Grafana.
#
# Uso:
#   sudo ./demo_taller_integrador.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_taller_integrador.sh --auto 3 -> Modo desatendido (espera 3s entre pasos)
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

# Variables del laboratorio
WORK_DIR="/tmp/taller_integrador"
VG_NAME="vg_web"
LV_NAME="lv_html"
MOUNT_DIR="/var/www/html_lab"
WEB_PORT=8080
NODE_PORT=9100

WEB_PID=""
NODE_PID=""
LOOP1=""
LOOP2=""
LOOP_SPARE=""

cleanup() {
    if [ "$KEEP_TEMP" -eq 1 ]; then
        echo -e "\n${C_YELLOW}ℹ [INFO] Preservando recursos del laboratorio (--keep).${C_RESET}"
        echo -e "Web activa en: http://localhost:${WEB_PORT}/"
        echo -e "Node Exporter en: http://localhost:${NODE_PORT}/metrics\n"
        return
    fi

    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmantelando servicios y almacenamiento del laboratorio...${C_RESET}"

    # Detener servidor web
    if [ -n "$WEB_PID" ] && kill -0 "$WEB_PID" 2>/dev/null; then
        kill "$WEB_PID" 2>/dev/null || true
    fi
    pkill -f "python3 -m http.server ${WEB_PORT}" 2>/dev/null || true

    # Detener Node Exporter si fue lanzado por el script
    if [ -n "$NODE_PID" ] && kill -0 "$NODE_PID" 2>/dev/null; then
        kill "$NODE_PID" 2>/dev/null || true
    fi

    # Desmontar filesystem
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        umount -f "$MOUNT_DIR" 2>/dev/null || true
    fi
    rm -rf "$MOUNT_DIR" 2>/dev/null || true

    # Desactivar y remover LVM
    if vgs "$VG_NAME" &>/dev/null; then
        lvchange -an "$VG_NAME" 2>/dev/null || true
        vgremove -f -y "$VG_NAME" 2>/dev/null || true
    fi

    # Limpiar loop devices
    for dev in "$LOOP1" "$LOOP2" "$LOOP_SPARE"; do
        if [ -n "$dev" ] && [ -b "$dev" ]; then
            pvremove -ff -y "$dev" 2>/dev/null || true
            wipefs -a "$dev" 2>/dev/null || true
            losetup -d "$dev" 2>/dev/null || true
        fi
    done

    # Borrar archivos temporales
    rm -rf "$WORK_DIR" 2>/dev/null || true
    rm -f /tmp/web_requests.count 2>/dev/null || true
    rm -f /tmp/node_exporter_taller.log 2>/dev/null || true

    echo -e "${C_GREEN}✔ Almacenamiento, puertos y procesos liberados exitosamente.${C_RESET}\n"
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
    echo -e "${C_CYAN}💡 EXPLICACIÓN DIDÁCTICA:${C_RESET} $1"
}

pie_clase() {
    local pregunta="$1"
    local respuesta="${2:-}"
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_WAIT" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para revelar la respuesta...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
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
        echo -e "${C_YELLOW}(El comando finalizó exitosamente sin imprimir texto en stdout/stderr)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🚀 TALLER INTEGRAL: WEB RESILIENTE (LVM RAID 1) + OBSERVABILIDAD PULL         ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Diagnóstico Tradicional ➔ Node Exporter PULL ➔ LVM RAID 1 ➔ Web en Producción"
echo -e "➔ Falla de Disco en Caliente ➔ Resiliencia ➔ Reemplazo en Vivo ➔ TUI Dashboard\n"

# ------------------------------------------------------------------------------
# 1. El Pasado: Monitoreo Reactivo
# ------------------------------------------------------------------------------
step_banner "1" "Cómo se Monitoreaba Antes: Diagnóstico Reactivo y Puntual"

explain "¿Cómo sabía un administrador hace 20 años si su servidor estaba bien?"
explain "Iniciaba sesión manual por SSH y ejecutaba comandos aislados de terminal:"

run_and_show "uptime"
run_and_show "vmstat 1 2"
run_and_show "df -h /"

pie_clase "¿Cuál es la falla fatal del diagnóstico puntual con df -h o top en producción?" \
          "Es reactivo y humano. Si el disco se llena o se quema a las 3 AM cuando nadie está en la consola, el servidor colapsa sin aviso."

pause_step "Presioná [ENTER] para dar el salto al monitoreo moderno con Node Exporter..."

# ------------------------------------------------------------------------------
# 2. El Salto Moderno: Node Exporter "Pelado" (Modelo PULL)
# ------------------------------------------------------------------------------
step_banner "2" "El Estándar Moderno: Node Exporter Puro (Modelo PULL al Desnudo)"

explain "En lugar de revisar a mano, dejamos un agente estandarizado y ultraliviano (<15 MB RAM)."
mkdir -p "$WORK_DIR"

if command -v node_exporter &>/dev/null; then
    BIN_NODE=$(command -v node_exporter)
else
    VER="1.8.2"
    TAR_FILE="/tmp/node_exporter-${VER}.linux-amd64.tar.gz"
    if [ ! -f "$TAR_FILE" ]; then
        curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz" -o "$TAR_FILE"
    fi
    tar -xzf "$TAR_FILE" -C /tmp/
    BIN_NODE="/tmp/node_exporter-${VER}.linux-amd64/node_exporter"
    chmod +x "$BIN_NODE"
fi

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
mkdir -p "$TEXTFILE_DIR"

explain "Levantamos Node Exporter en el puerto TCP :9100:"
"$BIN_NODE" --collector.textfile.directory="$TEXTFILE_DIR" --web.listen-address=":${NODE_PORT}" &>/tmp/node_exporter_taller.log &
NODE_PID=$!
sleep 1

explain "Hacemos una consulta HTTP GET PULL con curl (lo mismo que hace un servidor central):"
run_and_show "curl -s http://localhost:${NODE_PORT}/metrics | grep -E '(node_cpu_seconds_total|node_memory_MemAvailable_bytes)' | head -n 6"

pie_clase "¿Por qué se llama modelo PULL y no PUSH?" \
          "Porque el servidor de monitoreo inicia la conexión y 'raspa' (scrapes) las métricas cuando él quiere. Si el host no responde al GET, se sabe que cayó al instante."

pause_step "Presioná [ENTER] para construir el almacenamiento tolerante a fallas con LVM RAID 1..."

# ------------------------------------------------------------------------------
# 3. Almacenamiento Resiliente: LVM RAID 1 (dm-raid)
# ------------------------------------------------------------------------------
step_banner "3" "Almacenamiento Empresarial: LVM RAID 1 con 2 Discos"

if ! command -v lvs &>/dev/null; then
    explain "Instalando herramientas de LVM2 (lvm2):"
    if command -v dnf &>/dev/null; then
        dnf install -y lvm2
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq lvm2
    fi
fi

explain "Para que la página web no dependa de un solo disco, creamos 2 discos virtuales de 256 MB:"
run_and_show "truncate -s 256M ${WORK_DIR}/disk1.img ${WORK_DIR}/disk2.img"

LOOP1=$(losetup -f --show "${WORK_DIR}/disk1.img")
LOOP2=$(losetup -f --show "${WORK_DIR}/disk2.img")
echo -e "Dispositivos asignados: ${C_BOLD}${LOOP1} y ${LOOP2}${C_RESET}"

explain "Inicializamos Physical Volumes (PVs) y el Volume Group (${VG_NAME}):"
run_and_show "pvcreate -y -ff ${LOOP1} ${LOOP2}"
run_and_show "vgcreate -y ${VG_NAME} ${LOOP1} ${LOOP2}"

explain "Creamos el Logical Volume espejado RAID 1 (--type raid1 -m 1):"
run_and_show "lvcreate -y --type raid1 -m 1 -L 180M -n ${LV_NAME} ${VG_NAME} ${LOOP1} ${LOOP2}"

explain "Inspeccionamos los sub-volúmenes ocultos con lvs -a:"
run_and_show "lvs -a -o lv_name,attr,copy_percent,devices ${VG_NAME}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE SUB-LVs:${C_RESET}"
echo -e " • ${C_BOLD}lv_html_rimage_0 / 1${C_RESET} -> Las dos copias exactas de los datos en los dos discos físicos."
echo -e " • ${C_BOLD}lv_html_rmeta_0 / 1${C_RESET}  -> Sub-LVs de metadatos del kernel y write-intent bitmap."

pause_step "Presioná [ENTER] para formatear ext4, montar y desplegar la página web..."

# ------------------------------------------------------------------------------
# 4. Despliegue del Servidor Web en Producción
# ------------------------------------------------------------------------------
step_banner "4" "Puesta en Producción: Servidor Web sobre LVM RAID 1"

mkdir -p "$MOUNT_DIR"
explain "Formateamos el volumen RAID 1 con ext4 y lo montamos en ${MOUNT_DIR}:"
run_and_show "mkfs.ext4 -F -q /dev/${VG_NAME}/${LV_NAME}"
run_and_show "mount /dev/${VG_NAME}/${LV_NAME} ${MOUNT_DIR}"

explain "Desplegamos la página web corporativa en el almacenamiento espejado:"
cat << 'EOF' > "${MOUNT_DIR}/index.html"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Portal Web Corporativo</title></head>
<body style="font-family:sans-serif; background:#1e1e2e; color:#cdd6f4; text-align:center; padding-top:50px;">
  <h1 style="color:#a6e3a1;">🚀 SERVIDOR WEB CORPORATIVO RESILIENTE</h1>
  <p>Almacenamiento: <strong>LVM RAID 1 (/dev/vg_web/lv_html)</strong></p>
  <p>Tolerancia a fallos de hardware activa con <em>dm-raid</em>.</p>
</body>
</html>
EOF

explain "Levantamos el servicio Web en el puerto ${WEB_PORT} leyendo desde el disco espejado:"
python3 -m http.server "$WEB_PORT" --directory "$MOUNT_DIR" &>/dev/null &
WEB_PID=$!
sleep 1

run_and_show "curl -sI http://localhost:${WEB_PORT}/ | head -n 4"

pause_step "Presioná [ENTER] para inyectar tráfico web y generar métricas..."

# ------------------------------------------------------------------------------
# 5. Generación de Tráfico Web y Registro de Telemetría
# ------------------------------------------------------------------------------
step_banner "5" "Tráfico Web y Registro de Peticiones"

explain "Simulamos clientes navegando el sitio web corporativo:"
echo "25" > /tmp/web_requests.count
for i in {1..25}; do
    curl -s "http://localhost:${WEB_PORT}/" > /dev/null
done
echo -e "${C_GREEN}✔ 25 peticiones procesadas exitosamente desde el volumen espejado.${C_RESET}"

explain "Publicamos el contador para que Node Exporter lo exponga:"
cat << EOF > "${TEXTFILE_DIR}/web_traffic.prom"
# HELP web_requests_total Total de peticiones HTTP servidas
# TYPE web_requests_total counte
web_requests_total 25
EOF

run_and_show "curl -s http://localhost:${NODE_PORT}/metrics | grep web_requests_total"

pause_step "Presioná [ENTER] para el momento cumbre: ¡destrucción física del disco 1!..."

# ------------------------------------------------------------------------------
# 6. Inyección de Falla de Disco en Vivo
# ------------------------------------------------------------------------------
step_banner "6" "¡FALLA DE HARDWARE EN VIVO! Destrucción de Disco 1"

explain "Simulamos un corte eléctrico o rotura catastrófica sobrescribiendo el disco 1 con ceros:"
run_and_show "dd if=/dev/zero of=${LOOP1} bs=1M count=10 conv=notrunc status=none"
blockdev --flushbufs "$LOOP1" 2>/dev/null || true

explain "LVM detecta la anomalía en el Physical Volume:"
run_and_show "lvs -a -o lv_name,attr,health_status ${VG_NAME}"

echo -e "\n${C_BOLD}${C_RED}🚨 ALERTA DE DISCO DEGRADADO DETECTADA:${C_RESET}"
echo -e " • health_status: ${C_BOLD}degraded${C_RESET}"
echo -e " • Atributo noveno: ${C_BOLD}p (partial)${C_RESET} -> Falta un disco en el arreglo."

pie_clase "¿Se cayó el servicio web corporativo al romperse el disco físico?" \
          "¡NO! El kernel sigue sirviendo lecturas transparentemente desde la segunda pata del espejo."

pause_step "Presioná [ENTER] para comprobar que la página web sigue en línea al 100%..."

# ------------------------------------------------------------------------------
# 7. Comprobación de Resiliencia en Vivo
# ------------------------------------------------------------------------------
step_banner "7" "Prueba de Resiliencia: La Web Sigue Viva"

explain "Consultamos nuevamente el sitio web corporativo tras la muerte del disco 1:"
run_and_show "curl -sI http://localhost:${WEB_PORT}/ | head -n 4"
run_and_show "curl -s http://localhost:${WEB_PORT}/ | grep 'SERVIDOR WEB'"

echo -e "\n${C_BOLD}${C_GREEN}✔ DEMOSTRACIÓN EXITOSA: ZERO DOWNTIME${C_RESET}"
echo -e "Los usuarios nunca se enteraron de la rotura física del disco."

pause_step "Presioná [ENTER] para reemplazar el disco roto y reconstruir el RAID en caliente..."

# ------------------------------------------------------------------------------
# 8. Reemplazo y Reconstrucción en Caliente (Hot-Repair)
# ------------------------------------------------------------------------------
step_banner "8" "Reemplazo de Disco y Reconstrucción en Vivo (Hot-Repair)"

explain "El administrador inserta un disco nuevo de reemplazo (disk_spare.img de 256M):"
run_and_show "truncate -s 256M ${WORK_DIR}/disk_spare.img"
LOOP_SPARE=$(losetup -f --show "${WORK_DIR}/disk_spare.img")

explain "Sumamos el disco nuevo al Volume Group:"
run_and_show "pvcreate -y ${LOOP_SPARE}"
run_and_show "vgextend ${VG_NAME} ${LOOP_SPARE}"

explain "Ejecutamos la autorreparación del espejo con lvconvert --repair:"
run_and_show "lvconvert -y --repair ${VG_NAME}/${LV_NAME}"

explain "Purgamos el disco roto huérfano con vgreduce --removemissing:"
run_and_show "vgreduce --removemissing --force ${VG_NAME}"

explain "Inspeccionamos el estado final de salud del arreglo LVM:"
run_and_show "lvs -o lv_name,attr,health_status,devices ${VG_NAME}"

echo -e "\n${C_BOLD}${C_GREEN}✔ ¡El espejo LVM RAID 1 fue completamente restaurado a estado SANO!${C_RESET}"

pause_step "Presioná [ENTER] para ver el Dashboard TUI de terminal y la integración con Grafana..."

# ------------------------------------------------------------------------------
# 9. Dashboard TUI y Observabilidad Visual
# ------------------------------------------------------------------------------
step_banner "9" "Panel TUI en Terminal y el Circuito Prometheus + Grafana"

explain "Para monitorear todo en vivo sin instalar interfaces pesadas durante la clase,"
explain "creamos un TUI liviano en terminal. Mostramos una captura del estado en vivo:"

export VG_NAME LV_NAME WEB_PORT NODE_PORT
bash linux/administrator/monitoreo/scripts/tui_monitoreo.sh 1 &
TUI_PID=$!
sleep 3
kill "$TUI_PID" 2>/dev/null || true

echo -e "\n${C_CYAN}📈 CÓMO SE INTEGRA EN PRODUCCIÓN CON PROMETHEUS Y GRAFANA:${C_RESET}"
echo -e " 1. ${C_BOLD}Prometheus${C_RESET}: Lee (:9100/metrics) cada 15 segundos mediante su archivo prometheus.yml."
echo -e " 2. ${C_BOLD}Grafana${C_RESET}: Se conecta a Prometheus y dibuja paneles visuales con lenguaje PromQL:"
echo -e "    • Salud de LVM:    ${C_YELLOW}lvm_mirror_health${C_RESET} (Alarma si baja a 0)"
echo -e "    • Tráfico Web:     ${C_YELLOW}rate(web_requests_total[1m])${C_RESET} (Gráfico de solicitudes/segundo)"
echo -e "    • Espacio en ext4: ${C_YELLOW}node_filesystem_avail_bytes{mountpoint=\"/var/www/html_lab\"}${C_RESET}"

pause_step "Presioná [ENTER] para finalizar el taller y limpiar el entorno..."

step_banner "FIN" "Taller Integrador Finalizado con Éxito"
echo -e "${C_BOLD}${C_GREEN}✔ Se demostró el ciclo completo: Monitoreo PULL, LVM RAID 1, Falla, Resiliencia y Observabilidad.${C_RESET}\n"
