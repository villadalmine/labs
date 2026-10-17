---
id: integrador-4.3-btrfs-subvolumes-reflinks-raid1
title: 'Trabajo Integrador 3: Almacenamiento Avanzado Btrfs (Subvolúmenes, Reflinks
  O(1), RAID 1 en Vivo y Scrub)'
difficulty_level: 4
difficulty_label: 'Nivel 4: Proyectos Integradores en la Nube (AWS Free Tier con Terraform)'
section: '4.3'
sections:
- '4.3'
- '4'
category: cloud-iac
tags:
- cloud-iac
- storage
- btrfs
- cow
- copy-on-write
- subvolumes
- reflinks
- raid1
- rebalance
- scrub
- replace
- zstd
- aws
- ec2
- terraform
tools:
- terraform
- btrfs
- cp
- mkfs.btrfs
- dd
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
  notes: Despliegue multi-VM en AWS con Terraform (2 EC2 t3.micro, 4 discos EBS, script
    demo_integrador_btrfs.sh, conversión a RAID 1 y auto-curación con scrub).
environments:
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Proyecto integrador de almacenamiento empresarial de última generación
  con el sistema de archivos Btrfs en AWS. Enseña a estructurar subvolúmenes jerárquicos
  independientes (@app, @data, @snapshots) con compresión transparente ZSTD, clonar
  archivos instantáneamente en tiempo O(1) con 0 consumo extra vía Reflinks, convertir
  un disco simple a RAID 1 en vivo mediante btrfs balance, auto-reparar bloques corruptos
  con btrfs scrub y reemplazar discos defectuosos en caliente.
files:
  guide: trabajo_integrador_btrfs/trabajo_integrador_btrfs.md
  script: trabajo_integrador_btrfs/demo_integrador_btrfs.sh
  terraform: trabajo_integrador_btrfs/terraform
resource_type: cloud_project
has_guide: true
has_interactive_script: true
has_terraform: true
execution_mode: terraform_apply
prerequisites:
- lab-3.1-anatomia-filesystems
- integrador-4.1-servidor-web-raid-luks-borg
---

# Trabajo Integrador 4: Almacenamiento Avanzado con Btrfs (Subvolúmenes, Reflinks Zero-Copy, Conversión en Vivo a RAID 1, Scrub y Replicación Remota)

Este laboratorio avanzado de nivel profesional explora las capacidades de **Btrfs (B-tree File System)**, el sistema de archivos Copy-on-Write nativo del kernel Linux. Aprenderás a gestionar **subvolúmenes independientes**, aprovechar **Reflinks (clonación instantánea con deduplicación de punteros a nivel de bloque)**, configurar **compresión transparente ZSTD**, convertir en caliente un disco simple a **RAID 1 mediante rebalanceo en vivo**, recuperar errores de corrupción silenciosa con **Scrub**, y reemplazar discos dañados sin desconectar el sistema con **`btrfs replace`**.

---

## 🏗️ Arquitectura de la Solución

```
   +-------------------------------------------------------------+
   |             VM 1: SERVIDOR PRIMARIO BTRFS                   |
   |              (vm-btrfs-primary-prod)                        |
   |                                                             |
   |   Filesystem Btrfs Multi-Dispositivo (RAID 1 en caliente)   |
   |     |-- Disco 1 (nvme1n1 - 1 GB)                            |
   |     |-- Disco 2 (nvme2n1 - 1 GB) [Añadido con btrfs device] |
   |     +-- Disco 3 (nvme3n1 - 1 GB) [Reemplazo en caliente]    |
   |                                                             |
   |   Subvolúmenes Jerárquicos:                                 |
   |     * @app       -> /opt/app       (Código y microservicios)|
   |     * @data      -> /var/lib/data  (Compresión ZSTD:3)      |
   |     * @snapshots -> /.snapshots    (Instantáneas RO)        |
   |                                                             |
   |   Reflinks: cp --reflink=always (Clones Zero-Copy)          |
   |   Detección y Reparación: btrfs scrub                       |
   +-------------------------------------------------------------+
                                  |
                                  |  btrfs send | ssh btrfs receive
                                  v
   +-------------------------------------------------------------+
   |             VM 2: SERVIDOR DE RÉPLICA DR                    |
   |              (vm-btrfs-replica-dr)                          |
   |                                                             |
   |   Filesystem Btrfs Destino:                                 |
   |     +-- Disco 1 (nvme1n1 - 1 GB)                            |
   |     +-- Subvolumen Replicado: /mnt/backup/@data_snap        |
   +-------------------------------------------------------------+
```

---

## 🧠 Fundamentos Teóricos de Btrfs

### 1. ¿Qué es un Subvolumen en Btrfs?
Un **subvolumen** NO es una partición de disco de tamaño fijo ni un volumen LVM.
* Es un sistema de archivos virtual con su propio árbol de inodos y raíz independiente dentro del mismo pool de almacenamiento.
* **Espacio Compartido Dinámico:** Si el pool tiene 50 GB libres, todos los subvolúmenes ven 50 GB disponibles. No hay peligro de que una partición fija quede chica mientras a otra le sobra espacio.
* **Opciones de Montaje Independientes:** Puedes montar `@data` con compresión `compress=zstd:3` y montar `@app` con `noexec` o `nodatacow` según convenga.

### 2. Reflinks (Clonación Zero-Copy a nivel de archivo)
En ext4, copiar un archivo de 1 GB (`cp origen destino`) duplica 1 GB de bloques en el disco y tarda tiempo en I/O.
En **Btrfs**, gracias al flag `--reflink=always`:
```bash
cp --reflink=always database.db database_clon.db
```
* Btrfs crea una nueva entrada en el árbol de metadatos apuntando **a los mismos extents físicos existentes**.
* El clon se crea en **1 milisegundo**, consume **0 bytes adicionales** de disco físico, y si luego modificas el archivo clonado, el mecanismo Copy-on-Write (CoW) solo escribe bloques nuevos para las diferencias (deltas).

### 3. Gestión Multi-Dispositivo Nativa sin LVM ni mdadm
Btrfs gestiona discos directamente en el kernel:
* **`btrfs device add`:** Añade discos físicos en caliente a un sistema de archivos montado.
* **`btrfs balance`:** Redistribuye los chunks (*chunks* de datos y metadatos) en vivo y puede convertir perfiles de asignación (por ejemplo, de `single` a `raid1` de datos y metadatos) sin detener ningún proceso.
* **`btrfs replace`:** Reemplaza un disco físico dañado leyendo bloques sanos del mirror y escribiéndolos en el nuevo disco sin degradar el arreglo.

---

## 🚀 Fase 1: Despliegue de Infraestructura en AWS con Terraform

El laboratorio crea 2 instancias EC2 `t3.micro` en `eu-west-1`:
- **VM Primaria:** Con 3 discos EBS de 1 GB.
- **VM Réplica:** Con 1 disco EBS de 1 GB.

Desde tu terminal de **PowerShell** en Windows:

```powershell
cd linux/administrator/trabajo_integrador_btrfs/terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

Conéctate por SSH a ambas máquinas con los comandos impresos por Terraform:
```bash
ssh -i id_rsa_lab.pem ubuntu@<IP_PRIMARIA>
ssh -i id_rsa_lab.pem ubuntu@<IP_REPLICA>
```

---

## 🛠️ Fase 2: Formateo con Btrfs y Creación de Subvolúmenes

En la **VM Primaria**, instalamos las herramientas de Btrfs e inspeccionamos los discos:

```bash
# 1. Instalar utilidades btrfs-progs
sudo apt-get update
sudo apt-get install -y btrfs-progs

# 2. Inspeccionar discos
lsblk
```
Verás `/dev/nvme1n1`, `/dev/nvme2n1` y `/dev/nvme3n1` de 1 GB cada uno.

### 3. Crear el Filesystem Btrfs en el Disco 1
```bash
# Formatear el primer disco con etiqueta BTRFS_PROD
sudo mkfs.btrfs -L BTRFS_PROD /dev/nvme1n1

# Montar temporalmente el filesystem raíz para crear los subvolúmenes
sudo mkdir -p /mnt/btrfs_root
sudo mount /dev/nvme1n1 /mnt/btrfs_root
```

### 4. Crear los Subvolúmenes Jerárquicos
```bash
# Crear subvolúmenes para aplicación, datos persistentes y snapshots
sudo btrfs subvolume create /mnt/btrfs_root/@app
sudo btrfs subvolume create /mnt/btrfs_root/@data
sudo btrfs subvolume create /mnt/btrfs_root/@snapshots

# Listar subvolúmenes con sus IDs
sudo btrfs subvolume list /mnt/btrfs_root
```

Desmontamos la raíz de Btrfs:
```bash
sudo umount /mnt/btrfs_root
```

---

## 🗜️ Fase 3: Montaje con Compresión Transparente ZSTD

Montaremos los subvolúmenes en sus rutas finales utilizando **compresión ZSTD nivel 3**, que ofrece una tasa de compresión superior a GZIP con velocidades de descompresión cercanas a la memoria RAM.

```bash
# Crear directorios de destino
sudo mkdir -p /srv/microservicio /var/lib/app_data /.snapshots

# Obtener UUID del filesystem Btrfs
UUID_BTRFS=$(sudo blkid -s UUID -o value /dev/nvme1n1)

# Montar subvolumen @app
sudo mount -o subvol=@app,compress=zstd:3,noatime UUID=$UUID_BTRFS /srv/microservicio

# Montar subvolumen @data
sudo mount -o subvol=@data,compress=zstd:3,noatime UUID=$UUID_BTRFS /var/lib/app_data

# Montar subvolumen @snapshots
sudo mount -o subvol=@snapshots,noatime UUID=$UUID_BTRFS /.snapshots

# Verificar montajes y opciones activas
df -h /srv/microservicio /var/lib/app_data /.snapshots
mount | grep btrfs
```

---

## 🧬 Fase 4: Reflinks y Deduplicación Zero-Copy

Demostraremos el poder de los **Reflinks**: crear clones idénticos de archivos sin consumir espacio en disco ni tiempo de transferencia.

### 1. Crear un Archivo de Datos de Prueba
```bash
cd /var/lib/app_data

# Generar un archivo de texto/log repetitivo de 100 MB
sudo bash -c 'for i in $(seq 1 100000); do echo "REGISTRO-TRANSACCION-LINEA-$i-DATOS-CRITICOS-SISTEMA-PRODUCCION"; done > transacciones_maestras.db'

# Ver tamaño real y espacio libre en disco
ls -lh transacciones_maestras.db
sudo btrfs filesystem df /var/lib/app_data
```

### 2. Clonar el Archivo con `--reflink=always`
```bash
# Clonar instantáneamente sin duplicar bloques
sudo cp --reflink=always transacciones_maestras.db clone_testing.db

# Verificar que ambos archivos reportan el mismo tamaño lógico:
ls -lh
```

### 3. Comprobar que los Bloques Físicos son Compartidos
```bash
# Inspeccionar que el espacio libre del filesystem NO disminuyó ni un solo byte:
sudo btrfs filesystem df /var/lib/app_data

# Comprobar inodos y extents compartidos con filefrag:
sudo filefrag -v transacciones_maestras.db | head -n 8
sudo filefrag -v clone_testing.db | head -n 8
```
¡Ambos archivos apuntan a los mismos extents físicos de almacenamiento! Si modificas `clone_testing.db`, Btrfs solo escribirá los nuevos bloques modificados gracias a Copy-on-Write.

---

## 🔄 Fase 5: Conversión en Caliente de Single a RAID 1 con Rebalance

El filesystem inició con 1 solo disco (`nvme1n1`) en modo `single`. Ahora añadiremos el segundo disco (`nvme2n1`) y convertiremos tanto los datos como los metadatos a **RAID 1 (espejo redundante)** en vivo, mientras los archivos están abiertos y en uso.

### 1. Añadir el Segundo Disco al Filesystem
```bash
# Agregar /dev/nvme2n1 al filesystem Btrfs montado
sudo btrfs device add /dev/nvme2n1 /var/lib/app_data

# Verificar dispositivos del filesystem
sudo btrfs filesystem show /var/lib/app_data
```

Verás que el filesystem ahora tiene 2 dispositivos, pero los chunks existentes aún están en modo `single`.

### 2. Ejecutar la Conversión a RAID 1 con `btrfs balance`
El comando `btrfs balance` redistribuye los bloques existentes creando copias réplica en el segundo disco:

```bash
# Convertir chunks de datos (-dconvert=raid1) y chunks de metadatos (-mconvert=raid1)
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /var/lib/app_data

# Monitorear o comprobar estado del balanceo
sudo btrfs balance status /var/lib/app_data
```

### 3. Verificar la Nueva Topología RAID 1
```bash
sudo btrfs filesystem df /var/lib/app_data
```

Salida esperada:
```text
Data, RAID1: total=1.00GiB, used=...
System, RAID1: total=32.00MiB, used=...
Metadata, RAID1: total=256.00MiB, used=...
GlobalReserve, single: total=16.00MiB, used=0.00B
```

¡Tanto los datos como los metadatos ahora están protegidos en un arreglo RAID 1 nativo sin haber desmontado el sistema!

---

## 📡 Fase 6: Replicación Remota de Subvolúmenes con `btrfs send | ssh btrfs receive`

Btrfs permite exportar subvolúmenes de solo-lectura como flujos de bytes atómicos y recibirlos en otro servidor remoto.

### 1. Preparar la VM Réplica
En la terminal de la **VM Réplica**:
```bash
sudo apt-get update && sudo apt-get install -y btrfs-progs
sudo mkfs.btrfs -L BTRFS_BACKUP /dev/nvme1n1
sudo mkdir -p /mnt/dr_vault
sudo mount /dev/nvme1n1 /mnt/dr_vault
```

Configura la clave SSH pública de root de la máquina primaria en `/root/.ssh/authorized_keys` de la réplica (igual que en los laboratorios anteriores).

### 2. Generar un Snapshot de Solo-Lectura en la VM Primaria
`btrfs send` requiere obligatoriamente que el subvolumen sea de solo lectura (`-r`):

```bash
# Tomar snapshot RO del subvolumen @data
sudo btrfs subvolume snapshot -r /var/lib/app_data /.snapshots/data_snap_base

# Listar snapshots
sudo btrfs subvolume list /.snapshots
```

### 3. Enviar el Subvolumen por SSH
```bash
IP_REPLICA="<IP_PRIVADA_REPLICA>"

# Tubería de replicación remota
sudo btrfs send /.snapshots/data_snap_base | \
  ssh -o StrictHostKeyChecking=no root@$IP_REPLICA btrfs receive /mnt/dr_vault/
```

En la **VM Réplica**, comprueba que el subvolumen y todos sus archivos llegaron íntegros:
```bash
sudo ls -lh /mnt/dr_vault/data_snap_base
```

### 4. Demostrar Envío Incremental con Padre (`-p`)
En la **VM Primaria**:
```bash
# Modificar un archivo
sudo bash -c 'echo "NUEVA TRANSACCION BANCARIA #55201" >> /var/lib/app_data/transacciones_maestras.db'

# Tomar segundo snapshot RO
sudo btrfs subvolume snapshot -r /var/lib/app_data /.snapshots/data_snap_delta1

# Enviar ÚNICAMENTE la diferencia indicando el snapshot padre (-p)
sudo btrfs send -p /.snapshots/data_snap_base /.snapshots/data_snap_delta1 | \
  ssh root@$IP_REPLICA btrfs receive /mnt/dr_vault/
```

---

## 💥 Fase 7: Corrupción Inducida, Detección con `btrfs scrub` y Auto-Curación

Demostraremos cómo Btrfs detecta corrupción silenciosa de datos y cómo repara los bloques usando el espejo RAID 1.

### 1. Inyectar Basura en el Disco 2 con `dd`
```bash
# Dañar bloques en el disco 2 (/dev/nvme2n1)
sudo dd if=/dev/urandom of=/dev/nvme2n1 bs=1M count=1 seek=20 conv=notrunc status=none
```

### 2. Ejecutar `btrfs scrub`
Btrfs lee todos los datos y metadatos verificando sus checksums SHA256/xxhash contra la copia espejo:

```bash
# Iniciar el scrub en segundo plano
sudo btrfs scrub start /var/lib/app_data

# Consultar el estado y resultados del scrub
sudo btrfs scrub status /var/lib/app_data
```

Salida esperada:
```text
scrub status for ...
	scrub started at ... and finished after ...
	total to scrub: ...
	rate: ...
	corrected: 12 (auto-repaired from healthy mirror)
	uncorrectable: 0
	unverified: 0
```
¡Btrfs detectó los sectores dañados y los reparó automáticamente a partir del disco 1!

---

## 🔀 Fase 8: Reemplazo en Caliente de Disco Dañado (`btrfs replace`)

Si un disco físico falla permanentemente, Btrfs permite sustituirlo en caliente con un comando atómico: `btrfs replace`. Usaremos el **Disco 3** (`/dev/nvme3n1`):

```bash
# Ver el ID numérico de los dispositivos
sudo btrfs filesystem show /var/lib/app_data

# Reemplazar el disco 2 (/dev/nvme2n1) por el disco 3 (/dev/nvme3n1) en caliente
# Sintaxis: btrfs replace start <dispositivo_viejo> <dispositivo_nuevo> <punto_montaje>
sudo btrfs replace start /dev/nvme2n1 /dev/nvme3n1 /var/lib/app_data

# Monitorear el progreso de sustitución
sudo btrfs replace status /var/lib/app_data
```

Una vez completado al 100%, Btrfs desvincula `/dev/nvme2n1` y transfiere toda la réplica al nuevo disco sin desmontar ni reiniciar el servidor.

---

## 🧹 Fase 9: Destrucción de la Infraestructura

Para no generar costos en tu cuenta de AWS:

```powershell
cd linux/administrator/trabajo_integrador_btrfs/terraform
terraform destroy -auto-approve
```
