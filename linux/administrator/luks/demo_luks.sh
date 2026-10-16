#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Cifrado de Discos y Particiones con LUKS / dm-crypt
# Basado en: linux/administrator/luks.md
# Uso:
#   sudo ./demo_luks.sh          -> Modo interactivo (pausa con [ENTER])
#   sudo ./demo_luks.sh --auto 5 -> Modo automático (espera 5s entre pasos)
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
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"

IMG_FILE="/var/tmp/demo_luks.img"
MAP_NAME="demo_luks_mapper"
MOUNT_DIR="/mnt/demo_luks"
PASSPHRASE="ClaseLinuxLuks2026!"
LOOP_DEV=""

cleanup() {
    echo -e "\n${C_YELLOW}[!] Limpiando recursos de la prueba LUKS...${C_RESET}"
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
    echo -e "${C_GREEN}[OK] Recursos cerrados y eliminados correctamente.${C_RESET}"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Configuración amigable para TMUX
# ------------------------------------------------------------------------------
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
    echo -e "\n${C_MAGENTA}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW} PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}======================================================================${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💬 EXPLICACIÓN:${C_RESET} $1"
}

command_info() {
    echo -e "${C_BOLD}${C_GREEN}$ ${1}${C_RESET}"
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo auto)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_YELLOW}👉 ${msg}${C_RESET}"
        read -r
    fi
}

# ------------------------------------------------------------------------------
# 0. Verificaciones previas
# ------------------------------------------------------------------------------
step_banner "0" "Verificación de paquetes y herramientas"

explain "Comprobando la presencia de cryptsetup, losetup y e2fsprogs."
for pkg in cryptsetup losetup mkfs.ext4; do
    if ! command -v "$pkg" &>/dev/null; then
        echo -e "${C_RED}[ERROR] Falta la herramienta $pkg.${C_RESET}"
        echo "Instalala con: sudo apt install -y cryptsetup util-linux e2fsprogs"
        exit 1
    fi
done
echo -e "${C_GREEN}[OK] Herramientas LUKS disponibles.${C_RESET}"

pause_step "Presioná [ENTER] para crear el disco virtual de prueba..."

# ------------------------------------------------------------------------------
# 1. Crear el Disco Virtual y asociar Loop Device
# ------------------------------------------------------------------------------
step_banner "1" "Creación de Disco Virtual de 512MB"

explain "Para probar LUKS sin riesgo de dañar un disco físico real, creamos una imagen de 512MB en $IMG_FILE."
command_info "truncate -s 512M $IMG_FILE"
truncate -s 512M "$IMG_FILE"

explain "Asociamos la imagen a un loop device libre mediante 'losetup --find --show':"
LOOP_DEV=$(losetup --find --show "$IMG_FILE")
command_info "LOOP_DEV=\$(losetup --find --show $IMG_FILE) -> $LOOP_DEV"
echo -e "Dispositivo asignado: ${C_BOLD}$LOOP_DEV${C_RESET}"

pause_step "Presioná [ENTER] para inicializar y cifrar con LUKS..."

# ------------------------------------------------------------------------------
# 2. Inicializar formato LUKS (luksFormat)
# ------------------------------------------------------------------------------
step_banner "2" "Formateo con LUKS (cryptsetup luksFormat)"

explain "LUKS (Linux Unified Key Setup) crea un encabezado criptográfico en el dispositivo."
explain "El encabezado contiene ranuras de claves (keyslots) protegidas por contraseña y cifra con AES-XTS (256/512 bits)."
explain "Usaremos la contraseña demo: '${PASSPHRASE}'"

command_info "echo -n '$PASSPHRASE' | cryptsetup luksFormat -q --type luks2 $LOOP_DEV -"
echo -n "$PASSPHRASE" | cryptsetup luksFormat -q --type luks2 "$LOOP_DEV" -

echo -e "\n${C_BOLD}Información de la cabecera LUKS del dispositivo:${C_RESET}"
cryptsetup luksDump "$LOOP_DEV" | grep -E "(Version|Cipher name|Cipher mode|Key size|UUID|Keyslot)"

pause_step "Presioná [ENTER] para abrir el dispositivo descifrado (luksOpen)..."

# ------------------------------------------------------------------------------
# 3. Abrir el contenedor LUKS (luksOpen)
# ------------------------------------------------------------------------------
step_banner "3" "Apertura del contenedor criptográfico (luksOpen)"

explain "cryptsetup descifra la clave maestra usando la contraseña y la entrega al módulo dm-crypt del kernel."
explain "El kernel crea un dispositivo de bloques virtual transparente en /dev/mapper/$MAP_NAME."

command_info "echo -n '$PASSPHRASE' | cryptsetup luksOpen $LOOP_DEV $MAP_NAME -"
echo -n "$PASSPHRASE" | cryptsetup luksOpen "$LOOP_DEV" "$MAP_NAME" -

echo -e "\n${C_BOLD}Dispositivo mapeado activo:${C_RESET}"
ls -l "/dev/mapper/$MAP_NAME"
cryptsetup status "$MAP_NAME"

pause_step "Presioná [ENTER] para formatear con ext4 y montar el volumen..."

# ------------------------------------------------------------------------------
# 4. Formatear y Montar
# ------------------------------------------------------------------------------
step_banner "4" "Sistema de archivos ext4 y Montaje"

explain "Formateamos el dispositivo virtual /dev/mapper/$MAP_NAME con ext4."
explain "Todo lo que se escriba en este sistema de archivos será cifrado automáticamente por dm-crypt antes de tocar el disco."

command_info "mkfs.ext4 -F /dev/mapper/$MAP_NAME"
mkfs.ext4 -F "/dev/mapper/$MAP_NAME"

mkdir -p "$MOUNT_DIR"
command_info "mount /dev/mapper/$MAP_NAME $MOUNT_DIR"
mount "/dev/mapper/$MAP_NAME" "$MOUNT_DIR"

echo -e "\n${C_BOLD}Punto de montaje activo:${C_RESET}"
df -h "$MOUNT_DIR"

pause_step "Presioná [ENTER] para escribir un archivo confidencial de prueba..."

# ------------------------------------------------------------------------------
# 5. Escribir Datos Confidenciales
# ------------------------------------------------------------------------------
step_banner "5" "Almacenamiento de Datos Secretos"

explain "Escribimos un mensaje confidencial en $MOUNT_DIR/secreto.txt:"
echo "DATOS_CONFIDENCIALES: Clave de produccion bancaria 2026-XYZ" > "$MOUNT_DIR/secreto.txt"
command_info "cat $MOUNT_DIR/secreto.txt"
cat "$MOUNT_DIR/secreto.txt"

pause_step "Presioná [ENTER] para desmontar y cerrar el contenedor LUKS (luksClose)..."

# ------------------------------------------------------------------------------
# 6. Desmontar, Cerrar y Demostración Forense de Cifrado
# ------------------------------------------------------------------------------
step_banner "6" "Cierre seguro e Inspección Forense"

explain "Desmontamos el sistema de archivos y cerramos el mapeo criptográfico con 'cryptsetup luksClose'."
command_info "umount $MOUNT_DIR"
umount "$MOUNT_DIR"

command_info "cryptsetup luksClose $MAP_NAME"
cryptsetup luksClose "$MAP_NAME"

explain "¡Mirá ahora! El dispositivo /dev/mapper/$MAP_NAME ya no existe:"
ls -l "/dev/mapper/$MAP_NAME" 2>&1 || true

echo -e "\n${C_BOLD}${C_YELLOW}📢 DEMOSTRACIÓN DIDÁCTICA: ¿Qué ve un atacante si roba el disco?${C_RESET}"
explain "Intentamos buscar la cadena 'DATOS_CONFIDENCIALES' directamente en el disco crudo ($LOOP_DEV):"
command_info "strings $LOOP_DEV | grep 'DATOS_CONFIDENCIALES'"
if strings "$LOOP_DEV" 2>/dev/null | grep "DATOS_CONFIDENCIALES"; then
    echo -e "${C_RED}[ALERTA] Se encontró texto en claro.${C_RESET}"
else
    echo -e "${C_GREEN}[RESULTADO] ¡0 coincidencias! El disco es 100% ruido criptográfico ininteligible.${C_RESET}"
fi

pause_step "Presioná [ENTER] para reabrir el contenedor con la contraseña y recuperar los datos..."

# ------------------------------------------------------------------------------
# 7. Reabrir y Recuperar Datos
# ------------------------------------------------------------------------------
step_banner "7" "Reapertura con Contraseña y Verificación de Integridad"

explain "Reabrimos el contenedor usando la contraseña legítima:"
command_info "echo -n '$PASSPHRASE' | cryptsetup luksOpen $LOOP_DEV $MAP_NAME -"
echo -n "$PASSPHRASE" | cryptsetup luksOpen "$LOOP_DEV" "$MAP_NAME" -

command_info "mount /dev/mapper/$MAP_NAME $MOUNT_DIR"
mount "/dev/mapper/$MAP_NAME" "$MOUNT_DIR"

echo -e "\n${C_BOLD}Leyendo nuevamente el archivo secreto:${C_RESET}"
cat "$MOUNT_DIR/secreto.txt"
explain "¡Los datos están 100% intactos y disponibles!"

pause_step "Presioná [ENTER] para concluir y limpiar todos los recursos de prueba..."

step_banner "FIN" "Demostración de LUKS completada con éxito"
echo -e "${C_GREEN}¡Demostración de LUKS, encabezados dm-crypt y protección de bloques finalizada!${C_RESET}\n"
