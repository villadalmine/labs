#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Anatomía de Sistemas de Archivos en Linux
# ext4, XFS, Btrfs, tmpfs, tune2fs, Agotamiento de Inodos y Rescate de Superbloque
#
# Diseñado para clases en vivo:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema destacada en una caja limpia.
#  - Desglosa qué significa cada campo (Superbloques, Inodos, Bloques).
#  - Preguntas disparadoras ("pie de clase") para interactuar con los alumnos.
#
# Uso:
#   sudo ./demo_filesystems.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No desmontar ni limpiar al finalizar (dejar montado)
# ==============================================================================

set -uo pipefail

# Si se ejecuta en tmux, activar scroll con la rueda del ratón
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

# Paleta de colores didáctica
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[0;36m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo).${C_RESET}"
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
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "${AUTO_WAIT:-0}" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta...]${C_RESET} "
            read -r
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

DIR_LAB="/tmp/lab_demo_fs"
MNT_EXT4="/mnt/lab_demo_ext4"
MNT_XFS="/mnt/lab_demo_xfs"
MNT_BTRFS="/mnt/lab_demo_btrfs"
MNT_RAM="/mnt/lab_demo_ram"

LOOP_EXT4=""
LOOP_XFS=""
LOOP_BTRFS=""
LOOP_INODE=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando y liberando recursos del laboratorio...${C_RESET}"
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${C_GREEN}[INFO] Se mantienen los montajes activos por opción --keep.${C_RESET}"
        df -h | grep "/mnt/lab_demo" || true
        return
    fi

    for m in "$MNT_EXT4" "$MNT_XFS" "$MNT_BTRFS" "$MNT_RAM" "/mnt/lab_demo_inode"; do
        if mountpoint -q "$m" 2>/dev/null; then
            umount -f "$m" 2>/dev/null || true
        fi
        rm -rf "$m" 2>/dev/null || true
    done

    for l in "$LOOP_EXT4" "$LOOP_XFS" "$LOOP_BTRFS" "$LOOP_INODE"; do
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
echo -e "${C_BOLD}${C_GREEN} 🗄️ LABORATORIO EN VIVO: ANATOMÍA DE SISTEMAS DE ARCHIVOS EN LINUX             ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "ext4, XFS, Btrfs, tmpfs, tune2fs, Agotamiento de Inodos y Rescate de Superbloque"
echo -e "Arquitectura agnóstica con discos virtuales loop (/dev/loopX)\n"

# ==============================================================================
# PASO 1: VERIFICAR HERRAMIENTAS
# ==============================================================================
step_banner "1" "Verificación de paquetes y herramientas del sistema"

explain "Revisando utilitarios esenciales de formateo y gestión de sistemas de archivos:"
MISSING_PKGS=()
for tool in mkfs.ext4 tune2fs dumpe2fs mkfs.xfs xfs_info xfs_growfs mkfs.btrfs btrfs losetup; do
    if ! command -v "$tool" &>/dev/null; then
        MISSING_PKGS+=("$tool")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}Faltan herramientas: ${MISSING_PKGS[*]}. Instalando con el gestor del sistema...${C_RESET}"
    if command -v dnf &>/dev/null; then
        dnf install -y e2fsprogs xfsprogs btrfs-progs util-linux
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq e2fsprogs xfsprogs btrfs-progs util-linux
    fi
fi
echo -e "${C_GREEN}✔ Todas las herramientas necesarias están disponibles.${C_RESET}"

mkdir -p "$DIR_LAB" "$MNT_EXT4" "$MNT_XFS" "$MNT_BTRFS" "$MNT_RAM"

pie_clase "¿Qué capa del kernel permite que Linux use ext4, xfs o btrfs con los mismos comandos?" \
          "VFS (Virtual File System), la capa abstracta que unifica todas las llamadas POSIX."

pause_step "Presioná [ENTER] para crear el disco ext4 y analizar su superbloque..."

# ==============================================================================
# PASO 2: EXT4 AL DETALLE: SUPERBLOQUE Y GESTIÓN CON TUNE2FS
# ==============================================================================
step_banner "2" "ext4 al Detalle: Creación, Superbloque y tune2fs"

explain "Creamos un disco virtual loop de 300 MB para no arriesgar discos reales:"
run_and_show "dd if=/dev/zero of=${DIR_LAB}/disco_ext4.img bs=1M count=300 status=none && losetup -f --show ${DIR_LAB}/disco_ext4.img"
LOOP_EXT4=$(losetup -j "${DIR_LAB}/disco_ext4.img" | cut -d: -f1 | head -n 1)

explain "Formateamos con ext4 (tamaño de bloque 4096 bytes y etiqueta DISCO_EXT4):"
run_and_show "mkfs.ext4 -F -q -b 4096 -L 'DISCO_EXT4' ${LOOP_EXT4}"

explain "1) Inspeccionamos el Superbloque primario con tune2fs -l:"
run_and_show "tune2fs -l ${LOOP_EXT4} | grep -E '(Filesystem volume name|Filesystem state|Block size|Inode count|Reserved block count)'"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • ${C_BOLD}Block size: 4096${C_RESET} -> Unidad mínima de asignación física (4 KB)."
echo -e " • ${C_BOLD}Inode count${C_RESET} -> Cantidad fija de inodos reservada al formatear."
echo -e " • ${C_BOLD}Reserved block count${C_RESET} -> Bloques reservados por defecto para el usuario root (5%)."

pie_clase "¿Para qué reserva Linux un 5% de bloques para root en particiones ext4?" \
          "Para que si un usuario llena el disco al 100%, root pueda seguir iniciando sesión y los daemons no colapsen."

pause_step "Presioná [ENTER] para ver cómo un SysAdmin recupera ese 5% de espacio reservado..."

explain "2) Reducción de bloques reservados con tune2fs -m (optimización en discos de datos):"
run_and_show "tune2fs -m 1 ${LOOP_EXT4} && tune2fs -l ${LOOP_EXT4} | grep 'Reserved block count'"

explain "3) Modificación de etiqueta del volumen en caliente con tune2fs -L:"
run_and_show "tune2fs -L 'DATA_PROD' ${LOOP_EXT4} && lsblk -f ${LOOP_EXT4}"

explain "Montamos el sistema de archivos en ${MNT_EXT4}:"
run_and_show "mount ${LOOP_EXT4} ${MNT_EXT4} && df -h ${MNT_EXT4}"

pause_step "Presioná [ENTER] para simular la catástrofe 1: Agotamiento de Inodos vs Espacio..."

# ==============================================================================
# PASO 3: CATÁSTROFE EN PRODUCCIÓN: INODOS AGOTADOS (df -i vs df -h)
# ==============================================================================
step_banner "3" "Catástrofe Real: 'No space left on device' con Disco 90% Libre"

explain "Crearemos un disco de 20 MB pero forzando una cantidad minúscula de inodos (-N 512):"
mkdir -p /mnt/lab_demo_inode
run_and_show "dd if=/dev/zero of=${DIR_LAB}/disco_inode.img bs=1M count=20 status=none && losetup -f --show ${DIR_LAB}/disco_inode.img"
LOOP_INODE=$(losetup -j "${DIR_LAB}/disco_inode.img" | cut -d: -f1 | head -n 1)

run_and_show "mkfs.ext4 -F -q -N 512 ${LOOP_INODE} && mount ${LOOP_INODE} /mnt/lab_demo_inode"

explain "Comparativa inicial antes de la tormenta de archivos:"
run_and_show "df -h /mnt/lab_demo_inode && df -i /mnt/lab_demo_inode"

explain "Simulamos un servicio web o cron con bug que crea 520 archivos vacíos (0 bytes):"
run_and_show "bash -c 'for i in \$(seq 1 520); do touch /mnt/lab_demo_inode/sesion_\$i.tmp; done 2>/dev/null || true'"

explain "Ahora intentamos crear un archivo nuevo esencial en el disco:"
run_and_show "touch /mnt/lab_demo_inode/archivo_critico.txt"

echo -e "\n${C_BOLD}${C_RED}❌ ERROR OBTENIDO: 'No space left on device'${C_RESET}"

explain "Diagnóstico Forense comparativo en vivo: ¿Por qué falló si el disco no está lleno?"
run_and_show "df -h /mnt/lab_demo_inode"
run_and_show "df -i /mnt/lab_demo_inode"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • ${C_BOLD}df -h${C_RESET} muestra que el disco está al ${C_GREEN}1% de uso (¡99% libre!)${C_RESET}."
echo -e " • ${C_BOLD}df -i${C_RESET} muestra ${C_RED}100% de inodos usados (0 inodos libres)${C_RESET}."
echo -e " • En Linux, cada archivo o directorio requiere 1 inodo. Sin inodos libres, no se puede crear nada."

pie_clase "¿Cómo diagnostica un SysAdmin novato vs un SysAdmin profesional este problema?" \
          "El novato solo mira 'df -h' y no entiende el fallo; el profesional siempre revisa 'df -i'."

pause_step "Presioná [ENTER] para limpiar este disco y pasar al desastre de superbloque corrupto..."

umount /mnt/lab_demo_inode
losetup -d "$LOOP_INODE"
LOOP_INODE=""
rm -f "$DIR_LAB/disco_inode.img"

# ==============================================================================
# PASO 4: CATÁSTROFE 2: CORRUPCIÓN DE SUPERBLOQUE Y RESCATE CON E2FSCK
# ==============================================================================
step_banner "4" "Catástrofe Real: Corrupción de Superbloque y Rescate Forense"

explain "Desmontamos ${LOOP_EXT4} para investigar los Superbloques de respaldo:"
umount "$MNT_EXT4"

explain "Localizamos dónde colocó ext4 los bloques de respaldo con dumpe2fs:"
run_and_show "dumpe2fs ${LOOP_EXT4} 2>/dev/null | grep -i 'Backup superblock at' | head -n 3"

BACKUP_BLOCK=$(dumpe2fs "$LOOP_EXT4" 2>/dev/null | grep -i "Backup superblock at" | head -n 1 | awk '{print $4}' | tr -d ',')
[ -z "$BACKUP_BLOCK" ] && BACKUP_BLOCK="32768"

explain "INYECCIÓN DE FALLA: Destruimos intencionalmente el Superbloque Primario (bloque 1) con dd:"
run_and_show "dd if=/dev/urandom of=${LOOP_EXT4} bs=1024 count=4 seek=1 conv=notrunc status=none"

explain "Intentamos montar el sistema de archivos dañado:"
run_and_show "mount ${LOOP_EXT4} ${MNT_EXT4}"

echo -e "\n${C_BOLD}${C_RED}❌ ERROR: El kernel rechaza el montaje (wrong fs type, bad superblock, etc.)${C_RESET}"

pie_clase "¿Por qué el sistema no puede montar el disco? ¿Toda la información está perdida?" \
          "No: el superbloque primario contiene los metadatos raíz, pero ext4 guarda múltiples copias de respaldo."

pause_step "Presioná [ENTER] para rescatar el disco con e2fsck usando el bloque de respaldo ${BACKUP_BLOCK}..."

explain "OPERACIÓN DE RESCATE: Ejecutamos e2fsck forzando la lectura del superbloque de respaldo:"
run_and_show "e2fsck -b ${BACKUP_BLOCK} -y ${LOOP_EXT4}"

explain "Comprobamos si el sistema de archivos resucitó y vuelve a montarse:"
run_and_show "mount ${LOOP_EXT4} ${MNT_EXT4} && df -h ${MNT_EXT4}"

echo -e "${C_BOLD}${C_GREEN}✔ ¡ÉXITO TOTAL! El sistema de archivos fue reparado y montado intacto.${C_RESET}"

pause_step "Presioná [ENTER] para explorar XFS y la ampliación en caliente..."

# ==============================================================================
# PASO 5: XFS AL DETALLE: ALLOCATION GROUPS Y EXPANSION EN CALIENTE
# ==============================================================================
step_banner "5" "XFS en Profundidad: Allocation Groups y xfs_growfs"

explain "Creamos un disco virtual loop de 300 MB para XFS:"
run_and_show "dd if=/dev/zero of=${DIR_LAB}/disco_xfs.img bs=1M count=300 status=none && losetup -f --show ${DIR_LAB}/disco_xfs.img"
LOOP_XFS=$(losetup -j "${DIR_LAB}/disco_xfs.img" | cut -d: -f1 | head -n 1)

explain "Formateamos con XFS y lo montamos:"
run_and_show "mkfs.xfs -f -q -L 'STORAGE_XFS' ${LOOP_XFS} && mount ${LOOP_XFS} ${MNT_XFS}"

explain "1) Inspeccionamos la geometría interna de XFS con xfs_info (Allocation Groups):"
run_and_show "xfs_info ${MNT_XFS} | grep -E '(data|naming|log)'"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • XFS divide el disco en ${C_BOLD}Allocation Groups (agcount)${C_RESET} independientes."
echo -e " • Cada grupo tiene su propio gestor de inodos y espacio libre, permitiendo escrituras paralelas masivas."

explain "2) Ampliación en caliente (Online Growth): Aumentamos el archivo de 300 MB a 600 MB:"
run_and_show "truncate -s 600M ${DIR_LAB}/disco_xfs.img && losetup -c ${LOOP_XFS}"

explain "Tamaño actual según df -h:"
run_and_show "df -h ${MNT_XFS}"

explain "Ejecutamos xfs_growfs para expandir XFS sobre el espacio nuevo EN CALIENTE (montado):"
run_and_show "xfs_growfs ${MNT_XFS}"

explain "Comprobamos el nuevo tamaño expandido:"
run_and_show "df -h ${MNT_XFS}"

pie_clase "¿Se puede reducir de tamaño (shrink) un sistema de archivos XFS?" \
          "¡NUNCA! XFS está diseñado exclusivamente para crecer. Reducir un filesystem solo lo soporta ext4 o Btrfs."

pause_step "Presioná [ENTER] para explorar Btrfs y sus snapshots instantáneos Copy-on-Write..."

# ==============================================================================
# PASO 6: BTRFS: SUBVOLÚMENES Y SNAPSHOTS COPY-ON-WRITE
# ==============================================================================
step_banner "6" "Btrfs: Subvolúmenes y Snapshots Instantáneos (CoW)"

explain "Creamos un disco de 300 MB, formateamos con Btrfs y lo montamos:"
run_and_show "dd if=/dev/zero of=${DIR_LAB}/disco_btrfs.img bs=1M count=300 status=none && losetup -f --show ${DIR_LAB}/disco_btrfs.img"
LOOP_BTRFS=$(losetup -j "${DIR_LAB}/disco_btrfs.img" | cut -d: -f1 | head -n 1)
run_and_show "mkfs.btrfs -f -q -L 'STORAGE_BTRFS' ${LOOP_BTRFS} && mount ${LOOP_BTRFS} ${MNT_BTRFS}"

explain "1) Creamos un subvolumen independiente llamado @app_data:"
run_and_show "btrfs subvolume create ${MNT_BTRFS}/@app_data && btrfs subvolume list ${MNT_BTRFS}"

explain "2) Creamos un archivo de 20 MB simulando una base de datos:"
run_and_show "dd if=/dev/urandom of=${MNT_BTRFS}/@app_data/db.bin bs=1M count=20 status=none && ls -lh ${MNT_BTRFS}/@app_data/"

explain "3) Creamos un SNAPSHOT instantáneo con Copy-on-Write:"
run_and_show "btrfs subvolume snapshot ${MNT_BTRFS}/@app_data ${MNT_BTRFS}/@snapshot_seguridad"

explain "Comprobamos el consumo real de espacio en Btrfs:"
run_and_show "btrfs filesystem df ${MNT_BTRFS}"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • El snapshot se creó en ${C_BOLD}0 milisegundos${C_RESET}."
echo -e " • Gracias a ${C_BOLD}Copy-on-Write (CoW)${C_RESET}, el snapshot comparte los mismos bloques físicos que el original."
echo -e " • Consume ${C_BOLD}0 bytes adicionales${C_RESET} hasta que algún bloque sea modificado."

pause_step "Presioná [ENTER] para comparar Btrfs contra tmpfs en memoria RAM..."

# ==============================================================================
# PASO 7: TMPFS: VELOCIDAD Y VOLATILIDAD EN MEMORIA RAM
# ==============================================================================
step_banner "7" "tmpfs: Almacenamiento Volátil a Máxima Velocidad en RAM"

explain "Montamos un sistema de archivos tmpfs en memoria RAM (límite 100 MB):"
run_and_show "mount -t tmpfs -o size=100M tmpfs ${MNT_RAM} && df -h ${MNT_RAM}"

explain "Test de Benchmark: Escribimos 50 MB con sincronización a disco (fdatasync) en el loop device:"
run_and_show "dd if=/dev/zero of=${DIR_LAB}/test_disk.bin bs=1M count=50 conv=fdatasync 2>&1"

explain "Test de Benchmark: Escribimos exactamente los mismos 50 MB en memoria RAM (tmpfs):"
run_and_show "dd if=/dev/zero of=${MNT_RAM}/test_ram.bin bs=1M count=50 conv=fdatasync 2>&1"

echo -e "\n${C_CYAN}🔍 ANÁLISIS DE LA SALIDA:${C_RESET}"
echo -e " • tmpfs escribe directamente sobre las páginas del kernel en memoria RAM."
echo -e " • No hay llamadas de E/S física al bus de almacenamiento."
echo -e " • Peligro: Al reiniciar o apagar el servidor, ${C_BOLD}TODO lo almacenado en tmpfs se desvanece${C_RESET}."

pie_clase "¿Qué directorios de Linux suelen montarse sobre tmpfs?" \
          "/run, /tmp, /dev/shm (memoria compartida POSIX) y los sockets de procesos efímeros."

pause_step "Presioná [ENTER] para ver la matriz comparativa de síntesis..."

# ==============================================================================
# PASO 8: RESUMEN Y MATRIZ COMPARATIVA DE SÍNTESIS
# ==============================================================================
step_banner "8" "Matriz de Síntesis de Sistemas de Archivos"

echo -e "${C_BOLD}Resumen de comandos y herramientas aprendidas:${C_RESET}\n"
printf "${C_BOLD}%-10s %-22s %-24s %-25s${C_RESET}\n" "FS" "PARADIGMA" "HERRAMIENTA CLAVE" "CASO EN PRODUCCIÓN"
printf "%-10s %-22s %-24s %-25s\n" "----------" "----------------------" "------------------------" "-------------------------"
printf "%-10s %-22s %-24s %-25s\n" "ext4" "Journaling / Bloques" "tune2fs, dumpe2fs, e2fsck" "Estándar general, servidores"
printf "%-10s %-22s %-24s %-25s\n" "XFS" "Allocation Groups" "xfs_info, xfs_growfs" "Base de datos, I/O paralelo"
printf "%-10s %-22s %-24s %-25s\n" "Btrfs" "Copy-on-Write (CoW)" "btrfs subvolume, snapshot" "Snapshots O(1), NAS, rollbacks"
printf "%-10s %-22s %-24s %-25s\n" "tmpfs" "RAM Volátil en Kernel" "mount -t tmpfs" "Caché, IPC, /run, /tmp"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🎉 ¡DEMOSTRACIÓN DE FILESYSTEMS FINALIZADA CON ÉXITO!                          ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}\n"
