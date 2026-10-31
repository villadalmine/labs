---
id: lab-3.9-raid-lvm
title: 'RAID con LVM (dm-raid): Espejos, Paridad, Sub-LVs _rmeta, Degradación y lvconvert
  --repair'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.9'
sections:
- '3.9'
- '3'
category: storage
tags:
- storage
- raid
- lvm
- dm-raid
- raid0
- raid1
- raid5
- raid6
- raid10
- rmeta
- rimage
- online-resize
- lvextend
- lvconvert
- vgreduce
- loop-devices
tools:
- lvm
- pvcreate
- vgcreate
- lvcreate
- lvconvert
- lvextend
- lvs
- vgs
- mkfs.ext4
- losetup
- dd
- sha256sum
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
  notes: Probado con loop devices. Requiere dm-mod y dm-raid.
environments:
- WSL2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Guía exhaustiva sobre la implementación de RAID por software en LVM2
  utilizando el target del kernel dm-raid. Detalla la arquitectura de sub-volúmenes
  lógicos internos (_rmeta para metadatos y write-intent bitmap, _rimage para franjas
  de datos), el aprovisionamiento de arreglos RAID 0/1/5/6/10, la expansión en caliente
  del sistema de archivos y el volumen con lvextend -r, la inyección forense de fallas
  sobre Physical Volumes, la degradación parcial y el flujo de sustitución y autorrecuperación
  en caliente con lvconvert --repair y vgreduce --removemissing.
files:
  guide: raid/raid_lvm.md
  script: raid/demo_raid_lvm.sh
  terraform: null
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
prerequisites:
- lab-3.7-raid-teoria-comparativa
- lab-3.8-raid-mdadm
- lab-3.2-lvm2-online-resize
next_recommended_labs:
- lab-3.10-raid-btrfs
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Lab 3.9 · RAID con LVM (dm-raid): Sub-LVs, Degradación y Recuperación en Caliente

> **Serie RAID (de fácil a difícil):** 3.7 Teoría → 3.8 mdadm → **3.9 LVM RAID** → 3.10 Btrfs → 3.11 ZFS → 4.5 Integrador AWS con fallas, recuperación y métricas.

**Objetivo:** comprender y operar la integración nativa entre **Logical Volume Manager (LVM2)** y el subsistema RAID del kernel Linux mediante el módulo `dm-raid`. Aprenderás cómo LVM estructura de forma invisible los sub-volúmenes de metadatos (`_rmeta`) y de datos (`_rimage`), cómo crear volúmenes espejados o con paridad, expandirlos en caliente (`online grow`), diagnosticar el fallo de un Physical Volume (PV) y restaurar la salud del arreglo en caliente mediante `lvconvert --repair`.

**Requisitos:** permisos de `sudo`/root y herramientas de `lvm2` instaladas. Funciona sobre loop devices tanto en WSL2, VMs de VirtualBox como servidores Linux físicos.

---

## 1. Arquitectura: ¿Por qué LVM RAID en lugar de mdadm simple?

Históricamente, los administradores de sistemas creaban arreglos con `mdadm` (por ejemplo `/dev/md0`) y luego sobre ese dispositivo creaban un PV de LVM (`pvcreate /dev/md0`). Aunque ese patrón sigue siendo válido, genera **dos capas de administración separadas**:
1. Para agrandar el disco hay que ejecutar `--grow` en `mdadm` y luego `pvresize` en LVM.
2. Todo el VG queda atado al mismo tipo de RAID.

A partir de LVM 2.02.87+, Linux introdujo **LVM RAID (`dm-raid`)**, que aprovecha el código maduro de paridad y espejos del kernel (`md_mod`), pero permitiendo que **cada Logical Volume individual elija su propio nivel de resiliencia**:

```
                 Volume Group Unificado (vg_datos)
  ┌───────────────────────┬───────────────────────┬───────────────────────┐
  │ lv_scratch (RAID 0)   │ lv_database (RAID 10) │ lv_backups (RAID 5)   │
  │ Striping sin paridad  │ Espejos de alta veloc │ Paridad distribuida   │
  └───────────────────────┴───────────────────────┴───────────────────────┘
                                   │
              Capa de Device-Mapper (dm-raid + dm-linear)
                                   │
  ┌──────────────┬─────────────────┼─────────────────┬────────────────────┐
  │ PV 1 (sdb)   │ PV 2 (sdc)      │ PV 3 (sdd)      │ PV 4 (sde)         │
  └──────────────┴─────────────────┴─────────────────┴────────────────────┘
```

### 1.1 La anatomía oculta: Sub-LVs `_rmeta` y `_rimage`

Cuando creás un Logical Volume RAID 5 con 3 discos, LVM2 no crea un único bloque continuo. En su lugar, descompone la operación en **pares de sub-volúmenes ocultos**:

```
  Logical Volume Visible:  /dev/vg_raidlab/lv_prod (RAID 5)
                                    │
           ┌────────────────────────┼────────────────────────┐
           ▼                        ▼                        ▼
       Disco PV 1               Disco PV 2               Disco PV 3
  ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
  │ lv_prod_rmeta_0  │     │ lv_prod_rmeta_1  │     │ lv_prod_rmeta_2  │
  │ (Superbloque/BM) │     │ (Superbloque/BM) │     │ (Superbloque/BM) │
  ├──────────────────┤     ├──────────────────┤     ├──────────────────┤
  │ lv_prod_rimage_0 │     │ lv_prod_rimage_1 │     │ lv_prod_rimage_2 │
  │ (Franja Datos/P) │     │ (Franja Datos/P) │     │ (Franja Datos/P) │
  └──────────────────┘     └──────────────────┘     └──────────────────┘
```

- **`_rmeta_X`:** Un pequeño Logical Volume (típicamente 1 Physical Extent = 4 MiB) dedicado a almacenar la cabecera del superbloque del kernel y el **write-intent bitmap**.
- **`_rimage_X`:** El Logical Volume que contiene los datos reales o la paridad XOR correspondiente a esa pata del arreglo.

> 📖 **Glosario Técnico:** Para comprender cómo gestiona LVM el mapa de bits dentro de los sub-LVs `_rmeta` y cómo evita resincronizaciones completas, consulta [Write-Intent Bitmap en el Glosario](../GLOSARIO.md#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura).

---

## 2. Preparación del Entorno

Configuramos 4 loop devices de 256 MiB para simular 4 discos independientes:

```bash
sudo mkdir -p /tmp/raidlab
cd /tmp/raidlab

# Asegurar módulos cargados
sudo modprobe dm_mod dm_raid raid0 raid1 raid456 raid10

# Crear 4 discos sparse de 256M
for i in {1..4}; do
    sudo truncate -s 256M "disk_lvm${i}.img"
    sudo losetup -f --show "disk_lvm${i}.img"
done

# Listar loop devices
lsblk | grep disk_lvm
```

---

## 3. Creación de PVs y Volume Group

Convertimos los 4 dispositivos en Physical Volumes e integramos todo en un Volume Group:

```bash
# Inicializar PVs
sudo pvcreate -y /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3

# Crear Volume Group
sudo vgcreate vg_raidlab /dev/loop0 /dev/loop1 /dev/loop2 /dev/loop3

# Inspeccionar espacio disponible
sudo vgs vg_raidlab
```

---

## 4. Tour de Niveles de RAID en LVM

LVM2 permite especificar el tipo de RAID mediante la opción `--type`:

```bash
# 1. RAID 0 (Striping puro - 2 discos, sin redundancia)
sudo lvcreate -y --type raid0 -L 100M -i 2 -n lv_test_r0 vg_raidlab /dev/loop0 /dev/loop1
sudo lvs -o name,vg_name,segtype,size,devices vg_raidlab/lv_test_r0
sudo lvremove -y vg_raidlab/lv_test_r0

# 2. RAID 1 (Espejo de 2 vías con metadata y bitmap automáticos)
sudo lvcreate -y --type raid1 -L 100M -m 1 -n lv_test_r1 vg_raidlab /dev/loop0 /dev/loop1
sudo lvs -o name,vg_name,segtype,size,devices vg_raidlab/lv_test_r1
sudo lvremove -y vg_raidlab/lv_test_r1

# 3. RAID 5 (Paridad simple rotativa - 2 franjas de datos + 1 paridad = 3 discos)
sudo lvcreate -y --type raid5 -L 200M -i 2 -n lv_test_r5 vg_raidlab /dev/loop0 /dev/loop1 /dev/loop2
sudo lvs -o name,vg_name,segtype,size,devices vg_raidlab/lv_test_r5
sudo lvremove -y vg_raidlab/lv_test_r5
```

---

## 5. Creación del RAID 5 Principal e Inspección de Sub-LVs

Vamos a desplegar un volumen lógico RAID 5 de 300 MiB:

```bash
sudo lvcreate -y --type raid5 -i 2 -L 300M -n lv_prod vg_raidlab /dev/loop0 /dev/loop1 /dev/loop2
```

### Inspección con `lvs -a`

Para ver los sub-volúmenes ocultos de metadatos y datos, usamos el modificador `-a`:

```bash
sudo lvs -a -o lv_name,vg_name,attr,size,copy_percent,devices vg_raidlab
```

Salida típica:
```
  LV                VG         Attr       LSize   Cpy%Sync Devices
  lv_prod           vg_raidlab rwi-a-r--- 300.00m 100.00   lv_prod_rimage_0(0),...
  [lv_prod_rimage_0] vg_raidlab iwi-aor--- 152.00m          /dev/loop0(1)
  [lv_prod_rimage_1] vg_raidlab iwi-aor--- 152.00m          /dev/loop1(1)
  [lv_prod_rimage_2] vg_raidlab iwi-aor--- 152.00m          /dev/loop2(1)
  [lv_prod_rmeta_0]  vg_raidlab ewi-aor---   4.00m          /dev/loop0(0)
  [lv_prod_rmeta_1]  vg_raidlab ewi-aor---   4.00m          /dev/loop1(0)
  [lv_prod_rmeta_2]  vg_raidlab ewi-aor---   4.00m          /dev/loop2(0)
```

> 🔍 **Análisis forense:**
> - Notá cómo `lv_prod_rmeta_0` ocupa exactamente los primeros 4 MiB (`/dev/loop0(0)`) y `lv_prod_rimage_0` arranca a partir del extent 1 (`/dev/loop0(1)`).
> - Los atributos `rwi-a-r---`: la primera letra `r` indica **RAID**, y la novena `r` indica **refresh/resync completado**.

---

## 6. Sistema de Archivos y Expansión en Caliente (Online Grow)

Una de las grandes ventajas de LVM RAID frente a mdadm es la facilidad para redimensionar en caliente con un único comando:

```bash
# 1. Formatear y montar
sudo mkfs.ext4 -q -L lvmraid /dev/vg_raidlab/lv_prod
sudo mkdir -p /mnt/raidlab_lvm
sudo mount /dev/vg_raidlab/lv_prod /mnt/raidlab_lvm

# 2. Escribir datos de prueba con hash de control
sudo dd if=/dev/urandom of=/mnt/raidlab_lvm/archivo_critico.dat bs=1M count=35 status=none
sha256sum /mnt/raidlab_lvm/archivo_critico.dat | tee /tmp/sha_lvm.txt
df -h /mnt/raidlab_lvm

# 3. Extender el volumen RAID y el filesystem ext4 simultáneamente en caliente (+60 MiB)
sudo lvextend -r -L +60M vg_raidlab/lv_prod

# 4. Verificar nuevo tamaño sin haber desmontado
df -h /mnt/raidlab_lvm
```

LVM redimensiona automáticamente los sub-LVs de franja de datos manteniendo la paridad y notifica al kernel para expandir el sistema de archivos ext4 en vivo.

---

## 7. Simulación de Falla de Disco y Estado Degradado

Vamos a corromper intencionalmente la cabecera del disco `/dev/loop1` simulando un fallo catastrófico del controlador o medio magnético:

```bash
# Sobrescribir los primeros 10 MiB del disco físico
sudo dd if=/dev/zero of=/dev/loop1 bs=1M count=10 conv=notrunc status=none
sudo blockdev --flushbufs /dev/loop1 2>/dev/null || true

# Forzar a LVM a inspeccionar la salud del VG
sudo vgs --readonly vg_raidlab
sudo lvs -a -o lv_name,attr,health_status,devices vg_raidlab
```

### ¿Qué revela la salida de `lvs`?
- El atributo del LV cambia: la posición 9 muestra **`p` (parcial / degraded)**.
- La columna `Health` informa explícitamente: **`degraded`**.
- El sub-LV `lv_prod_rimage_1` figura con estado de error o missing.

### Verificación de disponibilidad de servicio
Leé el archivo mientras el arreglo está degradado:
```bash
sha256sum /mnt/raidlab_lvm/archivo_critico.dat
cat /tmp/sha_lvm.txt
```
El hash coincide exactamente. El kernel Linux sigue sirviendo lecturas calculando la paridad XOR al vuelo a través de `dm-raid`.

---

## 8. Sustitución y Recuperación en Vivo con `lvconvert --repair`

A diferencia de `mdadm --fail/--add`, en LVM el procedimiento de sustitución aprovecha la abstracción del Volume Group:

### Paso 1: Introducir un nuevo Physical Volume
```bash
# Simular un disco nuevo insertado en el servidor
sudo truncate -s 256M /tmp/raidlab/disk_spare.img
SPARE_DEV=$(sudo losetup -f --show /tmp/raidlab/disk_spare.img)

# Inicializar y sumarlo al VG existente
sudo pvcreate -y "$SPARE_DEV"
sudo vgextend vg_raidlab "$SPARE_DEV"
sudo vgs vg_raidlab
```

### Paso 2: Ejecutar la Autorreparación del Logical Volume
```bash
sudo lvconvert -y --repair vg_raidlab/lv_prod
```

LVM analiza la topología del LV, detecta qué sub-LVs (`_rmeta` y `_rimage`) estaban en el PV dañado, aloca nuevos extents en el disco `$SPARE_DEV` y le ordena a `dm-raid` reconstruir la paridad.

Podés monitorear el progreso de la reconstrucción con:
```bash
sudo lvs -a -o lv_name,copy_percent,health_status vg_raidlab
```
Cuando `Cpy%Sync` alcanza el 100%, el `health_status` vuelve a quedar vacío (sano).

### Paso 3: Purgar el PV Huérfano del Volume Group
```bash
# Eliminar el dispositivo faltante del registro de metadatos del VG
sudo vgreduce --removemissing --force vg_raidlab

# Confirmar estado final óptimo
sudo vgs vg_raidlab
sudo lvs -o lv_name,attr,health_status,devices vg_raidlab
```

Validá nuevamente la integridad del archivo:
```bash
sha256sum /mnt/raidlab_lvm/archivo_critico.dat
```
¡Recuperación completada al 100% sin una sola desconexión ni corrupción de datos!

### Paso 4: Limpieza del Entorno al Finalizar
Cuando desees desmontar el laboratorio y eliminar todos los recursos (Volume Group, LVs, PVs, loop devices y archivos en `/tmp/raidlab`), podés ejecutar el script de limpieza automatizado:
```bash
sudo ./linux/administrator/raid/limpiar_raid_lvm.sh
```
O de forma manual:
```bash
sudo umount /mnt/raidlab_lvm 2>/dev/null || true
sudo lvchange -an vg_raidlab 2>/dev/null || true
sudo vgremove -f -y vg_raidlab 2>/dev/null || true
losetup -a | grep '/tmp/raidlab' | cut -d: -f1 | while read -r dev; do
    sudo pvremove -ff -y "$dev" 2>/dev/null || true
    sudo wipefs -a "$dev" 2>/dev/null || true
    sudo losetup -d "$dev" 2>/dev/null || true
done
sudo rm -rf /tmp/raidlab /mnt/raidlab_lvm /tmp/sha_lvm.txt
```

---

## 9. Script Automatizado

El laboratorio cuenta con un script interactivo completo con verificación de integridad y limpieza segura:

```bash
cd linux/administrator/raid
chmod +x demo_raid_lvm.sh

# Modo interactivo paso a paso
sudo ./demo_raid_lvm.sh

# Modo desatendido para pruebas rápidas
sudo ./demo_raid_lvm.sh --auto 3
```

---

## 10. Ejercicios Prácticos

1. **¿Qué ventaja técnica ofrece LVM RAID frente a crear un VG encima de `/dev/md0`?**
2. **¿Qué función cumplen exactamente los volúmenes lógicos con sufijo `_rmeta`?**
3. **Si un PV falla en un VG que tiene un Logical Volume lineal (`linear`) y otro RAID 1 (`raid1`), ¿qué ocurre con cada uno?**
4. **¿Por qué `vgreduce --removemissing` requiere la opción `--force` cuando hay Logical Volumes con fallas parciales?**

<details><summary>Ver Respuestas Comentadas</summary>

1. Permite granularidad por volumen (tener LVs sin redundancia para caches temporales y LVs en RAID 5 para bases de datos en los mismos discos físicos), expansión en caliente sin doble paso y menor complejidad de administración de herramientas.
2. Contienen los metadatos propios del subsistema RAID del kernel y el **write-intent bitmap**. Permiten registrar las regiones sucias de escritura para que, tras un corte de luz, el resync sea casi instantáneo en lugar de recorrer todo el disco.
3. El LV lineal que tenía datos en el PV muerto queda corrupto o inaccesible (I/O error). El LV RAID 1 continúa operativo en estado degradado gracias a su otra copia en el PV sobreviviente.
4. Porque eliminar un PV faltante donde residen sub-LVs huérfanos destruye la metadata residual de esa pata del arreglo. La opción `--force` le confirma a LVM que el administrador acepta formalmente la baja definitiva de ese medio físico.
</details>

---

## 11. Qué sigue

➡️ **Lab 3.10 · [RAID con Btrfs](raid_btrfs.md)** — Sistemas de archivos Copy-on-Write modernos: perfiles por chunk, auto-reparación por checksum y conversión en vivo.
