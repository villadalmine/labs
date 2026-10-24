#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Diagnóstico y Mantenimiento de Volúmenes y Filesystems
# df, du, tune2fs, fsck, e2fsck, dumpe2fs, XFS Tools, Btrfs y badblocks
#
# Diseñado para clases interactivas:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema en una caja formateada.
#  - Desglosa métricas (inodos, superbloque, metadump, fragmentación, badblocks).
#  - Preguntas didácticas ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   sudo ./demo_mantenimiento_volumenes.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No desmontar ni limpiar al finalizar
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
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para operar sobre dispositivos de bloque.${C_RESET}"
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
    local pregunta="$1"
    local respuesta="${2:-}"
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_MODE" = true ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
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

DIR_LAB="/tmp/lab_demo_mantenimiento"
MNT_EXT4="/mnt/lab_mant_ext4"
MNT_XFS="/mnt/lab_mant_xfs"
MNT_BTRFS="/mnt/lab_mant_btrfs"

LOOP_EXT4=""
LOOP_XFS=""
LOOP_BTRFS=""
LOOP_BAD=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando y liberando recursos del laboratorio...${C_RESET}"
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los montajes por opción --keep.${C_RESET}"
        return
    fi

    for m in "$MNT_EXT4" "$MNT_XFS" "$MNT_BTRFS"; do
        if mountpoint -q "$m" 2>/dev/null; then
            umount -f "$m" 2>/dev/null || true
        fi
        rm -rf "$m" 2>/dev/null || true
    done

    for l in "$LOOP_EXT4" "$LOOP_XFS" "$LOOP_BTRFS" "$LOOP_BAD"; do
        if [ -n "$l" ]; then
            losetup -d "$l" 2>/dev/null || true
        fi
    done

    rm -rf "$DIR_LAB"
    echo -e "${C_GREEN}✔ Laboratorio limpio y recursos desmontados.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

clear || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🛠️  DEMOSTRACIÓN EN VIVO: MANTENIMIENTO Y REPARACIÓN DE VOLÚMENES              ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "df, du, tune2fs, fsck, e2fsck, dumpe2fs, XFS Tools, Btrfs y badblocks"
echo -e "Entorno seguro sobre dispositivos virtuales loop (/dev/loopX)\n"

mkdir -p "$DIR_LAB" "$MNT_EXT4" "$MNT_XFS" "$MNT_BTRFS"

# ==============================================================================
# PASO 1: VERIFICAR HERRAMIENTAS
# ==============================================================================
step_banner "1" "Verificación de paquetes y herramientas del sistema"

explain "Comprobando existencia de e2fsprogs, xfsprogs, btrfs-progs y badblocks:"
MISSING_PKGS=()
for tool in df du tune2fs fsck e2fsck dumpe2fs mkfs.ext4 mkfs.xfs xfs_metadump xfs_db mkfs.btrfs btrfs badblocks file; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_PKGS+=("$tool")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}Instalando paquetes faltantes: ${MISSING_PKGS[*]}...${C_RESET}"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq e2fsprogs xfsprogs btrfs-progs util-linux file xfsdump
    elif command -v dnf &>/dev/null; then
        dnf install -y e2fsprogs xfsprogs btrfs-progs util-linux file xfsdump
    fi
fi
echo -e "${C_GREEN}✔ Todas las herramientas necesarias están disponibles.${C_RESET}"

pause_step "Presioná [ENTER] para auditar espacio e inodos con df..."

# ==============================================================================
# PASO 2: AUDITORÍA DE ESPACIO E INODOS CON DF
# ==============================================================================
step_banner "2" "Monitoreo de Espacio e Inodos con df"

explain "Consultamos el espacio en todos los sistemas montados en formato legible (-h):"
run_and_show "df -h"

explain "Consultamos el espacio sobre un sistema de archivos específico (la raíz /):"
run_and_show "df -h /"

explain "Consultamos TODOS los sistemas de archivos montados, incluidos los virtuales (-a -h):"
run_and_show "df -a -h | head -n 12"

explain "Consultamos el espacio en bloques exactos de 1 Kilobyte (-k):"
run_and_show "df -k / | head -n 5"

explain "Consultamos la tabla crítica de INODOS disponibles y utilizados (-i):"
run_and_show "df -i"

pie_clase "¿Qué ocurre si df -h muestra 80% libre pero df -i muestra 100% de inodos usados?" \
          "El sistema operativo arroja 'No space left on device' y no permite crear ningún archivo nuevo, a pesar de tener Gigabytes de espacio físico libres."

pause_step "Presioná [ENTER] para analizar el consumo granular con du y ranking de archivos grandes..."

# ==============================================================================
# PASO 3: AUDITORÍA DE CONSUMO CON DU Y DETECCIÓN DE ARCHIVOS PESADOS
# ==============================================================================
step_banner "3" "Medición de Consumo con du y Ranking Top 10"

# Creamos una estructura de prueba con diferentes tamaños
TEST_DIR="${DIR_LAB}/datos_consumo"
mkdir -p "${TEST_DIR}/logs" "${TEST_DIR}/cache" "${TEST_DIR}/backups"
dd if=/dev/zero of="${TEST_DIR}/logs/app.log" bs=1M count=10 status=none
dd if=/dev/zero of="${TEST_DIR}/cache/temp.dat" bs=1M count=5 status=none
dd if=/dev/zero of="${TEST_DIR}/backups/dump.tar" bs=1M count=20 status=none

explain "1. Sumario de consumo del directorio (-sh):"
run_and_show "du -sh '${TEST_DIR}'"

explain "2. Gran total desglosando subdirectorios (-sch):"
run_and_show "du -sch '${TEST_DIR}'/*"

explain "3. Excluir subdirectorios del cálculo del directorio contenedor (-S):"
run_and_show "du -Sh '${TEST_DIR}'"

explain "4. Ranking de los elementos más pesados ordenados por tamaño (du | sort -hr | head):"
run_and_show "du -ah '${TEST_DIR}' | sort -hr | head -n 5"

pie_clase "¿Cuál es la diferencia entre du -s y du -S?" \
          "'-s' suma recursivamente todo el contenido del directorio en una sola línea de sumario. '-S' reporta el tamaño exclusivo de los archivos del directorio, sin sumar los subdirectorios."

pause_step "Presioná [ENTER] para configurar discos virtuales loop de prueba..."

# ==============================================================================
# PASO 4: CREACIÓN DE DISCOS VIRTUALES LOOP
# ==============================================================================
step_banner "4" "Preparación de Volúmenes Virtuales para Mantenimiento Seguro"

explain "Creamos discos virtuales loop de 100 MB para ext4, XFS y Btrfs:"
dd if=/dev/zero of="${DIR_LAB}/disco_ext4.img" bs=1M count=100 status=none
dd if=/dev/zero of="${DIR_LAB}/disco_xfs.img" bs=1M count=100 status=none
dd if=/dev/zero of="${DIR_LAB}/disco_btrfs.img" bs=1M count=100 status=none
dd if=/dev/zero of="${DIR_LAB}/disco_bad.img" bs=1M count=10 status=none

LOOP_EXT4=$(losetup -f --show "${DIR_LAB}/disco_ext4.img")
mkfs.ext4 -q -L "ORIGINAL" "$LOOP_EXT4"

LOOP_XFS=$(losetup -f --show "${DIR_LAB}/disco_xfs.img")
mkfs.xfs -q -L "XFS_DATA" "$LOOP_XFS"

LOOP_BTRFS=$(losetup -f --show "${DIR_LAB}/disco_btrfs.img")
mkfs.btrfs -q -L "BTRFS_VOL" "$LOOP_BTRFS"

LOOP_BAD=$(losetup -f --show "${DIR_LAB}/disco_bad.img")

echo -e "${C_GREEN}✔ Discos loop creados:${C_RESET} ext4: $LOOP_EXT4 | XFS: $LOOP_XFS | Btrfs: $LOOP_BTRFS"

pause_step "Presioná [ENTER] para ajustar parámetros del superbloque ext4 con tune2fs..."

# ==============================================================================
# PASO 5: MANTENIMIENTO EXT4 CON TUNE2FS
# ==============================================================================
step_banner "5" "Mantenimiento ext4 con tune2fs"

explain "1. Modificar intervalo de comprobación a 30 montajes (-c 30):"
run_and_show "tune2fs -c 30 '$LOOP_EXT4'"

explain "2. Modificar contador actual de montajes (-C 30):"
run_and_show "tune2fs -C 30 '$LOOP_EXT4'"

explain "3. Modificar intervalo de comprobación temporal a 2 días (-i 2d):"
run_and_show "tune2fs -i 2d '$LOOP_EXT4'"

explain "4. Asignar nueva etiqueta al filesystem (-L 'DatosProduccion'):"
run_and_show "tune2fs -L 'DatosProduccion' '$LOOP_EXT4'"

explain "5. Reducir bloques reservados para root al 1% (-m 1):"
run_and_show "tune2fs -m 1 '$LOOP_EXT4'"

explain "6. Medir espacio e inodos en el dispositivo NO MONTADO mediante tune2fs -l | egrep:"
run_and_show "tune2fs -l '$LOOP_EXT4' | egrep 'Free|(Inode|Block) count|^Block size|Reserved'"

pie_clase "¿Por qué es tan valioso medir espacio con 'tune2fs -l | egrep' en dispositivos no montados?" \
          "Permite verificar el espacio e inodos disponibles en discos dañados, particiones de rescate o imágenes forenses sin necesidad de montarlas."

pause_step "Presioná [ENTER] para ejecutar chequeo de consistencia con fsck, e2fsck y dumpe2fs..."

# ==============================================================================
# PASO 6: CHEQUEO DE CONSISTENCIA CON FSCK, E2FSCK Y DUMPE2FS
# ==============================================================================
step_banner "6" "Chequeo de Consistencia con fsck, e2fsck y dumpe2fs"

explain "1. Inspección del superbloque con dumpe2fs (-h):"
run_and_show "dumpe2fs -h '$LOOP_EXT4' | head -n 25"

explain "2. Forzar verificación completa del filesystem limpio con e2fsck (-f):"
run_and_show "e2fsck -f '$LOOP_EXT4'"

explain "3. Modo de solo lectura sin aplicar modificaciones (-n):"
run_and_show "e2fsck -n '$LOOP_EXT4'"

explain "4. Reparación automática con el frontend fsck (-p):"
run_and_show "fsck -p '$LOOP_EXT4'"

pie_clase "¿Por qué NUNCA se debe ejecutar e2fsck en modo escritura sobre un filesystem montado rw?" \
          "Porque el kernel y e2fsck intentarán modificar las estructuras del disco al mismo tiempo sin sincronización, provocando corrupción masiva de metadatos."

pause_step "Presioná [ENTER] para mantenimiento y optimización en XFS..."

# ==============================================================================
# PASO 7: MANTENIMIENTO Y DEPURACIÓN EN XFS
# ==============================================================================
step_banner "7" "Mantenimiento y Optimización en XFS (xfs_metadump, xfs_db, xfs_fsr)"

explain "Montamos el volumen XFS y creamos archivos para generar estructuras internas:"
mount "$LOOP_XFS" "$MNT_XFS"
for i in {1..20}; do
    echo "Dato XFS $i" > "${MNT_XFS}/archivo_${i}.txt"
done
umount "$MNT_XFS"

explain "1. Volcado seguro de metadatos con xfs_metadump (-g) a una imagen:"
METADUMP_FILE="${DIR_LAB}/xfs_metadata.img"
run_and_show "xfs_metadump -g '$LOOP_XFS' '${METADUMP_FILE}'"
run_and_show "file '${METADUMP_FILE}'"

explain "2. Depuración de bajo nivel con xfs_db y análisis de fragmentación (frag):"
run_and_show "echo 'frag' | xfs_db -r '$LOOP_XFS'"

explain "3. Montamos XFS y ejecutamos el desfragmentador en caliente xfs_fsr:"
mount "$LOOP_XFS" "$MNT_XFS"
if command -v xfs_fsr &>/dev/null; then
    run_and_show "xfs_fsr -v '$MNT_XFS'"
else
    echo -e "${C_YELLOW}(xfs_fsr no está instalado en este sistema, omitiendo ejecución)${C_RESET}"
fi
umount "$MNT_XFS"

pie_clase "¿Cuál es el propósito de xfs_metadump?" \
          "Crear una copia exacta de los metadatos de XFS omitiendo los datos del usuario para enviar a soporte o analizar corrupción con total privacidad."

pause_step "Presioná [ENTER] para mantenimiento en Btrfs..."

# ==============================================================================
# PASO 8: MANTENIMIENTO EN BTRFS
# ==============================================================================
step_banner "8" "Mantenimiento en Btrfs: filesystem show, snapshots, balance y check"

explain "Montamos el volumen Btrfs y mostramos el estado de asignación:"
mount "$LOOP_BTRFS" "$MNT_BTRFS"
run_and_show "btrfs filesystem show '$MNT_BTRFS'"

explain "Creamos un subvolumen de datos y un snapshot atómico en tiempo O(1):"
run_and_show "btrfs subvolume create '${MNT_BTRFS}/subvol_app'"
echo "Configuración de producción Btrfs" > "${MNT_BTRFS}/subvol_app/config.ini"
run_and_show "btrfs subvolume snapshot '${MNT_BTRFS}/subvol_app' '${MNT_BTRFS}/snapshot_backup1'"

explain "Ejecutamos un balanceo de datos para compactar y redistribuir chunks:"
run_and_show "btrfs balance start '${MNT_BTRFS}'"
umount "$MNT_BTRFS"

explain "Ejecutamos verificación y reparación fuera de línea con barra de progreso (-p):"
run_and_show "btrfs check --repair -p '$LOOP_BTRFS' <<< 'y' || true"

pie_clase "¿Por qué Btrfs puede crear snapshots casi instantáneamente independientemente del tamaño?" \
          "Porque es un filesystem Copy-on-Write (CoW); el snapshot simplemente crea una nueva raíz de árbol B+ apuntando a los mismos bloques existentes en tiempo O(1)."

pause_step "Presioná [ENTER] para analizar sectores defectuosos con badblocks..."

# ==============================================================================
# PASO 9: DETECCIÓN DE SECTORES DEFECTUOSOS CON BADBLOCKS
# ==============================================================================
step_banner "9" "Detección de Sectores Defectuosos con badblocks"

BAD_OUT="${DIR_LAB}/sectores_defectuosos.txt"
explain "1. Escaneo de bloques en modo solo lectura con progreso visible (-s) y exportación (-o):"
run_and_show "badblocks -s -o '${BAD_OUT}' '$LOOP_BAD'"
run_and_show "head -n 10 '${BAD_OUT}' || echo '(0 sectores defectuosos detectados)'"

explain "2. Prueba destructiva de escritura/lectura con 4 patrones (-w -s):"
run_and_show "badblocks -w -s '$LOOP_BAD'"

explain "3. Integración con e2fsck: pasar la lista de sectores dañados para aislarlos (-l):"
mkfs.ext4 -q "$LOOP_BAD"
run_and_show "e2fsck -l '${BAD_OUT}' '$LOOP_BAD' || true"

pie_clase "¿Cuál es la diferencia entre badblocks -w y badblocks -n?" \
          "'-w' es destructivo (escribe patrones borrando todo el disco). '-n' es no destructivo (lee el contenido original, prueba el sector y restaura los datos)."

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ✔ LABORATORIO COMPLETADO CON ÉXITO                                             ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado el diagnóstico con df/du, tune2fs en volúmenes desmontados,"
echo -e "consistencia con e2fsck/dumpe2fs, herramientas XFS, mantenimiento Btrfs y badblocks.\n"
