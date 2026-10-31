---
id: lab-3.4-cifrado-fuse-gocryptfs
title: Cifrado FUSE a Nivel de Archivo con Gocryptfs (Carpetas Cifradas vs Visibles)
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.4'
sections:
- '3.4'
- '3'
category: security
tags:
- security
- cifrado
- gocryptfs
- fuse
- archivos
- cloud-sync
- privacidad
tools:
- gocryptfs
- fusermount
- mkdir
- ls
requirements:
  root_required: false
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
  test_date: '2026-10-17'
  notes: Instalación de gocryptfs, inicialización de datos_cifrados, montaje en datos_visibles
    y desmontaje con fusermount -u.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Cifrado FUSE en espacio de usuario compatible con sincronización en buckets
    S3.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio sobre cifrado en espacio de usuario con gocryptfs utilizando
  FUSE (Filesystem in Userspace). Enseña a crear y montar directorios con cifrado
  transparente individual por archivo (AES-GCM), protegiendo nombres de archivo y
  contenidos sin requerir permisos de superusuario root ni formatear particiones completas,
  ideal para respaldos incrementales en la nube.
files:
  guide: gocryptfs/gocryptfs.md
  script: null
  terraform: null
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
prerequisites:
- lab-3.3-cifrado-luks
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

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


---

## 🔗 Enlaces Oficiales de Referencia

- [Sitio Oficial de gocryptfs](https://nuetzlich.net/gocryptfs/)
- [Repositorio GitHub Upstream rfjakob/gocryptfs](https://github.com/rfjakob/gocryptfs)
- [Auditoría de Seguridad y Criptografía de gocryptfs](https://nuetzlich.net/gocryptfs/security/)
- [Manual de libfuse y FUSE en el Kernel de Linux](https://docs.kernel.org/filesystems/fuse.html)
