# Laboratorio: LVM, ampliación en caliente y gocryptfs

En este laboratorio vas a crear discos virtuales con `loop devices`, agruparlos con LVM, crear un volumen lógico con ext4 y ampliarlo mientras sigue montado. Al final hay una práctica opcional con gocryptfs.

El laboratorio se basa en el script [lab_storage.sh](lab_storage.sh).

## Objetivos

Al terminar vas a poder:

- identificar la relación entre un loop device, un volumen físico (PV), un grupo de volúmenes (VG) y un volumen lógico (LV)
- crear y montar un volumen lógico con ext4
- ampliar el LV y el filesystem ext4 sin desmontarlo
- reconocer cómo se conecta gocryptfs a una carpeta cifrada y otra visible
- limpiar los recursos creados por la práctica

## Advertencia: ejecutar solo en una VM descartable

Este script usa nombres fijos para recursos del sistema:

- `/dev/loop20`, `/dev/loop21` y `/dev/loop22`
- el grupo LVM `vg_lab` y el volumen `/dev/vg_lab/lv_datos`
- `/tmp/lab_storage` y `/mnt/lab_lvm`
- dos carpetas `datos_cifrados` y `datos_visibles` bajo el `$HOME` del usuario efectivo

El modo `clean` intenta borrar esos recursos y las rutas indicadas. No ejecutes el script en una máquina con loop devices, recursos LVM o datos previos que quieras conservar. No cambies los nombres del script sin revisar también los comandos de limpieza.

## Requisitos

- Una VM Debian o Ubuntu descartable con acceso `sudo`.
- Bash y soporte de loop devices.
- Paquetes `lvm2`, `e2fsprogs` y `util-linux`.
- `gocryptfs` solo para la práctica opcional.
- Espacio libre para el archivo de prueba de 200 MB. Las imágenes se crean como archivos dispersos de 2 GB: su tamaño lógico no equivale necesariamente al espacio físico usado al inicio.

En Debian o Ubuntu, instalá las herramientas:

```bash
sudo apt update
sudo apt install -y lvm2 e2fsprogs util-linux
```

Para incluir la práctica opcional de gocryptfs:

```bash
sudo apt install -y gocryptfs
```

## Paso 1: revisar que los recursos estén libres

Antes de ejecutar el script, inspeccioná los loop devices y LVM:

```bash
sudo losetup -a
sudo pvs
sudo vgs
sudo lvs
```

Confirmá que `/dev/loop20`, `/dev/loop21` y `/dev/loop22` no estén asociados a otros archivos, y que no exista un `vg_lab` que quieras conservar.

También revisá qué valor de `$HOME` usará `sudo`, porque el script construye las rutas de gocryptfs a partir de esa variable:

```bash
sudo bash -c 'printf "HOME=%s\n" "$HOME"'
```

## Paso 2: ejecutar el laboratorio

Desde el directorio donde está `lab_storage.sh`, iniciá la práctica:

```bash
sudo bash ./lab_storage.sh run
```

El script también inicia el modo `run` si no se pasa un argumento:

```bash
sudo bash ./lab_storage.sh
```

## Paso 3: observar la creación de los discos virtuales

El script crea tres imágenes de 2 GB en `/tmp/lab_storage` y las asocia con los loop devices `/dev/loop20`, `/dev/loop21` y `/dev/loop22`.

Al terminar esta etapa, revisá las asociaciones:

```bash
sudo losetup -a
```

Los archivos `.img` funcionan como discos virtuales para esta práctica; no son discos físicos.

## Paso 4: observar la estructura LVM

El script prepara tres capas:

1. **PV (Physical Volume):** inicializa cada loop device para que LVM pueda usarlo.
2. **VG (Volume Group):** agrupa los tres PV bajo el nombre `vg_lab`.
3. **LV (Logical Volume):** crea `lv_datos` con un tamaño inicial de 1 GB.

Después de la ejecución, podés inspeccionar cada capa:

```bash
sudo pvs
sudo vgs
sudo lvs
```

El LV queda formateado con ext4 y montado en `/mnt/lab_lvm`.

## Paso 5: comprobar la ampliación en caliente

El script escribe un archivo de prueba de 200 MB, amplía el LV en 1.5 GB y después expande el filesystem ext4 sin desmontarlo.

Comprobá el estado final:

```bash
sudo df -h /mnt/lab_lvm
sudo ls -lh /mnt/lab_lvm/test_file.bin
sudo lvs
```

Compará el espacio mostrado antes y después de la extensión. El LV final tiene un tamaño aproximado de 2.5 GB, aunque la capacidad visible puede variar ligeramente por el formato y los metadatos del filesystem.

## Paso 6: práctica opcional con gocryptfs

El script no inicializa ni monta gocryptfs: si detecta que está instalado, solamente prepara las carpetas indicadas bajo el `$HOME` del usuario efectivo.

Para hacer la prueba como tu usuario normal, usá carpetas propias:

```bash
mkdir -p ~/datos_cifrados ~/datos_visibles
gocryptfs -init ~/datos_cifrados
gocryptfs ~/datos_cifrados ~/datos_visibles
```

Creá un archivo en el punto visible y compará ambas carpetas:

```bash
echo "archivo de prueba" > ~/datos_visibles/prueba.txt
ls -l ~/datos_visibles
ls -l ~/datos_cifrados
```

Los archivos legibles aparecen en `datos_visibles`; el contenido almacenado en `datos_cifrados` está cifrado. Al terminar, desmontá gocryptfs:

```bash
fusermount -u ~/datos_visibles
```

En algunas distribuciones el comando puede llamarse `fusermount3`:

```bash
fusermount3 -u ~/datos_visibles
```

## Paso 7: limpiar el entorno del laboratorio

Antes de limpiar, asegurate de que no haya datos que quieras conservar en las rutas fijas del script. Si ejecutaste la práctica opcional de gocryptfs, desmontala primero.

Luego ejecutá:

```bash
sudo bash ./lab_storage.sh clean
```

El script desmonta los puntos de montaje, elimina el LV/VG/PV, desconecta los loop devices y borra los archivos y directorios temporales definidos en el script.

Verificá que ya no aparezcan los recursos del laboratorio:

```bash
sudo losetup -a
sudo pvs
sudo vgs
sudo lvs
findmnt /mnt/lab_lvm
```

## Preguntas para cerrar la práctica

1. ¿Qué diferencia hay entre un PV, un VG y un LV?
2. ¿Qué comandos del script amplían el volumen lógico y el filesystem?
3. ¿Por qué se pudo ampliar ext4 sin desmontar `/mnt/lab_lvm`?
4. ¿Qué diferencia observaste entre `datos_visibles` y `datos_cifrados`?
5. ¿Por qué es importante comprobar los loop devices antes de ejecutar `clean`?

## Paso Extra: Redimensionamiento en Caliente del Root Filesystem (`/` Rootfs)

En servidores en producción (tanto en la nube como AWS/Azure o en hipervisores locales como Proxmox/VMware), un caso crítico frecuente es que el disco raíz del sistema operativo (`/`) se queda sin espacio.

**¿Cómo ampliar la partición raíz montada sin reiniciar el servidor ni desmontar el sistema?**

### 1. Diagnosticar con `lsblk` y `df -h`
```bash
lsblk
df -h /
```
Si el disco físico (ej: `nvme0n1` o `sda`) fue ampliado en el hipervisor o consola cloud de 10 GB a 20 GB, verás que el disco padre reporta 20G, pero la partición `nvme0n1p1` sigue en 9.9G.

### 2. Extender la tabla de particiones en caliente con `growpart`
El comando `growpart` (incluido en el paquete `cloud-guest-utils`) reescribe la tabla de particiones MBR/GPT en memoria y notifica al kernel en vivo:
```bash
sudo apt-get install -y cloud-guest-utils

# Sintaxis: growpart <dispositivo_padre> <numero_particion>
sudo growpart /dev/nvme0n1 1
# O en discos SCSI: sudo growpart /dev/sda 1
```

### 3. Expandir el sistema de archivos ext4 en caliente
Una vez agrandada la partición, se expande el sistema de archivos ext4 mientras está montado y en uso:
```bash
sudo resize2fs /dev/nvme0n1p1
```
*(Nota: Si el sistema de archivos fuera XFS, se usaría `sudo xfs_growfs /`)*

### 4. Verificar el resultado
```bash
df -h /
```
¡El espacio libre se incrementa de forma instantánea sin interrumpir ningún proceso en ejecución!

---

## Opción: Demostración interactiva paso a paso para dar clase (`demo_lab_storage.sh`)

Si vas a dar la clase o demostración en vivo, podés usar el script interactivo [`demo_lab_storage.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/demo_lab_storage.sh).

El script pausa en cada etapa (`[ENTER]`) para dar tiempo a la explicación teórica, muestra explicaciones y comandos resaltados con colores, detecta sesiones de `tmux` activando el scroll con ratón automáticamente, y al finalizar (o con `Ctrl+C`) ejecuta un `trap` para limpiar todos los loop devices, montajes y volúmenes LVM.

### Ejecución:

```bash
sudo ./demo_lab_storage.sh          # Modo interactivo (pausa con [ENTER])
sudo ./demo_lab_storage.sh --auto 5 # Modo automático (espera 5s por paso)
```