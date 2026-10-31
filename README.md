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
│   ├── procesos/              # Ciclo de vida, zombies, señales Unix y multiplexores (tmux, screen, zellij)
│   ├── nice/                  # Planificador CFS, prioridades nice/renice y afinidad de núcleos con taskset
│   ├── systemd/               # Timers periódicos (memlogger), socket activation y control de recursos con cgroups v2
│   ├── filesystems/           # Anatomía VFS, enlaces duros/simbólicos, tune2fs, XFS, Btrfs y mantenimiento de volúmenes
│   ├── storage/               # Dispositivos loop, volúmenes lógicos LVM2 y online resize
│   ├── cifrado/               # Fundamentos de criptografía y llaves (SSH, EC2, OpenVPN, TLS), comparativa en reposo
│   ├── luks/                  # Cifrado de bloques en reposo con LUKS2 (dm-crypt, keyslots, Argon2id, TPM2)
│   ├── gocryptfs/             # Cifrado FUSE en espacio de usuario a nivel de archivos/carpetas
│   ├── gpg/                   # Criptografía asimétrica, firmas de repositorios APT/RPM y backups cifrados
│   ├── backup/                # Respaldos clásicos (tar/rsync), deltas (rdiff/duplicity), imágenes crudas (dd) y LVM Snapshots
│   ├── borg/                  # Respaldos deduplicados y cifrados con BorgBackup y timers de systemd
│   ├── raid/                  # Arreglos RAID desde cero (mdadm, LVM dm-raid, Btrfs, OpenZFS)
│   ├── monitoreo/             # Observabilidad PULL/PUSH, Prometheus, Grafana, AI SRE (MCP), collectd/StatsD y cluster multi-nodo
│   ├── trabajo_integrador*/   # 5 Proyectos integradores de alta disponibilidad en AWS con Terraform
│   ├── GLOSARIO.md            # 📚 Glosario técnico cruzado de almacenamiento, resiliencia y criptografía
│   ├── metadata.schema.json   # 📜 Esquema formal JSON-Schema de metadatos curriculares
│   ├── catalog.json           # 🧠 Catálogo indexado de 47 laboratorios para motores RAG y agentes
│   └── README.md              # 📖 Índice principal y Plan de Carrera (Niveles 0 al 4)
│
└── ai/tutor/                  # 🤖 Ecosistema de Tutor de IA y Asistencia RAG
    ├── mcp/                   # Servidor MCP nativo (labs_mcp_server.py) y generador de corpus RAG
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
| **🟢 Nivel 1** | **Procesos, Señales, Diagnóstico y Hardware** | Control de trabajos (`fg`, `bg`, `nohup`), procesos zombies (`demo_zombie.sh`), scheduler CFS y afinidad (`demo_nice.sh`), diagnóstico forense en vivo (`uptime`, `vmstat`, `iostat`) y **auditoría de hardware (`demo_hardware.sh`: `lspci`, `lsusb`, `lshw`, `hwinfo`, `dmidecode`, `lscpu`)**. |
| **🟡 Nivel 2** | **Supervisión Moderna (Systemd & Cgroups)** | Timers automáticos (`memlogger.timer`), activación por sockets (`echo.socket`) y gobernanza dura de CPU/RAM con cgroups v2 (`systemd-cgroups`). |
| **🟠 Nivel 3** | **Storage, Filesystems, Cifrado, Backups y Observabilidad** | • **Filesystems & Enlaces:** Anatomía VFS (`demo_filesystems.sh`), enlaces duros y simbólicos (`demo_enlaces.sh`), diagnóstico y mantenimiento de volúmenes (`demo_mantenimiento_volumenes.sh`).<br>• **LVM2:** Volúmenes lógicos y expansión en caliente (`demo_lab_storage.sh`).<br>• **Criptografía & Cifrado:** Fundamentos de llaves y certificados (`demo_criptografia_llaves.sh`), LUKS2 (`demo_luks.sh`), gocryptfs FUSE (`demo_gocryptfs.sh`), GPG y firmas (`demo_gpg.sh`).<br>• **Backups:** Clásicos tar/rsync (`demo_backup_tar_rsync.sh`), deltas rdiff/duplicity (`demo_backup_rdiff_duplicity.sh`), crudos dd y snapshots LVM (`demo_backup_dd_snapshots.sh`), BorgBackup (`demo_borg.sh`).<br>• **Arreglos RAID:** Teoría XOR (`demo_raid_teoria.sh`), mdadm (`demo_raid_mdadm.sh`), LVM dm-raid (`demo_raid_lvm.sh`), Btrfs (`demo_raid_btrfs.sh`), OpenZFS (`demo_raid_zfs.sh`).<br>• **Observabilidad:** Métricas y Textfile Collector (`demo_monitoreo.sh`), AI SRE autónomo con MCP (`demo_ai_sre.sh`), monitoreo clásico collectd/StatsD (`demo_monitoreo_clasico.sh`), Alertmanager, Taller LVM RAID 1 (`demo_taller_integrador.sh`) y Monitoreo Centralizado Multi-Nodo en AWS (`demo_monitoreo_centralizado.sh`). |
| **🔴 Nivel 4** | **Proyectos Integradores en la Nube (AWS + Terraform)** | • **Integrador 1:** Servidor Web Nginx, RAID 1 (LVM vs mdadm), LUKS y Borg Remoto por SSH.<br>• **Integrador 2:** Docker Engine LVM Hot-Mirror, MySQL RAID 1, WordPress y S3 Cifrado (`demo_integrador_docker.sh`).<br>• **Integrador 3:** Almacenamiento Avanzado Btrfs: Subvolúmenes, Reflinks O(1), RAID 1 y Scrub (`demo_integrador_btrfs.sh`).<br>• **Integrador 4:** ZFS Enterprise HA Activo-Pasivo, Replicación Remota y AWS ALB Failover (`demo_integrador_zfs.sh`).<br>• **Integrador 5:** Almacenamiento Empresarial RAID en AWS, Inyección de Fallas y Métricas Prometheus (`demo_integrador_raid.sh`). |

👉 **Consultá el [Plan de Carrera Completo y Guías Paso a Paso](linux/administrator/README.md)**.

---

## 🤖 2. Tutor de IA y Recuperación Semántica RAG ([`ai/tutor/`](ai/tutor/README.md))

El repositorio implementa un catálogo formal de metadatos ([`catalog.json`](linux/administrator/catalog.json) validado por [`metadata.schema.json`](linux/administrator/metadata.schema.json)) con **47 laboratorios estructurados** diseñado para alimentar sistemas de IA sin alucinaciones:

- **Motor Pedagógico (`ai/tutor/tutor_engine.py`):** Recomienda el siguiente laboratorio según tu sistema operativo (`WSL2`, `AWS EC2`, `Debian`, `Ubuntu`), nivel y prerequisitos aprobados.
- **Servidor MCP Nativo (`ai/tutor/mcp/labs_mcp_server.py`):** Expone 7 herramientas dinámicas (preguntas socráticas progresivas, validación de entorno, consulta de laboratorios) para clientes compatibles con Model Context Protocol (Goose CLI, Claude Desktop, Cursor, Continue.dev).
- **Corpus RAG Local:** Compatible con Open WebUI, AnythingLLM y Ollama para estudiar offline en CPU.

👉 **Seguí la [Guía Paso a Paso para configurar tu Tutor Local de IA](ai/tutor/GUIA_PASO_A_PASO.md)**.

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
