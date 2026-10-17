---
id: lab-3.2-storage-paso-a-paso
title: 'Laboratorio Paso a Paso: Loop Devices, LVM y Redimensionamiento Ext4 Manual'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.2'
sections:
- '3.2'
- '3'
category: storage
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
tags:
- storage
- lvm
- pv
- vg
- lv
- loop-device
- ext4
- resize2fs
- lvextend
tools:
- truncate
- losetup
- pvcreate
- vgcreate
- lvcreate
- mkfs.ext4
- mount
- lvextend
- resize2fs
prerequisites:
- lab-3.2-storage-simple-loop
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 1024
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-17'
  notes: Ejecución paso a paso manual con 3 discos virtuales de 2 GiB y ampliación
    en caliente.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Totalmente compatible en Linux.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio manual paso a paso sobre administración de volúmenes LVM.
  Guía al alumno sin scripts para crear tres loop devices de 2 GiB, inicializar Physical
  Volumes (pvcreate), agruparlos en un Volume Group (vgcreate), crear un Logical Volume
  (lvcreate) con ext4 y ampliarlo en caliente con lvextend y resize2fs.
files:
  guide: storage/lab_storage_paso_a_paso.md
  script: null
  terraform: null
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio paso a paso: loop devices y LVM

En este laboratorio vas a ejecutar cada comando manualmente para ver cómo un archivo se convierte en un dispositivo de bloques, cómo LVM organiza ese almacenamiento y cómo se amplía un filesystem ext4 montado.

## Entorno

Usá una VM Debian o Ubuntu descartable con acceso a `sudo`. Todos los discos de esta práctica son archivos de prueba bajo `/tmp`; no uses discos físicos ni adaptes estos comandos a un equipo con datos que quieras conservar.

Instalá las herramientas necesarias:

```bash
sudo apt update
sudo apt install -y lvm2 e2fsprogs util-linux
```

## 1. Preparar tres discos de prueba

Creamos un directorio y tres archivos de 2 GiB. `truncate` fija el tamaño lógico; al ser archivos dispersos, al principio pueden ocupar mucho menos espacio físico.

```bash
mkdir -p /tmp/lab_storage_manual
truncate -s 2G /tmp/lab_storage_manual/disk1.img
truncate -s 2G /tmp/lab_storage_manual/disk2.img
truncate -s 2G /tmp/lab_storage_manual/disk3.img
ls -lh /tmp/lab_storage_manual
du -h /tmp/lab_storage_manual/*
```

Compará `ls` con `du`: el primero muestra el tamaño lógico y el segundo el espacio usado en el filesystem que guarda las imágenes.

## 2. Asociar los archivos a loop devices

Un loop device presenta un archivo como dispositivo de bloques. El kernel elige dispositivos libres; guardamos cada nombre en una variable para reutilizarlo en los siguientes comandos.

```bash
LOOP1=$(sudo losetup --find --show /tmp/lab_storage_manual/disk1.img)
LOOP2=$(sudo losetup --find --show /tmp/lab_storage_manual/disk2.img)
LOOP3=$(sudo losetup --find --show /tmp/lab_storage_manual/disk3.img)
printf 'LOOP1=%s\nLOOP2=%s\nLOOP3=%s\n' "$LOOP1" "$LOOP2" "$LOOP3"
sudo losetup -a
```

Anotá los tres valores impresos. Las variables duran mientras siga abierta esta terminal. Si la cerrás, recuperá los nombres con `sudo losetup -a` y volvé a asignarlos antes de continuar.

## 3. Crear los volúmenes físicos (PV)

`pvcreate` escribe metadatos de LVM en los loop devices para que LVM pueda administrarlos. Comprobá primero que las variables contienen los tres loop devices de este lab.

```bash
sudo pvcreate "$LOOP1" "$LOOP2" "$LOOP3"
sudo pvs
```

En `pvs` vas a ver los tres dispositivos como PV. Todavía no forman un grupo ni contienen un volumen lógico.

## 4. Agrupar los PV en un VG

`vgcreate` reúne los tres PV en un grupo de almacenamiento llamado `vg_lab`.

```bash
sudo vgcreate vg_lab "$LOOP1" "$LOOP2" "$LOOP3"
sudo vgs
```

Mirá `VFree`: representa el espacio del grupo que aún no asignaste a volúmenes lógicos.

## 5. Crear y montar un LV

`lvcreate` reserva 1 GiB del grupo. Después creamos un filesystem ext4 y lo montamos en `/mnt/lab_lvm`.

```bash
sudo lvcreate -L 1G -n lv_datos vg_lab
sudo lvs
sudo mkfs.ext4 /dev/vg_lab/lv_datos
sudo mkdir -p /mnt/lab_lvm
sudo mount /dev/vg_lab/lv_datos /mnt/lab_lvm
```

Comprobá el tamaño visible y que el montaje corresponde al LV:

```bash
df -h /mnt/lab_lvm
findmnt /mnt/lab_lvm
```

## 6. Escribir un archivo y observar el estado inicial

Escribimos 200 MiB de datos aleatorios para tener contenido dentro del filesystem antes de ampliarlo.

```bash
sudo dd if=/dev/urandom of=/mnt/lab_lvm/test_file.bin bs=1M count=200 status=progress
sudo ls -lh /mnt/lab_lvm/test_file.bin
df -h /mnt/lab_lvm
sudo lvs
```

Anotá el tamaño del LV y el espacio disponible que informa `df`.

## 7. Ampliar el LV y luego ext4

Primero `lvextend` aumenta el dispositivo lógico en 1.5 GiB. En este momento el dispositivo es más grande, pero ext4 todavía no ha usado ese espacio.

```bash
sudo lvextend -L +1.5G /dev/vg_lab/lv_datos
sudo lvs
df -h /mnt/lab_lvm
```

Compará los resultados: `lvs` debe mostrar el LV ampliado, mientras que el tamaño del filesystem en `df` todavía puede reflejar el tamaño anterior. Ahora `resize2fs` expande ext4 para ocupar el espacio nuevo, sin desmontarlo:

```bash
sudo resize2fs /dev/vg_lab/lv_datos
df -h /mnt/lab_lvm
sudo ls -lh /mnt/lab_lvm/test_file.bin
```

El archivo sigue ahí y el espacio disponible aumentó. El tamaño mostrado puede diferir un poco por los metadatos del filesystem.

## 8. Entender la cadena

- **Loop device:** presenta un archivo como dispositivo de bloques.
- **PV:** dispositivo que LVM inicializó para administrar.
- **VG:** grupo que suma la capacidad de uno o más PV.
- **LV:** volumen lógico creado a partir del espacio disponible en un VG.
- **Filesystem:** estructura ext4 creada dentro del LV y montada en una ruta.

El orden fue: archivo de imagen → loop device → PV → VG → LV → ext4 → punto de montaje.

## 9. Limpiar manualmente

Desmontá primero el filesystem. Luego eliminá el LV, el VG y la firma de LVM de los tres loop devices, en ese orden.

```bash
sudo umount /mnt/lab_lvm
sudo lvremove /dev/vg_lab/lv_datos
sudo vgremove vg_lab
sudo pvremove "$LOOP1" "$LOOP2" "$LOOP3"
sudo losetup -d "$LOOP1" "$LOOP2" "$LOOP3"
sudo rmdir /mnt/lab_lvm
rm -r /tmp/lab_storage_manual
```

Si cerraste la terminal, reemplazá las variables por los nombres anotados. Antes de ejecutar la limpieza, verificá que cada loop device siga asociado a uno de los archivos de `/tmp/lab_storage_manual`:

```bash
sudo losetup -a
sudo pvs
sudo vgs
sudo lvs
```

Al terminar, esos comandos ya no deben mostrar recursos de este laboratorio.

## Preguntas

1. ¿Qué diferencia hay entre ampliar el LV y ampliar ext4?
2. ¿Qué información aportan `pvs`, `vgs` y `lvs`?
3. ¿Por qué se pudo ejecutar `resize2fs` sin desmontar el filesystem?
4. ¿Qué comprobarías antes de borrar un loop device?