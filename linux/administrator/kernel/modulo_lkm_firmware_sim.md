---
id: lab-3.23-kernel-lkm-compilacion-firmware
title: Desarrollo, Compilación e Inyección de un Módulo LKM Educativo (Simulación
  de Firmware y Logs en Ring 0)
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Backups, Observabilidad
  & Kernel Avanzado'
section: '3.23'
sections:
- '3.23'
- '3'
category: fundamentals
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- kernel
- lkm
- kbuild
- c
- compilacion
- firmware
- syslog
- dmesg
- journalctl
- procfs
- sysfs
- tainted
- secure-boot
- insmod
- rmmod
tools:
- gcc
- make
- insmod
- rmmod
- modinfo
- lsmod
- dmesg
- journalctl
- cat
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 1024
  min_disks: 0
tested_environments:
- environment: QEMU/KVM
  type: virtualized
  instance_type: qemu-kvm
  os: Ubuntu 24.04 LTS
  kernel: 6.8.0-151-generic
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecutado de punta a punta demo_lkm_firmware_sim.sh --auto 0 y limpiar_lkm_firmware_sim.sh
    sobre kernel real 6.8.0-151-generic; compilado edu_firmware_sim.ko con Kbuild,
    probado insmod v1.0.0, /proc/edu_firmware_sim, /sys/module, dmesg, tainted=12288,
    hot-update a v2.0.0-patched y rmmod limpio.
- environment: Bare-Metal
  type: local
  instance_type: desktop
  os: Fedora Linux 44 (Sway Atomic)
  kernel: 7.2.11-200.fc44.x86_64
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Código fuente edu_firmware_sim.c y Kbuild Makefile validados frente a API
    moderna de kernel 6.x/7.x (proc_create_single, init_utsname).
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Compatible con linux-headers instalados y CAP_SYS_MODULE.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Aplicable en instancias EC2 instalando linux-headers-$(uname -r) y build-essential.
environments:
- QEMU/KVM
- Bare-Metal
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
- Fedora Linux 44 (Sway Atomic)
- Debian 12
status: PASSED
rag_summary: Laboratorio avanzado de ingeniería del Kernel Linux para escribir, compilar
  e inyectar un módulo cargable (LKM) real en C mediante Kbuild (edu_firmware_sim.c
  + Makefile). Simula un controlador de dispositivo que carga una versión de firmware
  configurable vía module_param, escribe trazas estructuradas en el ring buffer y
  syslog del kernel (pr_info / pr_notice visibles en dmesg y journalctl -k), expone
  parámetros vivos en /sys/module/edu_firmware_sim/parameters/ y publica telemetría
  en /proc/edu_firmware_sim mediante proc_create_single. Demuestra en vivo un flujo
  educativo de actualización de firmware en caliente (v1.0.0 a v2.0.0-patched) mediante
  rmmod e insmod, analiza las banderas de Kernel Taint (/proc/sys/kernel/tainted)
  y explica la firma de módulos bajo UEFI Secure Boot.
files:
  guide: kernel/modulo_lkm_firmware_sim.md
  script: kernel/demo_lkm_firmware_sim.sh
  terraform: null
prerequisites:
- lab-0.1-compilar
- lab-1.7-kernel-modulos-lkm-blacklists
- lab-1.8-kernel-sysfs-proc-sysctl
next_recommended_labs:
- lab-3.24-kernel-compilacion-gentoo-initramfs
- lab-3.25-kernel-seguridad-ataques-ebpf
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio 3.23: Compilar e Instalar un Módulo LKM Educativo (Simulación de Firmware y Logs en Ring 0)

> **Dificultad:** Avanzado (Nivel 3) | **Tiempo estimado:** 45 minutos | **Script interactivo:** [`demo_lkm_firmware_sim.sh`](demo_lkm_firmware_sim.sh) | **Código C:** [`src/edu_firmware_sim.c`](src/edu_firmware_sim.c) & [`src/Makefile`](src/Makefile)

En el [Lab 0.1](../compilar.md) compilaste un programa normal en espacio de usuario (**Ring 3**) que se comunica con el sistema a través de `libc`. En este laboratorio damos el salto directo a **Ring 0**: vas a compilar e insertar en el kernel en ejecución un **Módulo Cargable (`LKM`) real escrito en C**, simular la carga y actualización de firmware de un dispositivo virtual, emitir logs al sistema (`dmesg` / `journalctl -k` / `syslog`) y exponer interfaces en **`/proc`** y **`/sys`**.

---

## 🧬 1. Anatomía del Módulo Educativo [`src/edu_firmware_sim.c`](src/edu_firmware_sim.c)

A diferencia de un programa estándar (`main()`), un módulo LKM **no tiene función `main` ni usa `printf`**:
- Se compila contra las cabeceras exactas del kernel en ejecución (`/lib/modules/$(uname -r)/build`) usando el sistema **Kbuild**.
- Define dos ganchos de ciclo de vida:
  1. **`module_init(edu_fw_init)`:** Se ejecuta en Ring 0 en el instante en que hacés `insmod` o `modprobe`. Registra `/proc/edu_firmware_sim` con `proc_create_single()` y emite un mensaje `pr_info(...)` al *ring buffer* del kernel.
  2. **`module_exit(edu_fw_exit)`:** Se ejecuta al descargar el módulo con `rmmod` o `modprobe -r`. Elimina `/proc/edu_firmware_sim` (si olvidaras liberarlo, la siguiente lectura provocaría un **Kernel Oops / Panic**!) y escribe `pr_notice(...)`.
- Usa **`module_param(...)`** para recibir parámetros desde la línea de órdenes y exponerlos automáticamente bajo `/sys/module/edu_firmware_sim/parameters/`.

```text
  Usuario (Ring 3)                                           Kernel Linux (Ring 0)
  ────────────────                                           ─────────────────────
  insmod edu_firmware_sim.ko fw_version="1.0.0" ──────────► edu_fw_init()
                                                              ├─► pr_info() ──► ring buffer ──► dmesg / journald / syslog
                                                              ├─► proc_create_single() ──► /proc/edu_firmware_sim
                                                              └─► module_param() ────────► /sys/module/.../parameters/
  rmmod edu_firmware_sim ─────────────────────────────────► edu_fw_exit()
                                                              ├─► remove_proc_entry()
                                                              └─► pr_notice() ──► syslog / dmesg
```

> [!CAUTION]
> **Por qué los módulos LKM exigen máximo rigor:**
> En Ring 0 no hay recolector de basura ni protección de memoria por proceso. Si un módulo intenta desreferenciar un puntero `NULL` o olvida liberar un callback en `/proc`, **toda la máquina puede colgarse en un Kernel Panic**. Por eso en el [Lab 3.25](seguridad_ataques_kernel_ebpf.md) verás cómo **eBPF** resuelve observabilidad y seguridad sin correr ese riesgo.

---

## 🔧 2. Paso a Paso Manual: Compilación Kbuild y Simulación de Update de Firmware

### 2.1 Instalar Cabeceras del Kernel (Prerequisito de Compilación)
```bash
# En Debian / Ubuntu:
sudo apt-get update && sudo apt-get install -y build-essential linux-headers-$(uname -r)

# En RHEL / Rocky / Alma / Fedora clásica:
sudo dnf install -y gcc make kernel-devel-$(uname -r) elfutils-libelf-devel
```

### 2.2 Compilar Fuera del Árbol (*Out-of-Tree*) en `/tmp`
Copiá los fuentes a un directorio temporal para mantener limpio tu repositorio Git:
```bash
mkdir -p /tmp/mi_lkm_test
cp linux/administrator/kernel/src/* /tmp/mi_lkm_test/
make -C /tmp/mi_lkm_test
ls -lh /tmp/mi_lkm_test/edu_firmware_sim.ko
```

El archivo [`src/Makefile`](src/Makefile) invoca al sistema de construcción del kernel:
```makefile
obj-m += edu_firmware_sim.o
KDIR ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
```

### 2.3 Inspeccionar Metadatos antes de Insertar
```bash
modinfo /tmp/mi_lkm_test/edu_firmware_sim.ko
```
Vas a observar el campo **`vermagic`** (debe coincidir con la versión y flags SMP/PREEMPT del kernel activo), la licencia `GPL` y los parámetros declarados (`fw_version`, `device_name`, `reload_count`).

### 2.4 Fase 1: Cargar el Controlador Simulando Firmware `v1.0.0` y Revisar Logs
```bash
sudo insmod /tmp/mi_lkm_test/edu_firmware_sim.ko fw_version="1.0.0" device_name="edu-virt-nic0" reload_count=1

# 1. Ver el módulo activo en memoria
lsmod | grep edu_firmware_sim

# 2. Leer la interfaz creada por el módulo en /proc y su parámetro en /sys
cat /proc/edu_firmware_sim
cat /sys/module/edu_firmware_sim/parameters/fw_version

# 3. Comprobar el mensaje real emitido al ring buffer y sistema de logs
sudo dmesg -T | grep edu_firmware_sim
# En equipos con systemd-journald / rsyslog:
sudo journalctl -k -n 10 --no-pager | grep edu_firmware_sim
```

### 2.5 Fase 2: Simular "Actualización de Firmware" (`v1.0.0` → `v2.0.0-patched`)
Cuando actualizás firmware o un driver de dispositivo en caliente:
```bash
# Descargamos la versión previa de forma limpia
sudo rmmod edu_firmware_sim

# Cargamos la nueva revisión simulada
sudo insmod /tmp/mi_lkm_test/edu_firmware_sim.ko fw_version="2.0.0-patched" device_name="edu-virt-nic0" reload_count=2

# Verificamos el cambio en /proc, /sys y syslog/dmesg
cat /proc/edu_firmware_sim
sudo dmesg -T | grep edu_firmware_sim | tail -n 5
```

### 2.6 Fase 3: Descarga Limpia
```bash
sudo rmmod edu_firmware_sim
```

---

## ☣️ 3. *Kernel Taint* y Firma de Módulos bajo UEFI Secure Boot

Al insertar un módulo compilado por fuera del árbol oficial (*out-of-tree*) y sin firma criptográfica de la distribución, el kernel marca una bandera de diagnóstico llamada **`taint`** en `/proc/sys/kernel/tainted`:

| Letra / Bit | Significado en `dmesg` / `/proc/sys/kernel/tainted` | Por qué importa en Soporte Enterprise |
| :---: | :--- | :--- |
| **`O`** *(Bit 12 = 4096)* | *Out-of-tree module loaded* | Módulo compilado fuera del árbol oficial de `kernel.org` (ej. nuestro `edu_firmware_sim.ko` o VirtualBox). |
| **`E`** *(Bit 13 = 8192)* | *Unsigned module loaded* | Módulo sin firma criptográfica PKCS#7 válida. |
| **`P`** *(Bit 0 = 1)* | *Proprietary module loaded* | Módulo con `MODULE_LICENSE` no GPL (ej. driver propietario NVIDIA). |
| **`F`** *(Bit 4 = 16)* | *Module force loaded* | Se forzó la carga ignorando incompatibilidades de `vermagic` (`insmod -f`). |

> [!IMPORTANT]
> **¿Por qué `insmod` puede fallar con `Operation not permitted` o `Key was rejected by service`?**
> En equipos físicos con **UEFI Secure Boot** activo, el kernel habilita el modo **Lockdown (`integrity`)** y exige que todo `.ko` esté firmado con una clave de confianza (o una **MOK** —*Machine Owner Key*— enrolada con `mokutil`). Si estás en un entorno educativo o VM con Secure Boot, podés firmar tu `.ko` con `scripts/sign-file` tras enrolar tu llave MOK, o desactivar Secure Boot en la VM de laboratorio.

---

## 💻 4. Práctica Interactiva con `demo_lkm_firmware_sim.sh`

```bash
cd linux/administrator/kernel

# Modo interactivo paso a paso
sudo ./demo_lkm_firmware_sim.sh

# Modo automático
sudo ./demo_lkm_firmware_sim.sh --auto 0

# Limpieza manual si corriste con --keep
sudo ./limpiar_lkm_firmware_sim.sh
```

> 📖 **Glosario relacionado:** Consultá [LKM (Loadable Kernel Modules)](../GLOSARIO.md#lkm-loadable-kernel-modules-modprobe-y-blacklists) y [Kernel Taint, KASLR y Lockdown](../GLOSARIO.md#kernel-taint-kaslr-kptr_restrict-y-kernel-lockdown).
