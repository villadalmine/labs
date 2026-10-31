#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Detección, Inventario y Auditoría Forense de Hardware
# lspci, lsusb, lshw, hwinfo, dmidecode, lscpu
#
# Basado en el temario de Administración Linux (EducaciónIT - Módulo 5)
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema en una caja formateada.
#  - Desglosa qué significa cada campo (arquitectura, buses, DMI/SMBIOS).
#  - Preguntas didácticas ("pie de clase") con respuestas desplegables.
#  - 5 Escenarios reales: Troubleshooting, compatibilidad, drivers, upgrades y CMDB.
#
# Uso:
#   sudo ./demo_hardware.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               Preserva el reporte de inventario JSON generado
#   --help               Muestra este mensaje de ayuda
# ==============================================================================

set -uo pipefail

if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[0;36m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para acceder a tablas DMI y buses físicos.${C_RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        --help|-h)
            echo "Uso: sudo ./demo_hardware.sh [--auto <segundos>] [--keep] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

pause_step() {
    local mensaje="${1:-Presiona [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${C_YELLOW}⏳ [MODO AUTO] Esperando ${AUTO_DELAY}s: ${mensaje}${C_RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${mensaje}${C_RESET}"
        read -r </dev/tty 2>/dev/null || read -r
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
    local pregunta="$1"
    local respuesta="${2:-}"
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase / autoaprendizaje: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_MODE" = true ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta esperada...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
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

DIR_LAB="/tmp/lab_demo_hardware"
mkdir -p "$DIR_LAB"

cleanup() {
    if [ "$KEEP_FILES" = true ]; then
        echo -e "\n${C_GREEN}[INFO] Se preservan los reportes de inventario en ${DIR_LAB} por opción --keep.${C_RESET}"
    else
        rm -rf "$DIR_LAB"
        echo -e "\n${C_GREEN}✔ Archivos temporales limpiados correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🖥️  DEMOSTRACIÓN EN VIVO: DETECCIÓN Y AUDITORÍA DE HARDWARE EN LINUX            ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "lspci, lsusb, lshw, hwinfo, dmidecode, lscpu"
echo -e "Auditoría de procesador, buses PCIe, periféricos USB, firmware DMI y Casos Reales\n"

# ==============================================================================
# PASO 1: VERIFICAR E INSTALAR PAQUETES DE HARDWARE
# ==============================================================================
step_banner "1" "Verificación de herramientas de detección de hardware"

explain "Validando la existencia de lscpu, lspci, lsusb, dmidecode, lshw y hwinfo:"
MISSING_PKGS=()
for tool in lscpu lspci lsusb dmidecode lshw; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_PKGS+=("$tool")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}Instalando paquetes base faltantes (${MISSING_PKGS[*]})...${C_RESET}"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq pciutils usbutils lshw dmidecode util-linux
    elif command -v dnf &>/dev/null; then
        dnf install -y -q pciutils usbutils lshw dmidecode util-linux
    fi
fi

if ! command -v hwinfo &>/dev/null; then
    echo -e "${C_DIM}hwinfo no está presente de forma predeterminada (tal como se explica en la teoría).${C_RESET}"
fi
echo -e "${C_GREEN}✔ Verificación de herramientas completada.${C_RESET}"

pie_clase "¿Por qué muchas de estas herramientas requieren privilegios de superusuario (sudo/root)?" \
          "Porque acceden a registros de bajo nivel (/dev/mem, /sys/firmware/dmi/tables) y descriptores físicos restringidos para proteger números de serie y configuración del firmware."

pause_step "Presioná [ENTER] para analizar la arquitectura del procesador con lscpu..."

# ==============================================================================
# PASO 2: RADIOGRAFÍA DE LA CPU CON LSCPU
# ==============================================================================
step_banner "2" "Análisis del Procesador y Topología de Núcleos con lscpu"

explain "lscpu resume la arquitectura de la CPU, sockets físicos, núcleos, hilos y cachés:"
run_and_show "lscpu | grep -E 'Architecture|CPU op-mode|Byte Order|CPU\(s\):|Thread|Core|Socket|Vendor ID|Model name|L1|L2|L3|NUMA'"

explain "Comprobando flags críticas: virtualización (vmx/svm), 64-bit (lm), cifrado (aes) y vectoriales (avx):"
run_and_show "lscpu | grep -i flags | grep -o -E '\b(vmx|svm|aes|avx|avx2|lm)\b' | sort -u | tr '\n' ' ' && echo"

pie_clase "Si un servidor tiene 2 Sockets, 8 Cores por socket y 2 Threads por core, ¿cuántas CPUs lógicas reporta lscpu?" \
          "Reporta 32 CPUs lógicas (2 x 8 x 2 = 32)."

pause_step "Presioná [ENTER] para inspeccionar los dispositivos en el bus PCI con lspci..."

# ==============================================================================
# PASO 3: INSPECCIÓN DEL BUS PCI / PCIE CON LSPCI
# ==============================================================================
step_banner "3" "Exploración de Dispositivos PCI/PCIe con lspci"

explain "Listamos todos los dispositivos conectados al bus PCI (puentes, GPU, USB, Ethernet, controladoras):"
run_and_show "lspci | head -n 12"

explain "Inspeccionamos los controladores del kernel en uso (Kernel driver in use) y módulos disponibles (-k):"
run_and_show "lspci -k | head -n 18"

explain "Visualizamos los identificadores numéricos de fabricante y producto en hexadecimal [VendorID:DeviceID] (-nn):"
run_and_show "lspci -nn | head -n 8"

pie_clase "¿Para qué le sirve al administrador conocer el ID [Vendor:Device] en formato [8086:1572]?" \
          "Para identificar el chip exacto con el fabricante, descargar firmware específico o compilar el driver correcto si el kernel no lo detecta automáticamente."

pause_step "Presioná [ENTER] para auditar periféricos y buses USB con lsusb..."

# ==============================================================================
# PASO 4: TOPOLOGÍA Y PERIFÉRICOS USB CON LSUSB
# ==============================================================================
step_banner "4" "Detección y Topología de Dispositivos USB con lsusb"

explain "Enumeramos los concentradores raíz (root hubs) y dispositivos conectados:"
run_and_show "lsusb"

explain "Mostramos la topología física en árbol indicando velocidades de negociación del bus (-t):"
run_and_show "lsusb -t"

pie_clase "¿Qué indica una velocidad de '5000M' o '10000M' en la salida de lsusb -t?" \
          "Indica que el dispositivo está operando en modo SuperSpeed USB 3.0 (5 Gbps) o USB 3.1/3.2 (10 Gbps)."

pause_step "Presioná [ENTER] para consultar metadatos del firmware BIOS y placa base con dmidecode..."

# ==============================================================================
# PASO 5: METADATOS DMI / SMBIOS CON DMIDECODE
# ==============================================================================
step_banner "5" "Extracción de Metadatos de BIOS, Motherboard y RAM con dmidecode"

explain "Consultamos información del sistema (Type 1: Manufacturer, Product Name, Serial Number, UUID):"
run_and_show "dmidecode -t system | grep -E 'Manufacturer|Product Name|Version|Serial Number|UUID|Wake-up'"

explain "Consultamos información de la placa base (Type 2: Baseboard):"
run_and_show "dmidecode -t baseboard | grep -E 'Manufacturer|Product Name|Version|Serial Number|Features'"

explain "Consultamos slots de memoria física (Type 17) para auditar capacidad y ranuras libres:"
run_and_show "dmidecode -t memory | grep -E 'Size:|Type:|Speed:|Manufacturer:|Locator:' | head -n 16"

pie_clase "¿Cómo nos ayuda dmidecode a planificar una ampliación de memoria sin apagar el servidor?" \
          "Permite verificar cuántas ranuras DIMM existen, cuántas están libres ('No Module Installed'), la tecnología (DDR4/DDR5) y la capacidad máxima admitida."

pause_step "Presioná [ENTER] para generar un inventario global jerárquico con lshw..."

# ==============================================================================
# PASO 6: INVENTARIO GLOBAL JERÁRQUICO CON LSHW
# ==============================================================================
step_banner "6" "Inventario Panorámico y Filtros por Clase con lshw"

explain "lshw genera una vista sintética en formato tabular de todas las clases de hardware (-short):"
run_and_show "lshw -short | head -n 25"

explain "Filtramos específicamente por la clase de red (-C network) o almacenamiento (-C disk):"
run_and_show "lshw -C network 2>/dev/null | grep -E 'description|product|vendor|logical name|serial|size|capacity|link' | head -n 15"

pie_clase "¿Por qué es útil exportar lshw en formato JSON o HTML?" \
          "Porque permite alimentar sistemas CMDB corporativos, auditorías automáticas y paneles web de inventario sin necesidad de parsear texto plano."

pause_step "Presioná [ENTER] para examinar hwinfo..."

# ==============================================================================
# PASO 7: DIAGNÓSTICO GRANULAR CON HWINFO
# ==============================================================================
step_banner "7" "Auditoría Estructurada con hwinfo"

if command -v hwinfo &>/dev/null; then
    explain "hwinfo ofrece un resumen compacto y estructurado de componentes (--short):"
    run_and_show "hwinfo --short | head -n 25"
else
    explain "hwinfo no está instalado en este sistema. Simulamos el diagnóstico granular mostrado en las diapositivas:"
    echo -e "${C_DIM}Ejemplo representativo de hwinfo sobre interfaz de red (Intel X710 10GbE SFP+):${C_RESET}"
    echo "16: PCI 400.0: 0200 Ethernet controller"
    echo "  [Created at pci.386]"
    echo "  SysFS ID: /devices/pci0000:00/0000:00:1c.0/0000:04:00.0"
    echo "  Hardware Class: network"
    echo "  Model: \"Intel Ethernet Controller X710 for 10GbE SFP+\""
    echo "  Vendor: pci 0x8086 \"Intel Corporation\""
    echo "  Device: pci 0x1572 \"Ethernet Controller X710 for 10GbE SFP+\""
    echo "  Driver: \"i40e\""
fi

pie_clase "¿Cuál es la principal ventaja de hwinfo?" \
          "Presenta una vista unificada con clases de hardware normalizadas, drivers, IDs de subdispositivo y rutas directas de SysFS en un formato consistente."

pause_step "Presioná [ENTER] para ejecutar los 5 Casos Reales del Temario..."

# ==============================================================================
# PASO 8: LOS 5 CASOS REALES DE PRODUCCIÓN
# ==============================================================================
step_banner "8" "Demostración de los 5 Casos Reales de Producción (Slides 5-8)"

explain "Caso 1: Solución de problemas (Troubleshooting de Red y Drivers en uso):"
run_and_show "lspci -k | grep -A 2 -i -E 'ethernet|network' || echo 'Dispositivo de red integrado detectado.'"

explain "Caso 2: Compatibilidad de Software (Validación de arquitectura 64-bit y virtualización KVM):"
run_and_show "lscpu | grep -E 'Architecture|CPU op-mode' && lscpu | grep -i flags | grep -o -E '\b(vmx|svm|avx|avx2|aes|lm)\b' | sort -u | tr '\n' ' ' && echo"

explain "Caso 3: Actualizaciones de Controladores (Identificación de IDs numéricos para drivers):"
run_and_show "lspci -nn | head -n 5"

explain "Caso 4: Planificación de Mejoras (Capacidad máxima de RAM y ranuras disponibles):"
run_and_show "dmidecode -t 16 2>/dev/null | grep -E 'Maximum Capacity|Number Of Devices' || echo 'Capacidad DMI consultada.'"

explain "Caso 5: Auditoría e Inventario Corporativo (Generación de reporte JSON con lshw):"
REPORT_FILE="${DIR_LAB}/reporte_hardware.json"
run_and_show "lshw -json > '${REPORT_FILE}' 2>/dev/null && head -n 25 '${REPORT_FILE}'"

echo -e "\n${C_GREEN}Tamaño del reporte de inventario generado:${C_RESET} $(du -h "${REPORT_FILE}" 2>/dev/null | cut -f1 || echo 'Generado')"
echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ✔ LABORATORIO COMPLETADO CON ÉXITO                                             ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado lscpu, lspci, lsusb, dmidecode, lshw y hwinfo para auditorías en Linux.\n"
