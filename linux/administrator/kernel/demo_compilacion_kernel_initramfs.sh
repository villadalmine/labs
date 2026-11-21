#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Compilación de Kernel (Gentoo-Style) + Mini-OS + initramfs en QEMU
# Laboratorio: linux/administrator/kernel/compilacion_kernel_initramfs.md (Lab 3.24)
#
# - Modo por defecto (--fast): usa un kernel real instalado con algún driver
#   clave compilado como módulo (=m), fabrica un Mini-OS BusyBox (rootfs.img)
#   y ejecuta 2 actos reales en QEMU/KVM:
#     * Acto 1: Arrancar SIN -initrd -> Kernel panic: VFS: Unable to mount root fs.
#     * Acto 2: Arrancar CON initramfs.cpio.gz (conteniendo los .ko descomprimidos
#       + /init con insmod + switch_root) -> Arranque completo del Mini-OS!
# - Modo --build-kernel [--menuconfig]: descarga/extrae fuentes oficiales, aplica
#   fragmento Kconfig desatendido (CONFIG_VIRTIO_BLK=m) y compila bzImage + módulos.
# - Limpieza total garantizada (trap cleanup EXIT INT TERM).
#
# Uso:
#   sudo ./demo_compilacion_kernel_initramfs.sh [--auto <seg>] [--build-kernel] [--menuconfig] [--keep] [--clean]
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

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false
CLEAN_ONLY=false
BUILD_KERNEL=false
USE_MENUCONFIG=false
KERNEL_VERSION="${KERNEL_VERSION:-6.12.1}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                AUTO_DELAY="$2"
                shift 2
            else
                AUTO_DELAY=3
                shift
            fi
            ;;
        --build-kernel)
            BUILD_KERNEL=true
            shift
            ;;
        --menuconfig)
            USE_MENUCONFIG=true
            BUILD_KERNEL=true
            shift
            ;;
        --fast)
            BUILD_KERNEL=false
            shift
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Uso: sudo ./demo_compilacion_kernel_initramfs.sh [--auto <seg>] [--fast] [--build-kernel] [--menuconfig] [--keep] [--clean]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

DIR_LAB="/tmp/lab_demo_kernel_initramfs"

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Limpiando artefactos QEMU, discos virtuales e initramfs...${C_RESET}"
    rm -rf "${DIR_LAB}/mnt_root" 2>/dev/null || true
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "${C_GREEN}[INFO] Se preservan los artefactos en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_compilacion_kernel_initramfs.sh\n"
    else
        rm -rf "$DIR_LAB" 2>/dev/null || true
        echo -e "${C_GREEN}✔ Archivos temporales eliminados correctamente.${C_RESET}"
    fi
    echo -e "${C_GREEN}✔ Demostración finalizada.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para acceder a /boot/vmlinuz*, crear discos loop y ejecutar KVM.${C_RESET}"
    exit 1
fi

trap cleanup EXIT INT TERM

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
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
            sleep "$AUTO_DELAY"
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

rm -rf "$DIR_LAB"
mkdir -p "${DIR_LAB}/initramfs/bin" "${DIR_LAB}/initramfs/modules" "${DIR_LAB}/initramfs/dev" \
         "${DIR_LAB}/initramfs/proc" "${DIR_LAB}/initramfs/sys" "${DIR_LAB}/initramfs/mnt/root" \
         "${DIR_LAB}/rootfs_tree/bin" "${DIR_LAB}/rootfs_tree/sbin" "${DIR_LAB}/rootfs_tree/proc" \
         "${DIR_LAB}/rootfs_tree/sys" "${DIR_LAB}/rootfs_tree/dev" "${DIR_LAB}/rootfs_tree/etc"

clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 🚀 DEMOSTRACIÓN EN VIVO: COMPILACIÓN DE KERNEL, MINI-OS Y PARADOJA INITRAMFS  ${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "Demostración real en QEMU: Sin initramfs (Kernel Panic) vs Con initramfs (.ko + switch_root)\n"

# ==============================================================================
# PASO 1: VERIFICAR PREREQUISITOS (QEMU, BUSYBOX, CPIO Y KERNEL)
# ==============================================================================
step_banner "1" "Verificación de Emulador QEMU, BusyBox Estático y Herramientas"

for tool in qemu-system-x86_64 cpio gzip; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${C_RED}[ERROR] Falta el binario requerido '${tool}'. Instalalo (qemu-system-x86, cpio, gzip).${C_RESET}"
        exit 1
    fi
done

BUSYBOX_BIN=$(command -v busybox 2>/dev/null || command -v busybox-static 2>/dev/null || true)
if [ -z "$BUSYBOX_BIN" ]; then
    echo -e "${C_RED}[ERROR] Falta 'busybox' (instalá busybox-static en Ubuntu/Debian o busybox en Fedora).${C_RESET}"
    exit 1
fi

KVM_ARGS=""
if [ -w /dev/kvm ]; then
    KVM_ARGS="-enable-kvm -cpu host"
fi
run_and_show "echo \"QEMU: \$(which qemu-system-x86_64) | KVM: '${KVM_ARGS:-deshabilitado (usando TCG)}'\""
run_and_show "echo \"BusyBox: ${BUSYBOX_BIN}\" && file \"${BUSYBOX_BIN}\""

# ==============================================================================
# PASO 2: OBTENER / COMPILAR KERNEL Y LOCALIZAR UN MÓDULO CRÍTICO (=m)
# ==============================================================================
step_banner "2" "Preparación del Kernel y Selección del Driver Compilado como Módulo (=m)"

VMLINUZ=""
KVER_TARGET=""
TARGET_DRIVE_MODE="virtio"
TARGET_FS="ext4"
TARGET_MOD=""

if [ "$BUILD_KERNEL" = true ]; then
    explain "Modo --build-kernel activo: descargando y configurando fuentes oficiales de kernel.org (v${KERNEL_VERSION}):"
    MAJOR_SERIES="v${KERNEL_VERSION%%.*}.x"
    SRC_TAR="${DIR_LAB}/linux-${KERNEL_VERSION}.tar.xz"
    SRC_ROOT="${DIR_LAB}/linux-${KERNEL_VERSION}"
    BUILD_OUT="${DIR_LAB}/kernel_build"
    MOD_STAGE="${DIR_LAB}/mod_stage"
    mkdir -p "$BUILD_OUT" "$MOD_STAGE"

    run_and_show "curl -fSL \"https://cdn.kernel.org/pub/linux/kernel/${MAJOR_SERIES}/linux-${KERNEL_VERSION}.tar.xz\" -o \"${SRC_TAR}\" && tar -xf \"${SRC_TAR}\" -C \"${DIR_LAB}\""

    cat <<'EOF' > "${DIR_LAB}/gentoo_mini.config"
CONFIG_64BIT=y
CONFIG_SMP=y
CONFIG_PRINTK=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_PCI=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=m
CONFIG_EXT4_FS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_TTY=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
EOF
    run_and_show "make -C \"${SRC_ROOT}\" O=\"${BUILD_OUT}\" defconfig"
    run_and_show "cd \"${SRC_ROOT}\" && ./scripts/kconfig/merge_config.sh -m -O \"${BUILD_OUT}\" \"${BUILD_OUT}/.config\" \"${DIR_LAB}/gentoo_mini.config\""
    if [ "$USE_MENUCONFIG" = true ]; then
        make -C "$SRC_ROOT" O="$BUILD_OUT" menuconfig
    else
        make -C "$SRC_ROOT" O="$BUILD_OUT" olddefconfig >/dev/null
    fi
    run_and_show "grep -E 'CONFIG_(VIRTIO_BLK|EXT4_FS|BLK_DEV_INITRD)=' \"${BUILD_OUT}/.config\""
    explain "Compilando bzImage y módulos (puede demorar unos minutos)..."
    run_and_show "make -C \"${SRC_ROOT}\" O=\"${BUILD_OUT}\" -j\$(nproc) bzImage modules"
    run_and_show "make -C \"${SRC_ROOT}\" O=\"${BUILD_OUT}\" INSTALL_MOD_PATH=\"${MOD_STAGE}\" modules_install"

    VMLINUZ="${BUILD_OUT}/arch/x86/boot/bzImage"
    KVER_TARGET=$(ls "${MOD_STAGE}/lib/modules/" | head -n 1)
    TARGET_MOD="virtio_blk"
    MOD_BASE_DIR="${MOD_STAGE}"
else
    explain "Modo --fast: localizamos un kernel real instalado en /boot y verificamos qué driver crítico está compilado como módulo (=m) y no built-in (=y):"
    # Buscar un par vmlinuz + /lib/modules/<ver> válido
    for cand in /boot/vmlinuz-"$(uname -r)" /boot/vmlinuz-* /lib/modules/*/vmlinuz; do
        [ -f "$cand" ] || continue
        ver="${cand##*/vmlinuz-}"
        if [ "$ver" = "$cand" ]; then
            ver=$(basename "$(dirname "$cand")")
        fi
        if [ -d "/lib/modules/${ver}" ]; then
            VMLINUZ="$cand"
            KVER_TARGET="$ver"
            break
        fi
    done

    if [ -z "$VMLINUZ" ]; then
        echo -e "${C_RED}[ERROR] No se encontró imagen vmlinuz legible en /boot o /lib/modules. Ejecutá en una VM/host con kernel instalado o usá --build-kernel.${C_RESET}"
        exit 1
    fi

    MOD_BASE_DIR="/"
    # Detectar un driver de disco o filesystem que sea verdaderamente módulo (.ko*) en ese kernel
    if modprobe -S "$KVER_TARGET" --show-depends virtio_blk 2>/dev/null | grep -q '^insmod '; then
        TARGET_MOD="virtio_blk"
        TARGET_DRIVE_MODE="virtio"
        TARGET_FS="ext4"
    elif modprobe -S "$KVER_TARGET" --show-depends nvme 2>/dev/null | grep -q '^insmod '; then
        TARGET_MOD="nvme"
        TARGET_DRIVE_MODE="nvme"
        TARGET_FS="ext4"
    elif command -v mkfs.xfs &>/dev/null && modprobe -S "$KVER_TARGET" --show-depends xfs 2>/dev/null | grep -q '^insmod '; then
        TARGET_MOD="xfs"
        TARGET_DRIVE_MODE="virtio"
        TARGET_FS="xfs"
    elif modprobe -S "$KVER_TARGET" --show-depends ext2 2>/dev/null | grep -q '^insmod '; then
        TARGET_MOD="ext2"
        TARGET_DRIVE_MODE="virtio"
        TARGET_FS="ext2"
    else
        echo -e "${C_RED}[ERROR] No se encontró un módulo de arranque (virtio_blk/nvme/xfs/ext2) compilado como =m en ${KVER_TARGET}.${C_RESET}"
        exit 1
    fi

    run_and_show "echo \"Kernel seleccionado: ${VMLINUZ} (version ${KVER_TARGET})\""
    run_and_show "echo \"Driver critico seleccionado como [M]=m: ${TARGET_MOD} | Disco: ${TARGET_DRIVE_MODE} | FS: ${TARGET_FS}\""
    run_and_show "modprobe -S \"${KVER_TARGET}\" --show-depends \"${TARGET_MOD}\""
fi

pie_clase "¿Por qué en este experimento necesitamos que '${TARGET_MOD}' esté compilado como módulo (=m) y NO built-in (=y)?" \
          "Porque si estuviera built-in (=y) dentro de vmlinuz, el kernel podría montar el disco directamente sin initramfs; al ser =m, el driver vive como archivo .ko y demuestra la necesidad real de initramfs."

pause_step "Presioná [ENTER] para construir el disco Mini-OS (rootfs.img) y provocar el Acto 1 (Sin initramfs)..."

# ==============================================================================
# PASO 3: CONSTRUIR EL DISCO MINI-OS (rootfs.img) Y PROVOCAR KERNEL PANIC (ACTO 1)
# ==============================================================================
step_banner "3" "Acto 1: Mini-OS en Disco y Arranque SIN initramfs (Kernel Panic Controlado)"

explain "Construimos un Mini-OS minimalista basado en BusyBox dentro de una imagen de disco ${DIR_LAB}/rootfs.img (${TARGET_FS}):"
cp "$BUSYBOX_BIN" "${DIR_LAB}/rootfs_tree/bin/busybox"
chmod +x "${DIR_LAB}/rootfs_tree/bin/busybox"
for cmd in sh mount umount echo uname ls cat lsmod insmod poweroff sleep dmesg; do
    ln -sf /bin/busybox "${DIR_LAB}/rootfs_tree/bin/${cmd}"
done

cat <<'EOF' > "${DIR_LAB}/rootfs_tree/sbin/init"
#!/bin/sh
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
echo ""
echo "=================================================================="
echo "  MINI-OS EMBEBIDO ARRANCADO EXITOSAMENTE TRAS SWITCH_ROOT!"
echo "=================================================================="
echo -n "Kernel activo : "
uname -a
echo "Modulos cargados desde initramfs antes de montar '/':"
cat /proc/modules | head -n 10
echo "Sistema de archivos raiz montado:"
cat /proc/mounts | grep -E ' / |rootfs' | head -n 3
echo "=================================================================="
echo "Prueba completada con exito. Apagando VM QEMU..."
/bin/poweroff -f
EOF
chmod +x "${DIR_LAB}/rootfs_tree/sbin/init"

ROOTFS_IMG="${DIR_LAB}/rootfs.img"
if [ "$TARGET_FS" = "xfs" ]; then
    truncate -s 320M "$ROOTFS_IMG"
    run_and_show "mkfs.xfs -q \"${ROOTFS_IMG}\""
else
    truncate -s 48M "$ROOTFS_IMG"
    run_and_show "mkfs.${TARGET_FS} -F -d \"${DIR_LAB}/rootfs_tree\" \"${ROOTFS_IMG}\" 2>/dev/null || true"
fi

# Si mkfs no soportó -d (ej. mkfs.xfs o mkfs.ext2 antiguo), copiar vía mount -o loop
if [ "$TARGET_FS" = "xfs" ] || ! command -v debugfs &>/dev/null || [ "$TARGET_FS" = "ext2" ]; then
    mkdir -p "${DIR_LAB}/mnt_root"
    if mount -o loop "$ROOTFS_IMG" "${DIR_LAB}/mnt_root" 2>/dev/null; then
        cp -a "${DIR_LAB}/rootfs_tree/"* "${DIR_LAB}/mnt_root/"
        umount "${DIR_LAB}/mnt_root"
    fi
fi

if [ "$TARGET_DRIVE_MODE" = "nvme" ]; then
    QEMU_DRIVE_ARGS="-drive file=${ROOTFS_IMG},if=none,id=drv0,format=raw -device nvme,drive=drv0,serial=lab123"
    ROOT_DEV="/dev/nvme0n1"
else
    QEMU_DRIVE_ARGS="-drive file=${ROOTFS_IMG},if=virtio,format=raw"
    ROOT_DEV="/dev/vda"
fi

explain "ACTO 1: Arrancamos QEMU SIN '-initrd'. Al no poder cargar ${TARGET_MOD}.ko, el kernel DEBE entrar en Kernel Panic:"
QEMU_ACT1_LOG="${DIR_LAB}/qemu_act1.log"
QEMU_CMD_ACT1="timeout 20 qemu-system-x86_64 ${KVM_ARGS} -m 512M -nographic -no-reboot -kernel \"${VMLINUZ}\" ${QEMU_DRIVE_ARGS} -append \"root=${ROOT_DEV} rootfstype=${TARGET_FS} rw console=ttyS0 panic=1 rdinit=/none\""

echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR (ACTO 1 - SIN INITRAMFS) ───────────────────────────────────┐${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}$ ${QEMU_CMD_ACT1}${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DE CONSOLA SERIAL QEMU ────────────────────────────────────────────┤${C_RESET}"
eval "$QEMU_CMD_ACT1" >"$QEMU_ACT1_LOG" 2>&1 || true
grep -iE 'Linux version|Kernel panic|Unable to mount root|VFS:|Cannot open root' "$QEMU_ACT1_LOG" | tail -n 15 || tail -n 15 "$QEMU_ACT1_LOG"
echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"

pie_clase "¿Por qué apareció 'Kernel panic - VFS: Unable to mount root fs' en el Acto 1?" \
          "Porque el controlador '${TARGET_MOD}' está compilado como módulo (.ko) dentro del almacenamiento, pero sin initramfs el kernel no tiene forma de cargarlo antes de montar '/'."

pause_step "Presioná [ENTER] para construir initramfs.cpio.gz con el módulo .ko y ejecutar el Acto 2..."

# ==============================================================================
# PASO 4: CONSTRUIR INITRAMFS CON .KO DESCOMPRIMIDOS Y EJECUTAR ACTO 2
# ==============================================================================
step_banner "4" "Acto 2: Construcción Manual de initramfs.cpio.gz y Arranque con switch_root"

cp "$BUSYBOX_BIN" "${DIR_LAB}/initramfs/bin/busybox"
chmod +x "${DIR_LAB}/initramfs/bin/busybox"
for cmd in sh insmod mount umount echo sleep switch_root mkdir mknod ls cat; do
    ln -sf /bin/busybox "${DIR_LAB}/initramfs/bin/${cmd}"
done

explain "Extraemos ${TARGET_MOD} y TODAS sus dependencias (.ko), descomprimiendo .zst/.xz si hace falta para BusyBox insmod:"
INIT_INSMOD_LIST="${DIR_LAB}/insmod_order.txt"
: > "$INIT_INSMOD_LIST"

MODPROBE_BASE_OPT=""
if [ "$MOD_BASE_DIR" != "/" ]; then
    MODPROBE_BASE_OPT="-d ${MOD_BASE_DIR}"
fi

while read -r action modpath _rest; do
    if [ "$action" = "insmod" ] && [ -f "$modpath" ]; then
        bname=$(basename "$modpath")
        case "$bname" in
            *.ko.zst)
                out_ko="${bname%.zst}"
                zstd -d -f -q "$modpath" -o "${DIR_LAB}/initramfs/modules/${out_ko}"
                ;;
            *.ko.xz)
                out_ko="${bname%.xz}"
                xz -d -c "$modpath" > "${DIR_LAB}/initramfs/modules/${out_ko}"
                ;;
            *.ko)
                out_ko="$bname"
                cp "$modpath" "${DIR_LAB}/initramfs/modules/${out_ko}"
                ;;
            *)
                continue
                ;;
        esac
        echo "$out_ko" >> "$INIT_INSMOD_LIST"
    fi
done < <(modprobe ${MODPROBE_BASE_OPT} -S "$KVER_TARGET" --show-depends "$TARGET_MOD" 2>/dev/null)

# En caso de compilación custom (si virtio_blk requiere virtio_pci o viceversa), asegurar cualquier .ko presente si fuera necesario
run_and_show "cat \"${INIT_INSMOD_LIST}\" && ls -lh \"${DIR_LAB}/initramfs/modules/\""

cat <<EOF > "${DIR_LAB}/initramfs/init"
#!/bin/sh
/bin/mount -t proc proc /proc
/bin/mount -t sysfs sysfs /sys
/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

echo ""
echo "[initramfs] >>> Fase temprana en RAM iniciada (PID 1 = /init) <<<"
echo "[initramfs] Cargando cadena de modulos para habilitar '${TARGET_MOD}'..."
EOF

while read -r ko_file; do
    echo "echo \"[initramfs] insmod /modules/${ko_file}\"" >> "${DIR_LAB}/initramfs/init"
    echo "/bin/insmod \"/modules/${ko_file}\" || true" >> "${DIR_LAB}/initramfs/init"
done < "$INIT_INSMOD_LIST"

cat <<EOF >> "${DIR_LAB}/initramfs/init"
echo "[initramfs] Esperando dispositivo raiz ${ROOT_DEV}..."
i=0
while [ ! -b "${ROOT_DEV}" ] && [ \$i -lt 30 ]; do
    /bin/sleep 0.2
    i=\$((i + 1))
done
/bin/ls -l "${ROOT_DEV}" || true
echo "[initramfs] Montando ${ROOT_DEV} (${TARGET_FS}) en /mnt/root..."
/bin/mount -t ${TARGET_FS} "${ROOT_DEV}" /mnt/root || {
    echo "[initramfs] ERROR al montar ${ROOT_DEV}"
    /bin/sleep 1
    exit 1
}
echo "[initramfs] Transfiriendo control al sistema real mediante switch_root!"
exec /bin/switch_root /mnt/root /sbin/init
EOF
chmod +x "${DIR_LAB}/initramfs/init"

INITRAMFS_IMG="${DIR_LAB}/initramfs.cpio.gz"
run_and_show "cd \"${DIR_LAB}/initramfs\" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > \"${INITRAMFS_IMG}\" && ls -lh \"${INITRAMFS_IMG}\""

explain "ACTO 2: Ejecutamos EXACTAMENTE el mismo QEMU pero agregando '-initrd ${INITRAMFS_IMG}':"
QEMU_ACT2_LOG="${DIR_LAB}/qemu_act2.log"
QEMU_CMD_ACT2="timeout 25 qemu-system-x86_64 ${KVM_ARGS} -m 512M -nographic -no-reboot -kernel \"${VMLINUZ}\" -initrd \"${INITRAMFS_IMG}\" ${QEMU_DRIVE_ARGS} -append \"root=${ROOT_DEV} rootfstype=${TARGET_FS} rw console=ttyS0\""

echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR (ACTO 2 - CON INITRAMFS) ───────────────────────────────────┐${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}$ ${QEMU_CMD_ACT2}${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DE CONSOLA SERIAL QEMU ────────────────────────────────────────────┤${C_RESET}"
eval "$QEMU_CMD_ACT2" >"$QEMU_ACT2_LOG" 2>&1 || true
grep -A 25 'Fase temprana en RAM' "$QEMU_ACT2_LOG" || tail -n 25 "$QEMU_ACT2_LOG"
echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"

pie_clase "¿Qué hace exactamente 'exec switch_root /mnt/root /sbin/init' al final del arranque de initramfs?" \
          "Limpia el rootfs temporal de la memoria RAM, mueve el punto de montaje real '/' hacia el disco recién montado y reemplaza el PID 1 por el /sbin/init definitivo del sistema operativo."

echo -e "\n${C_BOLD}${C_GREEN}✔ Lab 3.24 completado con éxito.${C_RESET}"
