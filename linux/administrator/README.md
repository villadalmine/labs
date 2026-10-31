# Plan de Carrera: Administración de Servidores Linux

Este es el **índice principal y plan de estudios progresivo** del repositorio. Contiene los laboratorios prácticos, guías paso a paso y scripts interactivos de **Administración de Sistemas Linux, Almacenamiento Empresarial, Observabilidad y Alta Disponibilidad en la Nube**.

El contenido está estrictamente organizado de **menor a mayor complejidad pedagógica (Nivel 0 al Nivel 4)**: desde entender cómo se compila un binario y cómo el kernel gestiona los procesos, hasta levantar clusters de alta disponibilidad tolerantes a desastres en **AWS** con **Terraform**.

Todos los recursos disponen de **enlaces locales directos** (para navegar en tu editor o repositorio clonado) y **enlaces directos a GitHub** (para lectura web).

---

## 📖 Glosario Técnico y Base de Conocimientos
Dispones de un [**Glosario Técnico de Almacenamiento y Resiliencia**](GLOSARIO.md) con el análisis conceptual detallado, analogías didácticas y comparativas tecnológicas de mecanismos clave:
- [**Write-Intent Bitmap**](GLOSARIO.md#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura) (`mdadm`, `_rmeta`, ZFS, Btrfs)
- [**Write-Hole (Agujero de Escritura)**](GLOSARIO.md#write-hole-agujero-de-escritura)
- [**Copy-on-Write (CoW)**](GLOSARIO.md#copy-on-write-cow-copia-en-escritura)
- [**Dirty Time Logs (DTL) / TXG**](GLOSARIO.md#dirty-time-logs-dtl--transaction-groups-txg)
- [**ZIL & SLOG**](GLOSARIO.md#zil-zfs-intent-log--slog-separate-intent-log)
- [**Hot Spare**](GLOSARIO.md#hot-spare-disco-de-reserva-en-caliente)
- [**Scrubbing y Resilvering**](GLOSARIO.md#scrubbing-y-resilvering)

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
  1.5 Detección, Inventario y Auditoría Forense de Hardware (lspci, lsusb, lshw, hwinfo, dmidecode, lscpu)
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
  3.5 Estrategias y Arquitecturas de Respaldo: Full, Incremental, Diferencial y CDP (tar, rsync, rdiff-backup, duplicity, dd, LVM Snapshots y BorgBackup)
  3.6 Arquitecturas de Monitoreo y Observabilidad: Paradigmas (Pull vs Push), 4 Pilares, Métricas y Resiliencia en Producción (Prometheus, Node Exporter, Grafana y Alertmanager)
  3.7 RAID desde Cero: Teoría, Niveles, Metadatos, Caché y Comparativa (mdadm vs LVM vs Btrfs vs ZFS)
  3.8 RAID con mdadm: Creación, Superbloques 1.2, Bitmaps, Hot Spares y Degradación
  3.9 RAID con LVM (dm-raid): Sub-LVs _rmeta/_rimage, Online Resize y lvconvert --repair
  3.10 RAID con Btrfs: Perfiles Data/Metadata, Self-Healing por Checksum, Scrub y btrfs replace
  3.11 RAID con OpenZFS: Pools, RAIDZ sin Write-Hole, ARC/SLOG, Self-Healing y Resilvering
  3.12 Estructura de Enlaces en Filesystems: Hard Links, Symlinks y Búsqueda Forense con find
  3.13 Diagnóstico, Mantenimiento y Reparación de Volúmenes (df, du, tune2fs, fsck, e2fsck, dumpe2fs, XFS, Btrfs, badblocks)
  3.14 Métricas de Disco, Filesystems e Inodos (Node Exporter, Textfile Collector y Grafana)
  3.15 Gestión y Disparo de Alertas con Alertmanager (Terminal Local, sin Email/Slack externos)
  3.16 Taller Integrador: Servidor Web sobre LVM RAID 1, Node Exporter, Falla en Vivo y TUI
           │
           ▼
[NIVEL 4: PROYECTOS INTEGRADORES EN LA NUBE (AWS & TERRAFORM)]
  4.1 Integrador 1: Servidor Web Nginx, RAID 1 (LVM vs mdadm), LUKS y Borg Remoto por SSH
  4.2 Integrador 2: Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y AWS S3 Cifrado
  4.3 Integrador 3: Almacenamiento Avanzado Btrfs (Subvolúmenes, Reflinks O(1), RAID 1 y Scrub)
  4.4 Integrador 4: ZFS Enterprise HA Activo-Pasivo, Replicación Remota y AWS ALB Failover
  4.5 Integrador 5: Alta Disponibilidad RAID en AWS, Inyección de Fallas, Recuperación y Métricas Prometheus
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
| **2. Ciclo de Vida y Procesos Zombies** | [`procesos/proceso_zombie.md`](procesos/proceso_zombie.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/procesos/proceso_zombie.md) | [`demo_zombie.sh`](procesos/demo_zombie.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/procesos/demo_zombie.sh)) <br> [`zombie_maker.c`](procesos/zombie_maker.c) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/procesos/zombie_maker.c)) | Llamadas `fork()`, `wait()`, estados `Z` (defunct), señal `SIGCHLD`, subreapers (`PR_SET_CHILD_SUBREAPER`), mito de `kill -9`, adopción por `init/systemd` y liberación de la tabla de procesos. |
| **3. Planificación de CPU y Scheduler** | [`nice/nice.md`](nice/nice.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/nice/nice.md) | [`demo_nice.sh`](nice/demo_nice.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/nice/demo_nice.sh)) <br> [`cpu_worker.c`](nice/cpu_worker.c) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/nice/cpu_worker.c)) | Prioridad `nice` (-20 a 19), `renice` en caliente, planificador CFS (Completely Fair Scheduler), pesos matemáticos en el kernel y afinidad con `taskset`. |
| **4. Diagnóstico en Vivo y Estadísticas** | [`tools-stats.md`](tools-stats.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/tools-stats.md) <br> [`uptime.md`](uptime.md) · [GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/uptime.md) | Consola de diagnóstico | Métricas puntuales con `uptime` (carga 1, 5, 15 min), `vmstat` (espera de I/O `wa`, swap `si`/`so`), `iostat` (latencia y `await`), `sar`, `dstat`, `top` y `htop`. |
| **5. Detección, Inventario y Auditoría de Hardware** | [`hardware/deteccion_hardware.md`](hardware/deteccion_hardware.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/hardware/deteccion_hardware.md) | [`demo_hardware.sh`](hardware/demo_hardware.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/hardware/demo_hardware.sh) | Inventario de buses con `lspci` y `lsusb`, arquitectura CPU con `lscpu`, metadatos de bajo nivel de BIOS/firmware y placa base con `dmidecode` (DMI/SMBIOS), y reportes estructurados con `lshw` y `hwinfo`. |

---

## 🟡 Nivel 2: Supervisión y Gobernanza Moderna (Systemd & Cgroups)
*El estándar de la industria para inicio de servicios, tareas programadas y gobernanza dura de memoria y CPU.*

| Módulo | Guía Teórica (Local / GitHub) | Unidad de Demostración | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **6. Servicios Periódicos y Timers** | [`systemd/systemd-memlogger.md`](systemd/systemd-memlogger.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/systemd/systemd-memlogger.md) | `memlogger.service` <br> `memlogger.timer` | Reemplazo moderno de `cron`, unidades `Type=oneshot`, directivas `OnCalendar` y precisión temporal con `AccuracySec`. |
| **7. Activación por Sockets** | [`systemd/systemd-scoket.md`](systemd/systemd-scoket.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/systemd/systemd-scoket.md) | `echo.socket` <br> `echo@.service` | Socket activation bajo demanda, escucha pasiva del kernel, arranque instantáneo al recibir tráfico de red sin memoria ociosa. |
| **8. Límites con Cgroups v2** | [`systemd/systemd-cgroups.md`](systemd/systemd-cgroups.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/systemd/systemd-cgroups.md) | `systemd-run` | Control de contención: `CPUQuota`, `MemoryMax`, `MemoryHigh` y prevención de caídas generales de servidor por saturación. |

---

## 🟠 Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo
*Gestión de discos físicos y lógicos, estructura matemática del almacenamiento, seguridad criptográfica y observabilidad continua.*

| Módulo | Guía Teórica (Local / GitHub) | Script de Clase (Local / GitHub) | Conceptos Clave |
| :--- | :--- | :--- | :--- |
| **9. Anatomía de Filesystems y Diagnóstico Forense** | [`filesystems/anatomia_filesystems.md`](filesystems/anatomia_filesystems.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/anatomia_filesystems.md) | [`demo_filesystems.sh`](filesystems/demo_filesystems.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/demo_filesystems.sh) | Capa VFS, Superbloques y copias de respaldo, inodos vs bloques, `tune2fs`, `dumpe2fs`, `xfs_info`, `xfs_growfs`, crisis de **inodos agotados con 90% libre** (`df -i`), rescate de superbloque con `e2fsck -b`, Btrfs CoW y tmpfs en RAM. |
| **10. LVM2 y Online Resize** | [`storage/lab_storage.md`](storage/lab_storage.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/storage/lab_storage.md) | [`demo_lab_storage.sh`](storage/demo_lab_storage.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/storage/demo_lab_storage.sh) | Dispositivos loop, Physical Volumes (PV), Volume Groups (VG), Logical Volumes (LV), y redimensionamiento en caliente (`lvextend -r`, `resize2fs`, `growpart`). |
| **11. Arquitecturas de Cifrado en Linux (Comparativa)** | [`cifrado/cifrado_arquitecturas_comparativa.md`](cifrado/cifrado_arquitecturas_comparativa.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/cifrado/cifrado_arquitecturas_comparativa.md) | Guía comparativa | Matriz arquitectónica de cifrado en reposo: Bloques (LUKS2 / dm-crypt), Filesystem apilado (gocryptfs / FUSE) y Aplicación/Archivo (GPG / age). Comparativa de fuga de metadatos, rendimiento de I/O, privilegios de root y árbol de decisión para producción. |
| **12. Cifrado de Bloques en Reposo (LUKS2)** | [`luks/luks.md`](luks/luks.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/luks/luks.md) | [`demo_luks.sh`](luks/demo_luks.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/luks/demo_luks.sh) | `cryptsetup`, cifrado moderno con LUKS2 y función Argon2id, ciclo de vida de keyslots (`luksDump`, `luksAddKey`, `luksChangeKey`, `luksKillSlot`), respaldo crítico de cabeceras (`luksHeaderBackup`), desbloqueo automatizado con TPM 2.0 (`systemd-cryptenroll`) y centros de datos con Clevis/Tang (NBDE), optimización SSD (`--allow-discards`) e inspección forense con `strings`. |
| **13. Cifrado FUSE (gocryptfs)** | [`gocryptfs/gocryptfs.md`](gocryptfs/gocryptfs.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/gocryptfs/gocryptfs.md) | Guía práctica | Cifrado en espacio de usuario a nivel de archivos/directorios. Comparativa directa vs LUKS (ventajas en nubes y backup granular). |
| **14. Criptografía Asimétrica, Firmas y Backups (GPG)** | [`gpg/gpg_firmas_repositorios_backups.md`](gpg/gpg_firmas_repositorios_backups.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/gpg/gpg_firmas_repositorios_backups.md) | [`demo_gpg.sh`](gpg/demo_gpg.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/gpg/demo_gpg.sh) | GnuPG en entornos reales de producción: pares de claves Ed25519/Cv25519 con subclaves `[SC]` y `[E]`, firmas desasociadas (`--detach-sign`) y detección de manipulación, firma moderna de repositorios APT (`[signed-by=...]` en `/etc/apt/keyrings`) y RPM (`rpm --checksig`), pipeline automatizado de backups en streaming con clave pública en servidor (`mysqldump \| gzip \| gpg`) y comparativa con herramientas modernas (`age` y Mozilla SOPS). |
| **15a. Arquitecturas de Respaldo y Estrategias (Comparativa)** | [`backup/backup_arquitecturas_comparativa.md`](backup/backup_arquitecturas_comparativa.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/backup_arquitecturas_comparativa.md) | Guía comparativa | Taxonomía completa en 6 capas de copias de seguridad en Linux: Full, Incremental, Diferencial y Continuo (CDP). RPO vs RTO, Regla 3-2-1, pruebas de recuperación, y matriz de decisión con 10+ herramientas (`tar`, `dd`, `rsync`, `rdiff-backup`, `duplicity`, `borg`, `restic`, `bacula`, LVM/ZFS snapshots). |
| **15b. Respaldos Clásicos con tar y rsync (--link-dest)** | [`backup/backup_tar_rsync_incremental.md`](backup/backup_tar_rsync_incremental.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/backup_tar_rsync_incremental.md) | [`demo_backup_tar_rsync.sh`](backup/demo_backup_tar_rsync.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/demo_backup_tar_rsync.sh) <br> [`limpiar_backup_tar_rsync.sh`](backup/limpiar_backup_tar_rsync.sh) | Empaquetado `tar` con flags de producción (`-cvpzf`), incrementales con archivos de instantánea `.snar`, deduplicación por Hard Links en inodos con `rsync --link-dest`, verificación con `stat` y `sha256sum`, y rescate de desastre. |
| **15c. Respaldos con Deltas Inversos y Cifrado Remoto (rdiff-backup y Duplicity)** | [`backup/backup_rdiff_duplicity.md`](backup/backup_rdiff_duplicity.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/backup_rdiff_duplicity.md) | [`demo_backup_rdiff_duplicity.sh`](backup/demo_backup_rdiff_duplicity.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/demo_backup_rdiff_duplicity.sh) <br> [`limpiar_backup_rdiff_duplicity.sh`](backup/limpiar_backup_rdiff_duplicity.sh) | Arquitectura de espejo directo + deltas inversos con `rdiff-backup` (`--restore-as-of` para viajar en el tiempo), respaldos incrementales cifrados de extremo a extremo con GnuPG para almacenamiento remoto no confiable con `duplicity`, rotación mensual automática (`--full-if-older-than 1M`) y restauración. |
| **15d. Respaldos Crudos (dd) y Snapshots LVM Copy-on-Write** | [`backup/backup_dd_imagenes_raw_lvm_snapshots.md`](backup/backup_dd_imagenes_raw_lvm_snapshots.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/backup_dd_imagenes_raw_lvm_snapshots.md) | [`demo_backup_dd_snapshots.sh`](backup/demo_backup_dd_snapshots.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/backup/demo_backup_dd_snapshots.sh) <br> [`limpiar_backup_dd_snapshots.sh`](backup/limpiar_backup_dd_snapshots.sh) | Clonación de bajo nivel de sectores de arranque MBR/GPT y particiones con `dd` en streaming comprimido (`conv=noerror,sync`), inconsistencia de datos en caliente, congelamiento atómico con Snapshots LVM Copy-on-Write (`lvcreate -s`), extracción consistente en modo solo lectura, destrucción segura del snapshot y restauración forense con `e2fsck`. |
| **15e. Respaldos Deduplicados y Cifrados con BorgBackup** | [`borg/borg.md`](borg/borg.md) · [GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/borg/borg.md) <br> [`borg-con-systemd-timers.md`](borg/borg-con-systemd-timers.md) · [GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/borg/borg-con-systemd-timers.md) | [`demo_borg.sh`](borg/demo_borg.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/borg/demo_borg.sh) | BorgBackup: inicialización cifrada (repokey), deduplicación por chunking, montaje FUSE (`borg mount`), retención (`prune`) y timers automáticos. |
| **16a. Arquitecturas de Monitoreo y Observabilidad (Comparativa)** | [`monitoreo/monitoreo_arquitecturas_comparativa.md`](monitoreo/monitoreo_arquitecturas_comparativa.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/monitoreo_arquitecturas_comparativa.md) | Guía comparativa | Taxonomía de observabilidad moderna vs monitoreo clásico: los 4 pilares (Métricas TSDB, Logs, Trazas APM y Probes Sintéticos), debate arquitectural PULL (scraping) vs PUSH (streaming/agentes), formatos OpenMetrics y OTLP, y matriz de decisión entre 10 plataformas (Prometheus, VictoriaMetrics, Datadog, Graphite, Nagios, Zabbix, Loki, ELK, OpenTelemetry, Blackbox). |
| **16b. Monitoreo Continuo y Métricas en Producción** | [`monitoreo/monitoreo_metricas.md`](monitoreo/monitoreo_metricas.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/monitoreo_metricas.md) | [`demo_monitoreo.sh`](monitoreo/demo_monitoreo.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/demo_monitoreo.sh) <br> [`limpiar_monitoreo.sh`](monitoreo/limpiar_monitoreo.sh) | Diagnóstico puntual vs Monitoreo continuo, modelo PULL vs PUSH, Node Exporter, Textfile Collector, salud de mirrors RAID 1, peticiones HTTP, sesiones SSH y métricas de backup. |
| **16c. AI SRE, Protocolo MCP y Remediación Autónoma** | [`monitoreo/ai_sre_agentes_observabilidad.md`](monitoreo/ai_sre_agentes_observabilidad.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/ai_sre_agentes_observabilidad.md) | [`demo_ai_sre.sh`](monitoreo/demo_ai_sre.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/demo_ai_sre.sh) <br> [`limpiar_ai_sre.sh`](monitoreo/limpiar_ai_sre.sh) | Integración de observabilidad con Inteligencia Artificial y agentes de confiabilidad (AI SRE): ciclo cognitivo ReAct (Thought, Action, Observation), protocolo Model Context Protocol (MCP) para ejecución segura, guardrails de contención de blast radius, y agente CLI en Python (`ai_sre_agent.py`) para triage forense y autorremediación en caliente. |
| **16d. Monitoreo Clásico y Embebido (collectd, StatsD y CLI)** | [`monitoreo/monitoreo_clasico_collectd_statsd.md`](monitoreo/monitoreo_clasico_collectd_statsd.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/monitoreo_clasico_collectd_statsd.md) | [`demo_monitoreo_clasico.sh`](monitoreo/demo_monitoreo_clasico.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/demo_monitoreo_clasico.sh) <br> [`limpiar_monitoreo_clasico.sh`](monitoreo/limpiar_monitoreo_clasico.sh) | Filosofía y arquitectura de la vieja escuela (2000-2015): demonios ultraligeros en C (`collectd`), telemetría *fire-and-forget* no bloqueante sobre sockets UDP (`StatsD` en puerto 8125), almacenamiento circular RRD y CSV, y diagnóstico embebido por consola con `vmstat` e `iostat`. |
| **17. RAID desde Cero y Teoría Comparativa** | [`raid/raid_teoria.md`](raid/raid_teoria.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/raid_teoria.md) | [`demo_raid_teoria.sh`](raid/demo_raid_teoria.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/demo_raid_teoria.sh) | Concepto fundamental de RAID, striping, mirroring, paridad XOR con cálculo de bytes reales, superbloques, write-hole, bitmap, cachés (ARC/SLOG/write-through/write-back), bit-rot y comparativa técnica mdadm vs LVM vs Btrfs vs ZFS. |
| **18. RAID por Software con mdadm** | [`raid/raid_mdadm.md`](raid/raid_mdadm.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/raid_mdadm.md) | [`demo_raid_mdadm.sh`](raid/demo_raid_mdadm.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/demo_raid_mdadm.sh) | Arreglos RAID 0/1/5/6/10, formato de superbloques 1.2, write-intent bitmap interno, hot spares automáticos, simulación de fallas en vivo (`--fail`), recuperación transparente por paridad XOR, reemplazo de unidades (`--remove`/`--add`) y auditoría con scrub (`mismatch_cnt`). |
| **19. RAID con LVM (dm-raid)** | [`raid/raid_lvm.md`](raid/raid_lvm.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/raid_lvm.md) | [`demo_raid_lvm.sh`](raid/demo_raid_lvm.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/demo_raid_lvm.sh) <br> [`limpiar_raid_lvm.sh`](raid/limpiar_raid_lvm.sh) | Integración dm-raid, sub-volúmenes ocultos de metadatos (`_rmeta`) y datos (`_rimage`), expansión en caliente (`lvextend -r`), degradación parcial de PVs y flujo de autorrecuperación en caliente con `lvconvert --repair` y `vgreduce --removemissing`. |
| **20. RAID con Btrfs** | [`raid/raid_btrfs.md`](raid/raid_btrfs.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/raid_btrfs.md) | [`demo_raid_btrfs.sh`](raid/demo_raid_btrfs.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/demo_raid_btrfs.sh) | Perfiles independientes para datos (`-d`) y metadatos (`-m`), tolerancia a discos de tamaños asimétricos en RAID 1, advertencia del write-hole en RAID 5/6, auto-reparación silenciosa ante bit-rot por checksums CRC32C/XXHASH (*self-healing*), auditorías proactivas con `btrfs scrub` y reemplazo atómico con `btrfs replace`. |
| **21. RAID Empresarial con OpenZFS** | [`raid/raid_zfs.md`](raid/raid_zfs.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/raid_zfs.md) | [`demo_raid_zfs.sh`](raid/demo_raid_zfs.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/demo_raid_zfs.sh) | Storage Pools (`zpool`) y VDEVs, eliminación matemática del write-hole en RAIDZ mediante franjas de ancho variable, jerarquía de cachés ARC (RAM), L2ARC (SSD) y SLOG/ZIL para escrituras síncronas, auto-curación (*self-healing*) con checksums Fletcher4 de 256 bits y reconstrucción de bloques usados (*resilvering*). |
| **22. Estructura de Enlaces en Filesystems** | [`filesystems/enlaces_hard_soft_links.md`](filesystems/enlaces_hard_soft_links.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/enlaces_hard_soft_links.md) | [`demo_enlaces.sh`](filesystems/demo_enlaces.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/demo_enlaces.sh) | Separación dentry vs inodo, enlaces duros (`ln`), inodos compartidos (`ls -i`), contador `nlink`, enlaces simbólicos (`ln -s`), auditoría con `find` (`-type l -exec ls -l {} \;`, `-ls`, `-samefile` y `-xtype l -delete`), y cuatro casos reales de producción: despliegue atómico zero-downtime con `ln -sfn`, versionado de bibliotecas `.so` (SONAME), deduplicación instantánea de backups con `rsync --link-dest` y resolución de archivos borrados retenidos por procesos con `lsof +L1`. Incluye ruta rápida de autoaprendizaje. |
| **23. Diagnóstico y Mantenimiento de Volúmenes** | [`filesystems/mantenimiento_volumenes.md`](filesystems/mantenimiento_volumenes.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/mantenimiento_volumenes.md) | [`demo_mantenimiento_volumenes.sh`](filesystems/demo_mantenimiento_volumenes.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/filesystems/demo_mantenimiento_volumenes.sh) | Auditoría con `df` (`-h`, `-a`, `-k`, inodos `-i`) y `du` (top 10 consumo con `sort -hr`), ajuste de ext4 con `tune2fs` (intervalos `-c`/`-i`, etiquetas `-L`, bloques `-m`, journaling `-j`, lectura en particiones NO montadas), chequeo con `fsck`/`e2fsck` (`-p`, `-y`, `-c`, `-f`, `-n`), `dumpe2fs` (`-h`, `-x`), optimización XFS (`xfs_metadump`, `xfs_db` frag, `xfs_fsr`), Btrfs (`check --repair -p`, `balance`) y escaneo de sectores dañados con `badblocks` (`-s`, `-w`, `-n`, `-o`). |
| **24. Métricas de Disco, Filesystems e Inodos** | [`monitoreo/monitoreo_disco_custom.md`](monitoreo/monitoreo_disco_custom.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/monitoreo_disco_custom.md) | [`colector_disco.sh`](monitoreo/scripts/colector_disco.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/scripts/colector_disco.sh) <br> [`limpiar_monitoreo_disco_custom.sh`](monitoreo/limpiar_monitoreo_disco_custom.sh) | Recolección de telemetría de almacenamiento con Textfile Collector de Node Exporter: espacio usado/libre, inodos ocupados/totales y tipo de filesystem (ext4/xfs/btrfs). Inspección con `curl` y paneles en Grafana. |
| **25. Gestión y Disparo de Alertas con Alertmanager** | [`monitoreo/alertmanager_alertas_locales.md`](monitoreo/alertmanager_alertas_locales.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/alertmanager_alertas_locales.md) | [`webhook_receiver.py`](monitoreo/scripts/webhook_receiver.py) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/scripts/webhook_receiver.py) | Prometheus Alertmanager sin dependencias de correo ni webhooks externos: receptor local en terminal con Python, disparo de alertas por saturación de inodos en caliente, auto-resolución y guía de migración a producción. |
| **26. Taller Integrador: Web sobre LVM RAID 1, Node Exporter y Resiliencia en Vivo** | [`monitoreo/taller_integrador_web_lvm_monitoreo.md`](monitoreo/taller_integrador_web_lvm_monitoreo.md) <br> [🌐 Ver en GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/taller_integrador_web_lvm_monitoreo.md) | [`demo_taller_integrador.sh`](monitoreo/demo_taller_integrador.sh) <br> [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/monitoreo/demo_taller_integrador.sh) <br> [`tui_monitoreo.sh`](monitoreo/scripts/tui_monitoreo.sh) <br> [`limpiar_taller_integrador.sh`](monitoreo/limpiar_taller_integrador.sh) | Taller de integración para clases: evolución desde el monitoreo reactivo de los 90 hacia Node Exporter PULL, servidor web corporativo montado sobre LVM RAID 1 espejado, tráfico HTTP, destrucción intencional de disco con `dd`, demostración de cero caída (zero downtime), reconstrucción en caliente con `lvconvert --repair` y visualización en tiempo real mediante un dashboard gráfico de terminal (TUI) y Prometheus/Grafana. |

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
                  │
   [Integrador 5: RAID & Metrics]    --> Resiliencia RAID 5 + 5 EBS en AWS + Prometheus Node Exporter
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


### 5. [Trabajo Integrador 5: Almacenamiento Empresarial RAID en AWS, Inyección de Fallas, Recuperación y Observabilidad con Métricas](raid/integrador_aws/trabajo_integrador_raid.md) · [🌐 GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/integrador_aws/trabajo_integrador_raid.md)
* **Infraestructura:** 1 EC2 Ubuntu `t3.micro` + 5 discos EBS de 1 GB (gp3) + Prometheus Node Exporter en puerto 9100 + Servicio Web Nginx.
* **Archivos:** [`trabajo_integrador_raid.md`](raid/integrador_aws/trabajo_integrador_raid.md) | [`demo_integrador_raid.sh`](raid/integrador_aws/demo_integrador_raid.sh) ([GitHub](https://github.com/villadalmine/labs/blob/main/linux/administrator/raid/integrador_aws/demo_integrador_raid.sh)) | [Directorio Terraform](raid/integrador_aws/terraform/)
* **Qué enseña:**
  - Aprovisionamiento declarativo con Terraform de almacenamiento multi-disco en AWS.
  - Creación de RAID 5 con 3 discos de datos, 1 Hot Spare automático y Write-Intent Bitmap interno.
  - Implementación de pipeline de telemetría y observabilidad en tiempo real con Prometheus Node Exporter (Textfile Collector) y Systemd Timer cada 5 segundos (`raid_healthy`, `raid_failed_disks`, `raid_spare_disks`).
  - Inyección de caos (*Chaos Engineering*) con rotura física simulada en caliente de un volumen EBS.
  - Demostración de cero pérdida de datos y continuidad del servicio web mediante reconstrucción al vuelo por paridad XOR.
  - Activación automática del Hot Spare y seguimiento de métricas de resincronización.
  - Procedimiento formal de reemplazo físico de unidad (*drive swap*) con nuevo volumen EBS y auditoría de paridad (*scrubbing*).
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
