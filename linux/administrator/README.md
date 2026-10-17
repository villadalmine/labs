# Plan de Carrera: Administración de Servidores Linux

Este repositorio contiene el plan de estudios progresivo, laboratorios prácticos, guías paso a paso y scripts interactivos para clases de **Administración de Sistemas Linux, Almacenamiento Empresarial y Alta Disponibilidad en la Nube**.

El contenido está estructurado pedagógicamente en **4 niveles consecutivos (de menor a mayor complejidad)**, agrupando las temáticas relacionadas para que cada concepto sirva de base al siguiente.

---

## 🗺️ Mapa Curricular (De Menor a Mayor Complejidad)

```
[NIVEL 1: PROCESOS & CPU]
  1.1 Control de Trabajos y Señales (fg, bg, nohup, setsid)
  1.2 Ciclo de Vida y Procesos Zombies
  1.3 Prioridades de CPU (nice, renice, CFS, taskset)
           │
           ▼
[NIVEL 2: SYSTEMD & CGROUPS]
  2.1 Automatización con Systemd Timers (memlogger)
  2.2 Activación por Sockets bajo demanda (socket-activation)
  2.3 Gobernanza de Recursos con Cgroups v2 (CPU/Memory Limits)
           │
           ▼
[NIVEL 3: STORAGE, CIFRADO & BACKUP TRADICIONAL]
  3.1 LVM2 y Redimensionamiento en Caliente (Online Resize)
  3.2 Cifrado de Bloques con LUKS (dm-crypt)
  3.3 Cifrado de Filesystem FUSE con gocryptfs
  3.4 Respaldos Deduplicados con BorgBackup
           │
           ▼
[NIVEL 4: PROYECTOS INTEGRADORES EN LA NUBE (AWS)]
  4.1 Integrador 1: Web Nginx, RAID 1 (LVM vs mdadm), LUKS y Borg Remoto
  4.2 Integrador 2: Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y AWS S3
  4.3 Integrador 3: Btrfs Avanzado (Subvolúmenes, Reflinks Zero-Copy, RAID 1 en Vivo y Scrub)
  4.4 Integrador 4: ZFS HA Activo-Pasivo, Replicación Remota, AWS ALB Failover y Self-Healing
```

---

## 🟢 Nivel 1: Procesos, Señales y Planificación de CPU
*Fundamentos del sistema operativo: cómo interactúan los programas con el kernel, las terminales y los núcleos de CPU.*

| Módulo | Guía Teórica | Script de Clase / Código | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **1. Control de Trabajos y Terminales** | [`procesos/jobs-fg-bg-nohup-setsid.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/procesos/jobs-fg-bg-nohup-setsid.md) | Terminal interactiva | `Ctrl+Z`, `bg`, `fg`, `jobs`, `nohup`, `setsid`, desvinculación de TTY, señales `SIGHUP` y `SIGKILL`. |
| **2. Ciclo de Vida y Procesos Zombies** | [`procesos/proceso_zombie.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/procesos/proceso_zombie.md) | Demostración en bash | Llamadas `fork()`, `wait()`, estados `Z` (defunct), eliminación del padre e init adoption / reaping. |
| **3. Planificación de CPU y Scheduler** | [`nice/nice.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/nice/nice.md) | [`demo_nice.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/nice/demo_nice.sh) <br> [`cpu_worker.c`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/nice/cpu_worker.c) | Prioridad `nice` (-20 a 19), `renice`, planificador CFS (Completely Fair Scheduler), pesos de tiempo de CPU y afinidad con `taskset`. |

---

## 🟡 Nivel 2: Automatización Moderna y Control de Recursos (Systemd)
*El estándar moderno de inicio, supervisión y límites duros de recursos en Linux.*

| Módulo | Guía Teórica | Unidad de Demostración | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **4. Servicios Periódicos y Timers** | [`systemd/systemd-memlogger.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/systemd/systemd-memlogger.md) | `memlogger.service` <br> `memlogger.timer` | Reemplazo moderno de `cron`, unidades `Type=oneshot`, directivas `OnCalendar` y precisión con `AccuracySec`. |
| **5. Activación por Sockets** | [`systemd/systemd-scoket.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/systemd/systemd-scoket.md) | `echo.socket` <br> `echo@.service` | Socket activation bajo demanda, escucha pasiva del kernel, arranque instantáneo al recibir tráfico de red. |
| **6. Límites con Cgroups v2** | [`systemd/systemd-cgroups.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/systemd/systemd-cgroups.md) | `systemd-run` | Control de contención: `CPUQuota`, `MemoryMax`, `MemoryHigh` y prevención de caídas generales de servidor. |

---

## 🟠 Nivel 3: Almacenamiento Tradicional, Cifrado y Respaldos
*Gestión de discos físicos y lógicos, protección de datos en reposo y políticas de copias de seguridad.*

| Módulo | Guía Teórica | Script de Clase | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **7. LVM2 y Online Resize** | [`storage/lab_storage.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/storage/lab_storage.md) | [`demo_lab_storage.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/storage/demo_lab_storage.sh) | Dispositivos loop, Physical Volumes (PV), Volume Groups (VG), Logical Volumes (LV), y redimensionamiento en caliente (`lvextend -r`, `resize2fs`, `growpart`). |
| **8. Cifrado de Bloques (LUKS)** | [`luks/luks.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/luks/luks.md) | [`demo_luks.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/luks/demo_luks.sh) | `cryptsetup`, cifrado dm-crypt a nivel de sectores, mapeo en `/dev/mapper/`, inspección forense con `strings` y protección contra robo físico. |
| **9. Cifrado FUSE (gocryptfs)** | [`gocryptfs/gocryptfs.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/gocryptfs/gocryptfs.md) | Guía práctica | Cifrado en espacio de usuario a nivel de archivos/directorios. Comparativa directa vs LUKS (ventajas en nubes y backup granular). |
| **10. Respaldos y Deduplicación** | [`borg/borg.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/borg/borg.md) <br> [`borg/borg-con-systemd-timers.md`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/borg/borg-con-systemd-timers.md) | [`demo_borg.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/borg/demo_borg.sh) | BorgBackup: inicialización cifrada (repokey), deduplicación por chunking, montaje FUSE (`borg mount`), retención (`prune`) y timers automáticos. |

---

## 🔴 Nivel 4: Proyectos Integradores en la Nube (AWS Free Tier)
*Aplicación de todos los conocimientos previos en escenarios productivos reales desplegados con Terraform.*

```
   [Integrador 1: Storage Clásico]   --> LVM RAID 1 / mdadm + LUKS + Borg por SSH
                  │
   [Integrador 2: Contenedores]      --> Docker aislado en LVM Hot-Mirror + MySQL + S3
                  │
   [Integrador 3: Filesystem CoW]    --> Btrfs Subvolúmenes + Reflinks O(1) + Rebalance
                  │
   [Integrador 4: Enterprise HA]     --> ZFS Replicación Remota + AWS ALB Failover
```

### 1. [Trabajo Integrador 1: Servidor Web Nginx, LVM vs mdadm RAID 1, LUKS y Borg Remoto](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador/trabajo_integrador.md)
* **Infraestructura:** 2 EC2 Ubuntu `t3.micro` en AWS + 3 discos EBS de 1 GB.
* **Qué enseña:**
  - Creación de RAID 1 con LVM y comparación directa con `mdadm`.
  - Servidor Nginx resiliente a la destrucción física de un disco del arreglo.
  - Cifrado en capas (LUKS en el bloque de datos + gocryptfs en carpetas críticas).
  - Respaldo automatizado por SSH hacia una segunda máquina de backup con BorgBackup y timers de systemd.

### 2. [Trabajo Integrador 2: Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y AWS S3](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_docker/trabajo_integrador_docker.md)
* **Infraestructura:** 1 EC2 Ubuntu `t3.micro` + 4 discos EBS de 1 GB + Bucket S3 Cifrado + Rol IAM.
* **Qué enseña:**
  - Montaje obligatorio de `/var/lib/docker` en un volumen LVM dedicado **antes** de instalar Docker para proteger la raíz `/`.
  - Conversión en caliente (*hot-mirror*) del almacenamiento de Docker a RAID 1 sin apagar el demonio.
  - Almacenamiento redundante para MySQL 8.0 en `/srv/mysql_data` y despliegue de WordPress con Docker Compose.
  - Simulación de falla física de disco sin pérdida de transacciones (*zero downtime*).
  - Backup lógico consistente, cifrado simétrico con OpenSSL (AES-256) y subida a AWS S3 mediante IAM Instance Profile (sin claves estáticas).
  - Redimensionamiento en caliente (*online resize*) de `/var/lib/docker` y del rootfs (`/`) con `growpart` y `resize2fs`.
* **Script de Demostración:** [`demo_integrador_docker.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_docker/demo_integrador_docker.sh) (probado en AWS y con modo loop local).

### 3. [Trabajo Integrador 3: Almacenamiento Avanzado con Btrfs (Subvolúmenes, Reflinks Zero-Copy, RAID 1 en Vivo y Scrub)](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_btrfs/trabajo_integrador_btrfs.md)
* **Infraestructura:** 2 EC2 Ubuntu `t3.micro` + 4 discos EBS de 1 GB.
* **Qué enseña:**
  - Superación de los límites de LVM + ext4 mediante sistemas Copy-on-Write (CoW).
  - Subvolúmenes jerárquicos independientes (`@app`, `@data`, `@snapshots`) compartiendo espacio dinámico común.
  - Montaje avanzado con compresión transparente ZSTD nivel 3.
  - Reflinks (`cp --reflink=always`): clonación instantánea de archivos en tiempo $O(1)$ con **0 bytes de consumo extra**.
  - Conversión en caliente de disco simple a RAID 1 con `btrfs device add` y rebalanceo en vivo (`btrfs balance`).
  - Replicación remota de subvolúmenes con `btrfs send | ssh btrfs receive`.
  - Inyección de sectores dañados con `dd`, diagnóstico y auto-curación con `btrfs scrub`.
  - Reemplazo en caliente de discos averiados con `btrfs replace`.
* **Script de Demostración:** [`demo_integrador_btrfs.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_btrfs/demo_integrador_btrfs.sh).

### 4. [Trabajo Integrador 4: Alta Disponibilidad con ZFS Replicación Remota Activo-Pasivo y AWS Application Load Balancer](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_zfs/trabajo_integrador_zfs.md)
* **Infraestructura:** 2 EC2 Ubuntu `t3.micro` en AZs distintas + 3 discos EBS + AWS Application Load Balancer (ALB).
* **Qué enseña:**
  - Arquitectura empresarial ZFS on Linux: zpools, VDEVs y datasets con compresión LZ4.
  - Conversión a espejo en caliente (`zpool attach`) sin reiniciar ni desmontar.
  - Replicación periódica de snapshots incrementales por SSH (`zfs send -i | ssh zfs receive -F`).
  - Balanceo de carga HTTP gobernado por sonda de salud en `/health` (200 OK en activo, 503 en standby).
  - Simulación de caída del nodo primario y procedimiento de conmutación por error (*Failover*) con promoción de dataset en segundos.
  - Inyección de corrupción de bloques con `dd`, verificación con `zpool scrub` y demostración de auto-curación (*self-healing*).
* **Script de Demostración:** [`demo_integrador_zfs.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/trabajo_integrador_zfs/demo_integrador_zfs.sh).

---

## 🛠️ Cómo utilizar los Scripts Educativos en Clase

Todos los scripts interactivos (`demo_*.sh`) disponen de:
1. **Pausa manual con `[ENTER]`:** Para explicar la teoría antes de que el comando se ejecute.
2. **Soporte `tmux`:** Activa automáticamente el scroll del ratón (`mouse on`).
3. **Modo automático (`--auto <segundos>`):** Para corridas automáticas temporizadas.
4. **Modo Dual (Local o AWS):**
   - **En local / WSL2:** Sin parámetros, crean automáticamente discos virtuales loop de 1 GB.
   - **En AWS:** Pasando los dispositivos EBS reales como argumentos (`/dev/nvme1n1...`).
5. **Limpieza garantizada (`trap`):** Al finalizar o presionar `Ctrl+C`, desmontan y limpian todo.
