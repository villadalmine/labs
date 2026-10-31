# Laboratorios de Infraestructura, Linux y Sistemas Distribuidos

Repositorio de **laboratorios prácticos, guías de arquitectura paso a paso y scripts interactivos** enfocados en la **Administración Avanzada de Servidores Linux, Almacenamiento Empresarial, Observabilidad, Resiliencia y Proyectos en la Nube con Terraform**.

Incluye además un ecosistema integral de **Tutor Inteligente de Inteligencia Artificial y Retrieval-Augmented Generation (RAG)** con servidor MCP nativo para aprendizaje asistido por agentes.

---

## 🗺️ Estructura del Repositorio

El repositorio se organiza en dos grandes pilares complementarios:

```
labs/
├── linux/administrator/       # 🐧 Plan de Carrera y Laboratorios de Administración Linux
│   ├── hardware/              # Detección, inventario y auditoría física/lógica (lspci, dmidecode, etc.)
│   ├── procesos/              # Ciclo de vida, zombies, multiplexores (tmux) y señales Unix
│   ├── nice/                  # Planificador CFS, prioridades nice y afinidad taskset
│   ├── systemd/               # Timers, socket activation y control de recursos con cgroups v2
│   ├── filesystems/           # Anatomía VFS, hard/soft links, tune2fs, XFS, Btrfs y mantenimiento
│   ├── storage/               # Dispositivos loop, volúmenes lógicos LVM2 y online resize
│   ├── luks/ & gocryptfs/     # Cifrado de bloques en reposo y cifrado FUSE
│   ├── borg/ & backup/        # Respaldos deduplicados con BorgBackup y timers
│   ├── raid/                  # Arreglos RAID desde cero (mdadm, LVM dm-raid, Btrfs, OpenZFS)
│   ├── monitoreo/             # Observabilidad continua, LVM RAID 1, Prometheus Central y Grafana
│   ├── trabajo_integrador*/   # Proyectos de arquitectura en AWS con Terraform
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

| Nivel | Enfoque Tecnológico | Laboratorios Destacados |
| :--- | :--- | :--- |
| **🟢 Nivel 0** | **Fundamentos & Compilación** | Ciclo de compilación C con `gcc`, Makefiles e instalación en `/usr/local/bin`. |
| **🟢 Nivel 1** | **Procesos, Señales, Diagnóstico y Hardware** | Control de trabajos (`fg`, `bg`, `nohup`), procesos zombies (`SIGCHLD`), scheduler CFS (`nice`, `taskset`), métricas en vivo (`uptime`, `vmstat`, `iostat`) y **auditoría de hardware (`lspci`, `lsusb`, `lshw`, `hwinfo`, `dmidecode`, `lscpu`)**. |
| **🟡 Nivel 2** | **Supervisión Moderna (Systemd & Cgroups)** | Timers automáticos (`memlogger`), activación por sockets (`echo.socket`) y gobernanza dura de CPU/RAM con cgroups v2. |
| **🟠 Nivel 3** | **Storage, Filesystems, Cifrado, Backups y Observabilidad** | Anatomía de filesystems (ext4, XFS, Btrfs, tmpfs), **enlaces duros y simbólicos (`ln`, `find -samefile`, `-xtype l`)**, **diagnóstico y mantenimiento de volúmenes**, LVM2 en caliente, cifrado LUKS / gocryptfs, BorgBackup, arreglos RAID (mdadm, dm-raid, Btrfs, OpenZFS), **taller web LVM RAID 1 resiliente** y **monitoreo centralizado multi-nodo (Prometheus + Grafana en AWS)**. |
| **🔴 Nivel 4** | **Proyectos Integradores en la Nube (AWS + Terraform)** | Clústeres tolerantes a fallas con Terraform en AWS Free Tier (Nginx RAID 1 + LUKS + Borg, Docker en LVM Hot-Mirror, Btrfs Subvolúmenes y ZFS Enterprise HA con AWS ALB). |

👉 **Consultá el [Plan de Carrera Completo y Guías Paso a Paso](linux/administrator/README.md)**.

---

## 🤖 2. Tutor de IA y Recuperación Semántica RAG ([`ai/tutor/`](ai/tutor/README.md))

El repositorio implementa un catálogo formal de metadatos (`catalog.json` validado por `metadata.schema.json`) diseñado para alimentar sistemas de IA sin alucinaciones:

- **Motor Pedagógico (`ai/tutor/tutor_engine.py`):** Recomienda el siguiente laboratorio según tu sistema operativo (`WSL2`, `AWS EC2`, `Debian`, `Ubuntu`), nivel y prerequisitos aprobados.
- **Servidor MCP Nativo (`ai/tutor/mcp/labs_mcp_server.py`):** Expone 7 herramientas dinámicas (preguntas socráticas progresivas, validación de entorno, consulta de laboratorios) para clientes compatibles con Model Context Protocol (Goose CLI, Claude Desktop, Cursor, Continue.dev).
- **Corpus RAG Local:** Compatible con Open WebUI, AnythingLLM y Ollama para estudiar offline en CPU.

👉 **Seguí la [Guía Paso a Paso para configurar tu Tutor Local de IA](ai/tutor/GUIA_PASO_A_PASO.md)**.

---

## 🛠️ Cómo Ejecutar los Laboratorios

Todos los laboratorios incluyen demostraciones didácticas automatizadas (`demo_*.sh`):
- **Agnósticos y Seguros:** En entornos locales o WSL2 utilizan discos virtuales *loop* (`/dev/loopX`) para no comprometer el almacenamiento de tu equipo.
- **Pausas Didácticas:** Permiten avanzar paso a paso con preguntas y respuestas para clase en vivo.
- **Limpieza Garantizada:** Al presionar `Ctrl+C` o terminar, un handler `trap` desmonta y libera automáticamente todos los recursos.

```bash
# Ejemplo: Clonar y correr el laboratorio de diagnóstico y mantenimiento de volúmenes
git clone https://github.com/villadalmine/labs.git
cd labs/linux/administrator/filesystems
sudo ./demo_mantenimiento_volumenes.sh
```

---

## 📄 Licencia

Este proyecto está bajo la Licencia GPL v3. Consultá el archivo [`LICENSE`](LICENSE) para más detalles.
