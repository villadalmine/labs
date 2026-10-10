# Guía de Clase: Procesos, Systemd y Gestión de Almacenamiento

Esta guía está diseñada para ser leída paso a paso durante la clase. Contiene laboratorios prácticos y explicaciones teóricas listas para los alumnos.

---

## PARTE 1: Gestión de Procesos en Linux

### 1.1 Ejemplos Prácticos con `ps` (Para mostrar en clase)

El comando `ps` (Process Status) es la radiografía del sistema. Aquí tienes los ejemplos más visuales para ejecutar en vivo:

**A. El clásico absoluto (Todos los procesos del sistema)**
`ps aux`
*Explicación para la clase:* `a` (todos los usuarios), `u` (formato detallado con usuario y % de uso), `x` (procesos que no están atados a una terminal, como demonios).

**B. Los "Top 5" que más CPU consumen**
`ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 6`
*Explicación:* `-e` (todos), `-o` (elegimos las columnas exactas). `--sort=-%cpu` ordena de mayor a menor. Ideal para cazar programas bloqueados.

**C. Los "Top 5" que más Memoria RAM devoran**
`ps -eo pid,user,%mem,cmd --sort=-%mem | head -n 6`

**D. Ver la relación Padre-Hijo (Árbol de procesos)**
`pstree -p`
*Explicación:* Permite ver cómo `systemd` (PID 1) genera todos los demás procesos en formato de árbol.

---

### 1.2 Laboratorio: Activar la automatización con Systemd

Asumiendo que ya creamos el script en `/usr/local/bin/monitor_recursos.sh` y las unidades en `/etc/systemd/system/`, ejecutamos lo siguiente para darle vida a la automatización:

1. Dar permisos de ejecución al script:
`sudo chmod +x /usr/local/bin/monitor_recursos.sh`

2. Recargar systemd para que detecte los nuevos archivos:
`sudo systemctl daemon-reload`

3. Activar y arrancar el timer:
`sudo systemctl enable --now monitor.timer`

4. Esperar un minuto y leer los resultados generados:
`cat /tmp/cpu.log`
`cat /tmp/memoria.log`

---
---

## PARTE 2: Gestión de Discos y Almacenamiento

### 2.1 Herramientas Necesarias

¿Qué instalar? En un servidor nuevo siempre conviene asegurar estas herramientas:

`sudo apt update && sudo apt install lvm2 parted smartmontools ncdu xfsprogs btrfs-progs`

*   **Clásicas preinstaladas:** `fdisk` (particionar), `lsblk` (listar), `df` / `du` (uso de espacio).
*   **Extras:** `parted` (para discos > 2TB GPT), `smartmontools` (salud del disco físico), `ncdu` (explorador visual interactivo en terminal).

### 2.2 Explorar y Manejar Discos

**Para ver qué discos físicos están conectados:**
`lsblk`
*Explicación:* Muestra los discos crudos (`sda`, `sdb`) y sus particiones (`sda1`, `sda2`).

**Para ver cuánto espacio libre queda (Legible por humanos):**
`df -h`

**Particionar un disco nuevo (ejemplo /dev/sdb):**
`sudo fdisk /dev/sdb`
*(Presionar 'n' para nueva, 'p' primaria, 'w' para guardar).*

### 2.3 Tipos de File Systems (Sistemas de Archivos)

1.  **EXT4:** El estándar de Linux. Confiable, maduro. Permite achicar y agrandar particiones.
2.  **XFS:** Por defecto en RedHat/CentOS. Excelente para archivos gigantes y LVM. **Ojo:** *Se puede agrandar, pero NO se puede achicar.*
3.  **BTRFS / ZFS:** Los modernos. Soportan "Snapshots" (copias instantáneas), RAID por software nativo y auto-reparación de archivos corruptos.

---

### 2.4 Tipos de RAID (Explicación rápida)

*   **RAID 0 (Stripe):** Suma la velocidad y capacidad de 2 discos. Si 1 disco muere, pierdes TODO. (Puro rendimiento).
*   **RAID 1 (Mirror):** Espejo. 2 discos tienen la misma data. Si 1 muere, el sistema sigue. (Pura seguridad).
*   **RAID 5 (Paridad):** Mínimo 3 discos. Tolera que muera 1 disco. Mezcla seguridad y espacio.
*   **RAID 10:** Mezcla del 1 y el 0. Mínimo 4 discos. Máxima velocidad y máxima seguridad (El más costoso).

---

### 2.5 LVM (Logical Volume Manager): Conceptos Core

LVM es como "plastilina" para discos.
1.  **PV (Physical Volume):** Convertimos el disco crudo (`/dev/sdb`) en un bloque de plastilina.
2.  **VG (Volume Group):** Juntamos varios bloques de plastilina en una sola masa gigante (ej. `vg_datos`).
3.  **LV (Logical Volume):** Cortamos pedazos de esa masa gigante del tamaño que queramos (ej. `lv_home` de 50GB) y le damos formato.

---

### 2.6 LVM Práctico: Operaciones Paso a Paso

#### A. Crear un LVM desde Cero (con /dev/sdb)

1. Crear el Volumen Físico (PV):
`sudo pvcreate /dev/sdb`

2. Crear el Grupo de Volúmenes (VG) llamado "vg_servidor":
`sudo vgcreate vg_servidor /dev/sdb`

3. Crear el Volumen Lógico (LV) de 20GB llamado "lv_datos":
`sudo lvcreate -L 20G -n lv_datos vg_servidor`

4. Formatear y montar:
`sudo mkfs.ext4 /dev/vg_servidor/lv_datos`
`sudo mkdir /mnt/datos`
`sudo mount /dev/vg_servidor/lv_datos /mnt/datos`


#### B. Agrandar (Extender) una partición en caliente

*Situación: El servidor se quedó sin espacio. Conectaste un disco nuevo al servidor, o tienes espacio libre en el VG.*

1. Extender el Volumen Lógico (ejemplo: sumar 10GB al Home):
`sudo lvextend -L +10G /dev/vg_servidor/lv_home`
*(Para usar todo el espacio libre: `sudo lvextend -l +100%FREE /dev/vg_servidor/lv_home`)*

2. Avisarle al Sistema de Archivos que el disco creció (EN CALIENTE, sin apagar):
`sudo resize2fs /dev/vg_servidor/lv_home` *(Si es EXT4)*
`sudo xfs_growfs /home` *(Si es XFS)*


#### C. Achicar (Reducir) una partición EXT4

*Nota: XFS no se puede reducir. EXT4 requiere desmontar el volumen primero.*

1. Desmontar la partición obligatoriamente:
`sudo umount /home`

2. Revisar errores (Requisito obligatorio antes de achicar):
`sudo e2fsck -f /dev/vg_servidor/lv_home`

3. Achicar el FileSystem PRIMERO (ej: a 30GB):
`sudo resize2fs /dev/vg_servidor/lv_home 30G`

4. Achicar el Volumen Lógico DESPUÉS (pedirá confirmación):
`sudo lvreduce -L 30G /dev/vg_servidor/lv_home`

5. Volver a montar:
`sudo mount /dev/vg_servidor/lv_home /home`