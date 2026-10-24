---
id: lab-1.5-deteccion-hardware
title: Detección, Inventario y Auditoría Forense de Hardware en Linux (lspci, lsusb, lshw, hwinfo, dmidecode, lscpu)
difficulty_level: 1
difficulty_label: 'Nivel 1: Procesos, Señales, Terminales y Diagnóstico del Kernel'
section: '1.5'
sections:
- '1.5'
- '1'
category: observability
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- hardware
- lspci
- lsusb
- lshw
- hwinfo
- dmidecode
- lscpu
- inventario
- auditoria
- diagnostico
- pci
- usb
- dmi
- smbios
- cpu
tools:
- lspci
- lsusb
- lshw
- hwinfo
- dmidecode
- lscpu
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
  notes: Detección de dispositivos virtuales, arquitectura CPU con lscpu, extracción DMI y auditoría con lshw y hwinfo.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Compatible en instancias virtualizadas Xen y Nitro (KVM) en AWS.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio exhaustivo sobre detección, inventario y diagnóstico forense de hardware en servidores Linux. Enseña a interrogar los buses físicos y lógicos mediante lspci y lsusb, analizar la microarquitectura de la CPU con lscpu, extraer metadatos de bajo nivel del firmware BIOS y placa base mediante dmidecode (DMI/SMBIOS) y generar reportes jerárquicos de inventario con lshw y hwinfo.
files:
  guide: hardware/deteccion_hardware.md
  script: hardware/demo_hardware.sh
  terraform: null
prerequisites:
- lab-1.4-tools-stats
next_recommended_labs:
- lab-2.1-systemd-memlogger
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Detección, Inventario y Auditoría Forense de Hardware en Linux

En la administración profesional de servidores e infraestructura Linux, conocer con exactitud matemática el hardware sobre el que opera el sistema operativo es un requisito ineludible. Ya sea en servidores físicos dedicados (*Bare-Metal*), hipervisores de virtualización (KVM, Proxmox, VMware) o instancias elásticas en la nube (AWS EC2, Google Cloud, Azure), un administrador debe ser capaz de inventariar, diagnosticar y resolver conflictos de controladores y recursos físicos.

Este laboratorio aborda las herramientas estándar de detección y auditoría de hardware: `lspci`, `lsusb`, `lshw`, `hwinfo`, `dmidecode` y `lscpu`.

---

## 🗺️ Mapa Arquitectural: Del Hardware al Espacio de Usuario

```
+---------------------------------------------------------------------------------------------------+
|                                ESPACIO DE USUARIO (HERRAMIENTAS CLI)                              |
|                                                                                                   |
|    lscpu         lspci          lsusb          lshw          hwinfo          dmidecode            |
|      │             │              │              │              │                │                |
+------┼─────────────┼──────────────┼──────────────┼──────────────┼────────────────┼----------------+
|      │             │              │              │              │                │                |
|      ▼             ▼              ▼              ▼              ▼                ▼                |
|  /proc/cpuinfo   /sys/bus/pci   /sys/bus/usb   /sys/devices   /sys/bus     /sys/firmware/dmi/     |
|                                                                            /dev/mem (SMBIOS)      |
+---------------------------------------------------------------------------------------------------+
|                                          KERNEL LINUX                                             |
|                                                                                                   |
|               Subsistemas de Buses, Controladores (Device Drivers) y Módulos (.ko)                |
+---------------------------------------------------------------------------------------------------+
|                                        CAPA DE HARDWARE                                           |
|                                                                                                   |
|   CPU / Cores    Bus PCI/PCIe    Controlador USB   Placa Base / BIOS/UEFI   Memoria RAM / Discos  |
+---------------------------------------------------------------------------------------------------+
```

---

## 💡 Casos de Uso Reales en Producción

La información obtenida por las herramientas de detección de hardware es el punto de partida en múltiples situaciones operativas:

1. **Solución de problemas (Troubleshooting):**
   - Identificar por qué una placa de red Ethernet/SFP+ no levanta enlace o no recibe IP (verificar si el kernel cargó el módulo de controlador correcto con `lspci -k`).
   - Detectar placas aceleradoras GPU o controladoras RAID que no son reconocidas tras un reinicio.
2. **Compatibilidad de software y requisitos de despliegue:**
   - Validar flags de CPU requeridas por bases de datos modernas (ej. MongoDB 5.0+ exige instrucciones AVX; hipervisores exigen flags VT-x `vmx` o AMD-V `svm`).
   - Confirmar si el servidor dispone de memoria RAM suficiente y arquitectura de 64 bits (`x86_64` o `aarch64`).
3. **Actualización de controladores y microcódigo:**
   - Identificar el identificador de fabricante y modelo exacto (*Vendor ID:Device ID*) para compilar módulos con DKMS o aplicar parches de firmware del proveedor.
4. **Planificación de capacidad (Capacity Planning & Upgrades):**
   - Comprobar ranuras de memoria libres (*DIMM slots*) y velocidad máxima soportada con `dmidecode -t memory` sin abrir el chasis del servidor.
   - Verificar si quedan líneas PCIe disponibles para agregar discos NVMe o interfaces de red adicionales.
5. **Auditoría de seguridad e inventario corporativo:**
   - Registrar números de serie de chasis, placas base y discos para control de activos (*CMDB / Asset Management*).
   - Detectar inserción no autorizada de periféricos o llaves de almacenamiento USB.

> [!IMPORTANT]
> Gran parte de estas herramientas requieren privilegios de superusuario (`sudo` o `root`) para acceder a las tablas SMBIOS del firmware (`/sys/firmware/dmi/tables`) y descriptores completos de dispositivos. Ejecutarlas sin privilegios puede arrojar salidas incompletas o campos en blanco (`Permission denied`).

---

## 🔬 Comandos Esenciales de Detección y Diagnóstico

### 1. `lspci`: El Bus PCI / PCIe al Descubierto

El comando `lspci` interroga el bus Peripheral Component Interconnect (PCI) y PCI Express (PCIe). En él residen los dispositivos de alto rendimiento del servidor: puentes del procesador (*Host Bridges*), adaptadores de video, controladoras de almacenamiento (SATA, SAS, NVMe), controladoras de red Ethernet/Fibre Channel y concentradores USB.

```bash
# Listado estándar de dispositivos PCI
lspci
```

Ejemplo de salida representativa:
```text
00:00.0 Host bridge: Intel Corporation 8th Gen Core Processor Host Bridge/DRAM Registers (rev 07)
00:01.0 PCI bridge: Intel Corporation Skylake PCIe Controller (x16) (rev 07)
00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 620 (rev 07)
00:14.0 USB controller: Intel Corporation Sunrise Point-LP USB 3.0 xHCI Controller (rev 21)
00:14.2 Signal processing controller: Intel Corporation Sunrise Point-LP Thermal subsystem (rev 21)
00:16.0 Communication controller: Intel Corporation Sunrise Point-LP CSME HECI #1 (rev 21)
00:1f.6 Ethernet controller: Intel Corporation Ethernet Connection (3) I219-LM (rev 21)
```

#### Modos de inspección avanzada con `lspci`:
- **Ver el controlador del kernel en uso (`-k`):** Permite verificar qué módulo del kernel (`Kernel driver in use`) maneja cada dispositivo y cuáles están disponibles:
  ```bash
  lspci -k
  ```
- **IDs numéricos de fabricante y producto (`-nn`):** Muestra los identificadores hexadecimales oficiales asignados por el consorcio PCI-SIG:
  ```bash
  lspci -nn
  # Ejemplo: 00:1f.6 Ethernet controller [0200]: Intel Corporation [8086:156f] (rev 21)
  ```
- **Topología en árbol (`-tv`):** Muestra la jerarquía de buses, puentes y dispositivos:
  ```bash
  lspci -tv
  ```

---

### 2. `lsusb`: Detección y Topología del Bus USB

`lsusb` enumera los buses USB de la placa base y los dispositivos conectados a cada puerto (hubs integrados, teclados, tarjetas de red inalámbricas, discos externos, lectores de tarjetas).

```bash
# Listado básico de dispositivos USB
sudo lsusb
```

Ejemplo de salida:
```text
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 001 Device 004: ID 045e:0084 Microsoft Corp. Basic Optical Mouse
Bus 001 Device 003: ID 0bda:0129 Realtek Semiconductor Corp. RTS5129 Card Reader Controller
Bus 001 Device 002: ID 8087:8001 Intel Corp. Integrated Hub
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
```

#### Anatomía de la salida:
- **`Bus 001`**: Número de bus del controlador anfitrión.
- **`Device 004`**: Dirección de dispositivo asignada dinámicamente por el kernel al conectarse.
- **`ID 045e:0084`**: Código único de identificación asignado por el USB-IF (`045e` = Vendor ID de Microsoft; `0084` = Product ID del Mouse).
- **Descripción**: Cadena descriptiva provista por la base de datos `/var/lib/usbutils/usb.ids`.

#### Modos avanzados con `lsusb`:
- **Árbol de puertos y velocidades (`-t`):** Revela si un dispositivo USB 3.0 está negociando a alta velocidad (`5000M` / `10000M`) o degradado a USB 2.0 (`480M`):
  ```bash
  lsusb -t
  ```
- **Detalle exhaustivo de descriptores (`-v`):** Desglosa consumo eléctrico en miliamperios (mA), endpoints de transferencia e interfaces:
  ```bash
  sudo lsusb -v -d 045e:0084
  ```

---

### 3. `lscpu`: Radiografía del Procesador y la Arquitectura

`lscpu` extrae información estructurada sobre la Unidad Central de Procesamiento (CPU) a partir de `/proc/cpuinfo` y de la jerarquía de SysFS (`/sys/devices/system/cpu`).

```bash
lscpu
```

Ejemplo de salida:
```text
Architecture:                    x86_64
CPU op-mode(s):                  32-bit, 64-bit
Address sizes:                   39 bits physical, 48 bits virtual
Byte Order:                      Little Endian
CPU(s):                          8
On-line CPU(s) list:             0-7
Vendor ID:                       GenuineIntel
Model name:                      Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz
CPU family:                      6
Model:                           158
Thread(s) per core:              2
Core(s) per socket:              4
Socket(s):                       1
NUMA node(s):                    1
L1d cache:                       128 KiB (4 instances)
L1i cache:                       128 KiB (4 instances)
L2 cache:                        1 MiB (4 instances)
L3 cache:                        12 MiB (1 instance)
Flags:                           fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb invpcid_single pti ssbd ibrs ibpb stibp tpr_shadow flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 hle avx2 smep bmi2 erms invpcid rtm mpx rdseed adx smap clflushopt intel_pt xsaveopt xsavec xgetbv1 xsaves dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp md_clear flush_l1d arch_capabilities
```

#### Métricas clave a interpretar:
- **`Sockets`**: Cantidad de procesadores físicos montados en la placa madre.
- **`Core(s) per socket`**: Cantidad de núcleos físicos reales por cada procesador.
- **`Thread(s) per core`**: Si es mayor a 1, indica tecnología Hyper-Threading (Intel) o SMT (AMD). En el ejemplo anterior, $1 \text{ socket} \times 4 \text{ cores} \times 2 \text{ threads} = 8 \text{ CPUs lógicas}$.
- **`NUMA node(s)`**: Indica si la memoria está dividida en nodos de acceso no uniforme (habitual en servidores multi-socket para optimizar latencia de bus).
- **`Flags`**: Características de hardware habilitadas:
  - `lm` (*Long Mode*): Soporta instrucciones de 64 bits.
  - `vmx` / `svm`: Virtualización asistida por hardware (Intel VT-x / AMD-V).
  - `aes`: Aceleración por hardware para algoritmos de cifrado simétrico AES (vital para LUKS y gocryptfs).
  - `avx` / `avx2`: Extensiones vectoriales avanzadas para cálculo científico e IA.

---

### 4. `dmidecode`: Metadatos del Firmware, BIOS y Placa Base (DMI / SMBIOS)

`dmidecode` es la herramienta de mayor nivel forense para inspeccionar la tabla de datos **DMI** (*Desktop Management Interface*) o **SMBIOS** (*System Management BIOS*). Permite responder preguntas de hardware físico sin tener que reiniciar para entrar a la BIOS ni abrir el gabinete.

```bash
# Requiere sudo de forma obligatoria para leer /dev/mem o /sys/firmware/dmi/tables
sudo dmidecode
```

#### Consulta de tipos específicos (`-t` o `--type`):
La tabla SMBIOS clasifica la información por identificadores numéricos y palabras clave:

| Tipo | Palabra Clave | Información Extraída |
| :--- | :--- | :--- |
| **0** | `bios` | Versión del firmware, fecha de compilación, tamaño de ROM, capacidades de arranque. |
| **1** | `system` | Fabricante del equipo, modelo comercial, número de serie, UUID del chasis, tipo de encendido. |
| **2** | `baseboard` | Fabricante de la placa base, modelo, versión de revisión de hardware, número de serie. |
| **3** | `chassis` | Tipo de gabinete (Rack Mount 1U/2U/4U, Blade, Tower), estado de cerraduras de seguridad. |
| **4** | `processor` | Socket del procesador, voltaje, velocidad máxima y actual, soporte de 64 bits. |
| **16** | `memory` | Capacidad máxima de memoria RAM que soporta la placa base y controladora. |
| **17** | `memory` | Detalle ranura por ranura: fabricante del módulo (DIMM), tamaño, tipo (DDR4/DDR5), velocidad real. |

#### Ejemplos de uso directo en administración:

**Identificar el servidor, modelo y número de serie para garantías o soporte:**
```bash
sudo dmidecode -t system
```
Salida:
```text
Handle 0x0001, DMI type 1, 27 bytes
System Information
	Manufacturer: Dell Inc.
	Product Name: Latitude E7450
	Version: 01
	Serial Number: ABCDEFG
	UUID: 12345678-1234-5678-90ab-cdef12345678
	Wake-up Type: Power Switch
	SKU Number: Not Specified
	Family: Not Specified
```

**Verificar placa base:**
```bash
sudo dmidecode -t baseboard
```
Salida:
```text
Handle 0x0002, DMI type 2, 15 bytes
Base Board Information
	Manufacturer: Dell Inc.
	Product Name: 0NVJ4C
	Version: A00
	Serial Number: .ABCDE.
	Features:
		Board is a hosting board
		Board is replaceable
```

**Auditar slots de memoria RAM disponibles y ocupados:**
```bash
sudo dmidecode -t 17 | grep -E "Size:|Speed:|Manufacturer:|Part Number:|Locator:"
```

---

### 5. `lshw`: Visión Panorámica del Hardware Completo

`lshw` (*List Hardware*) integra la información de múltiples fuentes (`/proc`, SysFS, DMI, PCI, USB) en un árbol coherente de componentes físicos y lógicos.

```bash
# Resumen general del hardware en formato tabular
sudo lshw -short
```

Ejemplo de salida de `lshw -short`:
```text
H/W path           Device     Class          Description
========================================================
                              system         Latitude E7450 (Dell Inc.)
/0                            bus            0NVJ4C
/0/0                          memory         64KiB BIOS
/0/4                          processor      Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz
/0/4/5                        memory         128KiB L1 cache
/0/4/6                        memory         1MiB L2 cache
/0/4/7                        memory         12MiB L3 cache
/0/32                         memory         16GiB System Memory
/0/32/0                       memory         8GiB SODIMM DDR4 Synchronous 2400 MHz
/0/32/1                       memory         8GiB SODIMM DDR4 Synchronous 2400 MHz
/0/100                        bridge         8th Gen Core Processor Host Bridge/DRAM Registers
/0/100/2                      display        UHD Graphics 620
/0/100/14          usb1       bus            Sunrise Point-LP USB 3.0 xHCI Controller
/0/100/1f.6        eth0       network        Ethernet Connection (3) I219-LM
/0/1               scsi0      storage        
/0/1/0.0.0         /dev/sda   disk           512GB SanDisk SD8SN8U5
```

#### Filtrado por clases de componentes (`-C`):
Permite concentrarse en un subsistema específico sin verse abrumado por miles de líneas:
```bash
# Auditar interfaces de red cableadas e inalámbricas
sudo lshw -C network

# Auditar almacenamiento y discos
sudo lshw -C disk

# Auditar memoria del sistema
sudo lshw -C memory
```

#### Exportación para inventarios y automatización:
```bash
# Exportar reporte en formato JSON
sudo lshw -json > /tmp/hardware_inventory.json

# Exportar reporte legible en HTML con tablas
sudo lshw -html > /var/www/html/inventario.html
```

---

### 6. `hwinfo`: Información Estructurada y Exhaustiva

A diferencia de otras herramientas, `hwinfo` proporciona una salida altamente granular y clasificada, ideal para diagnósticos donde se requiere el código exacto de subdispositivo (*SubDevice ID*) y las rutas de SysFS.

```bash
# Instalación si no se encuentra disponible:
# Debian/Ubuntu: sudo apt-get install -y hwinfo
# RHEL/Fedora:   sudo dnf install -y hwinfo

# Resumen general rápido
hwinfo --short
```

Ejemplo de reporte sobre una interfaz de red (`hwinfo --network`):
```text
16: PCI 400.0: 0200 Ethernet controller
  [Created at pci.386]
  Unique ID: rBUF.2W34giDyZvD
  SysFS ID: /devices/pci0000:00/0000:00:1c.0/0000:04:00.0
  SysFS BusID: 0000:04:00.0
  Hardware Class: network
  Model: "Intel Ethernet Controller X710 for 10GbE SFP+"
  Vendor: pci 0x8086 "Intel Corporation"
  Device: pci 0x1572 "Ethernet Controller X710 for 10GbE SFP+"
  SubVendor: pci 0x15d9 "Super Micro Computer Inc"
  SubDevice: pci 0x000d 
  Driver: "i40e"
  Driver Modules: "i40e"
  Device File: eno1
  HW Address: 00:25:90:xx:xx:xx
  Link detected: yes
```

---

## 📊 Matriz Comparativa de Herramientas de Detección

| Herramienta | Origen de Datos | Nivel de Detalle | Requiere Root | Caso de Uso Primario |
| :--- | :--- | :--- | :--- | :--- |
| **`lscpu`** | `/proc/cpuinfo`, SysFS | Medio | ❌ No | Arquitectura, núcleos, sockets, flags de virtualización y cachés de CPU. |
| **`lspci`** | `/sys/bus/pci` | Alto | ⚠️ Parcial (`-v`/`-k` mejor con root) | Dispositivos conectados al bus PCI/PCIe, controladores y módulos de kernel asociados. |
| **`lsusb`** | `/sys/bus/usb`, devfs | Alto | ⚠️ Sí para descriptores (`-v`) | Periféricos y concentradores USB, topología y velocidades de enlace. |
| **`dmidecode`** | SMBIOS / DMI firmware | Muy Alto |  Sí | Números de serie de chasis/placa, versión de BIOS, slots de memoria física. |
| **`lshw`** | Integración multisubsistema | Muy Alto |  Sí (para datos completos) | Inventario integral físico y lógico del servidor; exportación JSON/HTML. |
| **`hwinfo`** | Probing activo de hardware | Exhaustivo |  Sí | Auditoría profunda de drivers, chips, sub-vendors y rutas SysFS. |

---

## 🛠️ Demostración Práctica Interactiva (`demo_hardware.sh`)

El repositorio incluye el script didáctico interactivo [`demo_hardware.sh`](demo_hardware.sh) que guía paso a paso al estudiante por todas estas herramientas, explicando en vivo qué significa cada valor.

### Ejecución en Terminal:

```bash
cd linux/administrator/hardware
sudo ./demo_hardware.sh
```

### Opciones disponibles:
- `--auto <segundos>`: Ejecución automatizada con pausas temporizadas para demostraciones en video o CI.
- `--help`: Muestra la ayuda de opciones.
