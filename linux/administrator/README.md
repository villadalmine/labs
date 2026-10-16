# Laboratorios de Administración de Linux

Repositorio de prácticas de laboratorio, guías paso a paso y scripts interactivos para clases de Administración de Servidores Linux.

---

## Estructura de Módulos

```text
linux/administrator/
├── nice/                          # Prioridad y consumo de CPU con nice, renice y CFS
│   ├── nice.md                    # Guía conceptual con pesos CFS y afinidad taskset
│   ├── demo_nice.sh               # Script interactivo paso a paso para la clase
│   └── cpu_worker.c               # Proceso en C para pruebas de carga y señales
│
├── storage/                       # Gestión de almacenamiento con LVM2 y Loop Devices
│   ├── lab_storage.md             # Guía de laboratorio de LVM y extensión en caliente
│   ├── demo_lab_storage.sh        # Script interactivo de LVM y resize2fs online
│   ├── lab_storage.sh             # Script automatizado tradicional
│   ├── lab_storage_paso_a_paso.md
│   └── lab_storage_simple.md
│
├── luks/                          # Cifrado de dispositivos de bloques (dm-crypt)
│   ├── luks.md                    # Guía de LUKS con loop device y partición real
│   └── demo_luks.sh               # Script interactivo con demostración forense
│
├── gocryptfs/                     # Cifrado FUSE a nivel de directorios
│   └── gocryptfs.md               # Guía práctica de gocryptfs
│
├── borg/                          # Copias de seguridad, deduplicación y retención
│   ├── borg.md                    # Guía básica de BorgBackup y montaje FUSE
│   ├── borg-con-systemd-timers.md # Automatización segura con systemd timers
│   └── demo_borg.sh               # Script interactivo con deduplicación y desastre
│
├── procesos/                      # Gestión de procesos, jobs y señales
│   ├── jobs-fg-bg-nohup-setsid.md # Control de trabajos y terminales
│   └── proceso_zombie.md          # Diagnóstico y ciclo de vida de procesos zombies
│
├── systemd/                       # Automatización moderna y control de recursos
│   ├── systemd-cgroups.md         # Límites de CPU y memoria con cgroups v2
│   ├── systemd-memlogger.md       # Monitores periódicos con oneshot y timers
│   └── systemd-scoket.md          # Activación por socket bajo demanda
│
├── trabajo_integrador/            # PROYECTO FINAL 1: Web + LVM/mdadm + LUKS + Borg
│   ├── trabajo_integrador.md      # Guía completa paso a paso para dar en clase
│   └── terraform/                 # IaC: 2 EC2 Ubuntu + 3 discos EBS en AWS Free Tier
│       ├── main.tf
│       ├── variables.tf
│       ├── providers.tf
│       ├── outputs.tf
│       └── README.md
│
├── trabajo_integrador_docker/     # PROYECTO FINAL 2: Docker LVM + MySQL RAID 1 + S3
│   ├── trabajo_integrador_docker.md # Guía paso a paso: Hot-Mirror, WordPress y S3
│   ├── demo_integrador_docker.sh  # Script interactivo completo y comprobado en AWS
│   └── terraform/                 # IaC: 1 EC2 Ubuntu + 4 discos EBS + S3 + IAM
│       ├── main.tf
│       ├── variables.tf
│       ├── providers.tf
│       ├── outputs.tf
│       └── README.md
│
├── trabajo_integrador_zfs/        # PROYECTO FINAL 3: ZFS HA Activo-Pasivo + AWS ALB
│   ├── trabajo_integrador_zfs.md  # Guía paso a paso: Pools, Hot Mirror, Failover y Scrub
│   ├── demo_integrador_zfs.sh     # Script interactivo completo de ZFS
│   └── terraform/                 # IaC: 2 EC2 Ubuntu + 3 discos EBS + ALB + Sonda
│       ├── main.tf
│       ├── variables.tf
│       ├── providers.tf
│       ├── outputs.tf
│       └── README.md
│
└── trabajo_integrador_btrfs/      # PROYECTO FINAL 4: Btrfs Avanzado (Reflinks, RAID1 y Replace)
    ├── trabajo_integrador_btrfs.md # Guía: Subvolúmenes, Reflinks, Balance RAID1 y Scrub
    ├── demo_integrador_btrfs.sh   # Script interactivo completo de Btrfs
    └── terraform/                 # IaC: 2 EC2 Ubuntu + 4 discos EBS (Hot Replace)
        ├── main.tf
        ├── variables.tf
        ├── providers.tf
        ├── outputs.tf
        └── README.md
```

---

## Cómo usar los scripts interactivos en clase

Cada módulo temático cuenta con un script interactivo (`demo_*.sh`) diseñado específicamente para proyectar en el aula o compartir pantalla:
1. **Pausa manual con `[ENTER]`:** Permite al docente dar la explicación teórica a su ritmo antes de ejecutar cada comando.
2. **Soporte para `tmux`:** Activa automáticamente el scroll con la rueda del ratón (`mouse on`).
3. **Modo automático (`--auto <segundos>`):** Avanza de forma autónoma con pausas temporizadas si se prefiere.
4. **Limpieza garantizada (`trap`):** Al finalizar o presionar `Ctrl+C`, desmonta y limpia todos los recursos temporales.

---

## Trabajos Integradores en la Nube (AWS)

1. **[Trabajo Integrador 1: Servidor Web Nginx, LVM vs mdadm RAID 1, LUKS, gocryptfs y Borg Remote Backup](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador/trabajo_integrador.md)**
   - Despliegue con Terraform de dos instancias EC2 Ubuntu en VPC propia con 3 discos EBS de 1 GB.
   - Demostración de degradación y reconstrucción de arreglos de almacenamiento.
   - Cifrado híbrido en capas (bloque y filesystem).
   - Respaldo remoto automatizado por SSH hacia una segunda máquina con BorgBackup y timers de systemd.

2. **[Trabajo Integrador 2: Docker Engine en LVM Espejado en Caliente + MySQL en LVM RAID 1 + WordPress + Backup Cifrado en AWS S3](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_docker/trabajo_integrador_docker.md)**
   - Despliegue con Terraform de una instancia EC2 Ubuntu con 4 discos EBS de 1 GB, bucket S3 cifrado y rol IAM.
   - Montaje de `/var/lib/docker` en un volumen LVM antes de instalar Docker.
   - Conversión en caliente (*hot-mirror*) del volumen de Docker a RAID 1 sin reiniciar el demonio.
   - Partición dedicada en LVM RAID 1 para base de datos MySQL 8.0 montada en `/srv/mysql_data`.
   - Despliegue de WordPress con Docker Compose persistiendo en el arreglo RAID 1.
   - Falla inducida de disco con cero tiempo de inactividad (*zero downtime*).
   - Backup de base de datos cifrado con OpenSSL (AES-256) subido a AWS S3 y prueba de *Disaster Recovery*.
   - Redimensionamiento en caliente (*online resize*) de `/var/lib/docker` y del rootfs (`/`) con `growpart` + `resize2fs`.

3. **[Trabajo Integrador 3: Alta Disponibilidad con ZFS Replicación Remota Activo-Pasivo y AWS Application Load Balancer](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_zfs/trabajo_integrador_zfs.md)**
   - Despliegue con Terraform de 2 instancias EC2 Ubuntu en zonas de disponibilidad separadas + 3 discos EBS + AWS ALB.
   - Creación de zpools nativos y datasets con compresión LZ4 transparente.
   - Conversión a espejo (Mirror) en caliente con `zpool attach` en vivo sin desmontar.
   - Replicación remota de snapshots incrementales por SSH con `zfs send | ssh zfs receive`.
   - Balanceo de carga HTTP gobernado por sonda de salud en `/health` (200 OK en activo, 503 en standby).
   - Simulación de colapso del nodo activo y conmutación automática (*failover*) con promoción de dataset.
   - Inyección de corrupción de bloques con `dd`, diagnóstico con `zpool scrub` y auto-curación (*self-healing*).

4. **[Trabajo Integrador 4: Almacenamiento Avanzado con Btrfs (Subvolúmenes, Reflinks Zero-Copy, Conversión en Vivo a RAID 1, Scrub y Reemplazo de Discos)](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_btrfs/trabajo_integrador_btrfs.md)**
   - Despliegue con Terraform de 2 instancias EC2 Ubuntu + 4 discos EBS dedicados.
   - Creación de subvolúmenes jerárquicos independientes (`@app`, `@data`, `@snapshots`) sobre espacio dinámico compartido.
   - Montaje avanzado con compresión transparente ZSTD nivel 3.
   - Demostración de Reflinks (`cp --reflink=always`) logrando clonación instantánea de archivos en $O(1)$ con 0 bytes de sobrecarga física.
   - Conversión en caliente de disco simple a RAID 1 en vivo mediante `btrfs device add` y `btrfs balance`.
   - Replicación remota de subvolúmenes con `btrfs send | ssh btrfs receive`.
   - Simulación de corrupción con `dd`, detección con `btrfs scrub` y auto-reparación.
   - Reemplazo en caliente de un disco físico dañado mediante `btrfs replace` sin degradar el servicio.
