# LUKS paso a paso: loop device y disco real

LUKS cifra dispositivos de bloques, como discos y particiones. Para probarlo sin tocar un disco físico podemos crear un archivo y conectarlo como `loop device`. Para uso real, se cifra una partición de un disco físico.

Esta guía tiene dos recorridos independientes:

1. **Prueba con loop device:** recomendada para aprender y comprobar que funciona.
2. **Disco físico real:** para una partición dedicada y sin datos importantes.

> `luksFormat` destruye los datos previos del dispositivo seleccionado. Revisá siempre la ruta antes de confirmar.

---

## Parte A: probar LUKS con un loop device

Este recorrido crea un archivo de 512 MB, lo conecta como dispositivo `/dev/loopN`, lo cifra, lo abre y lo monta. No formatea un disco físico.

### 1) Instalar las herramientas

En Debian o Ubuntu:

```bash
sudo apt update
sudo apt install -y cryptsetup util-linux e2fsprogs
```

### 2) Crear y ejecutar el script de prueba

Pegá el bloque en una terminal Bash de Linux. El script aborta si el archivo de prueba ya existe.

```bash
#!/usr/bin/env bash
set -euo pipefail

ARCHIVO="/var/tmp/luks-prueba.img"
MAPEO="luks_prueba"
MONTAJE="/mnt/luks-prueba"

if [ -e "$ARCHIVO" ]; then
  echo "Ya existe $ARCHIVO. No se modifica."
  echo "Cerrá y eliminá la prueba anterior antes de volver a empezar."
  exit 1
fi

sudo -v
sudo fallocate -l 512M "$ARCHIVO"
LOOP_DEVICE=$(sudo losetup --find --show "$ARCHIVO")

echo "Loop device asignado: $LOOP_DEVICE"
echo "Ahora se inicializará LUKS en ese loop device."
sudo cryptsetup -y luksFormat "$LOOP_DEVICE"
sudo cryptsetup luksOpen "$LOOP_DEVICE" "$MAPEO"
sudo mkfs.ext4 "/dev/mapper/$MAPEO"
sudo mkdir -p "$MONTAJE"
sudo mount "/dev/mapper/$MAPEO" "$MONTAJE"

echo "Prueba LUKS" | sudo tee "$MONTAJE/prueba.txt" >/dev/null
sudo ls -l "$MONTAJE"

echo
echo "Prueba lista y montada en $MONTAJE"
echo "Para cerrarla, seguí los comandos de la sección 3."
```

El comando `luksFormat` te pedirá confirmar con `YES` y establecer una contraseña.

### 3) Desmontar y cerrar la prueba

Ejecutá estos comandos al terminar:

```bash
sudo umount /mnt/luks-prueba
sudo cryptsetup luksClose luks_prueba
sudo losetup -d "$(sudo losetup -j /var/tmp/luks-prueba.img | cut -d: -f1)"
```

Para borrar el archivo de prueba y liberar el espacio:

```bash
sudo rm /var/tmp/luks-prueba.img
sudo rmdir /mnt/luks-prueba
```

> No borres el archivo mientras esté montado o abierto. Primero desmontá, cerrá LUKS y desconectá el loop device.

### 4) Volver a abrir la prueba más adelante

Si cerraste la prueba pero conservaste el archivo, podés volver a abrirla así:

```bash
LOOP_DEVICE=$(sudo losetup --find --show /var/tmp/luks-prueba.img)
sudo cryptsetup luksOpen "$LOOP_DEVICE" luks_prueba
sudo mount /dev/mapper/luks_prueba /mnt/luks-prueba
```

---

## Parte B: usar una partición de un disco físico

Usá este recorrido solamente con un disco o una partición dedicados. No uses la partición del sistema ni una que tenga datos que quieras conservar.

### 1) Identificar el disco y la partición

```bash
lsblk -f
```

Ejemplos de nombres de dispositivos:

```text
/dev/sdb1
/dev/nvme1n1p1
```

Comprobá cuál es el dispositivo correcto antes de seguir:

```bash
sudo lsblk -f /dev/sdb
```

Si el disco está vacío y todavía no tiene partición, podés crear una tabla GPT y una partición que ocupe el disco completo. **Estos comandos borran la estructura previa del disco indicado.**

```bash
sudo parted /dev/sdb --script mklabel gpt
sudo parted /dev/sdb --script mkpart primary 0% 100%
lsblk /dev/sdb
```

En este ejemplo, la partición será `/dev/sdb1`. En discos NVMe el nombre suele ser `/dev/nvme1n1p1`.

### 2) Cifrar la partición

Reemplazá `/dev/sdb1` por la partición que verificaste con `lsblk`:

```bash
sudo cryptsetup -y luksFormat /dev/sdb1
```

Confirmá escribiendo `YES` y elegí una contraseña. Guardala en un lugar seguro: si la perdés y no hay otra clave configurada, no podrás recuperar los datos.

### 3) Abrir el volumen cifrado

```bash
sudo cryptsetup luksOpen /dev/sdb1 datos_luks
```

Esto crea el dispositivo descifrado `/dev/mapper/datos_luks`.

### 4) Crear el sistema de archivos y montar

Este comando crea ext4 dentro del volumen cifrado. Ejecutalo solo la primera vez: volver a ejecutarlo borra los archivos del volumen.

```bash
sudo mkfs.ext4 /dev/mapper/datos_luks
sudo mkdir -p /mnt/datos_luks
sudo mount /dev/mapper/datos_luks /mnt/datos_luks
```

Probá guardar un archivo:

```bash
echo "Prueba LUKS en disco real" | sudo tee /mnt/datos_luks/prueba.txt
ls -l /mnt/datos_luks
```

### 5) Desmontar y bloquear

```bash
sudo umount /mnt/datos_luks
sudo cryptsetup luksClose datos_luks
```

Para volver a usarlo:

```bash
sudo cryptsetup luksOpen /dev/sdb1 datos_luks
sudo mount /dev/mapper/datos_luks /mnt/datos_luks
```

---

## Montaje automático con systemd

Esta configuración es opcional. Al usar `none` en `crypttab`, el sistema pide la contraseña durante el arranque.

### 1) Obtener el UUID LUKS

El UUID para `crypttab` es el de la partición cifrada:

```bash
sudo cryptsetup luksUUID /dev/sdb1
```

### 2) Agregar una línea a `/etc/crypttab`

Editá el archivo y reemplazá el UUID de ejemplo:

```text
datos_luks UUID=UUID-DE-LA-PARTICION none luks
```

### 3) Agregar una línea a `/etc/fstab`

```text
/dev/mapper/datos_luks /mnt/datos_luks ext4 defaults 0 2
```

En un servidor remoto, pedir una contraseña durante el arranque puede dejar el sistema esperando hasta que alguien la ingrese por consola.

---

## Resumen de los dos métodos

**Para probar sin disco físico:** archivo + `losetup` + LUKS. Usá la Parte A.

**Para cifrar almacenamiento real:** partición dedicada + LUKS. Usá la Parte B y revisá dos veces el dispositivo antes de ejecutar `luksFormat`.

## Opción: Demostración interactiva paso a paso para dar clase (`demo_luks.sh`)

Si vas a dar una clase sobre LUKS y cifrado de bloques, podés utilizar el script interactivo [`demo_luks.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/demo_luks.sh).

El script crea un disco virtual seguro, inicializa LUKS2 con AES-XTS, abre el mapeo `/dev/mapper/`, formatea con ext4, escribe un archivo confidencial, cierra el contenedor y **hace una inspección forense en vivo** demostrando que el disco crudo contiene solo ruido cifrado (`strings` devuelve 0 coincidencias), para finalmente reabrirlo con la contraseña y recuperar los datos intactos.

### Ejecución:

```bash
sudo ./demo_luks.sh          # Modo interactivo (pausa con [ENTER])
sudo ./demo_luks.sh --auto 5 # Modo automático (espera 5s por paso)
```