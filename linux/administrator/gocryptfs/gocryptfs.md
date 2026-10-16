# gocryptfs paso a paso

gocryptfs es una herramienta para cifrar una carpeta completa sin cifrar todo el disco. Funciona a nivel de archivos y usa FUSE, así que puedes trabajar normalmente con una carpeta visible y otra cifrada.

## Paso 1: instalar gocryptfs

```bash
sudo apt update
sudo apt install gocryptfs
```

## Paso 2: crear las carpetas

Necesitas dos carpetas:

- una carpeta cifrada: aquí quedarán los datos reales encriptados
- una carpeta visible: aquí trabajarás como si fuera la carpeta normal

```bash
mkdir -p ~/datos_cifrados
mkdir -p ~/datos_visibles
```

## Paso 3: inicializar la carpeta cifrada

Este paso crea la configuración principal de gocryptfs. Te pedirá una contraseña.

```bash
gocryptfs -init ~/datos_cifrados
```

Cuando te pida la contraseña, ingresá una fuerte y recordala. No la pierdas.

## Paso 4: montar la carpeta visible

Ahora abrimos la "ventana" para ver y usar los archivos descifrados:

```bash
gocryptfs ~/datos_cifrados ~/datos_visibles
```

A partir de este momento:

- todo lo que guardes en `~/datos_visibles` se cifra automáticamente
- los archivos reales quedarán en `~/datos_cifrados`

## Paso 5: probar que funciona

```bash
echo "hola" > ~/datos_visibles/prueba.txt
ls -l ~/datos_visibles
ls -l ~/datos_cifrados
```

Si todo salió bien, verás que `~/datos_visibles/prueba.txt` existe y que la carpeta cifrada tiene contenido cifrado.

## Paso 6: desmontar cuando quieras

Cuando termines, podés desmontar la carpeta para dejarla cerrada:

```bash
fusermount -u ~/datos_visibles
```

## Idea clave

Usá siempre la carpeta visible para trabajar.

No edites directamente la carpeta cifrada. La carpeta cifrada es el almacenamiento real, y la carpeta visible es la interfaz normal para usar archivos.

## Resumen

El flujo básico es este:

```bash
sudo apt install gocryptfs
mkdir -p ~/datos_cifrados ~/datos_visibles
gocryptfs -init ~/datos_cifrados
gocryptfs ~/datos_cifrados ~/datos_visibles
```

Y luego trabajas en `~/datos_visibles`.