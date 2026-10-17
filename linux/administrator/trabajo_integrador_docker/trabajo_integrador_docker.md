---
id: integrador-4.2-docker-lvm-hotmirror-mysql-s3
title: 'Trabajo Integrador 2: Docker Engine en LVM Hot-Mirror, MySQL RAID 1, WordPress
  y AWS S3 Cifrado'
difficulty_level: 4
difficulty_label: 'Nivel 4: Proyectos Integradores en la Nube (AWS Free Tier con Terraform)'
section: '4.2'
sections:
- '4.2'
- '4'
category: cloud-iac
tags:
- cloud-iac
- aws
- ec2
- terraform
- docker
- docker-compose
- mysql
- wordpress
- lvm
- hot-mirror
- raid1
- s3
- openssl
- iam
- online-resize
tools:
- terraform
- docker
- docker-compose
- aws-cli
- lvconvert
- lvextend
- resize2fs
- growpart
- openssl
requirements:
  root_required: true
  cloud_required: true
  min_ram_mb: 1024
  min_disks: 4
  cloud_provider: AWS
tested_environments:
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Despliegue verificado en AWS con Terraform (1 EC2 t3.micro, 4 discos EBS
    de 1 GB, bucket S3 cifrado y script interactivo demo_integrador_docker.sh).
environments:
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Proyecto integrador de nivel producción combinando Docker, almacenamiento
  en bloque y nube de AWS. Enseña a aislar /var/lib/docker en LVM antes de instalar
  Docker, convertir volúmenes a RAID 1 en caliente (hot-mirror) sin pausar el motor,
  alojar bases de datos MySQL persistentes para WordPress con tolerancia a fallos,
  realizar dumps lógicos consistentes cifrados con OpenSSL (AES-256) y subirlos a
  buckets S3 con IAM Instance Profiles.
files:
  guide: trabajo_integrador_docker/trabajo_integrador_docker.md
  script: trabajo_integrador_docker/demo_integrador_docker.sh
  terraform: trabajo_integrador_docker/terraform
resource_type: cloud_project
has_guide: true
has_interactive_script: true
has_terraform: true
execution_mode: terraform_apply
prerequisites:
- lab-3.2-lvm2-online-resize
- integrador-4.1-servidor-web-raid-luks-borg
---

# Trabajo Integrador 2: Docker Engine en LVM Espejado en Caliente + MySQL en LVM RAID 1 + WordPress + Backup Cifrado en AWS S3

Este laboratorio avanzado está diseñado para enseñar **almacenamiento empresarial en Linux**, **administración de Docker en producción**, **alta disponibilidad con LVM RAID 1**, **persistencia de bases de datos** y **políticas de respaldo seguro y cifrado en la nube de AWS**.

---

## 🏗️ Arquitectura del Laboratorio

```
                         +-----------------------------------------------+
                         |           Instancia AWS EC2 (Ubuntu)          |
                         |                                               |
  Internet ------------->|   Puerto 80: WordPress Container              |
                         |   Puerto 8080: Adminer Web UI                 |
                         |                                               |
                         |   Docker Engine (/var/lib/docker)             |
                         |      |                                        |
                         |      +--> LVM RAID 1 (vg_docker / lv_docker)  |
                         |             |-- Disco EBS 1 (1 GB)            |
                         |             +-- Disco EBS 2 (1 GB) [Espejo]   |
                         |                                               |
                         |   Base de Datos MySQL (/srv/mysql_data)       |
                         |      |                                        |
                         |      +--> LVM RAID 1 (vg_mysql / lv_mysql)    |
                         |             |-- Disco EBS 3 (1 GB)            |
                         |             +-- Disco EBS 4 (1 GB)            |
                         +-----------------------------------------------+
                                             |
                                 mysqldump + OpenSSL AES-256
                                             |
                                             v (IAM Instance Profile)
                         +-----------------------------------------------+
                         |            AWS S3 Bucket (Privado)            |
                         |        Cifrado del lado del servidor (SSE)    |
                         |       + Cifrado del lado del cliente          |
                         +-----------------------------------------------+
```

---

## 🎯 Objetivos de Aprendizaje

1. **Separación de Almacenamiento Crítico antes de Instalar Docker:** Aprender por qué `/var/lib/docker` jamás debe dejarse en la partición raíz `/` de un servidor de producción y cómo montarlo en un Logical Volume antes de instalar Docker.
2. **Conversión en Caliente a RAID 1 (Hot Mirror):** Transformar un volumen lineal LVM en un espejo RAID 1 en caliente con `lvconvert`, sin detener el servicio de contenedores ni un segundo.
3. **Almacenamiento Redundante para Bases de Datos:** Crear un volumen LVM RAID 1 nativo con dos discos dedicados para almacenar los datos persistentes de MySQL.
4. **Despliegue con Docker Compose:** Levantar un stack productivo de WordPress + MySQL 8.0 montando el volumen RAID 1 persistente.
5. **Simulación de Falla de Disco y Cero Downtime:** Simular la degradación del arreglo de discos y comprobar que las transacciones y lecturas de WordPress continúan intactas.
6. **Estrategia de Backup Cifrado Zero-Trust hacia AWS S3:** Generar volcados lógicos de la base de datos, cifrarlos con **OpenSSL AES-256-CBC**, y enviarlos de forma segura a un bucket S3 privado utilizando roles IAM de instancia (sin credenciales hardcodeadas).
7. **Simulación de Desastre y Restauración Completa:** Destruir intencionalmente la base de datos, descargar el backup cifrado desde S3, descifrarlo e inyectarlo en vivo para recuperar WordPress.

---

## 📋 Prerrequisitos

- Cuenta de AWS activa (capa gratuita / Free Tier).
- Herramienta **Terraform** instalada en tu sistema.
- AWS CLI configurado con tu perfil (por defecto `personal`).
- Cliente SSH o terminal de PowerShell / Linux / WSL.

---

## 🚀 Fase 1: Despliegue de la Infraestructura en AWS con Terraform

Todo el aprovisionamiento de la máquina virtual EC2 (`t2.micro`), los 4 discos EBS de 1 GB, el par de claves SSH, el Security Group y el bucket S3 privado con rol IAM se ejecuta automáticamente mediante Terraform.

Desde tu terminal de **PowerShell** en Windows:

```powershell
# 1. Ingresar al directorio de Terraform del laboratorio
cd linux/administrator/trabajo_integrador_docker/terraform

# 2. Inicializar los proveedores de Terraform
terraform init

# 3. Validar la sintaxis y ver el plan de despliegue
terraform validate
terraform plan

# 4. Desplegar los recursos en AWS
terraform apply -auto-approve
```

Al terminar, Terraform imprimirá los datos de conexión:
- **IP Pública:** `vm_docker_public_ip`
- **Comando SSH:** `ssh -i id_rsa_lab.pem ubuntu@<IP>`
- **Bucket S3:** `s3_backup_bucket`
- **URL Web WordPress:** `http://<IP>`
- **URL Adminer:** `http://<IP>:8080`

Conéctate por SSH al servidor:
```bash
ssh -i id_rsa_lab.pem ubuntu@<IP_PUBLICA>
```

> [!TIP]
> En Windows PowerShell, si SSH muestra un error de permisos sobre `id_rsa_lab.pem`, corrígelo con:
> ```powershell
> icacls.exe id_rsa_lab.pem /reset
> icacls.exe id_rsa_lab.pem /grant:r "$($env:USERNAME):(R)"
> icacls.exe id_rsa_lab.pem /inheritance:r
> ```

---

## 🔍 Fase 2: Inspección de Discos y Montaje de `/var/lib/docker` Antes de Instalar

> [!IMPORTANT]
> **¿Por qué hacerlo ANTES de instalar Docker?**
> Por defecto, Docker almacena imágenes, capas OverlayFS, volúmenes y contenedores en `/var/lib/docker`. Si instalas Docker primero, creará archivos dentro de la partición raíz `/`. Si luego montas un disco encima de esa carpeta, los archivos previos quedarán ocultos bajo el punto de montaje y el demonio fallará. Preparar y montar el disco **antes** garantiza que cada byte descargado por Docker vaya directamente al almacenamiento gestionado por LVM.

### 1. Inspeccionar los discos adjuntos
En instancias AWS Nitro / modernas de Ubuntu 24.04, los discos EBS aparecen como dispositivos NVMe (`/dev/nvme*n1`) o Xen (`/dev/xvd*`):

```bash
lsblk
```

Verás una salida similar a esta:
```text
NAME         MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
nvme0n1      259:0    0   10G  0 disk 
├─nvme0n1p1  259:1    0  9.9G  0 part /
├─nvme0n1p14 259:2    0    4M  0 part 
└─nvme0n1p15 259:3    0  106M  0 part /boot/efi
nvme1n1      259:4    0    1G  0 disk    <-- Disco A (Docker inicial)
nvme2n1      259:5    0    1G  0 disk    <-- Disco B (Docker hot mirror)
nvme3n1      259:6    0    1G  0 disk    <-- Disco C (MySQL pata 1)
nvme4n1      259:7    0    1G  0 disk    <-- Disco D (MySQL pata 2)
```

Para hacer el laboratorio agnóstico, definimos variables de shell con los nombres de tus 4 discos de 1 GB:

```bash
# Ajusta si en tu máquina se llaman /dev/xvdf o /dev/nvme1n1:
DISCO_DOCKER_A="/dev/nvme1n1"
DISCO_DOCKER_B="/dev/nvme2n1"
DISCO_MYSQL_A="/dev/nvme3n1"
DISCO_MYSQL_B="/dev/nvme4n1"

echo "Discos seleccionados:"
echo "Docker A: $DISCO_DOCKER_A | Docker B: $DISCO_DOCKER_B"
echo "MySQL A:  $DISCO_MYSQL_A  | MySQL B:  $DISCO_MYSQL_B"
```

### 2. Crear el Physical Volume y Volume Group para Docker
Usamos el **Disco A** como almacenamiento inicial:

```bash
# Inicializar disco como PV
sudo pvcreate $DISCO_DOCKER_A

# Crear el Volume Group 'vg_docker'
sudo vgcreate vg_docker $DISCO_DOCKER_A

# Verificar el VG
sudo vgs
```

### 3. Crear el Logical Volume y Formatearlo
Creamos el volumen lógico `lv_docker` usando el 100% del espacio libre de este disco:

```bash
# Crear el LV lineal de ~1 GB
sudo lvcreate -l 100%FREE -n lv_docker vg_docker

# Formatear con sistema de archivos ext4
sudo mkfs.ext4 -L DOCKER_ROOT /dev/vg_docker/lv_docker
```

### 4. Crear el Punto de Montaje y Persistir en `/etc/fstab`

```bash
# Crear la carpeta de Docker
sudo mkdir -p /var/lib/docker

# Obtener el UUID del volumen formateado
UUID_DOCKER=$(sudo blkid -s UUID -o value /dev/vg_docker/lv_docker)
echo "UUID de lv_docker: $UUID_DOCKER"

# Añadir la entrada persistente a /etc/fstab
echo "UUID=$UUID_DOCKER /var/lib/docker ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Montar todos los sistemas de archivos definidos en fstab
sudo mount -a

# Verificar que está montado
df -h /var/lib/docker
```

---

## 🐳 Fase 3: Instalación de Docker y Verificación del Almacenamiento

Ahora que `/var/lib/docker` es un sistema de archivos independiente montado sobre LVM, instalamos Docker Engine:

```bash
# Actualizar repositorios e instalar Docker + Docker Compose
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2

# Agregar el usuario actual (ubuntu) al grupo docker para no requerir sudo
sudo usermod -aG docker $USER
```

Para aplicar los permisos de grupo en tu sesión actual sin desconectarte:
```bash
newgrp docker
```

### Comprobación de Almacenamiento de Docker
Ejecuta el siguiente comando para verificar la raíz de almacenamiento:

```bash
docker info | grep "Docker Root Dir"
```

Salida esperada:
```text
 Docker Root Dir: /var/lib/docker
```

Probemos descargar una imagen de prueba y ver cómo los bloques se escriben en el volumen LVM:
```bash
# Descargar imagen ligera
docker pull alpine:latest

# Ver el espacio ocupado en nuestro volumen LVM
df -h /var/lib/docker
```

---

## 🔄 Fase 4: Conversión en Caliente de `/var/lib/docker` a RAID 1 (Espejo sin Downtime)

> [!NOTE]
> En este paso simularemos un requerimiento real de infraestructura: el servidor Docker ya está en producción con contenedores corriendo en un disco simple, y se requiere dotarlo de **alta disponibilidad física** añadiendo un segundo disco en espejo (RAID 1) **sin reiniciar el servidor ni detener el servicio Docker**.

### 1. Preparar el Segundo Disco (Disco B)
Inicializamos el segundo disco EBS de 1 GB y lo agregamos al grupo de volúmenes existente:

```bash
# Crear PV en el segundo disco
sudo pvcreate $DISCO_DOCKER_B

# Extender el VG vg_docker incorporando el nuevo disco
sudo vgextend vg_docker $DISCO_DOCKER_B

# Verificar que ahora vg_docker tiene 2 discos físicos
sudo pvs
```

### 2. Ejecutar la Conversión a RAID 1 en Caliente
Usamos la instrucción `lvconvert --type raid1 -m 1` para convertir el volumen lineal en un arreglo RAID 1 con 1 réplica (2 copias idénticas):

```bash
# Convertir a RAID 1 en vivo
sudo lvconvert --type raid1 -m 1 vg_docker/lv_docker
```

LVM creará automáticamente los subvolúmenes de metadata y de datos para el arreglo.

### 3. Monitorear la Sincronización en Tiempo Real
Observa cómo se sincronizan los datos entre ambos discos sin afectar el servicio:

```bash
sudo lvs -a -o +devices,copy_percent
```

Salida esperada:
```text
  LV                   VG        Attr       LSize   Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert Devices                         
  lv_docker            vg_docker rwi-a-r--- 1020.00m                                    100.00           lv_docker_rimage_0(0),lv_docker_rimage_1(0)
  [lv_docker_rimage_0] vg_docker iwi-aor--- 1020.00m                                                     /dev/nvme1n1(1)                    
  [lv_docker_rimage_1] vg_docker iwi-aor--- 1020.00m                                                     /dev/nvme2n1(1)                    
  [lv_docker_rmeta_0]  vg_docker ewi-aor---    4.00m                                                     /dev/nvme1n1(0)                    
  [lv_docker_rmeta_1]  vg_docker ewi-aor---    4.00m                                                     /dev/nvme2n1(0)                    
```

¡El directorio `/var/lib/docker` ahora está protegido contra fallas físicas de disco bajo un espejo LVM RAID 1!

---

## 🗄️ Fase 5: Almacenamiento Dedicado para MySQL en LVM RAID 1

Para la base de datos de producción, implementaremos una partición redundante dedicada montada en `/srv/mysql_data` utilizando los **Discos C y D**:

### 1. Inicializar los Discos de Base de Datos
```bash
# Crear PVs en Disco C y Disco D
sudo pvcreate $DISCO_MYSQL_A $DISCO_MYSQL_B

# Crear el Volume Group vg_mysql uniendo ambos discos
sudo vgcreate vg_mysql $DISCO_MYSQL_A $DISCO_MYSQL_B

# Inspeccionar el VG
sudo vgs vg_mysql
```

### 2. Crear Directamente un Logical Volume con RAID 1
En lugar de crearlo lineal y luego convertirlo, LVM permite crear volúmenes RAID 1 desde el inicio con el flag `--type raid1 -m 1`:

```bash
# Crear LV RAID 1 de 800 MB (dejando margen para la metadata del RAID)
sudo lvcreate --type raid1 -m 1 -L 800M -n lv_mysql vg_mysql

# Formatear el volumen RAID 1 con ext4
sudo mkfs.ext4 -L MYSQL_STORAGE /dev/vg_mysql/lv_mysql
```

### 3. Configurar el Punto de Montaje Persistente `/srv/mysql_data`

```bash
# Crear directorio de datos
sudo mkdir -p /srv/mysql_data

# Obtener UUID
UUID_MYSQL=$(sudo blkid -s UUID -o value /dev/vg_mysql/lv_mysql)
echo "UUID de lv_mysql: $UUID_MYSQL"

# Registrar en /etc/fstab
echo "UUID=$UUID_MYSQL /srv/mysql_data ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Montar y verificar
sudo mount -a
df -h /srv/mysql_data
```

---

## 🌐 Fase 6: Despliegue de WordPress + MySQL con Docker Compose

Crearemos un entorno completo de WordPress conectado a MySQL 8.0, donde los datos de la base de datos residen exclusivamente en `/srv/mysql_data` (el volumen RAID 1).

### 1. Crear el Directorio del Proyecto
```bash
sudo mkdir -p /opt/lab-app
sudo chown -R $USER:$USER /opt/lab-app
cd /opt/lab-app
```

### 2. Crear el Archivo `docker-compose.yml`

```bash
cat <<'EOF' > docker-compose.yml
services:
  db:
    image: mysql:8.0
    container_name: lab-mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword123
      MYSQL_DATABASE: wordpress_db
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppassword123
    volumes:
      - /srv/mysql_data:/var/lib/mysql
    networks:
      - app-net

  wordpress:
    image: wordpress:latest
    container_name: lab-wordpress
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
    volumes:
      - wp_html:/var/www/html
    networks:
      - app-net

  adminer:
    image: adminer:latest
    container_name: lab-adminer
    restart: always
    ports:
      - "8080:8080"
    networks:
      - app-net

volumes:
  wp_html:

networks:
  app-net:
    driver: bridge
EOF
```

### 3. Levantar los Contenedores
```bash
docker compose up -d
```

Verifica que los tres contenedores estén en estado `Up`:
```bash
docker compose ps
```

### 4. Verificar que MySQL está Escribiendo en el Disco RAID 1
Comprueba que los archivos de base de datos (`ibdata1`, esquemas, etc.) se están generando en `/srv/mysql_data`:
```bash
sudo ls -lh /srv/mysql_data
```

### 5. Configurar WordPress desde el Navegador
1. Abre tu navegador web e ingresa a: `http://<IP_PUBLICA>`
2. Selecciona idioma (Español), título del sitio (*"Sitio Web en Alta Disponibilidad LVM"*), usuario (*admin*), contraseña segura y correo.
3. Haz clic en **Instalar WordPress** e inicia sesión.
4. Crea una nueva entrada de blog:
   - **Título:** *"Prueba de Tolerancia a Fallos LVM RAID 1"*
   - **Contenido:** *"Esta publicación demuestra que la base de datos reside en un arreglo espejado en caliente."*
   - Haz clic en **Publicar**.

---

## 💥 Fase 7: Simulación de Fallo de Disco en MySQL y Cero Caída

Demostraremos qué ocurre cuando una de las patas del RAID 1 de MySQL falla físicamente.

### 1. Estado de Salud Inicial
```bash
sudo lvs -a -o +devices,health_status vg_mysql
```
Observarás que el atributo no reporta fallas y ambas patas (`rimage_0` y `rimage_1`) están activas.

### 2. Simular Falla del Disco C en Caliente
Podemos simular la pérdida del dispositivo bloqueando el acceso o marcando error en el dispositivo subyacente con `dmsetup`:

```bash
# Obtener el nombre del dispositivo de mapeo correspondiente a la pata 0
DM_PATA0=$(sudo dmsetup ls | grep "vg_mysql-lv_mysql_rimage_0" | awk '{print $1}')
echo "Dispositivo de pata 0: $DM_PATA0"

# Inyectar una tabla de error para simular fallo de I/O en ese disco:
sudo dmsetup suspend $DM_PATA0
sudo dmsetup load $DM_PATA0 --table "0 $(sudo blockdev --getsz /dev/mapper/$DM_PATA0) error"
sudo dmsetup resume $DM_PATA0
```

### 3. Verificar que WordPress Continúa Operando sin Caídas
1. Regresa al panel de WordPress en tu navegador.
2. Crea una **segunda entrada de blog**:
   - **Título:** *"Transacción Exitosa con Disco Dañado"*
   - **Contenido:** *"El disco primario está caído, pero el arreglo LVM redirigió las lecturas y escrituras al segundo disco sin que el usuario lo note."*
   - Publica la entrada.
3. Observa los logs de MySQL:
   ```bash
   docker logs --tail 20 lab-mysql
   ```
   ¡MySQL sigue respondiendo normalmente sin corrupción de transacciones!

### 4. Reparar el Arreglo RAID 1
```bash
# Restaurar la tabla del dispositivo
sudo lvchange --refresh vg_mysql/lv_mysql
sudo lvs -a -o +devices,health_status vg_mysql
```

---

## 🔐 Fase 8: Backup Cifrado de MySQL y Subida a AWS S3 (Zero-Trust)

Un principio cardinal de seguridad es el **Cifrado de Extremo a Extremo**: los respaldos deben cifrarse con algoritmos criptográficos robustos (AES-256) antes de abandonar el servidor hacia la nube.

Además, gracias al **IAM Instance Profile** configurado en Terraform, esta máquina virtual puede comunicarse con el bucket S3 de AWS sin almacenar claves de acceso (`AWS_ACCESS_KEY_ID`) en texto plano.

### 1. Obtener el Nombre del Bucket S3
El bucket generado por Terraform tiene un nombre único. Puedes consultarlo o leer la variable:

```bash
# Instalar AWS CLI si no está instalado
sudo apt-get install -y awscli

# Detectar el bucket asociado al laboratorio
BUCKET_S3=$(aws s3 ls | grep "lab-docker-backup" | awk '{print $3}')
echo "Bucket de Backup detectado: $BUCKET_S3"
```

### 2. Generar el Volcado Lógico de MySQL
Extraemos un dump consistente de la base de datos de WordPress desde el contenedor Docker:

```bash
mkdir -p /home/ubuntu/backups
cd /home/ubuntu/backups

# Exportar la base de datos completa
docker exec lab-mysql mysqldump -u root -prootpassword123 --single-transaction --routines --triggers wordpress_db > dump_wordpress.sql

# Verificar el tamaño y contenido legible del archivo SQL
ls -lh dump_wordpress.sql
head -n 20 dump_wordpress.sql
```

### 3. Cifrar el Dump con OpenSSL (AES-256-CBC + PBKDF2)
Cifraremos el archivo utilizando **AES de 256 bits** con clave derivada mediante PBKDF2 y salting:

```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_CIFRADO="backup_wordpress_${TIMESTAMP}.sql.enc"

# Cifrado simétrico (puedes definir una contraseña de clase, ej: ClaveSuperSegura2026!)
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
  -in dump_wordpress.sql \
  -out $BACKUP_CIFRADO \
  -pass pass:ClaveSuperSegura2026!

# Verificar que el archivo cifrado es completamente ininteligible
ls -lh $BACKUP_CIFRADO
head -c 80 $BACKUP_CIFRADO ; echo ""
```

### 4. Subir el Archivo Cifrado a AWS S3
```bash
# Subir al bucket privado
aws s3 cp $BACKUP_CIFRADO s3://$BUCKET_S3/backups/

# Listar el contenido del bucket en la nube
aws s3 ls s3://$BUCKET_S3/backups/
```

### 5. Eliminar el archivo SQL sin cifrar por seguridad
```bash
rm -f dump_wordpress.sql
```

---

## 🌪️ Fase 9: Simulación de Desastre y Restauración Completa desde S3

Demostraremos el proceso de recuperación ante desastres (*Disaster Recovery*): borraremos toda la base de datos de WordPress y la restauraremos a partir del backup cifrado alojado en S3.

### 1. Provocar el Desastre: Borrar la Base de Datos
```bash
# Eliminar la base de datos completa de WordPress
docker exec lab-mysql mysql -u root -prootpassword123 -e "DROP DATABASE wordpress_db;"
```

### 2. Comprobar la Caída del Sitio en el Navegador
Abre o refresca `http://<IP_PUBLICA>`:
- Verás el mensaje de error: **"Error establishing a database connection"** o la pantalla inicial de instalación invitando a reinstalar WordPress desde cero.
- Todo el sitio web y sus entradas han desaparecido.

### 3. Descargar el Backup Cifrado desde AWS S3
```bash
cd /home/ubuntu/backups

# Descargar la copia de seguridad desde el bucket S3
aws s3 cp s3://$BUCKET_S3/backups/$BACKUP_CIFRADO ./backup_descargado.sql.enc
```

### 4. Descifrar el Backup con OpenSSL
```bash
# Descifrar utilizando la misma contraseña y algoritmo
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
  -in ./backup_descargado.sql.enc \
  -out ./dump_restaurado.sql \
  -pass pass:ClaveSuperSegura2026!

# Verificar que el SQL ha sido recuperado
head -n 25 ./dump_restaurado.sql
```

### 5. Recrear la Base de Datos e Inyectar los Datos
```bash
# Recrear la base de datos vacía
docker exec lab-mysql mysql -u root -prootpassword123 -e "CREATE DATABASE wordpress_db;"

# Inyectar el dump descifrado en MySQL
docker exec -i lab-mysql mysql -u root -prootpassword123 wordpress_db < ./dump_restaurado.sql
```

### 6. Comprobación de Éxito
1. Refresca `http://<IP_PUBLICA>` en tu navegador.
2. Comprueba que **WordPress vuelve a estar 100% operativo**.
3. Todas las entradas de blog creadas antes de la catástrofe están intactas.
4. Limpia el archivo SQL descifrado temporal:
   ```bash
   rm -f ./dump_restaurado.sql ./backup_descargado.sql.enc
   ```

---

## 📈 Fase 10: Redimensionamiento en Caliente (Online Resize) de Sistemas de Archivos Montados

Uno de los problemas más comunes en producción es la saturación de espacio en disco. En la nube, **nunca se debe reiniciar un servidor** para ampliar el almacenamiento. A continuación, demostraremos cómo redimensionar sistemas de archivos ext4 en caliente mientras el sistema y los contenedores están en plena ejecución.

### Caso A: Ampliar el Almacenamiento de Docker (`/var/lib/docker`) en LVM
Si Docker se queda sin espacio para imágenes y capas, LVM permite extender el Logical Volume y el sistema de archivos subyacente sin detener el servicio:

```bash
# 1. Comprobar espacio actual
df -h /var/lib/docker

# 2. Extender el volumen lógico y el sistema de archivos en una sola operación atómica (-r)
# El flag -r (--resizefs) ejecuta internamente resize2fs en caliente
sudo lvextend -L +100M /dev/vg_docker/lv_docker -r 2>/dev/null || sudo lvextend -l +100%FREE /dev/vg_docker/lv_docker -r

# 3. Comprobar que el espacio disponible creció instantáneamente
df -h /var/lib/docker
```

### Caso B: Ampliar la Partición Raíz (`/`) de la Instancia EC2 sin Reiniciar
Cuando en la consola de AWS o mediante Terraform se amplía el disco EBS raíz (por ejemplo de 10 GB a 15 GB):
1. El disco físico (`/dev/nvme0n1`) refleja el nuevo tamaño en `lsblk`.
2. Sin embargo, la partición 1 (`nvme0n1p1`) y el sistema de archivos ext4 montado en `/` siguen con el tamaño antiguo.

Para extender la raíz en caliente sin reiniciar:

```bash
# 1. Verificar el paquete de utilidades de particionado en caliente
sudo apt-get install -y cloud-guest-utils

# 2. Extender la partición 1 dentro de la tabla de particiones GPT en caliente
# Sintaxis: growpart <dispositivo_padre> <numero_particion>
sudo growpart /dev/nvme0n1 1

# 3. Expandir el sistema de archivos ext4 montado en '/' en tiempo real
sudo resize2fs /dev/nvme0n1p1

# 4. Verificar que el sistema de archivos raíz creció con cero downtime
df -h /
```

---

## 🧹 Fase 11: Limpieza y Destrucción de Recursos

Para no generar costos en AWS, al finalizar la clase:

1. Vaciar el bucket S3 (AWS requiere que el bucket esté vacío para poder eliminarlo):
   ```bash
   aws s3 rm s3://$BUCKET_S3 --recursive
   ```
2. Cierra tu sesión SSH (`exit`).
3. Desde tu terminal de **PowerShell** en Windows:
   ```powershell
   cd linux/administrator/trabajo_integrador_docker/terraform
   terraform destroy -auto-approve
   ```

---

## 📚 Resumen Pedagógico de Comandos Clave

| Comando | Propósito |
| :--- | :--- |
| `pvcreate <disco>` | Inicializa un disco físico como Physical Volume de LVM |
| `vgcreate <vg> <discos>` | Agrupa uno o más discos en un Volume Group |
| `lvcreate -l 100%FREE -n <lv> <vg>` | Crea un volumen lógico lineal |
| `lvconvert --type raid1 -m 1 <vg>/<lv>` | Convierte en caliente un volumen lineal en RAID 1 (espejo) |
| `lvcreate --type raid1 -m 1 -L <size> -n <lv> <vg>` | Crea directamente un volumen lógico con RAID 1 |
| `lvs -a -o +devices,copy_percent` | Monitorea el progreso de sincronización del espejo en vivo |
| `openssl enc -aes-256-cbc -salt -pbkdf2` | Cifra un archivo con AES-256 y derivación segura de claves |
| `aws s3 cp <origen> s3://<bucket>/` | Sube un archivo a S3 usando el rol IAM de la instancia |
| `docker compose up -d` | Despliega los contenedores de WordPress y MySQL en segundo plano |
