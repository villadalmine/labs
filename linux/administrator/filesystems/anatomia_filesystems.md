# Laboratorio: Anatomía de Sistemas de Archivos en Linux (ext4, XFS, Btrfs, tmpfs) y Diagnóstico Forense

Este laboratorio práctico y agnóstico está diseñado para enseñar **cómo funcionan los sistemas de archivos por dentro**, cómo se estructuran los bloques e inodos en el disco, cómo utilizar herramientas avanzadas de administración y diagnóstico (`tune2fs`, `dumpe2fs`, `xfs_info`, `btrfs`, `df -i`) y cómo resolver **desastres reales de producción** (agotamiento de inodos y corrupción de superbloque).

---

## 🏗️ Arquitectura del Stack de Almacenamiento en Linux

```
+---------------------------------------------------------------------------------------------------+
|                                  APLICACIONES / ESPACIO DE USUARIO                                |
|                                                                                                   |
|    Bases de Datos, Contenedores Docker, Scripts, Servidor Web (Llamadas: open, read, write)       |
+--------------------------------------------------▲------------------------------------------------+
                                                   │
                                                   │ Llamadas al sistema POSIX (VFS API)
+--------------------------------------------------▼------------------------------------------------+
|                             CAPA VFS (VIRTUAL FILE SYSTEM DEL KERNEL)                             |
|                                                                                                   |
|   Traductor universal del kernel. Desacopla la aplicación del formato físico del almacenamiento.  |
|   Maneja Puntos de Montaje (/var, /mnt), descriptores de archivo y Caché de Página en RAM.        |
+--------------------------------------------------▲------------------------------------------------+
                                                   │
                ┌──────────────────────────────────┼──────────────────────────────────┐
                │                                  │                                  │
+---------------▼---------------+  +---------------▼---------------+  +---------------▼---------------+
|     SISTEMA DE ARCHIVOS       |  |      SISTEMA DE ARCHIVOS      |  |      SISTEMA DE ARCHIVOS      |
|             ext4              |  |              XFS              |  |             Btrfs             |
|                               |  |                               |  |                               |
|  * Superbloques prim/copias   |  |  * Allocation Groups (AG)     |  |  * Copy-on-Write (CoW)        |
|  * Grupos de Bloques          |  |  * Árboles B+ / Extents       |  |  * Subvolúmenes & Snapshots   |
|  * Tablas de Inodos fijas     |  |  * Inodos Dinámicos           |  |  * Checksums (Auto-reparación)|
|  * Journaling (Transacciones) |  |  * Expansión solo online      |  |  * Multi-device integrado     |
|  * 5% Bloques Reservados      |  |  * No permite reducción       |  |  * Compresión ZSTD nativa     |
+---------------▲---------------+  +---------------▲---------------+  +---------------▲---------------+
                │                                  │                                  │
+---------------┴──────────────────────────────────┴──────────────────────────────────┴---------------+
|                            CAPA DE BLOQUES (BLOCK DEVICE LAYER)                                    |
|                                                                                                   |
|   Dispositivos de Bloque: Discos SATA/NVMe (/dev/sdX, /dev/nvmeX), LVM (/dev/vg/lv),               |
|   RAID mdadm (/dev/mdX) o Discos Virtuales Loop (/dev/loopX en archivos .img)                     |
+---------------------------------------------------------------------------------------------------+
```

---

## 🔬 Anatomía Interna de un Filesystem: ext4 al Detalle

Un sistema de archivos **no es una caja vacía**; es una estructura matemática de metadatos grabada en los sectores del disco:

```
+---------------------------------------------------------------------------------------------------+
| ESTRUCTURA DE UNA PARTICIÓN / VOLUMEN FORMATEADO CON ext4                                         |
|                                                                                                   |
| [Boot Record]  [ Block Group 0 ]   [ Block Group 1 ]   [ Block Group 2 ] ... [ Block Group N ]    |
|   (1024 bytes)                                                                                    |
|                      │                                                                            |
|                      ▼                                                                            |
|   +───────────────────────────────────────────────────────────────────────────────────────────+   |
|   | CONTENIDO DE UN "BLOCK GROUP":                                                            |   |
|   |                                                                                           |   |
|   | 1. Superbloque (1 bloque):                                                                |   |
|   |    El "Cerebro". Tamaño de bloque, cantidad total de inodos, bloques libres y estado.     |   |
|   |                                                                                           |   |
|   | 2. Descriptores de Grupo (GDT):                                                           |   |
|   |    Punteros hacia los mapas de bits y tablas de inodos de este grupo.                     |   |
|   |                                                                                           |   |
|   | 3. Mapa de Bits de Bloques (Block Bitmap - 1 bloque):                                     |   |
|   |    Cada bit representa 1 bloque de datos: 0 = Libre, 1 = Ocupado.                         |   |
|   |                                                                                           |   |
|   | 4. Mapa de Bits de Inodos (Inode Bitmap - 1 bloque):                                      |   |
|   |    Cada bit representa 1 entrada en la tabla de inodos: 0 = Libre, 1 = Usado.             |   |
|   |                                                                                           |   |
|   | 5. Tabla de Inodos (Inode Table - Varios bloques contiguos):                              |   |
|   |    Guarda los metadatos de los archivos (dueño, permisos, tamaño, fechas, extents).       |   |
|   |                                                                                           |   |
|   | 6. Bloques de Datos (Data Blocks):                                                        |   |
|   |    Donde realmente se escriben los bytes del contenido del archivo.                       |   |
|   +───────────────────────────────────────────────────────────────────────────────────────────+   |
+---------------------------------------------------------------------------------------------------+
```

---

## 📊 Matriz Comparativa: ¿Qué Filesystem Elegir en Producción?

| Característica | ext4 | XFS | Btrfs | tmpfs |
| :--- | :--- | :--- | :--- | :--- |
| **Origen** | Evolución Linux (ext2/3) | Silicon Graphics (SGI) | Oracle / Comunidad Linux | Kernel Linux (Memoria RAM) |
| **Journaling** | Sí (ordered, journal, writeback) | Sí (registro transaccional) | No (usa Copy-on-Write) | No (Volátil en RAM) |
| **Inodos** | **Fijos** (se crean al formatear) | **Dinámicos** (crecen a demanda) | **Dinámicos** | Dinámicos en RAM |
| **Redimensionamiento** | Online agrandar / Offline achicar | **Solo agrandar en caliente** (No achica) | Online agrandar y achicar | Online instantáneo (`mount -o remount`) |
| **Snapshots Nativos** | No | No | **Sí** ($O(1)$ sin consumo inicial) | No |
| **Detección de Corrupción** | Checksum de metadatos | Checksum de metadatos | **Checksum de datos y metadatos** | No (RAM) |
| **Uso Típico** | Sistemas estándar, partición raíz `/`, compatibilidad | Bases de datos, discos gigantes >10TB, RHEL/CentOS default | Almacenamiento moderno, subvolúmenes, backups Btrfs send | Caché ultra-rápida, `/tmp`, `/run`, seguridad efímera |

---

## 🎯 Objetivos de Aprendizaje

1. Comprender la diferencia estructural entre el **Superbloque**, la **Tabla de Inodos** y los **Bloques de Datos**.
2. Dominar las herramientas de inspección y tuneo: `tune2fs`, `dumpe2fs`, `xfs_info`, `xfs_admin`, `btrfs` y `df -i`.
3. Ajustar los **bloques reservados de root** (reclamando gigabytes de espacio sin formatear).
4. Resolver el desastre clásico de producción: **"No space left on device" con 90% de disco libre** (agotamiento de inodos).
5. Recuperar un sistema de archivos dañado restaurando su **Superbloque de respaldo** (*Backup Superblock*).
6. Aprender a trabajar de manera **agnóstica** mediante dispositivos de bucle (*loop devices*) antes de llevarlo a producción en AWS EC2.

---

## 🛠️ Prerrequisitos y Preparación del Entorno

En cualquier distribución Ubuntu, Debian o WSL2:

```bash
sudo apt update
sudo apt install -y e2fsprogs xfsprogs btrfs-progs util-linux
```

Crearemos un directorio de trabajo para nuestras imágenes de disco:
```bash
sudo mkdir -p /tmp/lab_fs
cd /tmp/lab_fs
```

---

## 🧪 Laboratorio 1: Anatomía de ext4, Superbloque y Gestión con `tune2fs`

### 1. Crear un Disco Virtual de 500 MB y Formatearlo con ext4

```bash
# Crear un archivo de 500 MB relleno con ceros
sudo dd if=/dev/zero of=/tmp/lab_fs/disco_ext4.img bs=1M count=500 status=progress

# Asociarlo al primer dispositivo loop libre
LOOP_EXT4=$(sudo losetup -f --show /tmp/lab_fs/disco_ext4.img)
echo "Asociado a: $LOOP_EXT4"

# Formatear con ext4 asignando tamaño de bloque de 4KB (4096 bytes) y etiqueta
sudo mkfs.ext4 -b 4096 -L DISCO_DATOS "$LOOP_EXT4"
```

---

### 2. Inspeccionar el "Cerebro" del Filesystem: `dumpe2fs` y `tune2fs`

`dumpe2fs` y `tune2fs -l` leen directamente el **Superbloque**:

```bash
sudo tune2fs -l "$LOOP_EXT4" | head -n 35
```

**Parámetros clave que debes saber interpretar:**

* **`Block size: 4096`**: Cada bloque de disco tiene 4 KB. Un archivo de 10 bytes ocupa 4 KB en disco.
* **`Inode count: 32768`**: Total de archivos/directorios que este disco puede almacenar en su vida útil.
* **`Reserved block count: 6400 (5.00%)`**: ¡El 5% de la capacidad está reservada exclusivamente para el usuario `root`!
* **`Filesystem state: clean`**: El sistema de archivos se desmontó limpiamente y no requiere chequeo.
* **`Mount count` / `Maximum mount count`**: Número de veces que se ha montado antes de forzar un `fsck`.

---

### 3. El Truco del Administrador: Reclamar Espacio Reservado con `tune2fs -m`

Por defecto, ext4 reserva el **5% del espacio total** para que el usuario `root` pueda iniciar sesión si el disco se llena y para evitar fragmentación.
En un disco de 500 GB, el 5% son **25 GB desperdiciados** que los usuarios no pueden usar. En particiones secundarias de datos, se suele bajar al 1%:

```bash
# Reducir los bloques reservados de 5% a 1%
sudo tune2fs -m 1 "$LOOP_EXT4"

# Verificar el nuevo valor
sudo tune2fs -l "$LOOP_EXT4" | grep "Reserved block count"
```

---

### 4. Modificar la Etiqueta del Volumen en Caliente con `tune2fs -L`

```bash
sudo tune2fs -L "DATA_PRODUCCION" "$LOOP_EXT4"

# Verificar con blkid y lsblk
sudo blkid "$LOOP_EXT4"
```

---

### 5. Montar el Filesystem y Verificar Estadísticas de Bloques

```bash
sudo mkdir -p /mnt/lab_ext4
sudo mount "$LOOP_EXT4" /mnt/lab_ext4

# Ver espacio en bloques legibles por humanos
df -h /mnt/lab_ext4

# Ver estadísticas forenses del sistema de archivos montado
stat -f /mnt/lab_ext4
```

---

## 💥 Laboratorio 2: El Desastre Clásico de Producción (Inodos Agotados)

> [!WARNING]
> Este es uno de los problemas más frecuentes en servidores de producción (ej. servidores web con millones de sesiones PHP o colas de correo Postfix huérfanas).

### 1. El Concepto: ¿Bloques vs Inodos?
* **Bloques (`df -h`):** Miden el **espacio físico** (Megabytes, Gigabytes).
* **Inodos (`df -i`):** Miden la **cantidad de archivos y carpetas**. Cada archivo nuevo consume exactamente **1 inodo**, independientemente de si pesa 0 bytes o 10 GB.

---

### 2. Provocar el Colapso por Agotamiento de Inodos

Creamos un pequeño disco de 20 MB con muy pocos inodos para ver el fenómeno en segundos:

```bash
# 1. Crear disco de 20 MB
sudo dd if=/dev/zero of=/tmp/lab_fs/disco_inodos.img bs=1M count=20 status=none
LOOP_INO=$(sudo losetup -f --show /tmp/lab_fs/disco_inodos.img)

# 2. Formatear forzando pocos inodos (ej: 1024 inodos)
sudo mkfs.ext4 -N 1024 "$LOOP_INO"

# 3. Montar
sudo mkdir -p /mnt/lab_inodos
sudo mount "$LOOP_INO" /mnt/lab_inodos

# 4. Observar estado inicial de espacio vs inodos
echo "=== ESPACIO EN DISCO (df -h) ==="
df -h /mnt/lab_inodos
echo "=== INODOS DISPONIBLES (df -i) ==="
df -i /mnt/lab_inodos
```

Ahora llenamos los inodos creando archivos vacíos de 0 bytes:

```bash
# Crear 1020 archivos vacíos
sudo bash -c 'for i in $(seq 1 1020); do touch /mnt/lab_inodos/session_cache_$i; done 2>/dev/null || true'
```

Intentemos crear un archivo más:
```bash
sudo touch /mnt/lab_inodos/nuevo_archivo.txt
```
**Error en pantalla:**
```text
touch: cannot touch '/mnt/lab_inodos/nuevo_archivo.txt': No space left on device
```

### 3. El Diagnóstico Forense
Si el administrador novato ejecuta:
```bash
df -h /mnt/lab_inodos
```
Verá: **"Uso: 15% (85% LIBRE). ¡¿Por qué dice que no hay espacio?!"**

El administrador con experiencia ejecuta:
```bash
df -i /mnt/lab_inodos
```
Verá: **"IUse%: 100% (Inodos libres: 0). ¡Se agotaron las entradas de la tabla de inodos!"**

### 4. Cómo encontrar qué directorio consumió los inodos en el servidor
Comando forense esencial para encontrar qué carpeta tiene millones de archivitos:
```bash
sudo find /mnt/lab_inodos -xdev -type f | cut -d "/" -f 4 | head -n 5
# Conteo rápido de inodos por carpeta
sudo find /mnt/lab_inodos -maxdepth 1 -type d -exec sh -c 'echo -n "{}: "; find "{}" -type f | wc -l' \;
```

Limpieza del laboratorio de inodos:
```bash
sudo umount /mnt/lab_inodos
sudo losetup -d "$LOOP_INO"
sudo rm -f /tmp/lab_fs/disco_inodos.img
```

---

## 🌪️ Laboratorio 3: Simulación de Desastre y Rescate de Superbloque Dañado

El **Superbloque Primario** se ubica al principio de la partición (bloque 0 o 1). Si un corte de energía o un sector físico defectuoso corrompe esos primeros kilobytes, el kernel **no podrá montar el disco jamás**.

Afortunadamente, herramientas como `mkfs.ext4` crean automáticamente **superbloques de respaldo (*backup superblocks*)** dispersos a lo largo del disco.

### 1. Localizar los Superbloques de Respaldo

Podemos averiguar en qué bloques exactos se guardaron las copias con `dumpe2fs`:

```bash
sudo dumpe2fs "$LOOP_EXT4" | grep -i "superblock"
```
O simulando la creación sin escribir nada con el flag `-n`:
```bash
sudo mke2fs -n -b 4096 "$LOOP_EXT4" | grep -A 3 "Superblock backups"
```
*Salida típica:*
```text
Superblock backups stored on blocks:
    32768, 98304, 163840, 229376, 294912
```

---

### 2. Provocar la Catástrofe: Destruir el Superbloque Primario con `dd`

Desmontamos el disco y sobrescribimos con ceros o basura el bloque primario (primeros 2 KB):

```bash
sudo umount /mnt/lab_ext4

# Inyectar basura binaria en el primer bloque del superbloque
sudo dd if=/dev/urandom of="$LOOP_EXT4" bs=1024 count=4 seek=1 conv=notrunc status=none
```

Intentemos montar el disco ahora:
```bash
sudo mount "$LOOP_EXT4" /mnt/lab_ext4
```
**El kernel rechaza el montaje con el temido error:**
```text
mount: /mnt/lab_ext4: wrong fs type, bad option, bad superblock on /dev/loopX, missing codepage or helper program, or other error.
```

---

### 3. La Operación de Rescate: `e2fsck -b <bloque_respaldo>`

Le indicamos a `e2fsck` que ignore el superbloque principal quemado y use la copia de respaldo ubicada en el bloque **`32768`**:

```bash
sudo e2fsck -b 32768 -y "$LOOP_EXT4"
```

El asistente detectará que el superbloque primario está dañado, restaurará la estructura usando la copia de seguridad y dejará el filesystem en estado `clean`.

Comprobación del rescate:
```bash
sudo mount "$LOOP_EXT4" /mnt/lab_ext4
df -h /mnt/lab_ext4
echo "✓ ¡Sistema de archivos rescatado con éxito!"
```

---

## ⚡ Laboratorio 4: XFS en Profundidad (Allocation Groups y Expansión Online)

XFS es el sistema de archivos por defecto en distribuciones Enterprise (Red Hat Enterprise Linux, Rocky Linux, AlmaLinux) debido a su capacidad multihilo y rendimiento en discos masivos.

### 1. Crear y Formatear con XFS

```bash
sudo dd if=/dev/zero of=/tmp/lab_fs/disco_xfs.img bs=1M count=300 status=none
LOOP_XFS=$(sudo losetup -f --show /tmp/lab_fs/disco_xfs.img)

# Formatear con XFS y etiqueta
sudo mkfs.xfs -L "APP_STORAGE" "$LOOP_XFS"

sudo mkdir -p /mnt/lab_xfs
sudo mount "$LOOP_XFS" /mnt/lab_xfs
```

---

### 2. Inspeccionar la Geometría con `xfs_info`

A diferencia de ext4, XFS no usa `tune2fs`, sino `xfs_info` sobre el punto de montaje:

```bash
sudo xfs_info /mnt/lab_xfs
```

*Conceptos clave de XFS:*
* **`agcount=4` (Allocation Groups):** XFS divide el disco en sub-regiones independientes llamadas Allocation Groups. Cada grupo tiene sus propias estructuras de asignación de bloques. Esto permite que múltiples hilos de CPU lean y escriban en paralelo sin bloquear el resto del disco.
* **`bsize=4096`:** Tamaño del bloque de datos.
* **`log=internal`:** El journal de transacciones transcurre en un área dedicada de alta velocidad.

---

### 3. Redimensionamiento en Caliente con `xfs_growfs`

> [!IMPORTANT]
> **Regla de Oro de XFS:** XFS puede **agrandarse en caliente** mientras está montado y recibiendo tráfico con `xfs_growfs`, pero **NUNCA puede reducirse de tamaño**. Si necesitas achicar un XFS, debes hacer backup de los datos, formatear con menor tamaño y restaurar.

Simulamos un aumento del disco subyacente de 300 MB a 600 MB:

```bash
# 1. Agrandar el archivo de imagen
sudo truncate -s 600M /tmp/lab_fs/disco_xfs.img

# 2. Informar al loop device que el medio creció
sudo losetup -c "$LOOP_XFS"

# 3. Extender el sistema de archivos XFS montado
sudo xfs_growfs /mnt/lab_xfs

# 4. Verificar el nuevo tamaño
df -h /mnt/lab_xfs
```

---

## 🌳 Laboratorio 5: Btrfs (Copy-on-Write, Subvolúmenes y Snapshots $O(1)$)

Btrfs supera el paradigma tradicional combinando la capa de volumen lógico y el sistema de archivos mediante **Copy-on-Write**.

### 1. Crear y Formatear con Btrfs

```bash
sudo dd if=/dev/zero of=/tmp/lab_fs/disco_btrfs.img bs=1M count=300 status=none
LOOP_BTR=$(sudo losetup -f --show /tmp/lab_fs/disco_btrfs.img)

sudo mkfs.btrfs -L "LAB_BTRFS" "$LOOP_BTR"

sudo mkdir -p /mnt/lab_btrfs
sudo mount "$LOOP_BTR" /mnt/lab_btrfs
```

---

### 2. Subvolúmenes Jerárquicos y Snapshots Instantáneos

Un **subvolumen** en Btrfs no es una partición rígida; es un árbol de archivos independiente que comparte dinámicamente todo el espacio del disco:

```bash
# Crear subvolúmenes
sudo btrfs subvolume create /mnt/lab_btrfs/@data
sudo btrfs subvolume list /mnt/lab_btrfs

# Crear un archivo de 20 MB en el subvolumen
sudo dd if=/dev/urandom of=/mnt/lab_btrfs/@data/archivo_pesado.bin bs=1M count=20 status=none
ls -lh /mnt/lab_btrfs/@data/archivo_pesado.bin

# Crear un SNAPSHOT instantáneo de @data
sudo btrfs subvolume snapshot /mnt/lab_btrfs/@data /mnt/lab_btrfs/@data_snapshot_1
```

Verificar espacio:
```bash
sudo btrfs filesystem df /mnt/lab_btrfs
```
¡El snapshot se tomó en **0 milisegundos** y consumió **0 bytes extras**! Solo cuando modifiques el archivo original, Btrfs escribirá los nuevos bloques en otro sector (*Copy on Write*).

---

## 🚀 Laboratorio 6: `tmpfs` (Almacenamiento Volátil a Velocidad de Memoria RAM)

`tmpfs` es un sistema de archivos virtual que no reside en disco, sino directamente en la memoria RAM y Swap del kernel.

### 1. Montar un tmpfs con Límite de Tamaño

```bash
sudo mkdir -p /mnt/lab_ramdisk
sudo mount -t tmpfs -o size=100M tmpfs /mnt/lab_ramdisk

df -h /mnt/lab_ramdisk
```

### 2. Prueba de Velocidad: RAM vs Disco

Escribir 50 MB en RAM:
```bash
sudo dd if=/dev/zero of=/mnt/lab_ramdisk/test_ram.bin bs=1M count=50 conv=fdatasync
```

Escribir 50 MB en disco convencional:
```bash
sudo dd if=/dev/zero of=/tmp/lab_fs/test_disk.bin bs=1M count=50 conv=fdatasync
```
Observarás tasas de transferencia de **varios Gigabytes por segundo (GB/s)** en `tmpfs`.

---

## ☁️ Caso Real: Cómo Aplicar Esto en AWS EC2 (EBS Volumes)

Cuando en lugar de loop devices trabajas en una máquina virtual de AWS EC2:

1. **Adjuntar el volumen EBS:**
   En la consola de AWS o con Terraform, adjuntas discos EBS de tipo `gp3` a tu instancia EC2.
2. **Identificar los nombres de dispositivos:**
   En instancias modernas de AWS (Nitro System), los discos aparecen como `/dev/nvme1n1`, `/dev/nvme2n1`, etc.:
   ```bash
   lsblk
   ```
3. **Formatear y Administrar con los Mismos Comandos:**
   ```bash
   # Para ext4:
   sudo mkfs.ext4 -L EBS_DATA /dev/nvme1n1
   sudo tune2fs -m 1 /dev/nvme1n1

   # Para XFS:
   sudo mkfs.xfs -L EBS_XFS /dev/nvme2n1
   ```
4. **Montaje Persistente en `/etc/fstab` mediante UUID:**
   ```bash
   UUID_VAL=$(sudo blkid -s UUID -o value /dev/nvme1n1)
   echo "UUID=$UUID_VAL /datos ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
   sudo mount -a
   ```

---

## 🧹 Limpieza de Recursos del Laboratorio

```bash
sudo umount /mnt/lab_ext4 /mnt/lab_xfs /mnt/lab_btrfs /mnt/lab_ramdisk 2>/dev/null || true
sudo losetup -d "$LOOP_EXT4" "$LOOP_XFS" "$LOOP_BTR" 2>/dev/null || true
sudo rm -rf /tmp/lab_fs /mnt/lab_ext4 /mnt/lab_xfs /mnt/lab_btrfs /mnt/lab_ramdisk
```
