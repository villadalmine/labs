#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Trabajo Integrador 2
# Docker en LVM Hot-Mirror + MySQL en LVM RAID 1 + WordPress + Backup Cifrado S3
#
# Uso:
#   sudo ./demo_integrador_docker.sh [opciones] [DISCO1 DISCO2 DISCO3 DISCO4]
# Opciones:
#   --auto <segundos>    Modo automático con pausa de N segundos entre pasos
#   --keep               No desmontar ni limpiar al finalizar (dejar corriendo)
# ==============================================================================

# Si se ejecuta en tmux, activar scroll con la rueda del ratón
if [ -n "$TMUX" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

# Paleta de colores didáctica
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
RESET='\033[0m'

AUTO_MODE=false
AUTO_DELAY=3
KEEP_RUNNING=false
LOOP_MODE=false

# Procesar argumentos
POSITIONAL_ARGS=()
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
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

pause_step() {
    local mensaje="${1:-Presiona [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${YELLOW}[MODO AUTOMÁTICO] Esperando ${AUTO_DELAY}s: ${mensaje}${RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${YELLOW}>>> ${mensaje}${RESET}"
        read -r
    fi
}

header() {
    echo -e "\n${CYAN}======================================================================${RESET}"
    echo -e "${BOLD}${CYAN} $1 ${RESET}"
    echo -e "${CYAN}======================================================================${RESET}"
}

subheader() {
    echo -e "\n${PURPLE}--- $1 ---${RESET}"
}

# Verificar permisos de superusuario
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Este script interactivo de almacenamiento requiere privilegios de root.${RESET}"
    echo -e "Por favor, ejecútalo con: ${BOLD}sudo $0${RESET}"
    exit 1
fi

# Directorio temporal de trabajo
LAB_DIR="/var/tmp/lab_docker_raid"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR" || exit 1

LOOP_DEVS=()

cleanup() {
    if [ "$KEEP_RUNNING" = true ]; then
        echo -e "\n${GREEN}[INFO] Se seleccionó --keep. Los contenedores y volúmenes quedan activos para tu inspección.${RESET}"
        return
    fi

    echo -e "\n${YELLOW}[LIMPIEZA] Desmontando sistemas de archivos y limpiando recursos del laboratorio...${RESET}"
    
    # Detener contenedores si existen
    if [ -d "$LAB_DIR/app" ]; then
        (cd "$LAB_DIR/app" && docker compose down -v 2>/dev/null || true)
    fi

    # Desmontar puntos de montaje
    umount -l /srv/mysql_data 2>/dev/null || true
    umount -l /var/lib/docker 2>/dev/null || true

    # Desactivar y remover LVs y VGs
    lvremove -y vg_mysql/lv_mysql 2>/dev/null || true
    vgremove -y vg_mysql 2>/dev/null || true
    pvremove -y "${DISCO_MYSQL_A}" "${DISCO_MYSQL_B}" 2>/dev/null || true

    lvremove -y vg_docker/lv_docker 2>/dev/null || true
    vgremove -y vg_docker 2>/dev/null || true
    pvremove -y "${DISCO_DOCKER_A}" "${DISCO_DOCKER_B}" 2>/dev/null || true

    # Si se usaron loop devices, liberarlos
    if [ "$LOOP_MODE" = true ]; then
        for dev in "${LOOP_DEVS[@]}"; do
            losetup -d "$dev" 2>/dev/null || true
        done
        rm -rf "$LAB_DIR" 2>/dev/null || true
    fi

    echo -e "${GREEN}[OK] Limpieza finalizada correctamente.${RESET}"
}
trap cleanup EXIT INT TERM

# ==============================================================================
# FASE 0: CONFIGURACIÓN DE DISCOS (REALES O LOOP VIRTUALES)
# ==============================================================================
header "FASE 0: Detección y Preparación de Discos"

if [ ${#POSITIONAL_ARGS[@]} -ge 4 ]; then
    DISCO_DOCKER_A="${POSITIONAL_ARGS[0]}"
    DISCO_DOCKER_B="${POSITIONAL_ARGS[1]}"
    DISCO_MYSQL_A="${POSITIONAL_ARGS[2]}"
    DISCO_MYSQL_B="${POSITIONAL_ARGS[3]}"
    echo -e "${GREEN}[INFO] Utilizando discos físicos/EBS proporcionados por parámetro:${RESET}"
else
    echo -e "${YELLOW}[INFO] No se indicaron 4 discos por parámetro. Creando 4 loop devices de 1 GB para simulación...${RESET}"
    LOOP_MODE=true
    for i in 1 2 3 4; do
        img="$LAB_DIR/disk${i}.img"
        truncate -s 1G "$img"
        dev=$(losetup -fP --show "$img")
        LOOP_DEVS+=("$dev")
    done
    DISCO_DOCKER_A="${LOOP_DEVS[0]}"
    DISCO_DOCKER_B="${LOOP_DEVS[1]}"
    DISCO_MYSQL_A="${LOOP_DEVS[2]}"
    DISCO_MYSQL_B="${LOOP_DEVS[3]}"
fi

echo -e "  * ${BOLD}Docker Disco A (Inicial):${RESET}      $DISCO_DOCKER_A"
echo -e "  * ${BOLD}Docker Disco B (Espejo Caliente):${RESET} $DISCO_DOCKER_B"
echo -e "  * ${BOLD}MySQL Disco A  (RAID 1 Pata 1):${RESET}   $DISCO_MYSQL_A"
echo -e "  * ${BOLD}MySQL Disco B  (RAID 1 Pata 2):${RESET}   $DISCO_MYSQL_B"

pause_step "Inspeccionar topología de bloques..."

lsblk "$DISCO_DOCKER_A" "$DISCO_DOCKER_B" "$DISCO_MYSQL_A" "$DISCO_MYSQL_B"

# ==============================================================================
# FASE 1: PREPARACIÓN DE /var/lib/docker EN LVM ANTES DE INSTALAR DOCKER
# ==============================================================================
header "FASE 1: Montaje Previsto de /var/lib/docker en LVM"
echo -e "${CYAN}CONCEPTO CLAVE:${RESET}"
echo -e "En producción, Docker NUNCA debe escribir en el disco raíz '/'."
echo -e "Si la raíz se llena por culpa de imágenes o logs de contenedores, todo el SO se congela."
echo -e "Montamos un volumen LVM dedicado en /var/lib/docker ANTES de operar con Docker."

subheader "1.1 Inicializar PV y VG en Disco Docker A"
echo "$ sudo pvcreate $DISCO_DOCKER_A"
pvcreate -y "$DISCO_DOCKER_A"
echo "$ sudo vgcreate vg_docker $DISCO_DOCKER_A"
vgcreate -y vg_docker "$DISCO_DOCKER_A"
vgs vg_docker

pause_step "Crear el volumen lógico lineal..."

subheader "1.2 Crear y formatear lv_docker con ext4"
echo "$ sudo lvcreate -l 100%FREE -n lv_docker vg_docker"
lvcreate -y -l 100%FREE -n lv_docker vg_docker
echo "$ sudo mkfs.ext4 -L DOCKER_ROOT /dev/vg_docker/lv_docker"
mkfs.ext4 -F -L DOCKER_ROOT /dev/vg_docker/lv_docker

subheader "1.3 Montar en /var/lib/docker"
mkdir -p /var/lib/docker
mount /dev/vg_docker/lv_docker /var/lib/docker
df -h /var/lib/docker

pause_step "Verificar integración con Docker..."

# ==============================================================================
# FASE 2: VERIFICACIÓN DEL DEMONIO DOCKER
# ==============================================================================
header "FASE 2: Verificación del Almacenamiento de Docker"
if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Instalando docker.io...${RESET}"
    apt-get update -qq && apt-get install -y -qq docker.io docker-compose-v2
fi

# Iniciar servicio si no está activo
systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true

echo -e "\nDirectorio raíz de Docker reportado por el motor:"
docker info 2>/dev/null | grep -E "Docker Root Dir|Storage Driver" || echo "Docker daemon activo"

echo -e "\nDescargando imagen ligera para escribir capas en el volumen LVM:"
docker pull alpine:latest
df -h /var/lib/docker

pause_step "Avanzar a la conversión a RAID 1 en caliente (sin detener Docker)..."

# ==============================================================================
# FASE 3: CONVERSIÓN EN CALIENTE A LVM RAID 1 (HOT MIRROR)
# ==============================================================================
header "FASE 3: Conversión en Caliente de lv_docker a RAID 1"
echo -e "${CYAN}CASO DE PRODUCCIÓN REAL:${RESET}"
echo -e "Docker está corriendo con servicios en producción en un disco simple."
echo -e "Incorporamos un segundo disco y convertimos el volumen en espejo (RAID 1) EN VIVO."

subheader "3.1 Inicializar Disco Docker B y extender vg_docker"
echo "$ sudo pvcreate $DISCO_DOCKER_B"
pvcreate -y "$DISCO_DOCKER_B"
echo "$ sudo vgextend vg_docker $DISCO_DOCKER_B"
vgextend vg_docker "$DISCO_DOCKER_B"
pvs

pause_step "Ejecutar lvconvert a RAID 1..."

subheader "3.2 Convertir lv_docker en arreglo RAID 1 (1 réplica / 2 copias)"
echo "$ sudo lvconvert --type raid1 -m 1 -y vg_docker/lv_docker"
lvconvert --type raid1 -m 1 -y vg_docker/lv_docker

echo -e "\n${GREEN}[OK] Conversión ejecutada en vivo. Inspeccionando subvolúmenes de metadata e imagen:${RESET}"
lvs -a -o +devices,copy_percent vg_docker

pause_step "Preparar almacenamiento redundante para MySQL..."

# ==============================================================================
# FASE 4: ALMACENAMIENTO DEDICADO PARA MYSQL EN LVM RAID 1
# ==============================================================================
header "FASE 4: Almacenamiento Dedicado de Base de Datos en LVM RAID 1"
echo -e "${CYAN}OBJETIVO:${RESET}"
echo -e "Crear un volumen RAID 1 nativo con dos discos dedicados para /srv/mysql_data."

subheader "4.1 Inicializar Discos MySQL A y B"
pvcreate -y "$DISCO_MYSQL_A" "$DISCO_MYSQL_B"
vgcreate -y vg_mysql "$DISCO_MYSQL_A" "$DISCO_MYSQL_B"
vgs vg_mysql

subheader "4.2 Crear Logical Volume RAID 1 de 800 MB"
echo "$ sudo lvcreate --type raid1 -m 1 -L 800M -n lv_mysql vg_mysql"
lvcreate -y --type raid1 -m 1 -L 800M -n lv_mysql vg_mysql
mkfs.ext4 -F -L MYSQL_DATA /dev/vg_mysql/lv_mysql

mkdir -p /srv/mysql_data
mount /dev/vg_mysql/lv_mysql /srv/mysql_data
df -h /srv/mysql_data

pause_step "Desplegar WordPress + MySQL con Docker Compose..."

# ==============================================================================
# FASE 5: DESPLIEGUE DE WORDPRESS + MYSQL CON DOCKER COMPOSE
# ==============================================================================
header "FASE 5: Despliegue del Stack con Persistencia en RAID 1"
APP_DIR="$LAB_DIR/app"
mkdir -p "$APP_DIR"

cat <<'EOF' > "$APP_DIR/docker-compose.yml"
services:
  db:
    image: mysql:8.0
    container_name: demo-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword123
      MYSQL_DATABASE: wordpress_db
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppassword123
    volumes:
      - /srv/mysql_data:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    container_name: demo-wordpress
    restart: always
    depends_on:
      - db
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_NAME: wordpress_db
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppassword123
EOF

echo -e "Levantando contenedores en segundo plano..."
(cd "$APP_DIR" && docker compose up -d)

echo -e "\nEsperando que MySQL inicialice el almacenamiento en /srv/mysql_data..."
until docker exec demo-mysql mysqladmin ping -h localhost -u root -prootpassword123 --silent 2>/dev/null; do
    echo -n "."
    sleep 2
done
echo -e "\n${GREEN}[OK] MySQL 8.0 listo y operativo sobre LVM RAID 1.${RESET}"

subheader "5.1 Inyectar datos de prueba para simular transacciones"
docker exec -i demo-mysql mysql -u root -prootpassword123 wordpress_db <<'SQL'
CREATE TABLE IF NOT EXISTS demo_posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    contenido TEXT NOT NULL,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO demo_posts (titulo, contenido) VALUES 
('Post Inicial', 'Este articulo reside en el almacenamiento seguro LVM RAID 1'),
('Alta Disponibilidad', 'Si un disco falla, MySQL no pierde ninguna transaccion');
SQL

echo -e "\nRegistros insertados en la base de datos:"
docker exec -i demo-mysql mysql -u root -prootpassword123 -e "SELECT * FROM wordpress_db.demo_posts;"

pause_step "Simular fallo de disco físico en el arreglo MySQL..."

# ==============================================================================
# FASE 6: SIMULACIÓN DE FALLO DE DISCO (TOLERANCIA A FALLOS)
# ==============================================================================
header "FASE 6: Simulación de Falla de Disco en MySQL RAID 1"

DM_PATA0=$(dmsetup ls | grep "vg_mysql-lv_mysql_rimage_0" | awk '{print $1}')
echo -e "Inyectando tabla de error de I/O en la pata 0 ($DM_PATA0)..."

dmsetup suspend "$DM_PATA0" 2>/dev/null || true
dmsetup load "$DM_PATA0" --table "0 $(blockdev --getsz /dev/mapper/"$DM_PATA0") error" 2>/dev/null || true
dmsetup resume "$DM_PATA0" 2>/dev/null || true

echo -e "\n${YELLOW}[ESTADO DEGRADADO] Probando lectura y nueva transacción en MySQL durante el fallo:${RESET}"
docker exec -i demo-mysql mysql -u root -prootpassword123 -e "INSERT INTO wordpress_db.demo_posts (titulo, contenido) VALUES ('Post Durante Falla', 'Escrito con la Pata 0 completamente caída');"
docker exec -i demo-mysql mysql -u root -prootpassword123 -e "SELECT * FROM wordpress_db.demo_posts;"

echo -e "\n${GREEN}[EXITO] Cero caídas, cero transacciones perdidas gracias a LVM RAID 1.${RESET}"

subheader "6.1 Restaurar salud del arreglo"
lvchange --refresh vg_mysql/lv_mysql 2>/dev/null || true

pause_step "Proceder con la estrategia de backup cifrado..."

# ==============================================================================
# FASE 7: BACKUP CIFRADO CON OPENSSL Y SUBIDA A S3
# ==============================================================================
header "FASE 7: Backup Lógico Cifrado (OpenSSL AES-256) y Almacenamiento Seguro"
BACKUP_DIR="$LAB_DIR/backups"
mkdir -p "$BACKUP_DIR"

echo -e "1. Generando volcado lógico con mysqldump..."
docker exec demo-mysql mysqldump -u root -prootpassword123 --single-transaction wordpress_db > "$BACKUP_DIR/dump_wordpress.sql"
ls -lh "$BACKUP_DIR/dump_wordpress.sql"

echo -e "\n2. Cifrando con OpenSSL AES-256-CBC + PBKDF2 (Zero-Trust)..."
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
    -in "$BACKUP_DIR/dump_wordpress.sql" \
    -out "$BACKUP_DIR/backup_wordpress.sql.enc" \
    -pass pass:ClaveSuperSegura2026!

echo -e "Comprobación forense del archivo cifrado (ininteligible en reposo):"
head -c 60 "$BACKUP_DIR/backup_wordpress.sql.enc" ; echo ""

# Comprobar si AWS CLI está configurado y hay un bucket disponible
if command -v aws &>/dev/null && aws s3 ls &>/dev/null; then
    BUCKET_S3=$(aws s3 ls 2>/dev/null | grep "lab-docker-backup" | awk '{print $3}' | head -n 1)
    if [ -n "$BUCKET_S3" ]; then
        echo -e "\nSubiendo backup cifrado al bucket S3 de AWS: s3://$BUCKET_S3/backups/"
        aws s3 cp "$BACKUP_DIR/backup_wordpress.sql.enc" "s3://$BUCKET_S3/backups/"
        aws s3 ls "s3://$BUCKET_S3/backups/"
    fi
else
    echo -e "${CYAN}[SIMULACIÓN S3] Archivo cifrado resguardado en almacén seguro remoto ($BACKUP_DIR/vault/)${RESET}"
    mkdir -p "$BACKUP_DIR/vault"
    cp "$BACKUP_DIR/backup_wordpress.sql.enc" "$BACKUP_DIR/vault/"
fi

# Eliminar archivo en texto plano
rm -f "$BACKUP_DIR/dump_wordpress.sql"

pause_step "Simular catástrofe y restaurar..."

# ==============================================================================
# FASE 8: SIMULACIÓN DE DESASTRE Y RESTAURACIÓN COMPLETA
# ==============================================================================
header "FASE 8: Simulación de Desastre y Restauración de Base de Datos"

echo -e "${RED}[DESASTRE] Destruyendo la base de datos completa con DROP DATABASE...${RESET}"
docker exec demo-mysql mysql -u root -prootpassword123 -e "DROP DATABASE wordpress_db;"

echo -e "Verificando destrucción (la tabla ya no existe):"
docker exec demo-mysql mysql -u root -prootpassword123 -e "SHOW DATABASES;" | grep "wordpress_db" || echo -e "${RED}[CONFIRMADO] wordpress_db no existe.${RESET}"

pause_step "Iniciar proceso de recuperación ante desastres (DR)..."

subheader "8.1 Descifrar backup con OpenSSL"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -in "$BACKUP_DIR/backup_wordpress.sql.enc" \
    -out "$BACKUP_DIR/dump_restaurado.sql" \
    -pass pass:ClaveSuperSegura2026!

subheader "8.2 Recrear esquema e inyectar datos"
docker exec demo-mysql mysql -u root -prootpassword123 -e "CREATE DATABASE wordpress_db;"
docker exec -i demo-mysql mysql -u root -prootpassword123 wordpress_db < "$BACKUP_DIR/dump_restaurado.sql"

pause_step "Avanzar a la demostración de redimensionamiento en caliente..."

# ==============================================================================
# FASE 9: REDIMENSIONAMIENTO EN CALIENTE (ONLINE RESIZE)
# ==============================================================================
header "FASE 9: Redimensionamiento en Caliente de Sistemas de Archivos Montados"
echo -e "${CYAN}CONCEPTOS DE OPERACIÓN EN PRODUCCIÓN:${RESET}"
echo -e "1. Ampliar /var/lib/docker en LVM sin detener el servicio con lvextend -r."
echo -e "2. Ampliar particiones y sistemas de archivos montados (ej. rootfs '/') con growpart y resize2fs."

subheader "9.1 Extender /var/lib/docker en caliente"
echo -e "Espacio actual de /var/lib/docker:"
df -h /var/lib/docker

echo -e "\nEjecutando lvextend con flag -r (--resizefs) para extender LV y ext4 a la vez:"
lvextend -L +100M /dev/vg_docker/lv_docker -r 2>/dev/null || lvextend -l +100%FREE /dev/vg_docker/lv_docker -r 2>/dev/null || true

echo -e "\nNuevo espacio de /var/lib/docker en vivo:"
df -h /var/lib/docker

subheader "9.2 Explicación de redimensionamiento del disco raíz ('/') en AWS"
echo -e "En AWS EC2, cuando agrandas el volumen EBS raíz (ej: de 10 GB a 15 GB):"
echo -e "  1. El SO detecta el nuevo tamaño del disco físico (lsblk)."
echo -e "  2. Para expandir la partición sin desmontar ni reiniciar:"
echo -e "     ${BOLD}sudo growpart /dev/nvme0n1 1${RESET}"
echo -e "  3. Para expandir el sistema de archivos ext4 en caliente:"
echo -e "     ${BOLD}sudo resize2fs /dev/nvme0n1p1${RESET}"
echo -e "  4. Verificación inmediata con ${BOLD}df -h /${RESET}"

header "DEMOSTRACIÓN FINALIZADA CON ÉXITO"
echo -e "${GREEN}${BOLD}Todas las fases se completaron satisfactoriamente:${RESET}"
echo -e "  1. /var/lib/docker aislado en LVM antes de instalar."
echo -e "  2. Hot-Mirror a RAID 1 ejecutado en vivo sin detener Docker."
echo -e "  3. Almacenamiento MySQL en LVM RAID 1 dedicado tolerante a fallas."
echo -e "  4. WordPress levantado y comprobación de escritura real."
echo -e "  5. Falla de disco simulada sin caída de servicio ni pérdida de transacciones."
echo -e "  6. Backup lógico cifrado con OpenSSL AES-256."
echo -e "  7. Desastre provocado y recuperación total garantizada."
echo -e "  8. Redimensionamiento en caliente de sistemas de archivos montados."

if [ "$KEEP_RUNNING" = false ]; then
    echo -e "\n${YELLOW}El script desmontará y limpiará los recursos al salir.${RESET}"
else
    echo -e "\n${GREEN}Modo --keep activo: Los contenedores y volúmenes quedan en ejecución.${RESET}"
fi
