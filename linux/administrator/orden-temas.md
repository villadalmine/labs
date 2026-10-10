# Ruta de lectura: administración Linux

Esta guía indica qué archivos leer y en qué orden. El recorrido parte de observar el sistema, sigue con procesos y systemd, y después pasa a almacenamiento, cifrado y backups. La referencia LPIC-1 aparece al final, solo para ubicar la cobertura de certificación.

## 1. Observar antes de intervenir

1. Leé [uptime.md](uptime.md) para interpretar tiempo encendido, load average y sus datos en `/proc`.
2. Seguí con [tools-stats.md](tools-stats.md): compara CPU, memoria, disco, red y procesos con herramientas de consulta.

**Idea para conectar:** `uptime` resume el estado; las otras herramientas ayudan a investigar qué proceso o recurso explica ese estado.

## 2. Entender los procesos

1. Leé la sección de procesos de [guia_discos_procesos.md](guia_discos_procesos.md): `ps`, PID/PPID, consumo y árbol de procesos.
2. Usá [compilar.md](compilar.md) como introducción a compilar y ejecutar un programa.
3. Seguí con [proceso_zombie.md](proceso_zombie.md): creación de un hijo, señales, `wait()` y estado zombie.
4. Leé [jobs-fg-bg-nohup-setsid.md](jobs-fg-bg-nohup-setsid.md): trabajos de la shell, primer/segundo plano, sesión, hangup y reconexión.

**Idea para conectar:** primero identificás un proceso; después entendés quién lo creó, cómo controlarlo y qué cambia al separarlo de la terminal.

## 3. Observar y controlar el uso de CPU

1. Leé [nice.md](nice.md): comparar valores nice en competencia, observar `NI` y `%CPU`, cambiar prioridad con `renice` y fijar afinidad con `taskset`.
2. Después de entender la prioridad de un proceso, leé [systemd-cgroups.md](systemd-cgroups.md): limitar CPU de una unidad y observarla con `systemd-cgls`, `/proc/<PID>/cgroup` y `/sys/fs/cgroup`.

**Idea para conectar:** `nice` influye en la prioridad relativa del proceso; la cuota de systemd limita el consumo del grupo. No son controles equivalentes.

## 4. Aprender systemd desde un servicio

1. Leé [systemd-memlogger.md](systemd-memlogger.md) para seguir el ciclo de una unidad: crear, recargar, iniciar, consultar estado y revisar Journal.
2. Como ampliación, usá [systemd-scoket.md](systemd-scoket.md) para ver activación por socket y una unidad `.mount`.

**Idea para conectar:** systemd administra procesos fuera de la tabla de trabajos de una shell; la unidad define su ciclo de vida y el Journal recoge su salida.

## 5. Pasar de archivos a almacenamiento

1. Leé la sección de discos de [guia_discos_procesos.md](guia_discos_procesos.md): dispositivos, filesystems, `lsblk`, `df` y `du`.
2. Hacé [lab_storage_simple.md](lab_storage_simple.md): archivo → loop device → ext4 → montaje → desmontaje.
3. Luego hacé [lab_storage_paso_a_paso.md](lab_storage_paso_a_paso.md) a mano para agregar PV, VG y LV, y ampliar el filesystem.
4. Cuando entiendas los comandos, compará el recorrido manual con la versión automatizada de [lab_storage.md](lab_storage.md) y [lab_storage.sh](lab_storage.sh).

**Idea para conectar:** primero comprendés el filesystem y el montaje; después agregás la capa de administración LVM. Usá archivos de prueba en una VM, no discos con datos.

## 6. Cifrado y copias de seguridad

1. Leé [luks.md](luks.md) como práctica de cifrado de bloques sobre un loop device.
2. Compará ese enfoque con [gocryptfs.md](gocryptfs.md), que cifra archivos y nombres dentro de un directorio.
3. Leé [borg.md](borg.md) y probá crear e inspeccionar un backup manual.
4. Al final, seguí [borg-con-systemd-timers.md](borg-con-systemd-timers.md) para automatizar el backup y consultar su estado y registros.

**Idea para conectar:** LUKS protege un dispositivo; gocryptfs trabaja a nivel de archivos; Borg crea copias recuperables. Primero se entiende y prueba el flujo manual, después se automatiza.

## 7. Extensiones

Estas prácticas amplían el recorrido principal; conviene hacerlas cuando ya se dominan sus conceptos base:

- [systemd-cgroups.md](systemd-cgroups.md): cuotas y jerarquía de CPU en cgroups v2.
- [systemd-scoket.md](systemd-scoket.md): activación bajo demanda y montaje con systemd.
- [lab_storage.md](lab_storage.md): comparación con el flujo LVM automatizado.
- [luks.md](luks.md) y [gocryptfs.md](gocryptfs.md): comparación de capas de cifrado.
- [borg-con-systemd-timers.md](borg-con-systemd-timers.md): automatización del backup manual.

## Referencia final: cobertura LPIC-1

Esta tabla sirve para ubicar lo leído frente a objetivos de LPIC-1; no dicta el recorrido local ni implica que cada guía cubra por completo un objetivo.

| Objetivo | Relación con las guías locales | Cobertura |
| --- | --- | --- |
| 103.5 — Crear, monitorizar y terminar procesos | `uptime.md`, `tools-stats.md`, `proceso_zombie.md`, `jobs-fg-bg-nohup-setsid.md` | Parcial; usar las guías como práctica de procesos y observación. |
| 103.6 — Modificar prioridades de ejecución | `nice.md` | Directa para `nice`/`renice`; `taskset` es una ampliación de afinidad. |
| 104.1 — Crear particiones y filesystems | `lab_storage_simple.md`, `lab_storage_paso_a_paso.md` | Parcial; loop/ext4 y LVM como práctica local. |
| 104.2 — Mantener la integridad de filesystems | `lab_storage_paso_a_paso.md` menciona `e2fsck` | Insuficiente; falta una guía específica de comprobación y reparación. |
| 104.3 — Controlar montaje y desmontaje | `lab_storage_simple.md`, `luks.md`, `systemd-scoket.md` | Parcial; incluye montaje de prueba, no todo el objetivo. |
| 107.2 — Automatizar tareas programadas | `borg-con-systemd-timers.md` | Parcial; se centra en timers de systemd. |
| 108.2 — Registro del sistema | `systemd-memlogger.md`, `borg-con-systemd-timers.md` | Parcial; lectura del Journal asociada a servicios. |
| 110.3 — Proteger datos con cifrado | `luks.md`, `gocryptfs.md` | No asumir equivalencia: estas guías son extensiones de cifrado de disco/archivos; el objetivo oficial incluye SSH y GPG. |

Para completar los huecos de certificación, contrastá esta referencia con los [objetivos oficiales de LPI para el examen 101](https://www.lpi.org/our-certifications/exam-101-objectives/) y el [examen 102](https://www.lpi.org/our-certifications/exam-102-objectives/).