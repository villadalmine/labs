---
id: lab-3.8-raid-mdadm
title: 'RAID con mdadm: Creación de Arreglos, Metadatos, Bitmaps, Degradación y Recuperación
  en Caliente'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.8'
sections:
- '3.8'
- '3'
category: storage
tags:
- storage
- raid
- mdadm
- raid0
- raid1
- raid5
- raid6
- raid10
- hot-spare
- rebuild
- resync
- scrub
- superbloque
- bitmap
- loop-devices
tools:
- mdadm
- losetup
- lsblk
- mkfs.ext4
- dd
- sha256sum
- cat
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
  notes: Probado con loop devices sobre archivos sparse. Requiere modprobe md_mod
    raid1 raid456.
environments:
- WSL2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Guía práctica completa de administración de RAID por software en Linux
  con mdadm. Explica la arquitectura del subsistema md en el kernel, formatos de superbloque
  (1.2), gestión de write-intent bitmaps para evitar resyncs completos, creación de
  arreglos RAID 0/1/5/6/10, aprovisionamiento de hot spares, inyección de fallas en
  vivo, reconstrucción de datos transparente con paridad XOR, reemplazo de unidades
  y auditoría de paridad con scrub manual.
files:
  guide: raid/raid_mdadm.md
  script: raid/demo_raid_mdadm.sh
  terraform: null
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
prerequisites:
- lab-3.7-raid-teoria-comparativa
- lab-3.1-anatomia-filesystems
next_recommended_labs:
- lab-3.9-raid-lvm
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Lab 3.8 · RAID con mdadm: Arreglos, Metadatos, Bitmaps y Recuperación en Caliente

> **Serie RAID (de fácil a difícil):** 3.7 Teoría → **3.8 mdadm** → 3.9 LVM RAID → 3.10 Btrfs → 3.11 ZFS → 4.5 Integrador AWS con fallas, recuperación y métricas.

**Objetivo:** dominar la herramienta estándar de facto de RAID por software en Linux (`mdadm`). Aprenderás a crear arreglos de distintos niveles, inspeccionar metadatos (superbloques), configurar **write-intent bitmaps**, simular la rotura de un disco, verificar la integridad de los datos en caliente, observar la reconstrucción automática con **hot spare**, sustituir unidades y auditar la paridad con **scrub**.

**Requisitos:** permisos de `sudo`/root y soporte del módulo `md_mod` en el kernel Linux (incluido por defecto en Ubuntu Server, Debian y kernels estándar; en WSL2 se usan loop devices).

---

## 1. Arquitectura de mdadm y el subsistema `md`

En Linux, el subsistema **Multiple Device (`md`)** vive en el espacio del kernel (`drivers/md/`). La utilidad `mdadm` en espacio de usuario es el panel de control que programa y monitorea los dispositivos lógicos `/dev/mdX`.

```
  Espacio de Usuario:             mdadm, mkfs.ext4, monitoreo (/proc/mdstat)
                                          │  (ioctl / sysfs)
  Kernel Linux:                  Dispositivo de Bloque Virtual (/dev/md100)
                                          │
                            Subsistema MD (Personalidad raid5/raid1)
                            ┌─────────────┴─────────────┐
                    Cálculo XOR/Reed-Solomon     Write-Intent Bitmap
                            │                           │
  Capa de Bloques:    /dev/loop0     /dev/loop1     /dev/loop2     /dev/loop3 (Spare)
```

### 1.1 Versiones de Superbloque (Metadatos)

El superbloque contiene el UUID del arreglo, el rol del disco dentro del array, contadores de eventos y el nivel de paridad.

| Formato | Posición en el disco | Ventajas / Inconvenientes |
| :--- | :--- | :--- |
| **0.90** | Al final del dispositivo | Máximo 28 discos por arreglo. El inicio del disco parece un FS crudo (peligroso). Obsoleto. |
| **1.0** | Al final del disco | Permite que `/boot` arranque con bootloaders muy viejos sin driver RAID. |
| **1.1** | Al inicio del disco (offset 0) | Puede chocar con tablas de partición MBR/GPT. |
| **1.2 (por defecto)** | A 4 KiB del inicio del disco | No colisiona con tablas de partición ni firmas de arranque. Es el estándar moderno de producción. |

> 💡 **Regla de oro:** Cuando vayas a reutilizar un disco que perteneció a un arreglo RAID, ejecutá siempre:
> ```bash
> sudo mdadm --zero-superblock /dev/sdX
> sudo wipefs -a /dev/sdX
> ```
> De lo contrario, `systemd-udevd` intentará ensamblar arreglos fantasmas al bootear.

### 1.2 El Write-Intent Bitmap: Salvación tras un corte eléctrico

Cuando se escribe en RAID 1 o RAID 5/6, actualizar el dato y la paridad toma varias operaciones de disco. Si el servidor se apaga abruptamente:
- **Sin bitmap:** El kernel no sabe qué sectores estaban a mitad de escritura. Debe escanear y resincronizar el **100% de la capacidad de todos los discos** (en arreglos de 10 TB, esto puede tardar 20 horas).
- **Con bitmap (`--bitmap=internal`):** El kernel divide el disco en chunks lógicos (ej. 64 MiB) y mantiene un mapa de bits en el superbloque. Antes de escribir en un chunk, marca su bit en `1`. Al terminar, lo vuelve a `0`. Tras un reinicio forzado, solo resincroniza los chunks marcados con `1` (demora **segundos**).

> 📖 **Glosario Técnico:** Consulta el [análisis detallado del Write-Intent Bitmap en el Glosario](../GLOSARIO.md#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura) para conocer la analogía del "post-it en la enciclopedia", el impacto en rendimiento y su comparativa frente a ZFS y Btrfs.

---

## 2. Preparación del Laboratorio (WSL2 / Linux)

No necesitás discos físicos adicionales. Usamos **archivos sparse** (que no ocupan espacio real en disco hasta que se escriben) vinculados a **loop devices** (`/dev/loopX`).

```bash
# 1. Crear directorio de trabajo
sudo mkdir -p /tmp/raidlab
cd /tmp/raidlab

# 2. Cargar módulos del kernel
sudo modprobe md_mod raid0 raid1 raid456 raid10

# 3. Crear 6 imágenes de disco de 256 MiB (sparse)
for i in {1..6}; do
    sudo truncate -s 256M "disk${i}.img"
    sudo losetup -f --show "disk${i}.img"
done

# 4. Verificar los loop devices asignados
lsblk -o NAME,SIZE,TYPE,BACKING-FILE | grep raidlab
```

---

## 3. Tour Rápido de Niveles de RAID

Veamos cómo `mdadm` crea y dimensiona la capacidad de cada nivel con discos de 256 MiB:

```bash
# RAID 0 (Striping - 2 discos) -> Capacidad: 256 + 256 = ~512 MiB
sudo mdadm --create /dev/md101 --run --level=0 --raid-devices=2 /dev/loop0 /dev/loop1
blockdev --getsize64 /dev/md101
sudo mdadm --stop /dev/md101

# RAID 1 (Espejo - 2 discos) -> Capacidad: 256 MiB
sudo mdadm --create /dev/md102 --run --level=1 --raid-devices=2 /dev/loop0 /dev/loop1
sudo mdadm --stop /dev/md102

# RAID 5 (Paridad simple - 3 discos) -> Capacidad: (3 - 1) * 256 = ~512 MiB
sudo mdadm --create /dev/md103 --run --level=5 --raid-devices=3 /dev/loop0 /dev/loop1 /dev/loop2
sudo mdadm --stop /dev/md103

# RAID 6 (Doble paridad - 4 discos) -> Capacidad: (4 - 2) * 256 = ~512 MiB
sudo mdadm --create /dev/md104 --run --level=6 --raid-devices=4 /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3
sudo mdadm --stop /dev/md104

# Limpiar superbloques tras la prueba rápida
sudo mdadm --zero-superblock /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3
```

---

## 4. Laboratorio Principal: RAID 5 + Hot Spare + Bitmap

Vamos a armar un arreglo de producción real: 3 discos activos + 1 disco de repuesto en caliente (*Hot Spare*).

### Paso 1: Creación del Arreglo
```bash
sudo mdadm --create /dev/md100 \
    --run \
    --level=5 \
    --raid-devices=3 \
    --spare-devices=1 \
    --bitmap=internal \
    --name=labraid \
    /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3
```

### Paso 2: Observación de Sincronización Inicial
```bash
# Inspeccionar estado inmediato
cat /proc/mdstat

# Esperar a que culmine la sincronización
sudo mdadm --wait /dev/md100
```

### Paso 3: Formato y Montaje con Datos Críticos
```bash
sudo mkfs.ext4 -q -L raidlab /dev/md100
sudo mkdir -p /mnt/raidlab_md
sudo mount /dev/md100 /mnt/raidlab_md

# Escribir 30 MiB de datos pseudo-aleatorios y calcular su hash SHA-256
sudo dd if=/dev/urandom of=/mnt/raidlab_md/datos.bin bs=1M count=30 status=none
sha256sum /mnt/raidlab_md/datos.bin | tee /tmp/original_sha256.txt

df -h /mnt/raidlab_md
```

---

## 5. Inspección Forense: Superbloque y Bitmap

```bash
# 1. Visión global del arreglo
sudo mdadm --detail /dev/md100

# 2. Visión del disco individual (metadatos 1.2)
sudo mdadm --examine /dev/loop0

# 3. Inspección del write-intent bitmap
sudo mdadm --examine-bitmap /dev/loop0
```

En la salida de `--detail` notarás:
- `State : clean`
- `Active Devices : 3`
- `Working Devices : 4`
- `Spare Devices : 1`

---

## 6. Simulación de Falla y Reconstrucción Automática

Vamos a declarar deliberadamente que el disco `/dev/loop1` falló (`--fail`).

```bash
# 1. Romper el disco 1
sudo mdadm /dev/md100 --fail /dev/loop1

# 2. Consultar el estado en tiempo real
cat /proc/mdstat
```

Verás algo fascinante:
```
md100 : active raid5 loop3[3] loop1[4](F) loop2[2] loop0[0]
      522240 blocks super 1.2 level 5, 512k chunk, algorithm 2 [3/2] [U_U]
      [===>.................]  recovery = 18.2% (47616/261120) finish=0.1min speed=23808K/sec
```

1. El disco `loop1` queda marcado con `(F)` (*Faulty*).
2. El arreglo pasa a estado degradado temporal `[U_U]` (Up, Down, Up).
3. **El hot spare `loop3` entra automáticamente en acción** e inicia el proceso de **recovery** (reconstrucción por paridad).
4. **Verificación de disponibilidad:** En pleno proceso de degradación y reconstrucción, leé los datos y validá el hash:
   ```bash
   sha256sum /mnt/raidlab_md/datos.bin
   cat /tmp/original_sha256.txt
   ```
   ¡El hash es idéntico! El usuario nunca notó la rotura de hardware.

Esperá a que culmine la reconstrucción:
```bash
sudo mdadm --wait /dev/md100
cat /proc/mdstat
```
El arreglo vuelve a estar sano `[UUU]`.

---

## 7. Reemplazo del Disco Muerto por una Unidad Nueva

El disco roto (`/dev/loop1`) sigue asociado al arreglo en estado fallido. El procedimiento de sustitución física es:

```bash
# 1. Expulsar el disco dañado del arreglo
sudo mdadm /dev/md100 --remove /dev/loop1

# 2. Crear un nuevo disco (simulando que el técnico insertó un disco nuevo)
sudo truncate -s 256M /tmp/raidlab/disk_nuevo.img
NUEVO_DEV=$(sudo losetup -f --show /tmp/raidlab/disk_nuevo.img)

# 3. Insertar el nuevo disco como repuesto
sudo mdadm /dev/md100 --add "$NUEVO_DEV"

# 4. Verificar que vuelve a figurar 1 Spare Device disponible
sudo mdadm --detail /dev/md100 | grep -E "Active Devices|Spare Devices|State :"
```

---

## 8. Verificación de Integridad de Paridad: Scrubbing

En entornos de producción, discos giratorios o SSDs pueden sufrir alteraciones silenciosas (*latent sector errors*). El comando **scrub** lee todos los bloques de datos, recalcula la paridad y la compara con el bloque de paridad almacenado.

```bash
# Iniciar auditoría de paridad
echo check | sudo tee /sys/block/md100/md/sync_action

# Monitorear avance
cat /proc/mdstat

# Esperar a que finalice
sudo mdadm --wait /dev/md100

# Consultar discrepancias detectadas
cat /sys/block/md100/md/mismatch_cnt
```

> 🎯 Si `mismatch_cnt` es `0`, la paridad de todo el arreglo es 100% matemáticamente consistente.

---

## 9. Persistencia de Configuración para Producción

Para que Linux ensamble el arreglo automáticamente durante el arranque del sistema (`initramfs` y `systemd`):

```bash
# 1. Escanear y guardar la firma UUID en el archivo de configuración
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf

# 2. Actualizar la imagen del initramfs
sudo update-initramfs -u
```

---

## 10. Script Automatizado

Podés ejecutar todo este ciclo de aprendizaje de forma asistida o desatendida mediante el script provisto:

```bash
cd linux/administrator/raid
chmod +x demo_raid_mdadm.sh common.sh

# Modo interactivo (pausa en cada paso con explicaciones)
sudo ./demo_raid_mdadm.sh

# Modo automático (3 segundos por paso)
sudo ./demo_raid_mdadm.sh --auto 3
```

---

## 11. Ejercicios Prácticos de Autoevaluación

1. **¿Qué diferencia operativa existe entre `mdadm --stop` y `mdadm --zero-superblock`?**
2. **Si se rompen 2 discos al mismo tiempo en un RAID 5 de 4 discos, ¿los datos se pueden recuperar con mdadm?**
3. **¿Por qué el write-intent bitmap acelera el resync tras un corte de luz pero puede reducir levemente la velocidad de escritura secuencial pico?**
4. **Si tenés un RAID 1 de 2 discos de 1 TB y le agregás un tercer disco de 1 TB con `mdadm --add`, ¿se convierte en RAID 5 automáticamente?**

<details><summary>Ver Respuestas Comentadas</summary>

1. `--stop` detiene la actividad del arreglo en el kernel y libera el dispositivo `/dev/mdX`, pero **mantiene los metadatos intactos** en los discos (se puede volver a ensamblar con `mdadm --assemble`). `--zero-superblock` **borra definitivamente la cabecera de metadatos**, convirtiendo el disco en un medio en blanco.
2. **No.** RAID 5 utiliza una única ecuación de paridad XOR ($N-1$). Con 2 discos caídos hay 2 incógnitas, por lo que el sistema no tiene suficientes datos matemáticos para reconstruir. Se requeriría RAID 6 (con código Reed-Solomon Q).
3. Porque antes de modificar cualquier bloque de datos, el kernel debe realizar una escritura síncrona en el superbloque para marcar el bit correspondiente en `1`. Esa pequeña sobrecarga de I/O de metadatos protege contra horas de resync posterior.
4. **No.** Se agrega como un segundo disco espejo (3 copias idénticas) o como un hot spare. Para transformar un nivel de RAID en otro en caliente se requiere el comando `--grow --level=5`.
</details>

---

## 12. Qué sigue

➡️ **Lab 3.9 · [RAID con LVM (`dm-raid`)](raid_lvm.md)** — Combinando la flexibilidad de Logical Volume Manager con la resiliencia de paridad y espejos.
