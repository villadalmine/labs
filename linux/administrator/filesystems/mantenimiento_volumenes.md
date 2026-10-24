---
id: lab-3.13-mantenimiento-volumenes
title: 'Diagnóstico, Mantenimiento y Reparación de Volúmenes (df, du, tune2fs, fsck, e2fsck, dumpe2fs, XFS Tools, Btrfs y badblocks)'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.13'
sections:
- '3.13'
- '3'
category: storage
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- storage
- filesystems
- mantenimiento
- df
- du
- tune2fs
- fsck
- e2fsck
- dumpe2fs
- xfs
- xfs_metadump
- xfs_db
- xfs_fsr
- btrfs
- badblocks
- reparacion
- forense
tools:
- df
- du
- tune2fs
- fsck
- e2fsck
- dumpe2fs
- xfs_metadump
- xfs_db
- xfs_fsr
- btrfs
- badblocks
- sort
- head
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
  test_date: '2026-10-24'
  notes: Ejecución automatizada con demo_mantenimiento_volumenes.sh sobre loop devices. Validados ext4 (tune2fs, e2fsck, dumpe2fs), XFS (metadump, xfs_db frag, fsr), Btrfs (check repair, balance) y badblocks.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Totalmente compatible en volúmenes EBS gp3 y dispositivos de bloque en AWS.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio exhaustivo de diagnóstico, mantenimiento preventivo y reparación forense de volúmenes en Linux. Cubre auditoría de espacio e inodos con df y du (top 10 archivos pesados), parametrización de superbloques ext4 con tune2fs (intervalos de comprobación y medición de particiones no montadas), consistencia con fsck, e2fsck y dumpe2fs, herramientas avanzadas de XFS (xfs_metadump, xfs_db frag, xfs_fsr), mantenimiento de Btrfs (check --repair -p y balance) y análisis de sectores defectuosos con badblocks.
files:
  guide: filesystems/mantenimiento_volumenes.md
  script: filesystems/demo_mantenimiento_volumenes.sh
  terraform: null
prerequisites:
- lab-3.12-enlaces-hard-soft-links
next_recommended_labs:
- lab-3.2-lvm2-online-resize
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Diagnóstico, Mantenimiento y Reparación de Volúmenes y Filesystems

El almacenamiento es el componente más crítico y vulnerable de cualquier infraestructura. A diferencia de un fallo de CPU o memoria que suele resolverse reiniciando un servicio, una falla o corrupción en un sistema de archivos puede provocar **pérdida irreversible de datos**, tiempo de inactividad prolongado o interrupción de transacciones en bases de datos.

Este laboratorio proporciona una capacitación profunda en las herramientas estándar de diagnóstico, auditoría, mantenimiento y rescate de volúmenes en Linux:
1. **Auditoría de capacidad e inodos:** `df` y `du`.
2. **Mantenimiento en ext2/ext3/ext4:** `tune2fs`, `fsck`, `e2fsck` y `dumpe2fs`.
3. **Mantenimiento y optimización en XFS:** `xfs_metadump`, `xfs_db` y `xfs_fsr`.
4. **Mantenimiento en Btrfs:** `btrfs check`, `btrfs balance` y snapshots.
5. **Detección física de sectores dañados:** `badblocks`.

---

## 🗺️ Mapa de Herramientas según Filesystem y Nivel

```
+---------------------------------------------------------------------------------------------------+
| AUDITORÍA GLOBAL DE CAPACIDAD Y CONSUMO (Cualquier Filesystem / VFS)                             |
|                                                                                                   |
|     df (-h, -a, -k, -i)          ──► Espacio en particiones, inodos libres y pseudo-filesystems   |
|     du (-sh, -sch, -a, -c, -S)   ──► Consumo árbol por árbol y detección de archivos gigantes    |
+---------------------------------------------------------------------------------------------------+
| EXT2 / EXT3 / EXT4                  XFS                              BTRFS                        |
|                                                                                                   |
|  tune2fs  (intervalos, mount count,  xfs_metadump (dump metadatos)   btrfs check --repair -p     |
|            journaling, no montado)   xfs_db (análisis frag)          btrfs balance start          |
|  fsck / e2fsck (-p, -y, -c, -f, -n)  xfs_fsr (desfragmentador en     btrfs filesystem show        |
|  dumpe2fs (-h, -b, -i, -f, -x)                caliente)              btrfs subvolume snapshot     |
+---------------------------------------------------------------------------------------------------+
| ANÁLISIS FÍSICO DE MEDIOS Y SECTORES (Discos / SSDs / Particiones)                                |
|                                                                                                   |
|     badblocks (-s, -w, -n, -o)   ──► Escaneo de sectores defectuosos e inyección en fsck -c / -l  |
+---------------------------------------------------------------------------------------------------+
```

---

## 📊 1. Auditoría de Capacidad e Inodos con `df`

El comando `df` (*Disk Free*) informa sobre el espacio libre y utilizado en cada sistema de archivos montado.

### 1.1 Modos de Consulta Esenciales:

```bash
# 1. Espacio en formato legible por humanos (-h: Megabytes, Gigabytes)
df -h

# 2. Espacio sobre un punto de montaje o dispositivo específico
df -h /
df -h /dev/sda1

# 3. Mostrar TODOS los filesystems montados, incluidos los virtuales en memoria (-a)
df -a -h
# Revela tmpfs, sysfs, proc, devpts, cgroup2, ramfs y sockets virtuales del kernel.

# 4. Mostrar en bloques exactos de 1 Kilobyte (-k)
df -k
# Es el estándar recomendado para scripts de Bash o parsing automático de métricas.

# 5. Monitoreo crítico de INODOS disponibles y utilizados (-i)
df -i
```

### 1.2 Anatomía de Salidas:

Ejemplo de `df -h`:
```text
S.ficheros      Tamaño Usados Disp Uso% Montado en
udev              457M      0 457M   0% /dev
tmpfs              97M   568K  96M   1% /run
/dev/sda1         6,9G   1,5G 5,1G  22% /
tmpfs             481M      0 481M   0% /dev/shm
tmpfs             5,0M      0 5,0M   0% /run/lock
```

Ejemplo de `df -i`:
```text
S.ficheros       Nodos-i  NUsados   NLibres NUso% Montado en
udev              116862      442    116420    1% /dev
tmpfs             123020      648    122372    1% /run
/dev/sda1         462384    39627    422757    9% /
```

> [!WARNING]
> **Crisis de Inodos Agotados:** Un sistema de archivos puede tener decenas de Gigabytes libres según `df -h` pero fallar con el error `No space left on device` si `df -i` marca **100% de uso**. Esto ocurre comúnmente cuando aplicaciones generan millones de archivos diminutos (ej. sesiones PHP, spoolers de correo o cachés web).

---

## 📁 2. Medición Granular de Consumo con `du`

Mientras que `df` consulta los metadatos globales del superbloque del filesystem, `du` (*Disk Usage*) recorre recursivamente los directorios para calcular el espacio real ocupado por cada archivo y carpeta.

### 2.1 Sintaxis y Opciones Principales:

```bash
du [opciones] [ruta]
```

- `-a`: Muestra todos los ficheros individuales, no solo los directorios.
- `-c`: Genera una línea final con el gran total (`total`).
- `-h`: Muestra tamaños en formato legible (`K`, `M`, `G`).
- `-s`: Modo sumario (*summary*): muestra únicamente el total del directorio indicado, sin desglosar recursivamente cada subdirectorio.
- `-S`: Excluye los subdirectorios del cómputo local del directorio contenedor (*separate dirs*).

### 2.2 Patrones de Comando para el Administrador:

```bash
# Sumario legible de un directorio específico
du -sh /var

# Gran total de un directorio desglosando componentes (-sch)
du -sch /var

# Radiografía de consumo del primer nivel de la raíz
du -sch /* 2>/dev/null

# El "Top 10" de directorios o archivos más pesados del sistema
du -h /var 2>/dev/null | sort -hr | head -n 10
```

---

## 🔧 3. Herramientas de Mantenimiento en ext2, ext3 y ext4

Los sistemas de archivos de la familia `ext` son los más extendidos en entornos Linux tradicionales. Su comportamiento y fiabilidad pueden ajustarse con herramientas nativas.

### 3.1 `tune2fs`: Ajuste de Parámetros del Superbloque

`tune2fs` permite modificar el comportamiento del sistema de archivos sin necesidad de reformatear.

#### Parámetros Clave:
1. **Modificar intervalo de comprobación por número de montajes (`-c`):**
   ```bash
   # Forzar fsck cada 30 montajes
   sudo tune2fs -c 30 /dev/sda1
   ```
2. **Consultar o alterar el contador actual de montajes (`-C`):**
   ```bash
   sudo tune2fs -C 30 /dev/sda1
   ```
3. **Modificar intervalo de comprobación por tiempo (`-i`):**
   ```bash
   # Comprobar cada 2 días (2d), 3 semanas (3w) o 1 mes (1m)
   sudo tune2fs -i 2d /dev/sda1

   # Desactivar la comprobación periódica por tiempo (0)
   sudo tune2fs -i 0 /dev/sda1
   ```
4. **Etiquetar el volumen para montaje seguro por LABEL (`-L`):**
   ```bash
   sudo tune2fs -L "DatosProduccion" /dev/sda1
   ```
5. **Modificar el porcentaje de bloques reservados para root (`-m`):**
   ```bash
   # Reducir del 5% predeterminado a 1% para recuperar Gigabytes en discos grandes
   sudo tune2fs -m 1 /dev/sda1
   ```
6. **Agregar Journaling para convertir ext2 a ext3/ext4 (`-j`):**
   ```bash
   sudo tune2fs -j /dev/sda1
   ```
7. **Forzar operaciones (`-f`):** Permite aplicar modificaciones incluso si el filesystem tiene flags de advertencia.

#### 💡 Medir Espacio e Inodos en Dispositivos NO MONTADOS:
Un administrador no necesita montar una partición para conocer su estado de ocupación. `tune2fs -l` extrae directamente las estadísticas del superbloque:

```bash
sudo tune2fs -l /dev/sda1 | egrep 'Free|(Inode|Block) count|^Block size|Reserved'
```

Salida típica:
```text
Inode count:              65536
Block count:              262144
Reserved block count:     13107
Free blocks:              111889
Free inodes:              65396
Block size:               4096
Reserved GDT blocks:      127
Reserved blocks uid:      0 (user root)
Reserved blocks gid:      0 (group root)
```
> Con esta técnica es posible calcular matemáticamente:
> - $\text{Espacio Libre} = 111889 \times 4096 \text{ bytes} \approx 458 \text{ MB}$.
> - $\text{Inodos Libres} = 65396 \text{ de } 65536 \text{ disponibles}$.

---

### 3.2 `fsck` y `e2fsck`: Verificación y Reparación de Consistencia

`fsck` (*File System Consistency Check*) es el frontend general que detecta el tipo de filesystem e invoca la herramienta específica (como `e2fsck` para ext4).

```bash
# Sintaxis básica:
# sudo fsck [opciones] dispositivo
# sudo e2fsck [opciones] dispositivo
```

> [!CAUTION]
> **REGLA DE ORO DEL SYSADMIN:** Nunca ejecutes `fsck` o `e2fsck` en modo de escritura sobre un sistema de archivos montado en lectura/escritura. Hacerlo puede corromper severamente las estructuras del disco. Desmontá primero el volumen con `umount` o montalo en modo de solo lectura (`mount -o remount,ro`).

#### Opciones más utilizadas:
- `-a`: Realiza reparaciones automáticas seguras sin solicitar confirmación interactiva.
- `-p` (*Preen*): Reparación automática recomendada para arranque del sistema (idéntico a `-a` en e2fsck).
- `-y`: Responde afirmativamente ("yes") a todas las preguntas de reparación.
- `-f`: **Fuerza** la comprobación exhaustiva del sistema de archivos incluso si está marcado como limpio (*clean*).
- `-n`: Modo de **solo lectura**: verifica el disco y muestra los errores encontrados sin realizar ninguna modificación física.
- `-c`: Invoca automáticamente el utilitario `badblocks` para buscar sectores dañados en el disco y marcarlos como defectuosos en el inodo especial `bad_inodes`.

Ejemplos de comando:
```bash
# Comprobación segura automática
sudo e2fsck -p /dev/sda1

# Comprobación forzada interactiva
sudo e2fsck -f /dev/sda1

# Comprobación con escaneo de sectores dañados
sudo e2fsck -c /dev/sda1
```

---

### 3.3 `dumpe2fs`: Radiografía Forense de Grupos de Bloques

`dumpe2fs` vuelca la información física y matemática del superbloque y los descriptores de grupos:

```bash
sudo dumpe2fs /dev/sda1 | more
```

#### Opciones principales:
- `-h`: Muestra **únicamente el encabezado del superbloque**, omitiendo los miles de descriptores de grupos de bloques.
- `-b`: Muestra los bloques que han sido reservados por el sistema.
- `-i`: Muestra detalles de la tabla de inodos.
- `-x`: Salida detallada en hexadecimal con mapas de bits de grupos de bloques e inodos.

---

## ⚡ 4. Herramientas de Mantenimiento y Optimización en XFS

XFS es un sistema de archivos de alto rendimiento diseñado para grandes volúmenes y operaciones intensivas de I/O. Posee su propio conjunto especializado de herramientas de mantenimiento.

### 4.1 `xfs_metadump`: Copia de Seguridad Forense de Metadatos

`xfs_metadump` copia los metadatos (superbloques, inodos, árboles B+ y directorios) de un sistema de archivos XFS hacia un archivo imagen compacto, **omitiendo los datos de usuario**.

Es la herramienta estándar para enviar volcados de discos a ingenieros de soporte o desarrolladores del kernel para depurar fallas sin violar la privacidad de los datos.

> [!IMPORTANT]
> `xfs_metadump` debe ejecutarse **exclusivamente sobre sistemas de archivos desmontados, montados en solo lectura o congelados** con `xfs_freeze`.

```bash
# Volcar metadatos a prueba.img con barra de progreso (-g)
sudo xfs_metadump -g /dev/sdb1 prueba.img

# Verificar el archivo generado
file prueba.img
# Salida: prueba.img: XFS filesystem metadump image
```

---

### 4.2 `xfs_db`: Inspección y Depuración de Bajo Nivel

`xfs_db` es el depurador interactivo de estructuras XFS.

```bash
# Abrir en modo solo lectura (-r)
sudo xfs_db -r /dev/sdb1
```

Dentro del intérprete interactivo, el comando `frag` analiza el nivel de fragmentación de los archivos:

```text
xfs_db> frag
actual 92517, ideal 91628, fragmentation factor 0.96%
Note, this number is largely meaningless.
Files on this filesystem average 1.01 extents per file
xfs_db> quit
```

---

### 4.3 `xfs_fsr`: Reorganizador y Desfragmentador en Caliente

El comando `xfs_fsr` (*Filesystem Reorganizer*) desfragmenta los extents del sistema de archivos XFS reorganizando los bloques contiguos para optimizar las velocidades de lectura secuencial:

```bash
# Reorganizar y desfragmentar un volumen XFS montado
sudo xfs_fsr /dev/sdb1
```

---

## 🐬 5. Herramientas de Mantenimiento en Btrfs

Btrfs (*B-tree File System*) integra gestión de volúmenes, snapshots Copy-on-Write (CoW) y detección de corrupción por checksums.

### Comandos de Gestión y Mantenimiento:

```bash
# 1. Inspeccionar el estado de los dispositivos y espacio
sudo btrfs filesystem show /mnt/btrfs
sudo btrfs filesystem df /mnt/btrfs

# 2. Balanceo de datos y metadatos:
# Redistribuye y compacta los chunks entre los discos para recuperar espacio o preparar el volumen
sudo btrfs balance start /mnt/btrfs

# 3. Creación de snapshots atómicos O(1) de subvolúmenes
sudo btrfs subvolume snapshot /mnt/btrfs/subvol1 /mnt/btrfs/snapshot1

# 4. Verificación y Reparación Fuera de Línea con Progreso:
# btrfs check opera por defecto en modo de solo lectura.
# Para reparar daños físicos en los árboles B y ver el progreso se utilizan --repair y -p:
sudo btrfs check --repair -p /dev/sda1
```

---

## 💽 6. `badblocks`: Detección de Sectores Defectuosos en Almacenamiento

El comando `badblocks` escanea dispositivos de almacenamiento (discos rígidos magnéticos, SSDs, tarjetas SD, unidades NVMe) en busca de bloques y sectores físicos corruptos o ilegibles.

### 6.1 Sintaxis Básica:

```bash
badblocks [opciones] dispositivo [archivo_de_salida]
```

### 6.2 Modos de Operación y Parámetros:

- `-s`: Muestra el porcentaje y progreso del escaneo en tiempo real.
- `-w`: **Prueba de escritura destructiva**. Escribe cuatro patrones de prueba (`0xaa`, `0x55`, `0xff`, `0x00`) en cada sector del disco y los vuelve a leer para verificar la integridad física de los platos o celdas de silicio. **Borra todos los datos del disco**.
- `-n`: **Prueba de lectura-escritura NO destructiva**. Lee los datos originales, escribe el patrón de prueba, verifica y restaura los datos originales de forma transparente.
- `-o <archivo>`: Guarda la lista con los números de bloques defectuosos en un archivo de texto.

### 6.3 Ejemplos Prácticos y Flujo de Recuperación:

```bash
# 1. Escaneo en modo solo lectura con progreso visible
sudo badblocks -s /dev/sda

# 2. Guardar los sectores defectuosos en un archivo de texto
sudo badblocks -s -o /tmp/sectores_danados.txt /dev/sda

# 3. Prueba destructiva exhaustiva en un disco recién comprado
sudo badblocks -w -s /dev/sdb

# 4. Aislar sectores dañados en el filesystem:
# Pasamos la lista a e2fsck para que ext4 nunca vuelva a asignar esos bloques
sudo e2fsck -l /tmp/sectores_danados.txt /dev/sda
```

---

## 🛠️ Demostración Práctica Interactiva (`demo_mantenimiento_volumenes.sh`)

El repositorio incluye el script didáctico interactivo [`demo_mantenimiento_volumenes.sh`](demo_mantenimiento_volumenes.sh) que simula todos los sistemas de archivos (ext4, XFS, Btrfs) mediante dispositivos virtuales loop para practicar de forma segura sin riesgo para los discos reales del servidor.

### Ejecución:
```bash
cd linux/administrator/filesystems
sudo ./demo_mantenimiento_volumenes.sh
```

### Opciones:
- `--auto <segundos>`: Ejecución automatizada con pausas temporizadas.
- `--keep`: Mantiene montados los volúmenes de prueba para experimentación manual posterior.
