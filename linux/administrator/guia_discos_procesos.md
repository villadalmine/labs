# Guía de procesos, systemd y almacenamiento en Linux

Material de consulta sobre procesos, automatización con systemd, discos, sistemas de archivos, RAID y LVM.

## 1. Gestión de procesos

`ps` (*Process Status*) muestra información sobre los procesos que se están ejecutando.

### 1.1 Consultar procesos

Mostrar procesos de todos los usuarios, incluidos los que no están asociados a una terminal:

```bash
ps aux
```

Mostrar los cinco procesos con mayor uso de CPU:

```bash
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 6
```

Mostrar los cinco procesos con mayor uso de memoria:

```bash
ps -eo pid,user,%mem,cmd --sort=-%mem | head -n 6
```

En las opciones `-eo`, `-e` incluye los procesos y `-o` selecciona las columnas. La opción `--sort=-%cpu` ordena por CPU de mayor a menor.

Ver la relación padre-hijo en forma de árbol:

```bash
pstree -p
```

El árbol permite seguir cómo `systemd` (PID 1) inicia servicios y otros procesos.

### 1.2 Crear un monitor periódico con systemd

En este ejemplo el script registra cada minuto los cinco procesos con mayor uso de CPU y memoria. Crearemos el script y las unidades directamente desde la terminal con `tee`, sin abrir un editor.

#### Paso 1: crear el script

```bash
sudo tee /usr/local/bin/monitor_recursos.sh > /dev/null <<'EOF'
#!/bin/bash
# Script para registrar picos de consumo de CPU y RAM

FECHA=$(date '+%Y-%m-%d %H:%M:%S')

# Log de CPU
echo "=== TOP CPU: $FECHA ===" >> /tmp/cpu.log
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 6 >> /tmp/cpu.log
echo "" >> /tmp/cpu.log

# Log de Memoria
echo "=== TOP MEMORIA: $FECHA ===" >> /tmp/memoria.log
ps -eo pid,user,%mem,cmd --sort=-%mem | head -n 6 >> /tmp/memoria.log
echo "" >> /tmp/memoria.log
EOF
```

Dar permiso de ejecución:

```bash
sudo chmod +x /usr/local/bin/monitor_recursos.sh
```

#### Paso 2: probar el script manualmente

Ejecutalo una vez antes de automatizarlo:

```bash
sudo /usr/local/bin/monitor_recursos.sh
```

Comprobá que se hayan creado los logs y que tengan encabezado y procesos:

```bash
sudo cat /tmp/cpu.log
sudo cat /tmp/memoria.log
```

Cada ejecución agrega información al final de los archivos; no los vacía.

#### Paso 3: crear la unidad de servicio

El servicio es `oneshot`: ejecuta el script una vez y termina. El timer será quien lo vuelva a iniciar cada minuto.

```bash
sudo tee /etc/systemd/system/monitor.service > /dev/null <<'EOF'
[Unit]
Description=Monitoreo de CPU y RAM a archivos log

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor_recursos.sh
EOF
```

#### Paso 4: crear el timer

```bash
sudo tee /etc/systemd/system/monitor.timer > /dev/null <<'EOF'
[Unit]
Description=Ejecuta el monitor de recursos cada minuto

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
EOF
```

`Persistent=true` permite que systemd dispare una ejecución al volver a arrancar si se perdió una ejecución programada mientras el equipo estaba apagado.

#### Paso 5: cargar las unidades y activar el timer

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now monitor.timer
```

Verificar que el timer quedó activo y cuándo será su próxima ejecución:

```bash
systemctl status monitor.timer
systemctl list-timers --all monitor.timer
```

#### Paso 6: comprobar la ejecución

Esperá hasta la próxima ejecución y consultá el estado del servicio y los logs:

```bash
systemctl status monitor.service
sudo journalctl -u monitor.service -n 20 --no-pager
sudo tail -n 20 /tmp/cpu.log
sudo tail -n 20 /tmp/memoria.log
```

El Journal muestra cuándo systemd inició y terminó el servicio. Las listas de procesos se escriben en `/tmp/cpu.log` y `/tmp/memoria.log`.

#### Paso 7: detener o quitar el timer

Para detener el timer y evitar que se active en el próximo arranque:

```bash
sudo systemctl disable --now monitor.timer
```

Si también querés retirar las unidades, primero desactivalas y luego borrá los archivos:

```bash
sudo rm /etc/systemd/system/monitor.timer /etc/systemd/system/monitor.service
sudo systemctl daemon-reload
sudo systemctl reset-failed
```

Los logs de `/tmp` quedan disponibles para revisarlos hasta que los borres manualmente.

## 2. Discos y almacenamiento

### 2.1 Herramientas

En Debian o Ubuntu se pueden instalar estas utilidades con:

```bash
sudo apt update
sudo apt install lvm2 parted smartmontools ncdu xfsprogs btrfs-progs
```

Herramientas habituales:

- `fdisk`: administrar tablas de particiones.
- `lsblk`: listar dispositivos de bloques, particiones y puntos de montaje.
- `df` y `du`: consultar el espacio de los filesystems montados y el espacio usado por archivos y directorios.
- `parted`: crear y modificar tablas de particiones, incluidas tablas GPT.
- `smartmontools`: consultar información SMART de discos compatibles.
- `ncdu`: explorar interactivamente el uso de espacio desde la terminal.
- `xfsprogs` y `btrfs-progs`: utilidades para administrar filesystems XFS y Btrfs.

### 2.2 Inspeccionar discos y espacio

Listar los dispositivos de bloques:

```bash
lsblk
```

La salida puede incluir discos, particiones, volúmenes lógicos y sus puntos de montaje.

Consultar el espacio de los filesystems montados en formato legible:

```bash
df -h
```

### 2.3 Crear una partición con fdisk

El siguiente ejemplo abre el dispositivo `/dev/sdb` en la herramienta interactiva:

```bash
sudo fdisk /dev/sdb
```

Dentro de `fdisk`, `n` inicia la creación de una partición y `w` escribe los cambios. Las opciones disponibles dependen del tipo de tabla de particiones; revisá la selección antes de confirmar.

> **Advertencia:** crear o modificar particiones puede destruir datos. `/dev/sdb` es solo un ejemplo: identificá el dispositivo correcto con `lsblk` y trabajá únicamente sobre un disco destinado a la práctica.

### 2.4 Sistemas de archivos

- **ext4:** filesystem de uso general, maduro y ampliamente utilizado. Puede crecer y también reducirse, pero la reducción requiere desmontarlo y seguir un procedimiento cuidadoso.
- **XFS:** filesystem de alto rendimiento, común en sistemas empresariales. Puede crecer, pero no reducirse.
- **Btrfs y ZFS:** filesystems con funciones avanzadas, como snapshots y administración de volúmenes. Sus características y requisitos dependen de la configuración.

### 2.5 Niveles RAID

- **RAID 0 (striping):** distribuye los datos entre discos para sumar capacidad y rendimiento. No ofrece redundancia: la falla de un disco puede causar la pérdida del conjunto.
- **RAID 1 (mirroring):** mantiene copias idénticas en dos o más discos. Tolera la falla de un disco en una configuración de dos unidades, pero no sustituye a un backup.
- **RAID 5 (paridad):** requiere al menos tres discos y puede tolerar la falla de uno.
- **RAID 10:** combina espejado y distribución de datos. Requiere al menos cuatro discos y puede ofrecer rendimiento y redundancia, a costa de capacidad utilizable.

### 2.6 Conceptos de LVM

LVM (*Logical Volume Manager*) permite administrar el almacenamiento en capas:

1. **PV (Physical Volume):** dispositivo o partición inicializado para que LVM lo administre.
2. **VG (Volume Group):** grupo que reúne uno o más PV y ofrece espacio para asignar.
3. **LV (Logical Volume):** volumen creado dentro de un VG; sobre él se puede crear un filesystem.

La cadena habitual es: dispositivo o partición → PV → VG → LV → filesystem → punto de montaje.

## 3. Operaciones con LVM

> **Advertencia:** los siguientes comandos modifican metadatos de almacenamiento; `mkfs.ext4` crea un filesystem nuevo y puede sobrescribir datos. Practicá en una VM descartable o con discos virtuales vacíos. No copies `/dev/sdb` sin verificar antes a qué dispositivo corresponde.

### 3.1 Crear un volumen lógico

En este ejemplo se usa `/dev/sdb` como dispositivo de prueba. Primero se inicializa como PV y luego se crea un VG llamado `vg_servidor`:

```bash
sudo pvcreate /dev/sdb
sudo vgcreate vg_servidor /dev/sdb
```

Crear un LV de 20 GiB llamado `lv_datos`:

```bash
sudo lvcreate -L 20G -n lv_datos vg_servidor
```

Crear un filesystem ext4 y montarlo en `/mnt/datos`:

```bash
sudo mkfs.ext4 /dev/vg_servidor/lv_datos
sudo mkdir -p /mnt/datos
sudo mount /dev/vg_servidor/lv_datos /mnt/datos
```

### 3.2 Ampliar un volumen lógico

Si el VG tiene espacio libre, se puede ampliar el LV. Por ejemplo, sumar 10 GiB:

```bash
sudo lvextend -L +10G /dev/vg_servidor/lv_home
```

Para asignar al LV todo el espacio libre del VG:

```bash
sudo lvextend -l +100%FREE /dev/vg_servidor/lv_home
```

Luego hay que ampliar el filesystem para que use el nuevo espacio. Para ext4:

```bash
sudo resize2fs /dev/vg_servidor/lv_home
```

Para XFS, se indica el punto de montaje:

```bash
sudo xfs_growfs /home
```

Confirmá el tipo de filesystem y el punto de montaje antes de ejecutar el comando correspondiente. XFS debe estar montado para crecer.

### 3.3 Reducir un volumen lógico ext4

XFS no puede reducirse. Reducir un LV con ext4 requiere desmontar el filesystem, verificarlo y reducir primero el filesystem; solo después se reduce el LV. Un error de orden o de tamaño puede destruir datos. Hacé un backup y practicá fuera del sistema raíz.

Este ejemplo muestra el orden para un filesystem montado en `/home`. Los tamaños son ilustrativos: el tamaño final de ext4 debe quedar por debajo del tamaño final del LV, con margen suficiente.

Desmontar el filesystem:

```bash
sudo umount /home
```

Verificarlo antes de reducirlo:

```bash
sudo e2fsck -f /dev/vg_servidor/lv_home
```

Reducir ext4 a un tamaño menor que el tamaño final del LV; en este ejemplo, 28 GiB:

```bash
sudo resize2fs /dev/vg_servidor/lv_home 28G
```

Reducir el LV a 30 GiB:

```bash
sudo lvreduce -L 30G /dev/vg_servidor/lv_home
```

Volver a montar el filesystem:

```bash
sudo mount /dev/vg_servidor/lv_home /home
```