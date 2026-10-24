---
id: lab-3.12-enlaces-hard-soft-links
title: 'Estructura de Enlaces en Filesystems: Hard Links, Symlinks y Operaciones Forenses con find'
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
tools:
- ln
- ls
- find
- stat
- rm
- df
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
  test_date: '2026-10-24'
  notes: Demostración completa de enlaces duros, symlinks, contador nlink, aislamiento entre particiones con loop device y auditoría con find -samefile y -xtype l.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Compatible de manera nativa en cualquier sistema de archivos POSIX en AWS EC2.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio exhaustivo sobre la estructura y semántica de enlaces en sistemas de archivos Linux. Analiza la separación entre entradas de directorio (dentry) e inodos en el VFS, creación de enlaces duros (ln) y su contador de referencias (nlink), creación de enlaces simbólicos (ln -s) relativos y absolutos, demostración práctica de las restricciones entre particiones y operaciones forenses con find (-samefile para enlaces duros y -xtype l para enlaces rotos).
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

En los sistemas operativos Unix y Linux, los archivos no son simples nombres en una carpeta. Internamente existe una clara separación arquitectural entre el **nombre visible** del archivo y la **estructura de datos** que almacena sus atributos y su contenido en el disco.

Comprender esta separación y dominar los dos tipos de enlaces —**enlaces duros (*hard links*)** y **enlaces simbólicos o blandos (*soft links / symlinks*)**— es fundamental para administrar servidores, diseñar respaldos consistentes, organizar aplicaciones y resolver problemas forenses de espacio en disco.

---

## 🏗️ Arquitectura Interna: Dentry vs Inodo

En la capa VFS (*Virtual File System*) del kernel Linux:

1. **Directorio (`dentry`):** Un directorio es una tabla que asocia **nombres de archivo legibles** con **números de inodo**.
2. **Inodo (*Index Node*):** Es la estructura de datos en el disco que contiene los metadatos del archivo:
   - Propietario (`UID`) y Grupo (`GID`).
   - Permisos de acceso (`rwxr-xr-x`).
   - Tamaño exacto en bytes.
   - Marcas de tiempo (`atime`, `mtime`, `ctime`).
   - Punteros a los bloques físicos de datos en el disco.
   - **Contador de enlaces duros (`nlink` / link count).**
3. **Bloques de Datos:** El contenido binario real del archivo almacenado en sectores del disco.

```
+---------------------------------------------------------------------------------------------------+
| ENLACE DURO (HARD LINK)                                                                           |
|                                                                                                   |
|  [ Nombre: archivo1.txt ] ──┐                                                                     |
|                              ├─► [ Inodo: 291010 | nlink: 2 ] ──► [ Bloques de Datos: "Hola" ]   |
|  [ Nombre: archivo2.txt ] ──┘                                                                     |
+---------------------------------------------------------------------------------------------------+
| ENLACE SIMBÓLICO (SOFT LINK / SYMLINK)                                                            |
|                                                                                                   |
|  [ Nombre: acceso_directo ] ──► [ Inodo: 584920 ] ──► [ Bloque: "/home/user/archivo1.txt" ]       |
|                                                                          │                        |
|                                                                          ▼                        |
|                                                              [ Inodo: 291010 (Destino) ]          |
+---------------------------------------------------------------------------------------------------+
```

---

## 🔗 1. Enlace Duro (*Hard Link*)

Un enlace duro es una **segunda entrada de directorio** asociada directamente al **mismo inodo**.

### Características Fundamentales:
- **Indistinguibles:** No existe diferencia jerárquica entre el "original" y la "copia". Ambos son nombres equivalentes que apuntan al mismo inodo.
- **Mismo contenido y metadatos:** Si modificás el contenido de uno, el otro se actualiza inmediatamente porque leen los mismos bloques físicos. Si cambiás permisos con `chmod`, cambian para ambos.
- **Ciclo de vida gobernado por `nlink`:**
  - Al crear un archivo, su inodo tiene `nlink = 1`.
  - Al crear un hard link, `nlink` sube a `2`.
  - Si borrás uno de los archivos con `rm`, el kernel simplemente elimina la entrada del directorio y decrementa `nlink` a `1`.
  - **El archivo y sus bloques no se liberan ni se borran del disco hasta que `nlink` llegue a `0`** y ningún proceso lo tenga abierto.

### Sintaxis y Verificación:

```bash
# Crear un enlace duro
ln fichero1 fichero2

# Verificar que ambos comparten exactamente el mismo número de inodo (-i)
ls -i fichero[12]
```

Ejemplo de salida en terminal:
```text
291010 fichero1   291010 fichero2
```

Inspección detallada con `ls -l` o `stat`:
```bash
ls -l fichero[12]
# -rw-r--r-- 2 rino rino 1024 oct 24 10:00 fichero1
# -rw-r--r-- 2 rino rino 1024 oct 24 10:00 fichero2
```
> El número `2` tras los permisos indica el contador de enlaces duros (`nlink`).

### ⚠️ Restricciones Técnicas de los Enlaces Duros:
1. **No pueden cruzar sistemas de archivos (*Cross-device link*):** Los inodos son números locales e independientes en cada superbloque. El inodo `291010` de `/dev/sda1` no tiene ninguna relación con el inodo `291010` de `/dev/sdb1`. Intentar crear un enlace duro entre discos arroja el error del kernel:
   ```text
   ln: failed to create hard link 'fichero2': Invalid cross-device link (EXDEV)
   ```
2. **No se permiten en directorios:** Para prevenir ciclos infinitos y grafos circulares en el árbol jerárquico del VFS, el kernel prohíbe enlaces duros a directorios a usuarios normales y a root.

---

## 🔀 2. Enlace Simbólico o Blando (*Symbolic Link / Soft Link*)

Un enlace simbólico es un **archivo especial e independiente** cuyo bloque de datos contiene la **ruta de texto** (absoluta o relativa) hacia el archivo o directorio de destino.

### Características Fundamentales:
- **Inodo independiente:** Posee su propio número de inodo y tamaño igual a la cantidad de caracteres de la ruta de destino.
- **Tipo de archivo `l`:** En `ls -l` se identifica con una `l` al inicio de los permisos (`lrwxrwxrwx`) y muestra una flecha `->` apuntando al destino.
- **Rutas Relativas vs Absolutas:**
  - **Absoluta:** Apunta a la raíz (ej. `/home/educacionit/fichero`). Si el directorio se mueve a otro servidor o ruta, puede fallar si la ruta absoluta cambia.
  - **Relativa:** Apunta con relación a su directorio padre (ej. `../configs/app.conf`). Muy portable al mover directorios completos.
- **Flexibilidad total:**
  - Puede cruzar diferentes particiones, discos y montajes de red (NFS, SMB).
  - Puede apuntar a carpetas y directorios.
- **Enlaces Rotos (*Broken / Dangling Symlinks*):** Si el archivo destino se elimina o renombra, el symlink sigue existiendo pero apunta a un destino inexistente. Cualquier intento de lectura retornará `No such file or directory`.

### Sintaxis y Verificación:

```bash
# Crear un enlace simbólico con la opción -s
ln -s /home/educacionit/fichero /tmp/fichero

# Inspeccionar el enlace simbólico
ls -l /tmp/fichero
```

Ejemplo de salida en terminal:
```text
lrwxrwxrwx 1 educacionit educacionit 25 jun 29 15:24 /tmp/fichero -> /home/educacionit/fichero
```

#### Análisis de la salida:
- `l`: Identificador de tipo enlace simbólico.
- `rwxrwxrwx`: Los permisos de un symlink son siempre permisivos en el enlace; los permisos efectivos evaluados por el kernel son los del **archivo destino**.
- `25`: Tamaño en bytes del symlink, que coincide exactamente con los 25 caracteres de la cadena `"/home/educacionit/fichero"`.
- `-> /home/educacionit/fichero`: Destino referenciado.

---

## 🔍 3. Operaciones Avanzadas y Auditoría con `find`

En servidores de producción con millones de archivos, los administradores deben auditar enlaces duros ocultos, enlaces simbólicos activos y limpiar enlaces rotos que causan fallos en scripts.

### 3.1 Localizar todos los enlaces simbólicos
Para listar todos los enlaces simbólicos en un directorio y sus subdirectorios:

```bash
find /etc/ -type l -exec ls -l {} \;
```

O de forma más eficiente y compacta con la directiva interna `-ls`:
```bash
find /etc/ -type l -ls
```

Ejemplo de salida:
```text
lrwxrwxrwx 1 root root 18 abr 27 14:25 /etc/xdg/systemd/user -> ../../systemd/user
lrwxrwxrwx 1 root root 13 abr 27 16:35 /etc/rc2.d/S01ssh -> ../init.d/ssh
lrwxrwxrwx 1 root root 19 abr 27 14:25 /etc/rc2.d/S01zfs-mount -> ../init.d/zfs-mount
```

---

### 3.2 Localizar enlaces duros al mismo archivo (`-samefile`)
Dado que los enlaces duros comparten el mismo inodo y no tienen ningún puntero especial, localizarlos requiere buscar todas las entradas del sistema de archivos que compartan ese inodo.

El comando `find` ofrece el operador `-samefile`:

```bash
# Buscar todos los enlaces duros asociados a archivo.txt dentro de un directorio
find /home/usuario -samefile archivo.txt
```

> [!TIP]
> Dado que los hard links no pueden cruzar sistemas de archivos, es una buena práctica agregar la opción `-xdev` para no perder tiempo escaneando otras particiones o montajes de red:
> ```bash
> find / -xdev -samefile /var/log/critical.log
> ```
> Alternativamente, se puede buscar por el número de inodo exacto obtenido con `stat`:
> ```bash
> INODE=$(stat -c '%i' archivo.txt)
> find /home/usuario -xdev -inum "$INODE"
> ```

---

### 3.3 Localizar y Limpiar Enlaces Rotos (`-xtype l`)
Un enlace simbólico roto ocurre cuando su archivo de destino fue eliminado o movido.

El operador `-xtype` evalúa el tipo de archivo del **destino** al que apunta el enlace:
- Si el destino existe y es un archivo regular, `-type l` da verdadero, pero `-xtype f` da verdadero sobre el enlace.
- Si el destino **no existe** (enlace roto), `-xtype l` da verdadero.

```bash
# Localizar todos los enlaces rotos en el directorio actual
find . -xtype l
```

Ejemplo de salida:
```text
./enlace_huerfano
./app/config_antigua.json
```

Para ver el destino faltante de cada enlace roto:
```bash
find . -xtype l -exec ls -l {} \;
```

Para **eliminar de forma segura y automatizada** todos los enlaces rotos encontrados:
```bash
find . -xtype l -delete
```

---

## ⚖️ Tabla Comparativa Definitiva

| Criterio | Enlace Duro (*Hard Link*) | Enlace Simbólico (*Soft Link*) |
| :--- | :--- | :--- |
| **Comando de creación** | `ln archivo destino` | `ln -s archivo destino` |
| **Relación con Inodo** | Comparte el mismo inodo del original. | Posee su propio inodo nuevo. |
| **Espacio adicional en disco** | 0 bytes de bloques nuevos de datos. | Consume un inodo y bloque para el path. |
| **¿Cruza particiones/discos?** | ❌ **No** (restringido a la misma partición). |  **Sí** (cruza cualquier montaje o red). |
| **¿Apunta a directorios?** | ❌ **No** (prohibido por el kernel). |  **Sí** (totalmente soportado). |
| **Si se borra el original...** | Los datos **persisten** intactos mientras `nlink > 0`. | Queda **roto** (*broken symlink*). |
| **Comando de detección** | `find /dir -samefile archivo` o `-inum` | `find /dir -type l` |
| **Detección de huérfanos** | No aplica (no hay concepto de huérfano). | `find /dir -xtype l` |

---

## 🛠️ Demostración Práctica Interactiva (`demo_enlaces.sh`)

El repositorio incluye el script didáctico interactivo [`demo_enlaces.sh`](demo_enlaces.sh) que simula todos los escenarios de enlaces, crea discos virtuales loop para demostrar la restricción entre particiones y ejecuta las búsquedas forenses con `find`.

### Ejecución:
```bash
cd linux/administrator/filesystems
sudo ./demo_enlaces.sh
```

### Opciones:
- `--auto <segundos>`: Modo automatizado para clases grabadas o testing continuo.
- `--keep`: Deja los directorios y archivos de prueba montados para inspección manual.
