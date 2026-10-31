#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Tipos de Enlaces en Filesystems
# Hard Links, Symbolic Links, Inodos, Restricciones, Casos Reales y Auditoría con find
#
# Diseñado para clases interactivas y autoaprendizaje guiado:
#  - Muestra SIEMPRE el comando exacto ejecutado ($ comando).
#  - Muestra la salida real del sistema en una caja formateada.
#  - Desglosa qué ocurre en el inodo (número de inodo, nlink, dentry).
#  - Preguntas didácticas ("pie de clase") con respuestas desplegables.
#  - Casos reales de producción: Despliegue Zero-Downtime, backups con rsync
#    y archivos borrados retenidos por procesos (lsof +L1).
#
# Uso:
#   sudo ./demo_enlaces.sh [opciones]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No limpiar al finalizar (dejar archivos para práctica)
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
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para crear el disco virtual loop de prueba y auditar archivos.${C_RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false
BG_PID=""

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

DIR_LAB="/tmp/lab_demo_enlaces"
MNT_DISCO2="/mnt/lab_enlaces_disco2"
LOOP_DEV=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Desmontando y liberando recursos...${C_RESET}"
    if [ -n "$BG_PID" ] && kill -0 "$BG_PID" 2>/dev/null; then
        kill -9 "$BG_PID" 2>/dev/null || true
    fi

    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los archivos en ${DIR_LAB} por opción --keep.${C_RESET}"
        return
    fi

    if mountpoint -q "$MNT_DISCO2" 2>/dev/null; then
        umount -f "$MNT_DISCO2" 2>/dev/null || true
    fi
    rm -rf "$MNT_DISCO2" 2>/dev/null || true

    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi

    rm -rf "$DIR_LAB"
    echo -e "${C_GREEN}✔ Entorno limpio y recursos liberados.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🔗 DEMOSTRACIÓN EN VIVO: ENLACES EN FILESYSTEMS (HARD & SOFT LINKS)           ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Inodos, nlink, Auditoría con find (-samefile, -xtype l) y Casos Reales de Producción\n"

mkdir -p "$DIR_LAB" "$MNT_DISCO2"
cd "$DIR_LAB"

# ==============================================================================
# PASO 1: CREAR ARCHIVO BASE E INSPECCIONAR SU INODO
# ==============================================================================
step_banner "1" "Creación de Archivo Base e Inspección del Inodo Original"

explain "Creamos un archivo de texto 'documento_base.txt' y revisamos su inodo con ls -li y stat:"
echo "Información confidencial del servidor v1.0" > documento_base.txt

run_and_show "ls -li documento_base.txt"
run_and_show "stat documento_base.txt | grep -E 'Inode|Links|Size|Access: \('"

pie_clase "¿Qué indica el campo 'Links: 1' en la salida de stat?" \
          "Indica que existe exactamente 1 entrada de directorio (dentry) apuntando a este inodo en el sistema de archivos."

pause_step "Presioná [ENTER] para crear un Enlace Duro (Hard Link)..."

# ==============================================================================
# PASO 2: CREACIÓN DE ENLACE DURO (HARD LINK)
# ==============================================================================
step_banner "2" "Creación de Enlace Duro (ln) y Verificación de Inodo Compartido"

explain "Creamos un enlace duro 'enlace_duro1.txt' apuntando a 'documento_base.txt':"
run_and_show "ln documento_base.txt enlace_duro1.txt"

explain "Comprobamos que ambos nombres comparten exactamente el mismo número de inodo y Links subió a 2:"
run_and_show "ls -li documento_base.txt enlace_duro1.txt"

pie_clase "¿Cuánto espacio adicional en bloques de disco consumió la creación de enlace_duro1.txt?" \
          "0 bytes de bloques de datos. Solo consumió una pequeña entrada (dentry) en la tabla del directorio padre."

pause_step "Presioná [ENTER] para comprobar la modificación en caliente del enlace duro..."

# ==============================================================================
# PASO 3: MODIFICACIÓN SINCRONIZADA POR COMPARTIR BLOQUES
# ==============================================================================
step_banner "3" "Modificación Transparente: Edición cruzada en el mismo inodo"

explain "Escribimos datos adicionales a través de 'enlace_duro1.txt':"
run_and_show "echo 'Nueva línea añadida a través del hard link' >> enlace_duro1.txt"

explain "Verificamos que el contenido de 'documento_base.txt' cambió de forma inmediata:"
run_and_show "cat documento_base.txt"

pie_clase "¿Por qué se modificó 'documento_base.txt' si editamos 'enlace_duro1.txt'?" \
          "Porque ambos nombres apuntan a los mismos punteros de bloques en el inodo; no hay copia de datos ni duplicación."

pause_step "Presioná [ENTER] para poner a prueba la resiliencia al borrar el 'original'..."

# ==============================================================================
# PASO 4: BORRADO DEL ORIGINAL Y PERSISTENCIA DE DATOS
# ==============================================================================
step_banner "4" "Prueba Forense: ¿Qué ocurre si borramos el archivo original?"

explain "Eliminamos el archivo supuestamente 'original' (documento_base.txt):"
run_and_show "rm documento_base.txt"

explain "Comprobamos el estado del inodo y el contenido en 'enlace_duro1.txt':"
run_and_show "ls -li enlace_duro1.txt"
run_and_show "cat enlace_duro1.txt"

pie_clase "¿Se perdieron los datos al borrar 'documento_base.txt'?" \
          "No. El comando rm solo borró la dentry 'documento_base.txt' y redujo el contador nlink de 2 a 1. El inodo y los datos persisten intactos."

pause_step "Presioná [ENTER] para crear Enlaces Simbólicos (Symlinks)..."

# ==============================================================================
# PASO 5: ENLACES SIMBÓLICOS (SOFT LINKS / SYMLINKS)
# ==============================================================================
step_banner "5" "Creación de Enlaces Simbólicos con ln -s (Relativo y Absoluto)"

explain "Creamos un symlink 'acceso_directo.lnk' apuntando a 'enlace_duro1.txt':"
run_and_show "ln -s enlace_duro1.txt acceso_directo.lnk"

explain "Creamos un symlink hacia un directorio completo:"
mkdir -p configs
echo "PORT=8080" > configs/app.env
run_and_show "ln -s configs enlace_carpeta && ls -ld enlace_carpeta"

explain "Inspeccionamos los inodos, permisos y tamaños del symlink:"
run_and_show "ls -li enlace_duro1.txt acceso_directo.lnk"

pie_clase "¿Por qué el tamaño del symlink acceso_directo.lnk es exactamente de 16 bytes?" \
          "Porque el contenido del symlink es la cadena de texto de la ruta destino: 'enlace_duro1.txt' (16 caracteres = 16 bytes)."

pause_step "Presioná [ENTER] para simular y detectar Enlaces Rotos (Broken Symlinks)..."

# ==============================================================================
# PASO 6: SIMULACIÓN DE ENLACES ROTOS (BROKEN SYMLINKS)
# ==============================================================================
step_banner "6" "Simulación de Enlaces Huérfanos o Rotos"

explain "Eliminamos el archivo de destino del symlink para romper el enlace:"
run_and_show "rm enlace_duro1.txt"

explain "Intentamos leer el contenido a través del enlace simbólico roto:"
run_and_show "cat acceso_directo.lnk || true"

explain "Observamos cómo ls -l resalta el enlace roto hacia un destino inexistente:"
run_and_show "ls -l acceso_directo.lnk"

pie_clase "¿Qué error devuelve el sistema operativo si intentamos leer un symlink roto?" \
          "'No such file or directory' (ENOENT), porque el kernel resuelve el symlink hasta el destino y éste ya no existe."

pause_step "Presioná [ENTER] para realizar búsquedas forenses con find (-samefile y -xtype)..."

# ==============================================================================
# PASO 7: AUDITORÍA FORENSE CON FIND (-SAMEFILE Y -XTYPE L)
# ==============================================================================
step_banner "7" "Operaciones de Búsqueda Forense con find"

# Creamos un conjunto de prueba variado
echo "Archivo de base de datos" > produccion.db
ln produccion.db replica_local.db
ln produccion.db backup_hardlink.db
ln -s produccion.db symlink_valido.lnk
ln -s archivo_inexistente.txt symlink_roto_1.lnk
ln -s /ruta/fantasma symlink_roto_2.lnk

explain "1. Localizar todos los enlaces simbólicos del directorio (-type l):"
run_and_show "find . -type l -exec ls -l {} \;"

explain "2. Localizar TODOS los enlaces duros asociados a 'produccion.db' (-samefile):"
run_and_show "find . -samefile produccion.db"

explain "3. Localizar TODOS los enlaces rotos o huérfanos (-xtype l):"
run_and_show "find . -xtype l"

explain "4. Limpieza automatizada de enlaces rotos con find -xtype l -delete:"
run_and_show "find . -xtype l -delete && echo 'Verificando enlaces rotos restantes:' && find . -xtype l"

pie_clase "¿Por qué el operador '-xtype l' detecta enlaces rotos?" \
          "Porque -xtype evalúa el archivo de destino. Si el destino no existe, la desreferenciación falla y retorna tipo 'l'."

pause_step "Presioná [ENTER] para comprobar las restricciones de Hard Links entre particiones..."

# ==============================================================================
# PASO 8: DEMOSTRACIÓN DE RESTRICCIONES TÉCNICAS DE HARD LINKS
# ==============================================================================
step_banner "8" "Restricciones: Enlaces entre Particiones y Directorios"

explain "Montamos un disco virtual loop formateado en ext4 para simular un segundo filesystem independiente:"
dd if=/dev/zero of="${DIR_LAB}/disco2.img" bs=1M count=30 status=none
LOOP_DEV=$(losetup -f --show "${DIR_LAB}/disco2.img")
mkfs.ext4 -q "$LOOP_DEV"
mount "$LOOP_DEV" "$MNT_DISCO2"
echo "Datos en disco secundario" > "${MNT_DISCO2}/archivo_disco2.txt"

explain "Intentamos crear un HARD LINK que cruce particiones (/tmp -> /mnt):"
run_and_show "ln ${MNT_DISCO2}/archivo_disco2.txt ./hardlink_cruzado.txt || true"

explain "Comprobamos que un SYMLINK sí puede cruzar cualquier partición o disco:"
run_and_show "ln -s ${MNT_DISCO2}/archivo_disco2.txt ./symlink_cruzado.lnk && cat ./symlink_cruzado.lnk"

explain "Intentamos crear un HARD LINK hacia un directorio (configs):"
run_and_show "ln configs hardlink_directorio || true"

pie_clase "¿Por qué el kernel prohíbe hard links entre particiones y a directorios?" \
          "Entre particiones porque los inodos son locales a cada superbloque (EXDEV); a directorios para prevenir bucles cíclicos en el árbol VFS."

pause_step "Presioná [ENTER] para explorar el Caso Real 1: Despliegue Zero-Downtime con Symlinks..."

# ==============================================================================
# PASO 9: CASO REAL 1 - DESPLIEGUE ATÓMICO ZERO-DOWNTIME Y ROLLBACK
# ==============================================================================
step_banner "9" "Caso Real 1: Despliegue Atómico Zero-Downtime y Rollback Instantáneo"

explain "Simulamos un entorno de servidor web en producción con Nginx/PHP-FPM/Node:"
mkdir -p "${DIR_LAB}/deploy/releases/2026-10-25_v1.0"
mkdir -p "${DIR_LAB}/deploy/releases/2026-10-30_v2.0"

echo "<h1>App Producción: Versión 1.0 (Estable)</h1>" > "${DIR_LAB}/deploy/releases/2026-10-25_v1.0/index.html"
echo "<h1>App Producción: Versión 2.0 (Nueva Feature)</h1>" > "${DIR_LAB}/deploy/releases/2026-10-30_v2.0/index.html"

explain "El servidor web apunta a '/current'. Inicializamos con la Versión 1.0:"
run_and_show "ln -sfn ${DIR_LAB}/deploy/releases/2026-10-25_v1.0 ${DIR_LAB}/deploy/current"
run_and_show "cat ${DIR_LAB}/deploy/current/index.html"

explain "Realizamos el Despliegue Atómico a la Versión 2.0 en 1 milisegundo (ln -sfn):"
run_and_show "ln -sfn ${DIR_LAB}/deploy/releases/2026-10-30_v2.0 ${DIR_LAB}/deploy/current"
run_and_show "cat ${DIR_LAB}/deploy/current/index.html"

explain "Simulación de Fallo Crítico en v2.0 -> Ejecutamos Rollback Inmediato a v1.0:"
run_and_show "ln -sfn ${DIR_LAB}/deploy/releases/2026-10-25_v1.0 ${DIR_LAB}/deploy/current"
run_and_show "cat ${DIR_LAB}/deploy/current/index.html"

pie_clase "¿Por qué el flag -sfn es indispensable en el despliegue?" \
          "-s crea symlink, -f fuerza el reemplazo y -n evita que ln intente entrar dentro del directorio destino si current ya es un symlink a directorio."

pause_step "Presioná [ENTER] para explorar el Caso Real 2: Backups Deduplicados con rsync --link-dest..."

# ==============================================================================
# PASO 10: CASO REAL 2 - DEDUPLICACIÓN DE BACKUPS CON HARD LINKS
# ==============================================================================
step_banner "10" "Caso Real 2: Deduplicación y Backups Instantáneos con Hard Links"

mkdir -p "${DIR_LAB}/datos_origen"
mkdir -p "${DIR_LAB}/backups/dia1"
mkdir -p "${DIR_LAB}/backups/dia2"

echo "Configuración del sistema v1" > "${DIR_LAB}/datos_origen/sistema.conf"
echo "Base de datos transaccional día 1" > "${DIR_LAB}/datos_origen/ventas.db"

explain "Creamos el Backup Completo del Día 1:"
cp -p "${DIR_LAB}/datos_origen/"* "${DIR_LAB}/backups/dia1/"

explain "Para el Día 2, solo cambia 'ventas.db'. 'sistema.conf' permanece intacto:"
echo "Base de datos transaccional día 2 con nuevos registros" > "${DIR_LAB}/datos_origen/ventas.db"

explain "Ejecutamos rsync con --link-dest apuntando al backup de ayer:"
run_and_show "rsync -a --link-dest=${DIR_LAB}/backups/dia1/ ${DIR_LAB}/datos_origen/ ${DIR_LAB}/backups/dia2/"

explain "Verificamos que 'sistema.conf' comparte inodo entre día1 y día2 (0 bytes extra):"
run_and_show "ls -li ${DIR_LAB}/backups/dia1/sistema.conf ${DIR_LAB}/backups/dia2/sistema.conf"

explain "Verificamos que 'ventas.db' tiene inodos diferentes porque fue modificado:"
run_and_show "ls -li ${DIR_LAB}/backups/dia1/ventas.db ${DIR_LAB}/backups/dia2/ventas.db"

pie_clase "Si eliminamos el backup del dia1, ¿se corrompe o borra el archivo sistema.conf del dia2?" \
          "No, porque sistema.conf tiene nlink=2. Al borrar dia1, nlink baja a 1 y los datos permanecen completamente disponibles en dia2."

pause_step "Presioná [ENTER] para explorar el Caso Real 3: Archivos Borrados con Procesos Abiertos..."

# ==============================================================================
# PASO 11: CASO REAL 3 - EL MISTERIO DEL DISCO LLENO TRAS RM (LSOF +L1)
# ==============================================================================
step_banner "11" "Caso Real 3: Detección Forense de Espacio Fantasma (lsof +L1)"

explain "Simulamos un servicio que escribe en un log gigante y mantiene su descriptor abierto:"
echo "Iniciando servicio de base de datos..." > "${DIR_LAB}/servicio_activo.log"

# Abrimos el descriptor en segundo plano simulando un demonio
(
    exec 3> "${DIR_LAB}/servicio_activo.log"
    while true; do
        echo "Transacción activa $(date)" >&3
        sleep 1
    done
) &
BG_PID=$!
sleep 1

explain "Verificamos el inodo y contador de enlaces antes de borrar:"
run_and_show "ls -li ${DIR_LAB}/servicio_activo.log"

explain "Un operador ejecuta 'rm' para 'liberar espacio':"
run_and_show "rm ${DIR_LAB}/servicio_activo.log"

explain "El archivo ya NO aparece en el directorio con ls:"
run_and_show "ls -l ${DIR_LAB}/servicio_activo.log || true"

explain "Sin embargo, lsof detecta que el inodo sigue retenido en memoria por el proceso $BG_PID:"
run_and_show "lsof +L1 | grep '${DIR_LAB}' || lsof -p $BG_PID | grep '(deleted)'"

explain "Observamos el enlace en /proc/$BG_PID/fd/ que aún apunta al inodo borrado:"
run_and_show "ls -l /proc/$BG_PID/fd/"

explain "Terminamos el proceso y comprobamos que el kernel libera definitivamente los bloques:"
kill -9 "$BG_PID" 2>/dev/null || true
BG_PID=""
sleep 1
echo -e "${C_GREEN}Proceso terminado. Los bloques de disco fueron liberados al bitmap libre.${C_RESET}"

pie_clase "¿Cómo se libera espacio en producción si un log gigante está retenido por un proceso que no podés reiniciar?" \
          "Truncando el archivo a 0 bytes escribiendo directamente en su descriptor: > /proc/\$PID/fd/\$FD"

pause_step "Presioná [ENTER] para ver la auditoría real en /etc/ con find -type l -exec ls -l {} \;..."

# ==============================================================================
# PASO 12: AUDITORÍA EN EL SISTEMA REAL (/etc/)
# ==============================================================================
step_banner "12" "Auditoría en el Sistema Real: Inspección de Symlinks en /etc/"

explain "Ejecutamos el comando de auditoría real find en /etc/ (limitado a las primeras 10 líneas):"
run_and_show "find /etc/ -maxdepth 2 -type l -exec ls -l {} \; 2>/dev/null | head -n 10"

echo -e "\n${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} ✔ LABORATORIO COMPLETADO CON ÉXITO                                             ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Has dominado la arquitectura de inodos, diferencias entre hard y soft links,"
echo -e "restricciones de cruce de dispositivos, auditoría forense con find (-samefile, -xtype l)"
echo -e "y los tres grandes casos de uso de producción (Deploy Zero-Downtime, Backups y lsof +L1).\n"
