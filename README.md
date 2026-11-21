# Laboratorios de Infraestructura, Linux y Sistemas Distribuidos

Repositorio de **laboratorios prácticos, guías de arquitectura paso a paso y scripts interactivos** enfocados en la **Administración Avanzada de Servidores Linux, Almacenamiento Empresarial, Criptografía, Respaldos, Observabilidad, Resiliencia y Proyectos en la Nube con Terraform**.

Incluye además un ecosistema integral de **Tutor Inteligente de Inteligencia Artificial y Retrieval-Augmented Generation (RAG)** con servidor MCP nativo para aprendizaje asistido por agentes.

---

## 🗺️ Estructura Completa del Repositorio

El repositorio se organiza en dos grandes pilares complementarios:

```
labs/
├── linux/administrator/       # 🐧 Plan de Carrera y Laboratorios de Administración Linux
│   ├── hardware/              # Detección, inventario y auditoría física/lógica (lspci, dmidecode, lshw, hwinfo, lscpu)
│   ├── kernel/                # Arquitectura del Kernel (0.01->7.2), familias UNIX/BSD/NT/Android, OSTree/bootc, LKM, sysfs/sysctl, initramfs QEMU y eBPF
│   ├── virtualizacion/        # Historia VM/370->KVM/Hyper-V/ESXi, Jails/Zones/LPAR, Contenedores, OpenStack, Kubernetes/K9s y HPC Slurm
│   ├── procesos/              # Ciclo de vida, zombies, señales Unix y multiplexores (tmux, screen, zellij)
│   ├── nice/                  # Planificador CFS, prioridades nice/renice y afinidad de núcleos con taskset
│   ├── automatizacion/        # Planificación y automatización: Cron, Crontab, Anacron, comando at, Systemd Timers y Chrony (NTP)
│   ├── systemd/               # Timers periódicos (memlogger), socket activation y control de recursos con cgroups v2
│   ├── filesystems/           # Anatomía VFS, enlaces duros/simbólicos, tune2fs, XFS, Btrfs y mantenimiento de volúmenes
│   ├── storage/               # Dispositivos loop, volúmenes lógicos LVM2 y online resize
│   ├── cifrado/               # Criptografía, SSH (Cliente/Servidor/Túneles), WireGuard, OpenVPN y comparativa en reposo/tránsito
│   ├── luks/                  # Cifrado de bloques en reposo con LUKS2 (dm-crypt, keyslots, Argon2id, TPM2)
│   ├── gocryptfs/             # Cifrado FUSE en espacio de usuario a nivel de archivos/carpetas
│   ├── gpg/                   # Criptografía asimétrica, firmas de repositorios APT/RPM y backups cifrados
│   ├── backup/                # Respaldos clásicos (tar/rsync), deltas (rdiff/duplicity), imágenes crudas (dd) y LVM Snapshots
│   ├── borg/                  # Respaldos deduplicados y cifrados con BorgBackup y timers de systemd
│   ├── raid/                  # Arreglos RAID desde cero (mdadm, LVM dm-raid, Btrfs, OpenZFS)
│   ├── monitoreo/             # Observabilidad PULL/PUSH, Prometheus, Grafana, AI SRE (MCP), collectd/StatsD y cluster multi-nodo
│   ├── logs/                  # Gestión de Logs, Syslog, Journald, rsyslog TLS/Queues, Pipelines HA y Triage AI SRE
│   ├── graficos/              # Sistemas Gráficos: X11/Xorg, Wayland, WM/DE/DM, Xvfb, SSH -X, Túnel VNC y Accesibilidad
│   ├── trabajo_integrador*/   # 5 Proyectos integradores de alta disponibilidad en AWS con Terraform
│   ├── GLOSARIO.md            # 📚 Glosario técnico cruzado con documentación oficial (Kernel, Virtualización, Storage, Resiliencia y Criptografía)
│   ├── metadata.schema.json   # 📜 Esquema formal JSON-Schema de metadatos curriculares
│   ├── catalog.json           # 🧠 Catálogo indexado de 69 laboratorios para motores RAG y agentes
│   └── README.md              # 📖 Índice principal y Plan de Carrera (Niveles 0 al 4)
│
└── ai/tutor/                  # 🤖 Ecosistema de Tutor de IA y Asistencia RAG
    ├── mcp/                   # Servidor MCP nativo (labs_mcp_server.py) y generador de corpus RAG
    ├── hub/                   # Hub Multi-MCP: hub.py levanta varios MCP por HTTP y configura Open WebUI / VS Code
    ├── tutor_engine.py        # Motor de decisiones pedagógicas y recomendación de rutas
    ├── GUIA_PASO_A_PASO.md    # Despliegue de Open WebUI, Goose CLI y Ollama local en CPU
    └── README.md              # 📖 Arquitectura del Tutor Inteligente y Protocolos de Agente
```

---

## 🚀 1. Administración de Servidores Linux ([`linux/administrator/`](linux/administrator/README.md))

El contenido curricular de administración de sistemas está ordenado de **menor a mayor complejidad pedagógica (Nivel 0 al Nivel 4)**:

| Nivel | Enfoque Tecnológico | Laboratorios y Scripts de Demostración Destacados |
| :--- | :--- | :--- |
| **🟢 Nivel 0** | **Fundamentos & Compilación** | Ciclo de compilación C con `gcc`, Makefiles e instalación en `/usr/local/bin` (`holamundo.c`, `Makefile`). |
| **🟢 Nivel 1** | **Procesos, Señales, Diagnóstico, Kernel y Hardware** | Control de trabajos (`fg`, `bg`, `nohup`), procesos zombies (`demo_zombie.sh`), scheduler CFS y afinidad (`demo_nice.sh`), diagnóstico forense en vivo (`uptime`, `vmstat`, `iostat`), **auditoría de hardware (`demo_hardware.sh`)**, **Guía Maestra del Kernel (0.01→7.2, OSTree/bootc, AWS/Azure/GCP, Edge/Zephyr)**, `/boot` + LKM + blacklists (`demo_modulos_blacklists.sh`) y **`sysfs` + `sysctl` (`demo_sysfs_sysctl.sh`)**. |
| **🟡 Nivel 2** | **Automatización, Planificación, Actualización del Kernel y Gobernanza Moderna** | • **Planificación Clásica & Asíncrona:** Matriz de decisión (`automatizacion_arquitecturas_comparativa.md`), `cron` y `crontab` de 5 campos, operadores y macros (`demo_cron_crontab.sh`), `anacron` para sistemas intermitentes y `at` para ejecución única efímera (`demo_anacron_at.sh`).<br>• **Systemd & Sincronización NTP:** Desacoplamiento `.timer` + `.service`, `systemd-analyze calendar` y `Chrony` (`demo_systemd_timers_chrony.sh`), monitor periódico (`memlogger.timer`), activación por sockets (`echo.socket`) y gobernanza dura de CPU/RAM con cgroups v2 (`systemd-cgroups`).<br>• **Ciclo de Vida del Kernel:** Plan en 8 pasos, DKMS/kABI, Rollback GRUB2/OSTree, Livepatch (`kpatch`) y Smoke Test (`demo_actualizacion_kernel.sh`). |
| **🟠 Nivel 3** | **Storage, Filesystems, Cifrado, Backups, Logs, Observabilidad, Kernel Avanzado y Virtualización/HPC** | • **Filesystems & Enlaces:** Anatomía VFS (`demo_filesystems.sh`), enlaces duros y simbólicos (`demo_enlaces.sh`), diagnóstico y mantenimiento de volúmenes (`demo_mantenimiento_volumenes.sh`).<br>• **LVM2:** Volúmenes lógicos y expansión en caliente (`demo_lab_storage.sh`).<br>• **Criptografía & Cifrado:** Fundamentos de llaves y certificados (`demo_criptografia_llaves.sh`), **Arquitectura de Cifrado en SSH Cliente/Servidor, Túneles y WireGuard (`demo_ssh_cifrado.sh`)**, LUKS2 (`demo_luks.sh`), gocryptfs FUSE (`demo_gocryptfs.sh`), GPG y firmas (`demo_gpg.sh`).<br>• **Backups:** Clásicos tar/rsync (`demo_backup_tar_rsync.sh`), deltas rdiff/duplicity (`demo_backup_rdiff_duplicity.sh`), crudos dd y snapshots LVM (`demo_backup_dd_snapshots.sh`), BorgBackup (`demo_borg.sh`).<br>• **Arreglos RAID:** Teoría XOR (`demo_raid_teoria.sh`), mdadm (`demo_raid_mdadm.sh`), LVM dm-raid (`demo_raid_lvm.sh`), Btrfs (`demo_raid_btrfs.sh`), OpenZFS (`demo_raid_zfs.sh`).<br>• **Observabilidad:** Métricas y Textfile Collector (`demo_monitoreo.sh`), AI SRE autónomo con MCP (`demo_ai_sre.sh`), monitoreo clásico collectd/StatsD (`demo_monitoreo_clasico.sh`), Alertmanager, Taller LVM RAID 1 (`demo_taller_integrador.sh`) y Monitoreo Centralizado Multi-Nodo en AWS (`demo_monitoreo_centralizado.sh`).<br>• **Gestión de Logs & Pipelines:** Teoría maestra de logging (`logs_arquitecturas_teoria.md`), `/var/log`/`dmesg`/`logrotate` (`demo_logs_fundamentos.sh`), troubleshooting forense `journalctl` (`demo_journald_troubleshooting.sh`), `rsyslog` TLS + Disk Queues (`demo_rsyslog_pipelines.sh`) y logging centralizado + AI SRE (`demo_logging_centralizado_ai_sre.sh`).<br>• **Ingeniería del Kernel & eBPF:** Módulo LKM educativo de firmware en C (`demo_lkm_firmware_sim.sh`), compilación estilo Gentoo + Mini-OS + paradoja `initramfs` en QEMU/KVM (`demo_compilacion_kernel_initramfs.sh`) y ataques defensivos + Mini-IDS eBPF (`demo_seguridad_ataques_ebpf.sh`).<br>• **Sistemas Gráficos & Acceso Remoto:** Teoría e historia X11/Xorg vs. Wayland, WM/DE/DM y Accesibilidad (`sistemas_graficos_x11_wayland_teoria.md`), inspección headless `Xvfb` + `xauth`/`xhost` (`demo_x11_headless.sh`), exportación remota segura `SSH -X` + túnel VNC (`demo_acceso_grafico_remoto.sh`) y Podman Pod DOOM + noVNC en navegador (`demo_doom_podman_browser.sh`).<br>• **Virtualización, Cloud & HPC:** Historia de IBM VM/370 a `VT-x`/KVM/Hyper-V/ESXi, Jails/Zones/LPAR, Contenedores/MicroVMs, OpenStack, Kubernetes/`K9s`/`KubeVirt` y `Slurm` (`virtualizacion_contenedores_cloud_hpc_teoria.md`). |
| **🔴 Nivel 4** | **Proyectos Integradores en la Nube (AWS + Terraform)** | • **Integrador 1:** Servidor Web Nginx, RAID 1 (LVM vs mdadm), LUKS y Borg Remoto por SSH.<br>• **Integrador 2:** Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y S3 Cifrado (`demo_integrador_docker.sh`).<br>• **Integrador 3:** Almacenamiento Avanzado Btrfs: Subvolúmenes, Reflinks O(1), RAID 1 y Scrub (`demo_integrador_btrfs.sh`).<br>• **Integrador 4:** ZFS Enterprise HA Activo-Pasivo, Replicación Remota y AWS ALB Failover (`demo_integrador_zfs.sh`).<br>• **Integrador 5:** Almacenamiento Empresarial RAID en AWS, Inyección de Fallas y Métricas Prometheus (`demo_integrador_raid.sh`). |

👉 **Consultá el [Plan de Carrera Completo y Guías Paso a Paso](linux/administrator/README.md)**.

---

## 🤖 2. Tutor de IA y Recuperación Semántica RAG ([`ai/tutor/`](ai/tutor/README.md))

El repositorio implementa un catálogo formal de metadatos ([`catalog.json`](linux/administrator/catalog.json) validado por [`metadata.schema.json`](linux/administrator/metadata.schema.json)) con **69 laboratorios estructurados** diseñado para alimentar sistemas de IA sin alucinaciones:

- **Motor Pedagógico (`ai/tutor/tutor_engine.py`):** Recomienda el siguiente laboratorio según tu sistema operativo (`WSL2`, `AWS EC2`, `Debian`, `Ubuntu`), nivel y prerequisitos aprobados.
- **Servidor MCP Nativo (`ai/tutor/mcp/labs_mcp_server.py`):** Expone 7 herramientas dinámicas (preguntas socráticas progresivas, validación de entorno, consulta de laboratorios) para clientes compatibles con Model Context Protocol (Goose CLI, Claude Desktop, Cursor, Continue.dev).
- **Corpus RAG Local:** Compatible con Open WebUI, AnythingLLM y Ollama para estudiar offline en CPU.
- **Hub Multi-MCP (`ai/tutor/hub/hub.py`):** Levanta por HTTP este MCP junto con los de `study-cybercirujas`, `rag-tutor` y `oss-docs`, y los conecta a Open WebUI y VS Code con un comando. Ver la [Guía del Hub Multi-MCP](ai/tutor/GUIA_HUB_MCP.md).

👉 **Seguí la [Guía Paso a Paso para configurar tu Tutor Local de IA](ai/tutor/GUIA_PASO_A_PASO.md)**.

Para entender cómo te ayuda un agente con los labs, seguí esta secuencia: [agentes, herramientas y protocolos](ai/tutor/AGENTES_Y_PROTOCOLOS_MCP.md) → [práctica MCP de 15 minutos con Claude Code, Codex o Antigravity](ai/tutor/PRACTICA_15_MIN_MCP.md) → [hub con varias fuentes](ai/tutor/GUIA_HUB_MCP.md).

Docente: el estado de hitos y las instrucciones para retomar están en [el plan del Hub MCP](ai/tutor/hub/PLAN_DE_ACCION.md) y su [handover](ai/tutor/hub/TRASPASO.md).

---

## 🛠️ Cómo Ejecutar los Laboratorios Didácticos

Todos los laboratorios incluyen demostraciones didácticas automatizadas (`demo_*.sh`):
- **Agnósticos y Seguros:** En entornos locales o WSL2 utilizan discos virtuales *loop* (`/dev/loopX`) o directorios temporales aislados para no comprometer el almacenamiento de tu equipo.
- **Modo Interactivo (Pausas Didácticas):** Por defecto, pausan en cada paso (`[ENTER]`) mostrando preguntas socráticas para dar clase en vivo.
- **Modo Automático:** Agregando `--auto <segundos>`, avanzan de forma continua para presentaciones rápidas.
- **Limpieza Garantizada:** Al presionar `Ctrl+C` o terminar, un handler `trap` desmonta y libera automáticamente todos los recursos.

```bash
# Ejemplo 1: Clonar y correr el laboratorio de fundamentos de criptografía y llaves
git clone https://github.com/villadalmine/labs.git
cd labs/linux/administrator/cifrado
./demo_criptografia_llaves.sh

# Ejemplo 2: Auditoría forense de hardware en modo automático
cd labs/linux/administrator/hardware
sudo ./demo_hardware.sh --auto 2

# Ejemplo 3: Laboratorio de diagnóstico y mantenimiento de volúmenes
cd labs/linux/administrator/filesystems
sudo ./demo_mantenimiento_volumenes.sh
```

---

## 📄 Licencia

Este proyecto está bajo la Licencia GPL v3. Consultá el archivo [`LICENSE`](LICENSE) para más detalles.
