#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN DIDÁCTICA: Cifrado en Espacio de Usuario con Gocryptfs (FUSE)
# Laboratorio: linux/administrator/gocryptfs/gocryptfs.md
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Cifrado transparente archivo por archivo (AES-256-GCM + EME para nombres).
#  - Comparativa directa: Carpeta Visible (Plaintext) vs Carpeta Cifrada (Ciphertext).
#  - Operación en espacio de usuario sin privilegios root.
#  - Integración ideal para sincronización incremental en la nube (S3, Dropbox, Rsync).
#  - Preguntas disparadoras ("pie de clase") con respuestas desplegables.
#  - Limpieza garantizada al finalizar (fusermount -u y trap cleanup).
#
# Uso:
#   ./demo_gocryptfs.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_gocryptfs.sh --auto 2 -> Modo desatendido (espera 2s entre pasos)
#   ./demo_gocryptfs.sh --keep   -> Preserva las carpetas para pruebas manuales
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
KEEP_FILES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_WAIT="${2:-2}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
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

LAB_DIR="/tmp/demo_gocryptfs_$$"
DIR_CIPHER="${LAB_DIR}/datos_cifrados"
DIR_PLAIN="${LAB_DIR}/datos_visibles"
PASS_FILE="${LAB_DIR}/.vault_pass"
PASS_DEMO="ClaseGocryptfs2026!"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando sistema FUSE y limpiando recursos...${C_RESET}"
    if [ "$KEEP_FILES" = true ]; then
        echo -e "${C_GREEN}[INFO] Carpetas preservadas para práctica manual:${C_RESET}"
        echo -e "  • Cifrada: ${DIR_CIPHER}"
        echo -e "  • Visible: ${DIR_PLAIN}"
        echo -e "Para desmontar manualmente: fusermount -u ${DIR_PLAIN}"
        return
    fi

    if mountpoint -q "${DIR_PLAIN}" 2>/dev/null; then
        fusermount -u "${DIR_PLAIN}" 2>/dev/null || true
    fi
    rm -rf "${LAB_DIR}" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Sistema FUSE desmontado y carpetas temporales eliminadas.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_DIM}⏳ [MODO AUTO] Esperando ${AUTO_WAIT}s...${C_RESET}"
        sleep "$AUTO_WAIT"
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
        if [ "$AUTO_WAIT" -gt 0 ]; then
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

echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 🔐 DEMOSTRACIÓN EN VIVO: CIFRADO FUSE A NIVEL DE ARCHIVOS (GOCRYPTFS)         ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}===============================================================================${C_RESET}"
echo -e "Espacio de Usuario (sin root) ➔ Carpetas Cifrada vs Visible ➔ Cifrado AES-256-GCM\n"

# ==============================================================================
# PASO 0: VERIFICAR GOCRYPTFS Y FUSE
# ==============================================================================
step_banner "0" "Verificación de Herramientas (gocryptfs y fusermount)"

explain "Comprobando la presencia de gocryptfs en el sistema:"
if command -v gocryptfs >/dev/null 2>&1; then
    run_and_show "gocryptfs -version"
else
    echo -e "${C_RED}[ERROR] gocryptfs no está instalado.${C_RESET}"
    echo -e "Instálalo con: sudo apt install -y gocryptfs"
    exit 1
fi

pie_clase "¿Cuál es la diferencia fundamental entre LUKS y gocryptfs?" \
          "LUKS cifra a nivel de bloques/partición entera (requiere root y un tamaño fijo preasignado). gocryptfs cifra a nivel de archivos individuales sobre cualquier filesystem ordinario mediante FUSE (no requiere root y crece dinámicamente)."

pause_step "Presioná [ENTER] para crear las carpetas de trabajo..."

# ==============================================================================
# PASO 1: CREAR CARPETAS CIFRADA Y VISIBLE
# ==============================================================================
step_banner "1" "Estructura de Directorios: Carpeta Cifrada y Carpeta Visible"

explain "Necesitamos dos carpetas:"
explain "1) Carpeta Cifrada (Ciphertext): Almacena los bloques y nombres cifrados que se pueden sincronizar en la nube."
explain "2) Carpeta Visible (Plaintext): Punto de montaje FUSE donde el usuario trabaja en texto plano."

mkdir -p "${DIR_CIPHER}" "${DIR_PLAIN}"
run_and_show "ls -ld ${DIR_CIPHER} ${DIR_PLAIN}"

pause_step "Presioná [ENTER] para inicializar el contenedor criptográfico..."

# ==============================================================================
# PASO 2: INICIALIZAR EL DIRECTORIO CIFRADO (gocryptfs -init)
# ==============================================================================
step_banner "2" "Inicialización Criptográfica (gocryptfs -init)"

explain "Creamos el archivo de contraseña temporal seguro:"
echo "${PASS_DEMO}" > "${PASS_FILE}"
chmod 600 "${PASS_FILE}"

explain "Inicializamos la carpeta cifrada con la contraseña. Esto genera el archivo 'gocryptfs.conf':"
run_and_show "gocryptfs -init -q -passfile '${PASS_FILE}' '${DIR_CIPHER}'"

explain "Inspeccionamos los metadatos generados en la carpeta cifrada:"
run_and_show "ls -la '${DIR_CIPHER}'"

explain "Mostramos el archivo gocryptfs.conf (contiene el salt, versión y la Master Key cifrada con Scrypt):"
run_and_show "cat '${DIR_CIPHER}/gocryptfs.conf'"

pie_clase "Si un atacante roba el archivo 'gocryptfs.conf', ¿puede descifrar los datos?" \
          "No. El archivo contiene la clave maestra protegida por la función de derivación Scrypt con salting. Requiere la contraseña para descifrarla."

pause_step "Presioná [ENTER] para montar la carpeta visible con FUSE..."

# ==============================================================================
# PASO 3: MONTAR LA CARPETA VISIBLE (gocryptfs)
# ==============================================================================
step_banner "3" "Montaje del Filesystem Virtual en Espacio de Usuario"

explain "Montamos la carpeta cifrada en el punto visible utilizando FUSE:"
run_and_show "gocryptfs -q -passfile '${PASS_FILE}' '${DIR_CIPHER}' '${DIR_PLAIN}'"

explain "Comprobamos el tipo de filesystem montado mediante mount y df:"
run_and_show "mount | grep '${DIR_PLAIN}'"

pie_clase "¿Por qué el sistema de archivos aparece como 'fuse.gocryptfs'?" \
          "Porque el kernel delega las operaciones de lectura y escritura al proceso gocryptfs en espacio de usuario a través del módulo /dev/fuse."

pause_step "Presioná [ENTER] para escribir datos confidenciales..."

# ==============================================================================
# PASO 4: CREACIÓN DE ARCHIVOS Y COMPARATIVA EN VIVO
# ==============================================================================
step_banner "4" "Prueba en Vivo: Visión del Usuario vs Visión del Almacenamiento"

explain "Escribimos archivos corporativos confidenciales dentro de la carpeta visible:"
cat << 'EOF' > "${DIR_PLAIN}/clientes_banco.csv"
id,nombre,saldo,tarjeta_credito
1,Carlos Gardel,150000.50,4509-1234-5678-9012
2,Eva Duarte,850000.00,4509-9876-5432-1098
EOF

echo "CLAVE_PRIVADA_API_2026_XYZ_PRODUCTION" > "${DIR_PLAIN}/api_secret.token"
mkdir -p "${DIR_PLAIN}/documentos"
echo "Reporte confidencial de auditoría" > "${DIR_PLAIN}/documentos/reporte_anual.pdf"

explain "1. VISIÓN DEL USUARIO (Carpeta Visible - Texto Plano):"
run_and_show "tree '${DIR_PLAIN}' 2>/dev/null || ls -laR '${DIR_PLAIN}'"
run_and_show "cat '${DIR_PLAIN}/clientes_banco.csv'"

explain "2. VISIÓN DEL ALMACENAMIENTO FÍSICO O DE LA NUBE (Carpeta Cifrada):"
run_and_show "tree '${DIR_CIPHER}' 2>/dev/null || ls -laR '${DIR_CIPHER}'"

explain "Intentamos buscar texto plano en los archivos de la carpeta cifrada:"
run_and_show "strings '${DIR_CIPHER}'/* 2>/dev/null | grep 'Carlos Gardel' || echo 'CERO coincidencias: Todo el contenido y nombres están 100% cifrados.'"

pie_clase "¿Por qué los nombres de los archivos en la carpeta cifrada son cadenas aleatorias como 'k9Xq_...'?" \
          "Porque gocryptfs aplica cifrado de nombres de archivo (EME cipher) con inicialización vectorial por directorio (gocryptfs.diriv) para que nadie sepa ni siquiera cuántos archivos hay o cómo se llaman."

pause_step "Presioná [ENTER] para simular el cierre de sesión (desmontaje)..."

# ==============================================================================
# PASO 5: DESMONTAJE SEGURO Y PROTECCIÓN EN REPOSO
# ==============================================================================
step_banner "5" "Desmontaje con fusermount -u y Prueba de Seguridad"

explain "Desmontamos la carpeta visible con 'fusermount -u':"
run_and_show "fusermount -u '${DIR_PLAIN}'"

explain "Comprobamos el contenido de la carpeta visible tras el desmontaje:"
run_and_show "ls -la '${DIR_PLAIN}'"

explain "Los datos desaparecieron completamente de la vista del sistema operativo."
explain "Los archivos permanecen seguros en reposo dentro de la carpeta cifrada:"
run_and_show "ls -lh '${DIR_CIPHER}'"

pie_clase "¿Por qué gocryptfs es ideal para sincronizar carpetas con Google Drive, Dropbox, Nextcloud o AWS S3?" \
          "Porque cada archivo se cifra por separado. Si modificás 1 línea en 1 archivo, la nube solo sube ese archivo modificado, a diferencia de LUKS o VeraCrypt donde tendrías que resincronizar un archivo gigante de varios gigabytes."

pause_step "Presioná [ENTER] para reabrir el contenedor y validar la integridad..."

# ==============================================================================
# PASO 6: REAPERTURA Y VERIFICACIÓN DE INTEGRIDAD
# ==============================================================================
step_banner "6" "Reapertura de la Bóveda y Comprobación de Datos"

explain "El usuario reabre su bóveda volviendo a montar la carpeta visible:"
run_and_show "gocryptfs -q -passfile '${PASS_FILE}' '${DIR_CIPHER}' '${DIR_PLAIN}'"

explain "Verificamos que todos los archivos y contenidos se recuperaron intactos:"
run_and_show "cat '${DIR_PLAIN}/clientes_banco.csv'"
run_and_show "cat '${DIR_PLAIN}/api_secret.token'"
run_and_show "cat '${DIR_PLAIN}/documentos/reporte_anual.pdf'"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE GOCRYPTFS FINALIZADA CON ÉXITO!                          ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado el cifrado en espacio de usuario con FUSE, separación de carpetas,"
echo -e "cifrado individual de archivos y nombres, y desmontaje seguro con fusermount -u.\n"
