---
id: lab-3.12-enlaces-hard-soft-links
title: 'Estructura de Enlaces en Filesystems: Hard Links, Symlinks y Operaciones Forenses
  con find'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.12'
sections:
- '3.12'
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
- enlaces
- hardlinks
- symlinks
- inodos
- ln
- find
- samefile
- xtype
- dentry
- forense
- zero-downtime
- rsync
- soname
- lsof
tools:
- ln
- ls
- find
- stat
- rm
- df
- rsync
- lsof
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-30'
  notes: Demostración completa de enlaces duros, symlinks, contador nlink, aislamiento
    entre particiones con loop device, auditoría forense con find (-type l -exec,
    -samefile, -xtype l) y simulación de casos reales (deploy atómico, rsync --link-dest
    y archivos abiertos unlinked con lsof).
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-30'
  notes: Compatible de manera nativa en cualquier sistema de archivos POSIX en AWS
    EC2 (EBS gp3).
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: 'Guía y laboratorio exhaustivo de autoaprendizaje sobre la arquitectura
  de enlaces en sistemas de archivos Linux. Analiza la separación fundamental del
  VFS entre entradas de directorio (dentry) e inodos, la semántica de la llamada al
  sistema unlink(), la creación de enlaces duros (ln) y su contador nlink, los enlaces
  simbólicos (ln -s) relativos y absolutos con fast symlinks, y las restricciones
  físicas entre particiones (EXDEV) y directorios. Desarrolla a fondo comandos forenses
  con find (-type l -exec ls -l {} \;, -ls, -samefile, -inum, -xtype l y -delete)
  y cuatro casos reales de producción: despliegues atómicos zero-downtime con ln -sfn,
  versionado dinámico de bibliotecas compartidas (.so SONAME), deduplicación instantánea
  de backups con rsync --link-dest, y resolución de crisis de espacio en disco por
  archivos eliminados retenidos por procesos (lsof +L1).'
files:
  guide: filesystems/enlaces_hard_soft_links.md
  script: filesystems/demo_enlaces.sh
  terraform: null
prerequisites:
- lab-3.1-anatomia-filesystems
next_recommended_labs:
- lab-3.13-mantenimiento-volumenes
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Enlaces en Filesystems (Hard Links, Symlinks y Auditoría con find)

En los sistemas operativos Unix y Linux, los archivos no son simples nombres almacenados en carpetas. Internamente existe una estricta separación arquitectural entre el **nombre visible** del archivo y la **estructura de metadatos (inodo)** que gestiona sus propiedades y sus bloques físicos en el almacenamiento.

Comprender esta separación y dominar los dos tipos de enlaces —**enlaces duros (*hard links*)** y **enlaces simbólicos (*soft links / symlinks*)**— es imprescindible para cualquier administrador de sistemas, ingeniero DevOps o especialista en infraestructura: desde diseñar despliegues de software **Zero-Downtime** y optimizar respaldos mediante deduplicación instantánea, hasta resolver crisis de espacio fantasma en disco y auditar directorios críticos con `find`.

---

## ⚡ Ruta Rápida de Autoaprendizaje (Para entenderlo en 2 minutos)

> [!TIP]
> Si necesitás repasar rápidamente el concepto antes de una entrevista técnica o para explicarlo en clase, memorizá estas dos analogías y las cinco reglas de oro.

### 💡 La Analogía Mental Definitiva

```
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│  EL ENLACE DURO (HARD LINK): Dos llaves que abren exactamente la misma caja fuerte               │
│                                                                                                   │
│  - Tenés una caja fuerte de acero (el inodo con los datos).                                       │
│  - Le entregás una llave con la etiqueta "archivo1.txt" y otra con "archivo2.txt".                │
│  - Ambas abren la misma caja física. Si cambiás lo que hay adentro con una, cambia para la otra.  │
│  - Si tirás la llave "archivo1.txt" a la basura, la caja sigue intacta y se abre con la otra.     │
│  - La caja solo se funde y se destruye cuando no queda ninguna llave en existencia.              │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│  EL ENLACE SIMBÓLICO (SOFT LINK): Un cartel con una flecha que dice "La caja está allá"          │
│                                                                                                   │
│  - El cartel es un trozo de papel nuevo e independiente (tiene su propio inodo).                  │
│  - Su único contenido es el texto con la dirección: "/habitacion/304/caja.txt".                   │
│  - Si rompés el cartel, la caja física sigue en su lugar sin enterarse.                          │
│  - Si alguien se lleva la caja a otra habitación, el cartel sigue ahí pero apunta al vacío:       │
│    acabás de crear un ENLACE ROTO (Broken / Dangling Symlink).                                   │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 📌 Las 5 Reglas de Oro Inmutables:
1. **El nombre no es el archivo:** El inodo es el archivo real. El nombre es únicamente una entrada en una tabla de directorio (`dentry`).
2. **`rm` nunca borra bloques directamente:** El comando `rm` invoca la syscall `unlink()`. Solo elimina la `dentry` y resta 1 al contador de enlaces (`nlink`). Los datos físicos solo se liberan cuando `nlink == 0` **Y** ningún proceso tiene el archivo abierto.
3. **Los Hard Links no cruzan particiones:** Pertenecen exclusivamente a un único sistema de archivos porque los números de inodo son locales a cada superbloque. Tampoco pueden apuntar a directorios para evitar bucles infinitos en el VFS.
4. **Los Symlinks son archivos de texto con una ruta:** Poseen su propio inodo, tienen permisos `lrwxrwxrwx` (los permisos efectivos los dictamina el destino) y su tamaño en bytes equivale exactamente a la cantidad de caracteres de la ruta de destino.
5. **Los Symlinks pueden cruzar cualquier frontera:** Pueden apuntar a otras particiones, discos montados por red (NFS/SMB) o directorios completos.

---

## 🏗️ Arquitectura Interna a Nivel de Filesystem (FS)

Para entender cómo opera el kernel Linux (VFS - *Virtual File System*), debemos descomponer las 4 estructuras clave presentes en sistemas de archivos tipo ext4, XFS o UFS:

```
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                                ESTRUCTURA INTERNA DEL FILESYSTEM                                  │
│                                                                                                   │
│   1. SUPERBLOQUE          2. TABLA DE DIRECTORIOS           3. TABLA DE INODOS      4. BLOQUES    │
│  ┌──────────────────┐    ┌──────────────────────────────┐  ┌───────────────────┐   ┌────────────┐ │
│  │ Magic Number     │    │ Nombre (dentry) │ Inodo Ref. │  │ Inodo: 291010     │   │ Bloque 881 │ │
│  │ Tamaño de bloque │───►├─────────────────┼────────────┤─►│ UID / GID         ├──►│            │ │
│  │ Inodos totales   │    │ documento.txt   │ 291010     │  │ Permisos: rw-r--  │   │ "Contenido │ │
│  │ Bloques libres   │    │ enlace_duro.txt │ 291010     │  │ Tamaño: 4096 B    │   │  del       │ │
│  └──────────────────┘    │ acceso.lnk      │ 584920     │  │ Links (nlink): 2  │   │  archivo"  │ │
│                          └──────────────────────────────┘  │ Punteros de datos ├──►│            │ │
│                                         │                  └───────────────────┘   └────────────┘ │
│                                         │                                                         │
│                                         ▼                                                         │
│                            ┌────────────────────────────┐                                         │
│                            │ Inodo: 584920 (S_IFLNK)    │                                         │
│                            │ Modo: lrwxrwxrwx           │                                         │
│                            │ Tamaño: 13 bytes           │                                         │
│                            │ Destino: "documento.txt"   │                                         │
│                            └────────────────────────────┘                                         │
+───────────────────────────────────────────────────────────────────────────────────────────────────+
```

### 1. Entradas de Directorio (`dentry`):
Un directorio en Linux no es un contenedor físico especial; es simplemente un archivo especial cuyo contenido es una **tabla de correspondencias** entre cadenas de texto (nombres) y números de inodo:
```text
Nombre legible              -> Número de Inodo
"documento.txt"             -> 291010
"enlace_duro.txt"           -> 291010
"acceso.lnk"                -> 584920
```

### 2. El Inodo (*Index Node* - `struct ext4_inode`):
Es la estructura fundamental de almacenamiento. No contiene el nombre del archivo, sino todos sus atributos de control:
- Identificadores de usuario y grupo (`UID`, `GID`).
- Modo de archivo (`permissions`, flags de ejecución).
- Marcas de tiempo (`atime`, `mtime`, `ctime`, `crtime`).
- Punteros directos, indirectos o árboles de extents hacia los bloques físicos de datos.
- **Contador de enlaces duros (`i_links_count` / `nlink`):** Número de dentries que apuntan a este inodo en todo el sistema de archivos.

### 3. Fast Symlinks vs Slow Symlinks:
- **Fast Symlink:** Si la ruta del destino del enlace simbólico es corta (en ext4, menor o igual a **60 bytes**), el kernel almacena la cadena de texto directamente dentro del espacio del inodo reservado para los punteros de bloques. **No consume ningún bloque de datos del disco**.
- **Slow Symlink:** Si la ruta excede los 60 bytes, el inodo asigna un bloque de datos tradicional de 4 KiB para guardar la cadena de texto con la ruta.

---

## 🔗 1. Enlace Duro (*Hard Link*) en Detalle

Un enlace duro consiste en crear una **nueva entrada de directorio (`dentry`)** que apunta a un inodo preexistente.

### Comportamiento Operativo:
- **Indistinguibles:** Para el sistema operativo, `archivo1` y `archivo2` son exactamente el mismo archivo con dos nombres distintos. No hay un "padre" ni un "hijo".
- **Sincronización total:** Al escribir datos en uno, se leen inmediatamente en el otro porque leen y escriben sobre los mismos sectores físicos.
- **Ciclo de vida por decremento (`nlink`):**
  - Creación de archivo base: `nlink = 1`.
  - Creación de hard link: `nlink = 2`.
  - Ejecutar `rm archivo1`: El kernel ejecuta la syscall `unlink("archivo1")`. Elimina la dentry de la tabla del directorio y reduce `nlink` a `1`.
  - **Los datos no se borran.** `archivo2` sigue accediendo a los bloques con total normalidad.
  - Solo cuando `nlink` llega a `0` y no hay procesos con descriptores abiertos, el kernel marca el inodo y sus bloques como libres en los bitmaps del filesystem.

### ⚠️ Restricciones Técnicas Absolutas:
1. **Prohibido cruzar sistemas de archivos (*Cross-Device Link - EXDEV*):**
   Los números de inodo son únicos únicamente dentro de la partición gobernada por su superbloque. El inodo `1042` de `/dev/sda1` no tiene ninguna relación con el inodo `1042` de `/dev/nvme0n1p1`. Si intentás hacer un enlace duro entre dos puntos de montaje distintos, el kernel rechaza la llamada con:
   ```text
   ln: failed to create hard link 'destino': Invalid cross-device link (EXDEV)
   ```
2. **Prohibido enlazar directorios:**
   Para garantizar que la estructura jerárquica del sistema de archivos sea un grafo acíclico dirigido (árbol VFS) y evitar bucles infinitos en herramientas de recorrido (`find`, `du`, `tar`) o corrupciones en las entradas `.` y `..`, el kernel prohíbe enlaces duros a directorios (`EPERM`).

---

## 🔀 2. Enlace Simbólico (*Soft Link / Symlink*) en Detalle

Un enlace simbólico es un **archivo independiente** de tipo `l` (`S_IFLNK`) cuyo contenido es la ruta hacia otro archivo o carpeta.

### Comportamiento Operativo:
- **Inodo propio:** Consume su propio inodo y un tamaño reportado equivalente a la longitud en caracteres de la ruta destino.
- **Permisos virtuales `lrwxrwxrwx`:** Los permisos del enlace simbólico en sí son irrelevantes; el kernel siempre evalúa los permisos del **archivo destino** al resolver la ruta.
- **Rutas Relativas vs Rutas Absolutas:**
  - **Absoluta (`ln -s /var/log/app.log /tmp/app.log`):** Funciona desde cualquier lugar del sistema, pero se rompe si se cambia la raíz del sistema de archivos (ej. dentro de un contenedor Docker, chroot o si se monta el disco como esclavo en `/mnt`).
  - **Relativa (`ln -s ../configs/app.conf ./app.conf`):** Es altamente portable. Si movés toda la estructura de directorios a otro servidor o ruta, el enlace continúa funcionando intacto.
- **Enlaces Rotos (*Dangling / Broken Symlinks*):**
  Si el archivo o carpeta de destino se elimina o renombra, el symlink sigue apuntando a una ruta que ya no existe. Cualquier intento de lectura retornará el error `ENOENT`:
  ```text
  cat: enlace_roto: No such file or directory
  ```

---

## 🔍 3. Auditoría Forense y Operaciones con `find`

En servidores corporativos con millones de archivos, los administradores deben rastrear enlaces duros ocultos, auditar symlinks del sistema y limpiar enlaces rotos que provocan caídas en pipelines de despliegue o scripts de cron.

### 3.1 Localizar todos los enlaces simbólicos en `/etc/`
Para encontrar todos los symlinks en un directorio jerárquico como `/etc/`:

```bash
find /etc/ -type l -exec ls -l {} \;
```

#### 🔬 Disección minuciosa del comando:
- `find /etc/`: Punto de inicio del escaneo recursivo.
- `-type l`: Filtra exclusivamente elementos cuyo tipo de inodo sea enlace simbólico (`S_IFLNK`).
- `-exec`: Indica a `find` que por cada coincidencia debe ejecutar el comando que sigue.
- `ls -l`: Lista en formato largo para revelar permisos (`lrwxrwxrwx`), tamaño y la flecha `->` apuntando al destino.
- `{}`: Marcador de posición (*placeholder*) que `find` reemplaza automáticamente por la ruta de cada archivo encontrado.
- `\;`: Delimitador que indica el final del comando a ejecutar. La barra invertida `\` escapa el punto y coma `;` para que la shell no lo interprete antes de tiempo. Con `\;`, se invoca una instancia independiente de `ls` por cada archivo encontrado.

#### ⚡ Comparativa de Rendimiento:
| Variante del Comando | Comportamiento en el Kernel | Nivel de Sobrecarga |
| :--- | :--- | :--- |
| `find /etc/ -type l -exec ls -l {} \;` | Ejecuta un `fork()` + `exec()` **por cada archivo**. | Alto en miles de archivos. |
| `find /etc/ -type l -exec ls -l {} +` | Agrupa cientos de archivos en una sola llamada (como `xargs`). | **Bajo y muy rápido**. |
| `find /etc/ -type l -ls` | Utiliza la acción nativa integrada de `find` sin generar subprocesos. | **Instantáneo (0 fork/exec)**. |

---

### 3.2 Localizar todos los Enlaces Duros compartidos (`-samefile`, `-inum`, `-links`)
Dado que los hard links no tienen un puntero hacia el original, para saber qué otros archivos comparten el mismo inodo debemos escanear el sistema de archivos:

```bash
# 1. Buscar todas las dentries que comparten el inodo con un archivo de referencia
find /var/www -xdev -samefile index.html

# 2. Buscar por número de inodo directo (obtenido con stat)
INODE=$(stat -c '%i' index.html)
find /var/www -xdev -inum "$INODE"

# 3. Localizar todos los archivos regulares que tengan más de 1 hard link (nlink > 1)
find /var/www -type f -links +1
```
> [!IMPORTANT]
> Agregá siempre la opción `-xdev` (o `-mount`). Como los hard links no pueden cruzar particiones, `-xdev` evita perder tiempo escaneando otros discos montados, `/proc`, `/sys` o recursos NFS de red.

---

### 3.3 Detección y Limpieza de Enlaces Rotos (*Dangling Symlinks*)
Un enlace roto apunta a un destino inexistente. El operador `-xtype` de `find` evalúa el tipo del **destino desreferenciado**:
- Si el destino existe y es un archivo, `-type l` es verdadero y `-xtype f` es verdadero.
- Si el destino **no existe** (enlace roto), la desreferenciación falla y `-xtype l` devuelve verdadero.

```bash
# 1. Encontrar todos los symlinks rotos en el directorio actual
find . -xtype l

# 2. Inspeccionar a dónde apuntaban los enlaces rotos
find . -xtype l -exec ls -l {} \;

# 3. Eliminar de forma automatizada y segura todos los enlaces rotos
find . -xtype l -delete
```

---

### 3.4 El misterio del "Espacio Fantasma": Archivos eliminados con procesos abiertos
Un problema clásico en producción ocurre cuando se borra un archivo gigante de log con `rm /var/log/app.log`:
- `du -sh /var/log` reporta que el directorio está vacío.
- `df -h /` sigue mostrando el disco **100% ocupado**.

**¿Por qué sucede?**
El comando `rm` ejecutó `unlink()`, eliminó la dentry del directorio y redujo `nlink` a `0`. Sin embargo, el proceso de la aplicación sigue en ejecución y mantiene el descriptor de archivo (`file descriptor`) abierto en memoria. Mientras el proceso no cierre el archivo o muera, el kernel **no libera los bloques de datos**.

```bash
# Detectar archivos con nlink = 0 retenidos por procesos en ejecución
lsof +L1

# O filtrar directamente por archivos eliminados
lsof / | grep '(deleted)'
```

**Solución sin reiniciar el servicio:**
Podés truncar el archivo a 0 bytes escribiendo directamente en su descriptor en `/proc`:
```bash
# Reemplazá <PID> y <FD> con los valores obtenidos de lsof
> /proc/<PID>/fd/<FD>
```

---

## 🏢 Casos Reales de Producción en Linux

A continuación se detallan cuatro casos de uso estándar que todo ingeniero encuentra en entornos corporativos:

### Caso Real 1: Despliegues Atómicos Zero-Downtime con Symlinks
Herramientas como Capistrano, Laravel Envoy, Deployer o los pipelines de Kubernetes utilizan enlaces simbólicos para cambiar versiones de código en 1 milisegundo sin interrumpir las peticiones HTTP de los clientes:

```
/var/www/app/
├── releases/
│   ├── 2026-10-25_v1.0/   (Versión previa)
│   └── 2026-10-30_v2.0/   (Nueva versión ya construida y probada)
└── current ──► releases/2026-10-30_v2.0/
```

Nginx apunta siempre a:
```nginx
root /var/www/app/current/public;
```

#### El comando de cambio atómico (`ln -sfn`):
```bash
# -s: simbólico
# -f: forzar sobrescritura
# -n: no seguir el symlink si apunta a un directorio (tratar current como archivo)
ln -sfn /var/www/app/releases/2026-10-30_v2.0 /var/www/app/current
```

**Rollback Instantáneo:** Si la versión 2.0 arroja errores en producción, el rollback toma menos de 1 segundo:
```bash
ln -sfn /var/www/app/releases/2026-10-25_v1.0 /var/www/app/current
```

---

### Caso Real 2: Versionado Dinámico de Bibliotecas Compartidas (`.so` SONAME)
En `/usr/lib/x86_64-linux-gnu/`, el sistema operativo organiza las bibliotecas dinámicas utilizando una jerarquía de symlinks:

```text
libssl.so       -> libssl.so.3          (Enlace para compilar código con gcc -lssl)
libssl.so.3     -> libssl.so.3.0.13     (SONAME: Lo que busca el Dynamic Linker ld.so al iniciar apps)
libssl.so.3.0.13                        (Archivo binario ELF físico compilado en el disco)
```

**Ventaja:** Cuando Canonical o Red Hat publican un parche de seguridad crítico (ej. `libssl.so.3.0.14`), el gestor de paquetes copia el archivo nuevo y actualiza el symlink `libssl.so.3 -> libssl.so.3.0.14`. **Todos los ejecutables del sistema quedan parcheados sin necesidad de recompilar ningún binario.**

---

### Caso Real 3: Deduplicación y Backups Instantáneos con `rsync --link-dest`
Herramientas como Apple Time Machine, BackupPC o scripts de respaldo empresariales crean copias diarias completas que consumen únicamente el espacio de los archivos que cambiaron:

```bash
# Crear el backup del día de hoy usando el de ayer como base de hard links
rsync -a --delete \
  --link-dest=/backups/2026-10-29/ \
  /datos/empresa/ \
  /backups/2026-10-30/
```

**Mecanismo interno:**
- Si un archivo de 2 GB no cambió entre ayer y hoy, `rsync` no copia los datos: **crea un Hard Link hacia el inodo del backup de ayer**.
- El backup de hoy parece una copia 100% completa y navegable, pero consumió **0 bytes** de espacio nuevo en disco.
- Si borrás el backup de ayer, el de hoy continúa intacto porque el contador `nlink` pasa de 2 a 1.

---

### Caso Real 4: Habilitación y Enmascaramiento de Servicios en Systemd
Systemd gestiona los servicios que deben iniciar en el arranque creando symlinks dentro de directorios `.wants/`:

```bash
# Habilitar Nginx para que inicie en el arranque:
sudo systemctl enable nginx
# Crea el symlink:
# /etc/systemd/system/multi-user.target.wants/nginx.service -> /lib/systemd/system/nginx.service

# Deshabilitar Nginx:
sudo systemctl disable nginx
# Simplemente elimina el symlink del directorio .wants/

# Enmascarar Nginx (impedir que nadie lo inicie, ni manual ni por dependencias):
sudo systemctl mask nginx
# Crea un symlink hacia /dev/null:
# /etc/systemd/system/nginx.service -> /dev/null
```

---

## ⚖️ Tabla Comparativa Definitiva

| Criterio Técnico | Enlace Duro (*Hard Link*) | Enlace Simbólico (*Soft Link / Symlink*) |
| :--- | :--- | :--- |
| **Comando de creación** | `ln archivo destino` | `ln -s archivo destino` |
| **Asignación de Inodo** | Comparte exactamente el mismo inodo original. | Inodo nuevo e independiente (`S_IFLNK`). |
| **Consumo de espacio nuevo** | 0 bytes de bloques de datos adicionales. | Solo el texto de la ruta (Fast Symlink: 0 bloques). |
| **¿Cruza particiones o discos?** | ❌ **No** (Error `EXDEV - Invalid cross-device link`). |  **Sí** (cruza cualquier montaje, red o tmpfs). |
| **¿Apunta a directorios?** | ❌ **No** (prohibido por el kernel para evitar bucles). |  **Sí** (totalmente soportado). |
| **Si se borra el original...** | Los datos persisten intactos mientras `nlink > 0`. | Queda roto (*Broken / Dangling*) con error `ENOENT`. |
| **Inspección de inodo** | `ls -li` o `stat` (segunda columna: `Links > 1`). | `ls -l` (permisos `lrwxrwxrwx`, tamaño = largo de ruta). |
| **Búsqueda con find** | `find / -xdev -samefile archivo` o `-inum INODO` | `find / -type l -exec ls -l {} \;` o `-ls` |
| **Detección de enlaces rotos** | No aplica (no existe el concepto de huérfano). | `find . -xtype l` (purgar con `-delete`). |

---

## 🧪 Mini-Laboratorio Práctico de Autoaprendizaje (15 minutos)

Podés ejecutar estos cuatro mini-labs directamente en tu terminal (en `/tmp`) para experimentar de primera mano cada fenómeno:

### Mini-Lab 1: Rompiendo el mito del "archivo original" (Hard Links)
```bash
cd /tmp
echo "Datos ultra secretos v1.0" > secreto.txt

# 1. Crear hard link
ln secreto.txt copia_duro.txt

# 2. Verificar inodos y contador nlink (debe ser 2)
ls -li secreto.txt copia_duro.txt

# 3. Modificar a través del enlace duro
echo "Nueva línea agregada" >> copia_duro.txt
cat secreto.txt

# 4. Borrar el supuesto "original"
rm secreto.txt

# 5. Comprobar que los datos siguen existiendo
cat copia_duro.txt
stat copia_duro.txt | grep Links
# (Observá que Links bajó a 1; el inodo sobrevivió)
```

### Mini-Lab 2: Symlinks Relativos vs Absolutos
```bash
mkdir -p /tmp/lab_symlinks/{origen,enlaces}
echo "Configuración de Base de Datos" > /tmp/lab_symlinks/origen/db.conf

# Crear uno absoluto y uno relativo dentro de /tmp/lab_symlinks/enlaces
ln -s /tmp/lab_symlinks/origen/db.conf /tmp/lab_symlinks/enlaces/abs.lnk
ln -s ../origen/db.conf /tmp/lab_symlinks/enlaces/rel.lnk

# Comprobar que ambos leen correctamente
cat /tmp/lab_symlinks/enlaces/abs.lnk
cat /tmp/lab_symlinks/enlaces/rel.lnk

# Mover la carpeta completa a otra ubicación
mv /tmp/lab_symlinks /tmp/lab_movido

# ¿Cuál sobrevivió?
cat /tmp/lab_movido/enlaces/rel.lnk   #  FUNCIONA (ruta relativa mantenida)
cat /tmp/lab_movido/enlaces/abs.lnk   # ❌ FALLA (busca /tmp/lab_symlinks que ya no existe)
```

### Mini-Lab 3: Cacería forense con `find` y limpieza de rotos
```bash
cd /tmp
mkdir -p caceria && cd caceria
touch real.txt
ln -s real.txt symlink_bueno.lnk
ln -s inexistente.txt symlink_roto.lnk

# Listar todos los symlinks como en /etc:
find . -type l -exec ls -l {} \;

# Detectar únicamente los rotos:
find . -xtype l

# Purgar los rotos en un solo paso:
find . -xtype l -delete
ls -l
```

### Mini-Lab 4: Simulación de Deploy Atómico Zero-Downtime
```bash
cd /tmp
mkdir -p deploy/{releases/v1,releases/v2}
echo "<h1>Bienvenido a la Versión 1.0</h1>" > deploy/releases/v1/index.html
echo "<h1>Bienvenido a la Versión 2.0 (Nueva)</h1>" > deploy/releases/v2/index.html

# Apuntar a la versión 1
ln -sfn /tmp/deploy/releases/v1 /tmp/deploy/current
cat /tmp/deploy/current/index.html

# Despliegue atómico a la versión 2:
ln -sfn /tmp/deploy/releases/v2 /tmp/deploy/current
cat /tmp/deploy/current/index.html

# Rollback de emergencia:
ln -sfn /tmp/deploy/releases/v1 /tmp/deploy/current
cat /tmp/deploy/current/index.html
```

---

## 🎯 Preguntas de Autoevaluación ("Ponte a prueba")

<details>
<summary><b>1. Si ejecuto <code>chmod 777 enlace_simbolico</code>, ¿qué permisos cambian en el sistema?</b></summary>
<br>
<b>Respuesta:</b> Cambian los permisos del <b>archivo de destino</b>, no del symlink. Los symlinks en Linux siempre muestran <code>lrwxrwxrwx</code>, pero el kernel evalúa la llamada <code>chmod</code> sobre el destino desreferenciado. (Para modificar los atributos del enlace propiamente dicho, algunas herramientas utilizan la flag <code>-h</code> o syscalls como <code>lchmod</code>, aunque en Linux los permisos del symlink no restringen el acceso).
</details>

<details>
<summary><b>2. ¿Por qué al ejecutar <code>ln /etc/resolv.conf /tmp/resolv_copia</code> recibo el error <code>Invalid cross-device link (EXDEV)</code>?</b></summary>
<br>
<b>Respuesta:</b> Porque en la gran mayoría de distribuciones modernas de Linux, el directorio <code>/tmp</code> está montado sobre un sistema de archivos independiente en memoria RAM de tipo <code>tmpfs</code>, mientras que <code>/etc</code> reside en la partición raíz en disco (ext4, XFS o Btrfs). Dado que los inodos son locales a cada filesystem, un enlace duro no puede cruzar la frontera entre dos superbloques distintos.
</details>

<details>
<summary><b>3. ¿Cómo encontrarías en todo el sistema todos los archivos que tienen exactamente 3 enlaces duros?</b></summary>
<br>
<b>Respuesta:</b> Utilizando el operador <code>-links</code> de find:
<br>
<code>sudo find / -xdev -type f -links 3 -ls</code>
</details>

<details>
<summary><b>4. Si un script en producción está fallando porque un archivo dice existir según un chequeo pero falla al abrirse con <code>No such file or directory</code>, ¿cuál es la causa más probable?</b></summary>
<br>
<b>Respuesta:</b> Se trata de un <b>enlace simbólico roto (*broken symlink*)</b>. La entrada en el directorio existe (por lo que herramientas como <code>ls</code> lo ven), pero al intentar abrirlo, el kernel intenta desreferenciar la ruta de destino y devuelve el error <code>ENOENT</code>. Se audita de inmediato con <code>find . -xtype l</code>.
</details>

---

## 🛠️ Demostración Práctica Interactiva (`demo_enlaces.sh`)

El repositorio incluye el script didáctico interactivo [`demo_enlaces.sh`](demo_enlaces.sh) que simula todos los escenarios de enlaces en vivo, crea discos virtuales loop para demostrar la restricción entre particiones, ejecuta las búsquedas forenses con `find` y reproduce los casos reales de producción (despliegue atómico, rsync link-dest y archivos abiertos unlinked).

### Ejecución:
```bash
cd linux/administrator/filesystems
sudo ./demo_enlaces.sh
```

### Opciones de ejecución:
- `--auto <segundos>`: Modo automatizado para clases grabadas o testing continuo (ej. `sudo ./demo_enlaces.sh --auto 2`).
- `--keep`: Preserva los directorios y archivos de prueba creados en `/tmp` para inspección manual post-laboratorio.
