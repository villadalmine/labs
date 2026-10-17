---
id: lab-0.1-compilar
title: Compilación de Programas en C, Makefiles y Resolución de Dependencias
difficulty_level: 0
difficulty_label: 'Nivel 0: Fundamentos y Compilación de Software'
section: '0.1'
sections:
- '0.1'
- '0'
category: fundamentals
tags:
- compilacion
- c
- gcc
- make
- makefile
- dependencias
- headers
- ncurses
tools:
- gcc
- make
- apt
- git
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
  test_date: '2026-10-17'
  notes: Compilación de programa en C con resolución de cabeceras libncurses-dev y
    ejecución interactiva.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Compatible en cualquier distribución Debian/Ubuntu con build-essential.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio introductorio de compilación en Linux. Enseña a descargar
  código fuente en C, diagnosticar errores de cabeceras faltantes (fatal error curses.h),
  instalar paquetes de desarrollo (libncurses-dev), interpretar Makefiles y compilar
  binarios nativos con make y gcc.
files:
  guide: compilar.md
  script: null
  terraform: null
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
---

# Compilar un programa en Linux

Una forma práctica de aprender cómo se compila un programa es descargar su código fuente, intentar compilarlo y resolver las dependencias que falten.

En este ejemplo vamos a usar `sl` (Steam Locomotive), un programa pequeño escrito en C. Depende de `ncurses`, una biblioteca que permite dibujar interfaces de texto en la terminal.

## Paso 1: descargar el código fuente

Cloná el repositorio y entrá en el directorio del proyecto:

```bash
git clone https://github.com/mtoyoda/sl.git
cd sl
```

Podés revisar los archivos del proyecto:

```bash
ls
```

Entre ellos vas a encontrar `sl.c`, que contiene el código en C, y `Makefile`, que describe cómo compilar el programa.

## Paso 2: intentar compilar

Ejecutá `make` para que lea el `Makefile` y compile el código:

```bash
make
```

Si todavía no están instalados los archivos de desarrollo de `ncurses`, vas a ver un error parecido a este:

```text
sl.c:42:10: fatal error: curses.h: No such file or directory
   42 | #include <curses.h>
      |          ^~~~~~~~~~
compilation terminated.
make: *** [Makefile:13: sl] Error 1
```

El compilador no encuentra `curses.h`, una cabecera de desarrollo de `ncurses` que el código necesita para compilar.

## Paso 3: instalar la dependencia de desarrollo

En Debian y Ubuntu, las bibliotecas suelen dividirse en dos tipos de paquetes:

- Los paquetes de ejecución contienen las bibliotecas que necesitan los programas ya compilados.
- Los paquetes de desarrollo contienen archivos como las cabeceras `.h` y otros recursos necesarios para compilar.

Instalá el paquete de desarrollo de `ncurses`:

```bash
sudo apt update
sudo apt install -y libncurses-dev
```

## Paso 4: compilar y ejecutar

Volvé a compilar:

```bash
make
```

Si la compilación termina correctamente, se genera un ejecutable llamado `sl`. Ejecutalo desde el directorio del proyecto:

```bash
./sl
```

`sl` muestra una locomotora en la terminal. Es un programa clásico que suele aparecer cuando alguien escribe `sl` por error en lugar de `ls`.

## Paso 5: revisar las bibliotecas dinámicas con `ldd`

El ejecutable necesita bibliotecas compartidas disponibles en el sistema. Podés ver cuáles son con `ldd`:

```bash
ldd ./sl
```

La salida puede ser parecida a esta; las direcciones y algunas rutas dependen del sistema:

```text
linux-vdso.so.1 (0x00007ffe3b1c6000)
libncurses.so.6 => /lib/x86_64-linux-gnu/libncurses.so.6 (0x00007f3a8b400000)
libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6 (0x00007f3a8b3d0000)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f3a8b000000)
```

Esto muestra que el ejecutable es dinámico: no incluye todas las bibliotecas dentro del archivo. Cuando se ejecuta, el sistema carga las bibliotecas compartidas que necesita, como `libncurses` y `libc`.

## Resumen

El flujo del ejemplo es:

```bash
git clone https://github.com/mtoyoda/sl.git
cd sl
make
sudo apt update
sudo apt install -y libncurses-dev
make
./sl
ldd ./sl
```

La primera ejecución de `make` puede fallar si falta `libncurses-dev`. Después de instalar la dependencia, se vuelve a compilar y se ejecuta el programa.