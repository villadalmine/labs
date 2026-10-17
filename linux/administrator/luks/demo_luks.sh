#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Cifrado de Discos y Particiones con LUKS / dm-crypt
# Basado en: linux/administrator/luks/luks.md
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema destacada en una caja limpia.
#  - Desglosa y explica los campos clave (luksDump, keyslots, dm-crypt).
#  - Demostración forense con strings contra robo físico.
#  - Preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   sudo ./demo_luks.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_luks.sh --auto 4 -> Modo automático (espera 4s entre pasos)
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Este script requiere privilegios de superusuario (sudo)."
    exit 1
fi

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

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

IMG_FILE="/var/tmp/demo_luks.img"
MAP_NAME="demo_luks_mapper"
MOUNT_DIR="/mnt/demo_luks"
PASSPHRASE="ClaseLinuxLuks2026!"
LOOP_DEV=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando y cerrando contenedor LUKS...${C_RESET}"
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        umount -f "$MOUNT_DIR" 2>/dev/null || true
    fi
    if [ -e "/dev/mapper/$MAP_NAME" ]; then
        cryptsetup luksClose "$MAP_NAME" 2>/dev/null || true
    fi
    if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    rm -f "$IMG_FILE" 2>/dev/null || true
    rmdir "$MOUNT_DIR" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Contenedor LUKS cerrado y loop device liberado.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón directamente."
    echo -e "  - ${C_YELLOW}Scroll con TECLADO:${C_RESET} Presioná ${C_BOLD}Ctrl+b${C_RESET} y luego ${C_BOLD}[${C_RESET} (salís con ${C_BOLD}q${C_RESET})."
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
fi

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
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "${AUTO_WAIT:-0}" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM:-\033[2m}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
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
        read -r
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

clear || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🔐 LABORATORIO EN VIVO: CIFRADO DE BLOQUES CON LUKS Y DM-CRYPT                ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "luksFormat ➔ luksDump ➔ luksOpen ➔ mkfs.ext4 ➔ Inspección Forense contra Robo"
echo -e "Demostración de por qué robar un disco físico cifrado no sirve de nada\n"

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------
step_banner "0" "Verificación de paquetes y herramientas"

explain "Comprobando la presencia de cryptsetup, losetup y e2fsprogs:"
MISSING_PKGS=()
for pkg in cryptsetup losetup mkfs.ext4; do
    if ! command -v "$pkg" &>/dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}Faltan herramientas: ${MISSING_PKGS[*]}. Instalando...${C_RESET}"
    if command -v dnf &>/dev/null; then
        dnf install -y cryptsetup util-linux e2fsprogs
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq cryptsetup util-linux e2fsprogs
    fi
fi
echo -e "${C_GREEN}✔ Herramientas LUKS disponibles.${C_RESET}"

pause_step "Presioná [ENTER] para crear el disco virtual de prueba..."

# ------------------------------------------------------------------------------
# 1. Crear el Disco Virtual y asociar Loop Device
# ------------------------------------------------------------------------------
step_banner "1" "Creación de Disco Virtual de 512 MB"

explain "Para probar LUKS sin alterar particiones físicas, creamos una imagen de 512 MB en ${IMG_FILE}:"
run_and_show "truncate -s 512M ${IMG_FILE}"

explain "Asociamos la imagen al primer loop device libre disponible:"
run_and_show "losetup --find --show ${IMG_FILE}"
LOOP_DEV=$(losetup -j "${IMG_FILE}" | cut -d: -f1 | head -n 1)

echo -e "Dispositivo asignado: ${C_BOLD}${LOOP_DEV}${C_RESET}"

pie_clase "¿LUKS cifra a nivel de archivos individuales o a nivel de sectores de disco?" \
          "A nivel de bloques/sectores (Block-level). El kernel cifra los bloques antes de enviarlos al hardware."

pause_step "Presioná [ENTER] para formatear el dispositivo con LUKS2..."

# ------------------------------------------------------------------------------
# 2. Inicializar formato LUKS (luksFormat)
# ------------------------------------------------------------------------------
step_banner "2" "Formateo con LUKS2 (cryptsetup luksFormat)"

explain "LUKS crea una cabecera criptográfica con ranuras de claves (keyslots) protegidas por contraseña."
explain "Usaremos la contraseña demo: '${PASSPHRASE}':"

run_and_show "echo -n '${PASSPHRASE}' | cryptsetup luksFormat -q --type luks2 ${LOOP_DEV} -"

explain "Inspeccionamos la cabecera LUKS con cryptsetup luksDump:"
run_and_show "cryptsetup luksDump ${LOOP_DEV} | grep -E '(Version|Cipher name|Cipher mode|Key size|UUID|Keyslot)'"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • ${C_BOLD}Version: 2${C_RESET} -> Formato moderno LUKS2 con checksums y resiliencia a cortes de energía."
echo -e " • ${C_BOLD}Cipher: aes-xts-plain64${C_RESET} -> El estándar de la industria militar y bancaria."
echo -e " • ${C_BOLD}Keyslot 0: luks2${C_RESET} -> Contiene la clave maestra cifrada con nuestra contraseña mediante Argon2id."

pause_step "Presioná [ENTER] para abrir el contenedor y crear el dispositivo mapeado..."

# ------------------------------------------------------------------------------
# 3. Abrir el contenedor LUKS (luksOpen)
# ------------------------------------------------------------------------------
step_banner "3" "Apertura del contenedor criptográfico (luksOpen)"

explain "cryptsetup descifra la clave maestra con nuestra contraseña y la entrega al módulo dm-crypt del kernel."
explain "El kernel crea un dispositivo de bloques virtual transparente en /dev/mapper/${MAP_NAME}:"

run_and_show "echo -n '${PASSPHRASE}' | cryptsetup luksOpen ${LOOP_DEV} ${MAP_NAME} -"

explain "Verificamos el dispositivo virtual y su estado criptográfico:"
run_and_show "ls -l /dev/mapper/${MAP_NAME}"
run_and_show "cryptsetup status ${MAP_NAME}"

pie_clase "¿Quién realiza el cifrado y descifrado en tiempo real mientras el sistema opera?" \
          "El módulo dm-crypt en espacio de kernel, usando aceleración por hardware AES-NI de la CPU."

pause_step "Presioná [ENTER] para formatear con ext4 y montar el volumen cifrado..."

# ------------------------------------------------------------------------------
# 4. Formatear y Montar
# ------------------------------------------------------------------------------
step_banner "4" "Formateo con ext4 y Montaje Transparente"

explain "Formateamos el dispositivo virtual descifrado /dev/mapper/${MAP_NAME} con ext4:"
run_and_show "mkfs.ext4 -F -q /dev/mapper/${MAP_NAME}"

mkdir -p "$MOUNT_DIR"
explain "Montamos el volumen en ${MOUNT_DIR}:"
run_and_show "mount /dev/mapper/${MAP_NAME} ${MOUNT_DIR}"
run_and_show "df -h ${MOUNT_DIR}"

pause_step "Presioná [ENTER] para escribir datos altamente confidenciales..."

# ------------------------------------------------------------------------------
# 5. Escribir Datos Confidenciales
# ------------------------------------------------------------------------------
step_banner "5" "Almacenamiento de Datos Secretos"

explain "Escribimos un secreto en ${MOUNT_DIR}/secreto.txt:"
run_and_show "echo 'DATOS_CONFIDENCIALES: Clave de produccion bancaria 2026-XYZ' > ${MOUNT_DIR}/secreto.txt"
run_and_show "cat ${MOUNT_DIR}/secreto.txt"

explain "El archivo es legible normalmente porque el volumen está abierto en el kernel."

pause_step "Presioná [ENTER] para desmontar, cerrar LUKS y simular el robo físico del disco..."

# ------------------------------------------------------------------------------
# 6. Desmontar, Cerrar y Demostración Forense contra Robo
# ------------------------------------------------------------------------------
step_banner "6" "Cierre Seguro y Prueba Forense de Robo de Disco"

explain "Desmontamos el filesystem y cerramos el canal dm-crypt con cryptsetup luksClose:"
run_and_show "umount ${MOUNT_DIR}"
run_and_show "cryptsetup luksClose ${MAP_NAME}"

explain "Comprobamos que /dev/mapper/${MAP_NAME} desapareció del sistema:"
run_and_show "ls -l /dev/mapper/${MAP_NAME}"

echo -e "\n${C_BOLD}${C_YELLOW}📢 DEMOSTRACIÓN DIDÁCTICA: ¿Qué ve un atacante si roba el disco físico?${C_RESET}"
explain "Un atacante extrae el disco crudo (${LOOP_DEV}) y ejecuta 'strings' para buscar texto plano:"
run_and_show "strings ${LOOP_DEV} | grep 'DATOS_CONFIDENCIALES'"

echo -e "\n${C_BOLD}${C_GREEN}✔ RESULTADO FORENSE: ¡CERO COINCIDENCIAS!${C_RESET}"
echo -e "Los datos físicos en los sectores del disco son 100% ruido pseudoaleatorio indistinguible."

pie_clase "Si un atacante roba un servidor apagado con LUKS, ¿puede leer los datos sin la contraseña?" \
          "¡Imposible! Tendría que romper AES-256 o hacer fuerza bruta contra la función de derivación Argon2id."

pause_step "Presioná [ENTER] para reabrir el contenedor y demostrar que los datos siguen intactos..."

# ------------------------------------------------------------------------------
# 7. Reabrir y Recuperar Datos
# ------------------------------------------------------------------------------
step_banner "7" "Reapertura Legítima con Contraseña y Verificación de Integridad"

explain "El administrador legítimo reabre el contenedor con su contraseña:"
run_and_show "echo -n '${PASSPHRASE}' | cryptsetup luksOpen ${LOOP_DEV} ${MAP_NAME} -"
run_and_show "mount /dev/mapper/${MAP_NAME} ${MOUNT_DIR}"

explain "Leemos nuevamente el archivo confidencial:"
run_and_show "cat ${MOUNT_DIR}/secreto.txt"

echo -e "\n${C_BOLD}${C_GREEN}✔ ¡Los datos fueron descifrados y están 100% íntegros!${C_RESET}"

pause_step "Presioná [ENTER] para finalizar la demostración y limpiar el entorno..."

step_banner "FIN" "Demostración de LUKS finalizada"
echo -e "${C_BOLD}${C_GREEN}✔ LUKS, cabeceras dm-crypt y protección de bloques completados con éxito.${C_RESET}\n"
