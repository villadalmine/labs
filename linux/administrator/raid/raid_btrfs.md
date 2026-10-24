---
id: lab-3.10-raid-btrfs
title: 'RAID con Btrfs: Perfiles Data/Metadata, Conversión en Vivo, Self-Healing, Scrub
  y btrfs replace'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.10'
sections:
- '3.10'
- '3'
category: storage
tags:
- storage
- raid
- btrfs
- cow
- self-healing
- bitrot
- checksum
- scrub
- replace
- balance
- subvolumes
- loop-devices
tools:
- btrfs
- mkfs.btrfs
- losetup
- dd
- sha256sum
- sync
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Probado con loop devices sobre archivos sparse. Requiere soporte de kernel para
    btrfs.
environments:
- WSL2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Guía técnica avanzada de administración de RAID integrado en el sistema de archivos
  Btrfs. Explica el modelo Copy-on-Write a nivel de chunks, la separación independiente
  de perfiles para datos (-d) y metadatos (-m), la tolerancia a discos de tamaños asimétricos
  en RAID 1, la advertencia del write-hole en RAID 5/6, la detección y auto-reparación
  silenciosa de bit-rot mediante checksums criptográficos (self-healing), auditorías
  proactivas con btrfs scrub y la sustitución atómica de discos defectuosos con btrfs replace.
files:
  guide: raid/raid_btrfs.md
  script: raid/demo_raid_btrfs.sh
  terraform: null
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
prerequisites:
- lab-3.7-raid-teoria-comparativa
- lab-3.8-raid-mdadm
- lab-3.9-raid-lvm
next_recommended_labs:
- lab-3.11-raid-zfs
mcp_tools:
- linux-labs-tutor
- bash
---

# Lab 3.10 · RAID con Btrfs: Perfiles, Conversión en Vivo, Self-Healing y Reemplazo

> **Serie RAID (de fácil a difícil):** 3.7 Teoría → 3.8 mdadm → 3.9 LVM RAID → **3.10 Btrfs** → 3.11 ZFS → 4.5 Integrador AWS con fallas, recuperación y métricas.

**Objetivo:** dominar la arquitectura de RAID integrado a nivel de sistema de archivos con **Btrfs**. Aprenderás cómo Btrfs gestiona de manera independiente los perfiles de datos (`Data`) y metadatos (`Metadata`), cómo convertir un disco simple a un arreglo RAID 1 en caliente mediante `btrfs balance`, cómo funciona el mecanismo de **Self-Healing** (auto-curación por checksums ante fallos de *bit rot* silenciosos) y cómo reemplazar discos dañados en línea con `btrfs replace`.

**Requisitos:** permisos de `sudo`/root y herramientas `btrfs-progs`. Compatible con WSL2 (con kernel que soporte btrfs), VMs de Ubuntu en VirtualBox y servidores Linux.

---

## 1. Arquitectura: La revolución del RAID a nivel de Filesystem

En los arreglos tradicionales (`mdadm`, RAID por hardware o LVM `dm-raid`), el subsistema RAID es **completamente ciego al contenido**: no sabe qué bloques contienen archivos reales, cuáles son metadatos y cuáles están vacíos. Además:
- Exigen que los discos sean del mismo tamaño (o se desperdicia espacio).
- No pueden detectar si un bloque se alteró silenciosamente (*silent data corruption* / *bit rot*).

**Btrfs (B-tree File System)** fusiona el gestor de almacenamiento y el sistema de archivos:

```
  ┌────────────────────────────────────────────────────────┐
  │                 SISTEMA DE ARCHIVOS BTRFS              │
  │     Archivos, Subvolúmenes (@app, @data), Snapshots    │
  ├────────────────────────────────────────────────────────┤
  │                 ÁRBOL DE CHUNKS Y CHECKSUMS            │
  │   Cada bloque de 4 KiB tiene su hash CRC32C o XXHASH   │
  ├────────────────────────────┬───────────────────────────┤
  │    PERFIL METADATA (RAID1) │     PERFIL DATA (RAID1)   │
  │     2 copias garantizadas  │    2 copias garantizadas  │
  ├────────────────────────────┴───────────────────────────┤
  │                POOL DE DISCOS HETEROGÉNEOS             │
  │     Disco 1 (250 GB)   Disco 2 (500 GB)   Disco 3 (1 TB)│
  └────────────────────────────────────────────────────────┘
```

### 1.1 ¿Qué significa realmente RAID 1 en Btrfs?

> ⚠️ **Concepto clave:** En Btrfs, **RAID 1 NO significa duplicar discos completos de igual capacidad**.
> Significa: **"Para cada chunk de datos, guardar 2 copias en 2 dispositivos físicos distintos"**.

Esto permite combinar discos de capacidades desiguales sin perder espacio útil:
Si tenés discos de **1 TB, 2 TB y 3 TB**, Btrfs asigna cada par de copias en los dos discos que tengan más espacio libre en ese instante, logrando una capacidad útil de **3 TB en RAID 1** sin desperdiciar nada.

### 1.2 La advertencia de RAID 5 y 6 en Btrfs

Btrfs soporta `raid5` y `raid6`, pero el código actual aún posee vulnerabilidades ante el **write-hole** en caso de caídas de tensión bruscas combinadas con fallos de lectura.
- **Producción recomendada:** `raid1`, `raid1c3` (3 copias), `raid10`, `dup` (metadatos duplicados en un solo disco) o `single`.
- **RAID 5/6:** Reservado para experimentación o reemplazado por ZFS RAIDZ.

---

## 2. Preparación del Laboratorio (WSL2 / Linux)

Creamos 3 loop devices de 256 MiB para simular los discos:

```bash
sudo mkdir -p /tmp/raidlab
cd /tmp/raidlab

# Cargar soporte de kernel
sudo modprobe btrfs 2>/dev/null || true

# Crear 3 discos sparse
for i in {1..3}; do
    sudo truncate -s 256M "disk_btrfs${i}.img"
    sudo losetup -f --show "disk_btrfs${i}.img"
done

# Verificar
lsblk | grep disk_btrfs
```

---

## 3. Creación Inicial en Disco Simple y Separación de Perfiles

Formateamos únicamente el primer disco (`/dev/loop0`) y montamos el sistema de archivos:

```bash
sudo mkfs.btrfs -f -L btrfslab /dev/loop0
sudo mkdir -p /mnt/raidlab_btrfs
sudo mount /dev/loop0 /mnt/raidlab_btrfs

# Escribir 25 MiB de datos y registrar su hash SHA-256
sudo dd if=/dev/urandom of=/mnt/raidlab_btrfs/archivo_importante.txt bs=1M count=25 status=none
sha256sum /mnt/raidlab_btrfs/archivo_importante.txt | tee /tmp/sha_btrfs.txt
```

### Inspección de Asignación de Bloques
```bash
sudo btrfs filesystem df /mnt/raidlab_btrfs
sudo btrfs filesystem usage /mnt/raidlab_btrfs
```

Notarás que Btrfs separa:
- **Data:** `single` (1 copia).
- **Metadata:** `dup` (duplicada en el mismo disco para prevenir pérdida de estructura).
- **System:** `dup`.

---

## 4. Conversión en Caliente a RAID 1 (Online Balance)

No necesitás desmontar el disco ni reiniciar el sistema. Sumamos el segundo disco (`/dev/loop1`) y convertimos en caliente:

```bash
# 1. Sumar el segundo disco al pool del filesystem
sudo btrfs device add -f /dev/loop1 /mnt/raidlab_btrfs

# 2. Inspeccionar dispositivos asociados
sudo btrfs filesystem show /mnt/raidlab_btrfs

# 3. Rebalancear y convertir simultáneamente Data y Metadata a RAID 1
sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/raidlab_btrfs

# 4. Verificar el nuevo perfil activo
sudo btrfs filesystem df /mnt/raidlab_btrfs
```

Salida esperada:
```
Data, RAID1: total=64.00MiB, used=25.00MiB
System, RAID1: total=32.00MiB, used=16.00KiB
Metadata, RAID1: total=64.00MiB, used=144.00KiB
GlobalReserve, single: total=5.50MiB, used=0.00B
```
¡Todo el sistema de archivos se convirtió a RAID 1 en vivo mientras los datos seguían accesibles!

---

## 5. El Gran Diferencial: Self-Healing frente a Bit-Rot

¿Qué pasa si un sector magnético o una celda flash se degrada físicamente y un bit se daña silenciosamente (*silent bit rot*)?
- En `mdadm` o LVM: el kernel lee ese bloque corrupto y se lo entrega a la aplicación (base de datos corrupta sin enterarte).
- En **Btrfs**: el kernel calcula el hash criptográfico del bloque leído, detecta que no coincide con el guardado en el árbol de metadatos, lee automáticamente la copia sana del otro disco, **entrega el dato correcto y reescribe silenciosamente el bloque malo** (*self-healing*).

### Demostración Práctica de Corrupción Inducida
```bash
# Sincronizar buffers
sudo sync

# Inyectar bytes basura directamente sobre el sector físico de /dev/loop0
sudo dd if=/dev/urandom of=/dev/loop0 bs=4k count=1 seek=12000 conv=notrunc status=none
sudo sync

# Leer el archivo y calcular el hash SHA-256
sha256sum /mnt/raidlab_btrfs/archivo_importante.txt
cat /tmp/sha_btrfs.txt
```

¡El hash sigue siendo 100% idéntico!

### Inspección del Registro de Corrección Forense
```bash
sudo btrfs device stats /mnt/raidlab_btrfs
```
Verás:
- `corruption_errs`: Contador incrementado (detectó la corrupción).
- `read_io_errs`: 0 (el disco respondió, pero con datos falsos).
- `dmesg | grep -i btrfs`: Mensaje del kernel informando la auto-reparación transparente.

---

## 6. Auditoría Proactiva de Consistencia con Scrub

Para no esperar a que una aplicación lea un bloque dañado, los administradores ejecutan tareas periódicas de **scrubbing**:

```bash
# Iniciar auditoría completa en primer plano (-B)
sudo btrfs scrub start -B -d /mnt/raidlab_btrfs

# Consultar el reporte final
sudo btrfs scrub status /mnt/raidlab_btrfs
```

El scrub lee cada bloque, recalcula el checksum y repara cualquier anomalía contra las copias redundantes.

---

## 7. Falla de Disco y Reemplazo en Caliente con `btrfs replace`

Vamos a destruir intencionalmente el disco `/dev/loop1`:

```bash
# Sobrescribir el disco 2 simulando muerte total
sudo dd if=/dev/zero of=/dev/loop1 bs=1M count=50 conv=notrunc status=none
sudo sync
```

El sistema sigue funcionando y los datos siguen accesibles. Para reemplazar la unidad defectuosa por el disco nuevo (`/dev/loop2`):

```bash
# Ejecutar reemplazo en caliente (dispositivo con devid 2 reemplazado por /dev/loop2)
sudo btrfs replace start -B -f 2 /dev/loop2 /mnt/raidlab_btrfs

# Verificar estado final
sudo btrfs replace status /mnt/raidlab_btrfs
sudo btrfs filesystem show /mnt/raidlab_btrfs
```

A diferencia de `mdadm --add` (que reconstruye el disco físico completo de principio a fin), `btrfs replace` **solo copia los chunks que realmente contienen datos**, completando el proceso en una fracción mínima de tiempo.

---

## 8. Script Automatizado

Probá todo este laboratorio con un solo comando:

```bash
cd linux/administrator/raid
chmod +x demo_raid_btrfs.sh

# Interactivo
sudo ./demo_raid_btrfs.sh

# Automático
sudo ./demo_raid_btrfs.sh --auto 3
```

---

## 9. Ejercicios Prácticos

1. **¿Por qué Btrfs puede armar un RAID 1 con un disco de 500 GB, uno de 1 TB y uno de 2 TB sin desperdiciar almacenamiento?**
2. **¿Cuál es el riesgo del "write-hole" en Btrfs con perfiles RAID 5/6 y por qué no afecta a RAID 1?**
3. **¿Qué diferencia existe entre `btrfs device remove` y `btrfs replace`?**
4. **Si un archivo se corrompe en un filesystem Btrfs montado en modo `single` (un solo disco), ¿qué ocurre cuando una aplicación intenta leerlo?**

<details><summary>Ver Respuestas Comentadas</summary>

1. Porque no espeja discos completos, sino **chunks individuales** (de 1 GB). En cada asignación, Btrfs busca los dos discos con mayor capacidad disponible y aloja allí las dos copias.
2. En RAID 5/6, una caída de corriente durante la actualización de un chunk y su bloque de paridad puede dejar una franja desincronizada. En RAID 1, cada copia es autosuficiente y cuenta con su propio checksum; no depende de un cálculo matemático entre terceros discos.
3. `device remove` rebalancea todos los datos del disco saliente repartiéndolos entre los demás discos sobrevivientes del pool. `replace` es una operación punto a punto: transfiere directamente los bloques del disco origen al nuevo disco de destino de forma atómica y mucho más rápida.
4. Btrfs detecta el error de checksum al leer el bloque y, al no tener una copia redundante alternativa para reparar, **aborta la lectura y devuelve un error de I/O (`EIO`)** a la aplicación. Esto evita que la aplicación consuma datos corruptos en silencio.
</details>

---

## 10. Qué sigue

➡️ **Lab 3.11 · [RAID con ZFS (OpenZFS)](raid_zfs.md)** — Almacenamiento empresarial crítico: pools, vdevs, RAIDZ sin write-hole, memoria ARC y cachés SLOG/L2ARC.
