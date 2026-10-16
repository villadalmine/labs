# Laboratorios de Administración de Linux

Repositorio de prácticas de laboratorio, guías paso a paso y scripts interactivos para clases de Administración de Servidores Linux.

---

## Estructura de Módulos

```text
linux/administrator/
├── nice/                     # Prioridad y consumo de CPU con nice, renice y CFS
│   ├── nice.md               # Guía conceptual con pesos CFS y afinidad taskset
│   ├── demo_nice.sh          # Script interactivo paso a paso para la clase
│   └── cpu_worker.c          # Proceso en C para pruebas de carga y señales
│
├── storage/                  # Gestión de almacenamiento con LVM2 y Loop Devices
│   ├── lab_storage.md        # Guía de laboratorio de LVM y extensión en caliente
│   ├── demo_lab_storage.sh   # Script interactivo de LVM y resize2fs online
│   ├── lab_storage.sh        # Script automatizado tradicional
│   ├── lab_storage_paso_a_paso.md
│   └── lab_storage_simple.md
│
├── luks/                     # Cifrado de dispositivos de bloques (dm-crypt)
│   ├── luks.md               # Guía de LUKS con loop device y partición real
│   └── demo_luks.sh          # Script interactivo con demostración forense
│
├── gocryptfs/                # Cifrado FUSE a nivel de directorios
│   └── gocryptfs.md          # Guía práctica de gocryptfs
│
├── borg/                     # Copias de seguridad, deduplicación y retención
│   ├── borg.md               # Guía básica de BorgBackup y montaje FUSE
│   ├── borg-con-systemd-timers.md # Automatización segura con systemd timers
│   └── demo_borg.sh          # Script interactivo con deduplicación y desastre
│
├── procesos/                 # Gestión de procesos, jobs y señales
│   ├── jobs-fg-bg-nohup-setsid.md # Control de trabajos y terminales
│   └── proceso_zombie.md     # Diagnóstico y ciclo de vida de procesos zombies
│
├── systemd/                  # Automatización moderna y control de recursos
│   ├── systemd-cgroups.md    # Límites de CPU y memoria con cgroups v2
│   ├── systemd-memlogger.md  # Monitores periódicos con oneshot y timers
│   └── systemd-scoket.md     # Activación por socket bajo demanda
│
└── trabajo_integrador/       # PROYECTO FINAL INTEGRADOR (AWS Free Tier)
    ├── trabajo_integrador.md # Guía completa paso a paso para dar en clase
    └── terraform/            # Código IaC para levantar 2 EC2 Ubuntu + 3 discos EBS
        ├── main.tf
        ├── variables.tf
        ├── providers.tf
        ├── outputs.tf
        └── README.md
```

---

## Cómo usar los scripts interactivos en clase

Cada módulo cuenta con un script interactivo (`demo_*.sh`) diseñado específicamente para proyectar en el aula o compartir pantalla:
1. **Pausa manual con `[ENTER]`:** Permite al docente dar la explicación teórica a su ritmo antes de ejecutar cada comando.
2. **Soporte para `tmux`:** Activa automáticamente el scroll con la rueda del ratón.
3. **Modo automático (`--auto <segundos>`):** Avanza de forma autónoma con pausas temporizadas si se prefiere.
4. **Limpieza garantizada (`trap`):** Al finalizar o presionar `Ctrl+C`, desmonta y limpia todos los recursos temporales.
