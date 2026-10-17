# Plan de Carrera: Administración de Servidores Linux

Este es el **índice principal y plan de estudios progresivo** del repositorio. Contiene los laboratorios prácticos, guías paso a paso y scripts interactivos de **Administración de Sistemas Linux, Almacenamiento Empresarial, Observabilidad y Alta Disponibilidad en la Nube**.

El contenido está estrictamente organizado de **menor a mayor complejidad pedagógica (Nivel 0 al Nivel 4)**: desde entender cómo se compila un binario y cómo el kernel gestiona los procesos, hasta levantar clusters de alta disponibilidad tolerantes a desastres en **AWS** con **Terraform**.

Todos los recursos disponen de **enlaces locales directos** (para navegar en tu editor o repositorio clonado) y **enlaces directos a GitHub** (para lectura web).

---

## 🗺️ Mapa Curricular (Ordenado por Complejidad Ascendente)

```
[NIVEL 0: FUNDAMENTOS & COMPILACIÓN DE SOFTWARE]
  0.1 Del Código Fuente al Binario: gcc, Makefiles e Instalación en el Sistema
           │
           ▼
[NIVEL 1: PROCESOS, SEÑALES, TERMINALES & DIAGNÓSTICO EN VIVO]
  1.1 Control de Trabajos y Multiplexores (fg, bg, nohup, setsid, tmux, screen, zellij)
  1.2 Ciclo de Vida y Procesos Zombies (fork, wait, SIGCHLD, init adoption)
  1.3 Planificación de CPU, Prioridades y Afinidad (nice, renice, CFS, taskset)
  1.4 Diagnóstico Forense de Rendimiento en Tiempo Real (uptime, vmstat, iostat, sar, dstat)
           │
           ▼
[NIVEL 2: SUPERVISIÓN & GOBERNANZA MODERNA (SYSTEMD)]
  2.1 Tareas Periódicas con Systemd Timers (memlogger)
  2.2 Activación de Servicios por Sockets bajo demanda (socket-activation)
  2.3 Gobernanza de Recursos con Cgroups v2 (Límites duros de CPUQuota y MemoryMax)
           │
           ▼
[NIVEL 3: STORAGE, FILESYSTEMS, CIFRADO, BACKUPS & MONITOREO]
  3.1 Anatomía de Filesystems y Diagnóstico Forense (ext4, XFS, Btrfs, tmpfs, tune2fs, inodos agotados)
  3.2 Almacenamiento Lógico LVM2 y Redimensionamiento en Caliente (PV, VG, LV, Online Resize)
  3.3 Cifrado de Bloques con LUKS (dm-crypt, llaves de descifrado e inspección forense)
  3.4 Cifrado FUSE a Nivel de Archivos con gocryptfs
  3.5 Respaldos Deduplicados y Cifrados con BorgBackup y Timers
  3.6 Monitoreo Continuo y Métricas en Producción (Node Exporter, Textfile, LVM Mirror, Tráfico y Backups)
           │
           ▼
[NIVEL 4: PROYECTOS INTEGRADORES EN LA NUBE (AWS & TERRAFORM)]
  4.1 Integrador 1: Servidor Web Nginx, RAID 1 (LVM vs mdadm), LUKS y Borg Remoto por SSH
  4.2 Integrador 2: Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y AWS S3 Cifrado
  4.3 Integrador 3: Almacenamiento Avanzado Btrfs (Subvolúmenes, Reflinks O(1), RAID 1 y Scrub)
  4.4 Integrador 4: ZFS Enterprise HA Activo-Pasivo, Replicación Remota y AWS ALB Failover
```

---

## 🧠 Catálogo Estructurado de Metadatos y Consultas para RAG / IA

Todas las guías y laboratorios del repositorio incorporan **metadatos formales estandarizados** mediante **YAML Frontmatter** en cada archivo `.md` y un registro consolidado en [`catalog.json`](catalog.json) validado por [`metadata.schema.json`](metadata.schema.json).

Esta estructura está diseñada para alimentar motores de **Retrieval-Augmented Generation (RAG)**, bases vectoriales (Chroma, Pinecone, Qdrant) y agentes de IA autónomos, permitiendo responder con cero alucinación preguntas como: *"¿Qué laboratorios de nivel 3 fueron probados en WSL2 con Ubuntu 24.04 y pasaron exitosamente?"*.

### 🔍 Capacidades del Sistema de Metadatos:
- **Ambientes de Prueba Registrados:** Registro de ejecuciones en `WSL2`, `AWS EC2`, con detalle de kernel y tipo de instancia.
- **Veredicto y Estado:** Estados `PASSED` (probado y aprobado de punta a punta con scripts), `VERIFIED` (validado por arquitectura en AWS), `FAILED` o `PENDING`.
- **Sistemas Operativos Validados:** Ej: `Ubuntu 24.04 LTS`, `Debian 12`.
- **Taxonomía Completa (Tags & Tools):** Etiquetas curriculares y listado exacto de comandos evaluados (`tune2fs`, `node_exporter`, `lvextend`, `borg`, `taskset`).
- **Resumen Semántico Denso (`rag_summary`):** Párrafos de alta densidad de información para embeddings vectoriales.
- **Especificación Completa:** Consultá la guía de arquitectura en [`METADATA_SPEC.md`](METADATA_SPEC.md).

### ⚡ Consultas Rápidas desde Terminal:
Podés consultar el catálogo interactivamente utilizando el script [`query_catalog.py`](query_catalog.py) (o su wrapper [`query_catalog.sh`](query_catalog.sh)):

```bash
# Listar todos los laboratorios con su estado y ambiente probado
python query_catalog.py --list

# Filtrar por etiqueta temática (ej: storage, lvm, prometheus, btrfs)
python query_catalog.py --tag storage

# Filtrar por ambiente y estado de validación
python query_catalog.py --env WSL2 --status PASSED

# Filtrar por sistema operativo
python query_catalog.py --os "Ubuntu 24.04 LTS"

# Exportar contexto enriquecido formateado para inyectar en el prompt de un LLM / RAG
python query_catalog.py --rag-context --tag monitoring

# Re-sincronizar el catálogo tras editar o añadir nuevas guías Markdown
python query_catalog.py --sync
```

### 🤖 Ecosistema de Tutor de IA, RAG y Protocolos de Agentes (Centralizado en `ai/tutor/`):
Todo el entorno de estudio inteligente (interfaces web, agentes de terminal, extensiones de editor y protocolos) se encuentra unificado en la carpeta raíz [`ai/tutor/`](../../ai/tutor/README.md):
- **Guía Maestra Paso a Paso:** Seguí [`ai/tutor/GUIA_PASO_A_PASO.md`](../../ai/tutor/GUIA_PASO_A_PASO.md) para levantar **Open WebUI** (RAG local en CPU), **Goose CLI** (agente autónomo en terminal) y **Continue.dev / Cline** en VS Code, con Ollama local o OpenRouter.
- **Motor de Decisiones Pedagógicas (`ai/tutor/tutor_engine.py`):** Diseñado para protocolos de agentes (`jdev`, MCP o Tool-Calling), evalúa el perfil del estudiante, resuelve el siguiente laboratorio compatible y valida prerequisitos:
  ```bash
  # Recomendación pedagógica del siguiente lab según entorno y labs ya cursados
  python ../../ai/tutor/tutor_engine.py recommend --env WSL2 --os "Ubuntu 24.04 LTS" --completed lab-0.1-compilar

  # Validación de prerequisitos antes de ejecutar
  python ../../ai/tutor/tutor_engine.py verify --id lab-3.2-lvm2-online-resize --env WSL2 --root
  ```
- **Servidor MCP Nativo:** [`ai/tutor/mcp/labs_mcp_server.py`](../../ai/tutor/mcp/labs_mcp_server.py) expone las herramientas del catálogo para cualquier cliente compatible.

### 🛠️ Herramienta ABM de Metadatos de Laboratorios (`manage_catalog.py`):
Facilita la adición, edición o remoción de campos en lote sobre todos los archivos `.md`, creación de nuevos labs y validación estricta del esquema:
  ```bash
  # Extender un nuevo atributo a todos los laboratorios
  python manage_catalog.py add-field --field "target_audience" --default "junior-sysadmin"

  # Eliminar un atributo obsoleto en todo el repositorio
  python manage_catalog.py remove-field --field "target_audience"

  # Crear la plantilla de un nuevo laboratorio con frontmatter validado
  python manage_catalog.py new-lab --id lab-1.5-system-calls --title "Llamadas al Sistema con strace" --category processes --section 1.5

  # Validar integridad contra metadata.schema.json
  python manage_catalog.py validate
  ```

---

## 🟢 Nivel 0: Fundamentos y Compilación de Software
*Comprender qué ocurre antes de que un servicio exista en el sistema: código fuente, llamadas al sistema, compilación y enlaces de bibliotecas.*

| Módulo | Guía Teórica (Local / GitHub) | Recursos Prácticos | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **0. Compilación e Instalación** | [`compilar.md`](compilar.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/compilar.md) | `holamundo.c` <br> `Makefile` | Ciclo de compilación con `gcc`, optimizaciones (`-O2`), Makefiles (`all`, `install`, `clean`, `uninstall`), variables de prefijo (`/usr/local/bin`) y permisos Unix. |

---

## 🟢 Nivel 1: Procesos, Señales, Terminales y Diagnóstico del Kernel
*Fundamentos del sistema operativo: cómo interactúan los programas con el procesador, las terminales y los núcleos de CPU.*

| Módulo | Guía Teórica (Local / GitHub) | Script de Clase / Demostración | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **1. Control de Trabajos y Multiplexores** | [`procesos/jobs-fg-bg-nohup-setsid.md`](procesos/jobs-fg-bg-nohup-setsid.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/procesos/jobs-fg-bg-nohup-setsid.md) | Terminal interactiva | `&`, `jobs`, `fg`, `bg`, `nohup`, `setsid`, señales `SIGHUP` y `SIGKILL`. Uso de multiplexores (`tmux`, `screen`, `zellij`), zoom de paneles (`Ctrl+b z`), división de cuadrículas y tamaño de fuentes en **Apache Guacamole**. |
| **2. Ciclo de Vida y Procesos Zombies** | [`procesos/proceso_zombie.md`](procesos/proceso_zombie.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/procesos/proceso_zombie.md) | Demostración en bash | Llamadas `fork()`, `wait()`, estados `Z` (defunct), señal `SIGCHLD`, adopción por `init/systemd` y liberación de la tabla de procesos. |
| **3. Planificación de CPU y Scheduler** | [`nice/nice.md`](nice/nice.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/nice/nice.md) | [`demo_nice.sh`](nice/demo_nice.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/nice/demo_nice.sh)) <br> [`cpu_worker.c`](nice/cpu_worker.c) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/nice/cpu_worker.c)) | Prioridad `nice` (-20 a 19), `renice` en caliente, planificador CFS (Completely Fair Scheduler), pesos matemáticos en el kernel y afinidad con `taskset`. |
| **4. Diagnóstico en Vivo y Estadísticas** | [`tools-stats.md`](tools-stats.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/tools-stats.md) <br> [`uptime.md`](uptime.md) · [GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/uptime.md) | Consola de diagnóstico | Métricas puntuales con `uptime` (carga 1, 5, 15 min), `vmstat` (espera de I/O `wa`, swap `si`/`so`), `iostat` (latencia y `await`), `sar`, `dstat`, `top` y `htop`. |

---

## 🟡 Nivel 2: Supervisión y Gobernanza Moderna (Systemd & Cgroups)
*El estándar de la industria para inicio de servicios, tareas programadas y gobernanza dura de memoria y CPU.*

| Módulo | Guía Teórica (Local / GitHub) | Unidad de Demostración | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **5. Servicios Periódicos y Timers** | [`systemd/systemd-memlogger.md`](systemd/systemd-memlogger.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/systemd/systemd-memlogger.md) | `memlogger.service` <br> `memlogger.timer` | Reemplazo moderno de `cron`, unidades `Type=oneshot`, directivas `OnCalendar` y precisión temporal con `AccuracySec`. |
| **6. Activación por Sockets** | [`systemd/systemd-scoket.md`](systemd/systemd-scoket.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/systemd/systemd-scoket.md) | `echo.socket` <br> `echo@.service` | Socket activation bajo demanda, escucha pasiva del kernel, arranque instantáneo al recibir tráfico de red sin memoria ociosa. |
| **7. Límites con Cgroups v2** | [`systemd/systemd-cgroups.md`](systemd/systemd-cgroups.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/systemd/systemd-cgroups.md) | `systemd-run` | Control de contención: `CPUQuota`, `MemoryMax`, `MemoryHigh` y prevención de caídas generales de servidor por saturación. |

---

## 🟠 Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo
*Gestión de discos físicos y lógicos, estructura matemática del almacenamiento, seguridad criptográfica y observabilidad continua.*

| Módulo | Guía Teórica (Local / GitHub) | Script de Clase (Local / GitHub) | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **8. Anatomía de Filesystems y Diagnóstico Forense** | [`filesystems/anatomia_filesystems.md`](filesystems/anatomia_filesystems.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/anatomia_filesystems.md) | [`demo_filesystems.sh`](filesystems/demo_filesystems.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/demo_filesystems.sh) | Capa VFS, Superbloques y copias de respaldo, inodos vs bloques, `tune2fs`, `dumpe2fs`, `xfs_info`, `xfs_growfs`, crisis de **inodos agotados con 90% libre** (`df -i`), rescate de superbloque con `e2fsck -b`, Btrfs CoW y tmpfs en RAM. |
| **9. LVM2 y Online Resize** | [`storage/lab_storage.md`](storage/lab_storage.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/storage/lab_storage.md) | [`demo_lab_storage.sh`](storage/demo_lab_storage.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/storage/demo_lab_storage.sh) | Dispositivos loop, Physical Volumes (PV), Volume Groups (VG), Logical Volumes (LV), y redimensionamiento en caliente (`lvextend -r`, `resize2fs`, `growpart`). |
| **10. Cifrado de Bloques (LUKS)** | [`luks/luks.md`](luks/luks.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/luks/luks.md) | [`demo_luks.sh`](luks/demo_luks.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/luks/demo_luks.sh) | `cryptsetup`, cifrado dm-crypt a nivel de sectores, mapeo en `/dev/mapper/`, inspección forense con `strings` y protección contra robo físico. |
| **11. Cifrado FUSE (gocryptfs)** | [`gocryptfs/gocryptfs.md`](gocryptfs/gocryptfs.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/gocryptfs/gocryptfs.md) | Guía práctica | Cifrado en espacio de usuario a nivel de archivos/directorios. Comparativa directa vs LUKS (ventajas en nubes y backup granular). |
| **12. Respaldos y Deduplicación** | [`borg/borg.md`](borg/borg.md) · [GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/borg/borg.md) <br> [`borg-con-systemd-timers.md`](borg/borg-con-systemd-timers.md) · [GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/borg/borg-con-systemd-timers.md) | [`demo_borg.sh`](borg/demo_borg.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/borg/demo_borg.sh) | BorgBackup: inicialización cifrada (repokey), deduplicación por chunking, montaje FUSE (`borg mount`), retención (`prune`) y timers automáticos. |
| **13. Monitoreo Continuo y Métricas en Producción** | [`monitoreo/monitoreo_metricas.md`](monitoreo/monitoreo_metricas.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/monitoreo_metricas.md) | [`demo_monitoreo.sh`](monitoreo/demo_monitoreo.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/demo_monitoreo.sh) | Diagnóstico puntual vs Monitoreo continuo, modelo PULL vs PUSH, Node Exporter, Textfile Collector, salud de mirrors RAID 1, peticiones HTTP, sesiones SSH y métricas de backup. |

---

## 🔴 Nivel 4: Proyectos Integradores en la Nube (AWS Free Tier con Terraform)
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

### 1. [Trabajo Integrador 1: Servidor Web Nginx, LVM vs mdadm RAID 1, LUKS y Borg Remoto](trabajo_integrador/trabajo_integrador.md) · [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador/trabajo_integrador.md)
* **Infraestructura:** 2 EC2 Ubuntu `t3.micro` en AWS + 3 discos EBS de 1 GB.
* **Archivos:** [`trabajo_integrador.md`](trabajo_integrador/trabajo_integrador.md) | [Directorio Terraform](trabajo_integrador/terraform/)
* **Qué enseña:**
  - Creación de RAID 1 con LVM y comparación directa con `mdadm`.
  - Servidor Nginx resiliente a la destrucción física de un disco del arreglo.
  - Cifrado en capas (LUKS en el bloque de datos + gocryptfs en carpetas críticas).
  - Respaldo automatizado por SSH hacia una segunda máquina de backup con BorgBackup y timers de systemd.

### 2. [Trabajo Integrador 2: Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y AWS S3](trabajo_integrador_docker/trabajo_integrador_docker.md) · [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador_docker/trabajo_integrador_docker.md)
* **Infraestructura:** 1 EC2 Ubuntu `t3.micro` + 4 discos EBS de 1 GB + Bucket S3 Cifrado + Rol IAM.
* **Archivos:** [`trabajo_integrador_docker.md`](trabajo_integrador_docker/trabajo_integrador_docker.md) | [`demo_integrador_docker.sh`](trabajo_integrador_docker/demo_integrador_docker.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador_docker/demo_integrador_docker.sh)) | [Directorio Terraform](trabajo_integrador_docker/terraform/)
* **Qué enseña:**
  - Montaje obligatorio de `/var/lib/docker` en un volumen LVM dedicado **antes** de instalar Docker para proteger la raíz `/`.
  - Conversión en caliente (*hot-mirror*) del almacenamiento de Docker a RAID 1 sin apagar el demonio.
  - Almacenamiento redundante para MySQL 8.0 en `/srv/mysql_data` y despliegue de WordPress con Docker Compose.
  - Simulación de falla física de disco sin pérdida de transacciones (*zero downtime*).
  - Backup lógico consistente, cifrado simétrico con OpenSSL (AES-256) y subida a AWS S3 mediante IAM Instance Profile (sin claves estáticas).
  - Redimensionamiento en caliente (*online resize*) de `/var/lib/docker` y del rootfs (`/`) con `growpart` y `resize2fs`.

### 3. [Trabajo Integrador 3: Almacenamiento Avanzado con Btrfs (Subvolúmenes, Reflinks Zero-Copy, RAID 1 en Vivo y Scrub)](trabajo_integrador_btrfs/trabajo_integrador_btrfs.md) · [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador_btrfs/trabajo_integrador_btrfs.md)
* **Infraestructura:** 2 EC2 Ubuntu `t3.micro` + 4 discos EBS de 1 GB.
* **Archivos:** [`trabajo_integrador_btrfs.md`](trabajo_integrador_btrfs/trabajo_integrador_btrfs.md) | [`demo_integrador_btrfs.sh`](trabajo_integrador_btrfs/demo_integrador_btrfs.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador_btrfs/demo_integrador_btrfs.sh)) | [Directorio Terraform](trabajo_integrador_btrfs/terraform/)
* **Qué enseña:**
  - Superación de los límites de LVM + ext4 mediante sistemas Copy-on-Write (CoW).
  - Subvolúmenes jerárquicos independientes (`@app`, `@data`, `@snapshots`) compartiendo espacio dinámico común.
  - Montaje avanzado con compresión transparente ZSTD nivel 3.
  - Reflinks (`cp --reflink=always`): clonación instantánea de archivos en tiempo $O(1)$ con **0 bytes de consumo extra**.
  - Conversión en caliente de disco simple a RAID 1 con `btrfs device add` y rebalanceo en vivo (`btrfs balance`).
  - Replicación remota de subvolúmenes con `btrfs send | ssh btrfs receive`.
  - Inyección de sectores dañados con `dd`, diagnóstico y auto-curación con `btrfs scrub`.
  - Reemplazo en caliente de discos averiados con `btrfs replace`.

### 4. [Trabajo Integrador 4: Alta Disponibilidad con ZFS Replicación Remota Activo-Pasivo y AWS Application Load Balancer](trabajo_integrador_zfs/trabajo_integrador_zfs.md) · [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador_zfs/trabajo_integrador_zfs.md)
* **Infraestructura:** 2 EC2 Ubuntu `t3.micro` en AZs distintas + 3 discos EBS + AWS Application Load Balancer (ALB).
* **Archivos:** [`trabajo_integrador_zfs.md`](trabajo_integrador_zfs/trabajo_integrador_zfs.md) | [`demo_integrador_zfs.sh`](trabajo_integrador_zfs/demo_integrador_zfs.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/trabajo_integrador_zfs/demo_integrador_zfs.sh)) | [Directorio Terraform](trabajo_integrador_zfs/terraform/)
* **Qué enseña:**
  - Arquitectura empresarial ZFS on Linux: zpools, VDEVs y datasets con compresión LZ4.
  - Conversión a espejo en caliente (`zpool attach`) sin reiniciar ni desmontar.
  - Replicación periódica de snapshots incrementales por SSH (`zfs send -i | ssh zfs receive -F`).
  - Balanceo de carga HTTP gobernado por sonda de salud en `/health` (200 OK en activo, 503 en standby).
  - Simulación de caída del nodo primario y procedimiento de conmutación por error (*Failover*) con promoción de dataset en segundos.
  - Inyección de corrupción de bloques con `dd`, verificación con `zpool scrub` y demostración de auto-curación (*self-healing*).

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
