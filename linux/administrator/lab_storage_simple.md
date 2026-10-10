# Laboratorio simple: un disco virtual con loop

En esta práctica corta vas a crear un archivo de prueba, usarlo como disco virtual, formatearlo con ext4, montarlo, guardar un archivo y desmontarlo. No usa LVM ni discos físicos.

Usá una VM Debian o Ubuntu descartable. Instalá las herramientas:

```bash
sudo apt update
sudo apt install -y e2fsprogs util-linux
```

## 1. Crear una imagen de 512 MiB

```bash
mkdir -p /tmp/lab_storage_simple
truncate -s 512M /tmp/lab_storage_simple/disco.img
ls -lh /tmp/lab_storage_simple/disco.img
```

## 2. Conectarla como dispositivo

```bash
LOOP=$(sudo losetup --find --show /tmp/lab_storage_simple/disco.img)
printf 'Dispositivo de prueba: %s\n' "$LOOP"
sudo losetup -a
```

El valor de `LOOP` debe ser un dispositivo `/dev/loop...` asociado al archivo `disco.img`.

## 3. Crear ext4 y montarlo

`mkfs.ext4` prepara un filesystem nuevo en el dispositivo de prueba. Este comando borra el contenido previo del dispositivo indicado; verificá que `LOOP` apunte al archivo del laboratorio.

```bash
sudo mkfs.ext4 "$LOOP"
sudo mkdir -p /mnt/lab_storage_simple
sudo mount "$LOOP" /mnt/lab_storage_simple
findmnt /mnt/lab_storage_simple
df -h /mnt/lab_storage_simple
```

## 4. Guardar y leer un archivo

```bash
echo 'Mi primer disco virtual' | sudo tee /mnt/lab_storage_simple/nota.txt
sudo cat /mnt/lab_storage_simple/nota.txt
sudo ls -l /mnt/lab_storage_simple
```

El archivo vive dentro del filesystem montado, que a su vez está respaldado por `disco.img`.

## 5. Desmontar y limpiar

Desmontá antes de desconectar el loop device. Después verificá que el dispositivo ya no esté asociado y borrá el archivo de prueba.

```bash
sudo umount /mnt/lab_storage_simple
sudo losetup -d "$LOOP"
sudo losetup -a
sudo rmdir /mnt/lab_storage_simple
rm -r /tmp/lab_storage_simple
```

Si abrís otra terminal antes de limpiar, recuperá el nombre del dispositivo con `sudo losetup -a` y asignalo de nuevo a `LOOP`. Confirmá que pertenece a `disco.img` antes de desconectarlo.

## Para comprobar lo aprendido

Explicá con tus palabras qué hacen `truncate`, `losetup`, `mkfs.ext4`, `mount` y `umount`, y dibujá la relación entre el archivo, el dispositivo y el punto de montaje.