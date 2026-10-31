---
id: lab-1.5-deteccion-hardware
title: Detección, Inventario y Auditoría Forense de Hardware en Linux (lspci, lsusb,
  lshw, hwinfo, dmidecode, lscpu)
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
- troubleshooting
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
  os: Rocky Linux 10.2 / Ubuntu 24.04 LTS
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-30'
  notes: Detección completa de dispositivos PCI virtuales, arquitectura de CPU con
    lscpu, extracción DMI/SMBIOS con dmidecode y auditoría con lshw y hwinfo.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-30'
  notes: Compatible en instancias virtualizadas Xen y Nitro (KVM) en AWS.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
- Rocky Linux 10.2
status: PASSED
rag_summary: 'Laboratorio integral y guía de autoaprendizaje sobre detección, inventario
  y diagnóstico forense de hardware en Linux. Basado en el temario oficial de administración
  de sistemas, enseña a interrogar los buses físicos y lógicos mediante lspci y lsusb,
  analizar la microarquitectura de la CPU con lscpu, extraer metadatos de firmware
  BIOS y placa base mediante dmidecode (DMI/SMBIOS) y generar reportes jerárquicos
  de inventario con lshw y hwinfo. Cubre los cinco grandes escenarios operativos de
  producción: resolución de problemas (troubleshooting de red y drivers), compatibilidad
  de software (flags AVX/VT-x), actualizaciones de controladores (Vendor:Device IDs),
  planificación de mejoras (slots DIMM libres sin abrir el chasis) y auditoría corporativa
  automatizada en JSON/HTML para CMDB.'
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

El sistema operativo Linux es ampliamente reconocido por su **flexibilidad y capacidad para adaptarse a múltiples configuraciones de hardware**: desde microcontroladores embebidos y computadoras portátiles hasta supercomputadoras y servidores corporativos en la nube.

En un entorno Linux, es esencial poder detectar y obtener **información detallada sobre los componentes físicos y lógicos** del sistema. Esto no solo garantiza un funcionamiento óptimo, sino que constituye el pilar indispensable para la **resolución de incidencias, la compatibilidad de software, la planificación de mejoras y la auditoría de seguridad corporativa**.

Este laboratorio cubre las 6 herramientas esenciales de auditoría de hardware en Linux: `lscpu`, `lspci`, `lsusb`, `dmidecode`, `lshw` y `hwinfo`.

---

## ⚡ Ruta Rápida de Autoaprendizaje (Cheat Sheet de 60 Segundos)

> [!TIP]
> Cada herramienta responde a una pregunta diferente del sistema. Memorizá esta tabla para saber exactamente qué comando ejecutar en cada situación:

| Herramienta | ¿Qué pregunta responde? | Caso típico de uso | ¿Requiere `sudo`? |
| :--- | :--- | :--- | :--- |
| **`lscpu`** | *"¿Qué procesador tengo y cuántos núcleos/hilos hay?"* | Comprobar núcleos, arquitectura 64-bit y soporte de virtualización. | ❌ No |
| **`lspci`** | *"¿Qué placas internas y controladoras están conectadas?"* | Identificar tarjeta de red, GPU, controladora SATA/NVMe y drivers. | ⚠️ Parcial (`-k` con root) |
| **`lsusb`** | *"¿Qué periféricos externos y hubs USB están enchufados?"* | Detectar pendrives, dongles, lectores de tarjeta y módems. | ⚠️ Sí para `-v` |
| **`dmidecode`** | *"¿Qué dice la BIOS/UEFI sobre la placa, serial y memoria RAM?"* | Ver ranuras de memoria libres, modelo del chasis y serial del equipo. |  **Sí (obligatorio)** |
| **`lshw`** | *"¿Cómo es el árbol jerárquico completo del hardware?"* | Exportar inventario corporativo completo a JSON o HTML. |  **Sí (para ver todo)** |
| **`hwinfo`** | *"¿Cuáles son los detalles técnicos y rutas SysFS de cada chip?"* | Diagnóstico granular de controladores y subdispositivos. | ⚠️ Opcional (`sudo` da más) |

---

## 🏗️ Arquitectura Interna: Del Silicio al Espacio de Usuario

En Linux, las herramientas de diagnóstico no "adivinan" el hardware; interrogan a las interfaces que el **Kernel Linux** expone a través de pseudo-sistemas de archivos en memoria:

```
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                                ESPACIO DE USUARIO (HERRAMIENTAS CLI)                              │
│                                                                                                   │
│    lscpu         lspci          lsusb          lshw          hwinfo          dmidecode            │
│      │             │              │              │              │                │                │
+------┼─────────────┼──────────────┼──────────────┼──────────────┼────────────────┼────────────────+
│      ▼             ▼              ▼              ▼              ▼                ▼                │
│  /proc/cpuinfo   /sys/bus/pci   /sys/bus/usb   /sys/devices   /sys/bus     /sys/firmware/dmi/     │
│                                                                            /dev/mem (SMBIOS)      │
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                                          KERNEL LINUX                                             │
│                                                                                                   │
│              Subsistemas de Buses, Controladores (Device Drivers) y Módulos (.ko)                 │
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                                        CAPA DE HARDWARE                                           │
│                                                                                                   │
│   CPU / Cores    Bus PCI/PCIe    Controlador USB   Placa Base / BIOS/UEFI   Memoria RAM / Discos  │
+───────────────────────────────────────────────────────────────────────────────────────────────────+
```

1. **`/proc/cpuinfo`:** Expone las capacidades del procesador (flags, frecuencias, núcleos, cachés).
2. **`/sys/bus/pci/`:** Árbol de SysFS que mapea direcciones de bus, vendor IDs, device IDs y drivers asociados.
3. **`/sys/bus/usb/`:** Registro de topología de concentradores raíz (*root hubs*) y endpoints USB.
4. **`/sys/firmware/dmi/tables` & `/dev/mem`:** Tablas SMBIOS (*System Management BIOS*) escritas por el fabricante en la memoria ROM del firmware.

> [!IMPORTANT]
> **¿Por qué muchas herramientas exigen `sudo` o `root`?**
> Para proteger la seguridad del sistema y la privacidad física (números de serie, UUIDs del chasis, llaves de firmware y direcciones físicas de memoria en `/dev/mem`). Si ejecutás `dmidecode`, `lshw` o `lspci -v` como usuario normal, el kernel restringirá el acceso y verás campos vacíos o errores de `Permission denied`.

---

## 🔬 Los 6 Comandos Fundamentales en Profundidad

### 1. `lspci`: El Bus PCI / PCIe al Descubierto

Lista todos los dispositivos conectados al bus **PCI (*Peripheral Component Interconnect*)** y **PCIe**: puentes del procesador (*Host Bridges*), adaptadores de video, controladoras de red Ethernet, interfaces inalámbricas, controladoras SATA/NVMe y concentradores USB integrados.

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
- **Verificar el controlador del kernel en uso (`-k`):** Es el modo más importante para administradores de sistemas. Permite saber qué módulo del kernel está controlando el dispositivo y qué controladores alternativos existen:
  ```bash
  lspci -k
  # Salida:
  # 00:1f.6 Ethernet controller: Intel Corporation Ethernet Connection (3) I219-LM
  #         Kernel driver in use: e1000e
  #         Kernel modules: e1000e
  ```
- **IDs numéricos de fabricante y producto (`-nn`):** Muestra los códigos hexadecimales asignados por el consorcio PCI-SIG (`[VendorID:DeviceID]`):
  ```bash
  lspci -nn
  # Ejemplo: 00:1f.6 Ethernet controller [0200]: Intel Corporation [8086:156f] (rev 21)
  ```
- **Topología en árbol (`-tv`):** Muestra cómo se conectan los puentes y ranuras secundarias:
  ```bash
  lspci -tv
  ```

---

### 2. `lsusb`: Detección y Topología del Bus USB

Muestra los concentradores raíz (*root hubs*) y todos los dispositivos USB conectados al sistema (teclados, ratones, pendrives, impresoras, dongles de red, lectores de tarjetas).

```bash
# Listar dispositivos USB conectados
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

#### Anatomía de la salida de `lsusb`:
- **`Bus 001`**: Número de bus del controlador anfitrión (*Host Controller*).
- **`Device 004`**: Dirección de dispositivo asignada dinámicamente por el kernel al conectarlo.
- **`ID 045e:0084`**: Código de 16 bits en hexadecimal del consorcio USB-IF:
  - `045e`: **Vendor ID** (Identificador del fabricante: Microsoft Corp.).
  - `0084`: **Product ID** (Identificador del modelo: Basic Optical Mouse).
- **Descripción textual**: Obtenida a partir de la base de datos local `/var/lib/usbutils/usb.ids`.

#### Modos avanzados con `lsusb`:
- **Árbol de puertos y velocidades (`-t`):** Crucial para saber si un dispositivo USB 3.0 está negociando a velocidad SuperSpeed (`5000M` / `10000M`) o degradado a USB 2.0 (`480M`):
  ```bash
  lsusb -t
  ```
- **Detalle de descriptores (`-v`):** Muestra consumo eléctrico en miliamperios (mA) y configuraciones de energía:
  ```bash
  sudo lsusb -v -d 045e:0084
  ```

---

### 3. `lscpu`: Radiografía del Procesador y la Arquitectura

Interroga `/proc/cpuinfo` y SysFS para generar un resumen comprensible de la CPU, sockets, núcleos lógicos y capacidades de instrucción.

```bash
lscpu
```

Ejemplo de salida:
```text
Architecture:                    x86_64
CPU op-mode(s):                  32-bit, 64-bit
Byte Order:                      Little Endian
CPU(s):                          8
On-line CPU(s) list:             0-7
Thread(s) per core:              2
Core(s) per socket:              4
Socket(s):                       1
NUMA node(s):                    1
Vendor ID:                       GenuineIntel
CPU family:                      6
Model:                           158
Model name:                      Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz
L1d cache:                       128 KiB (4 instances)
L1i cache:                       128 KiB (4 instances)
L2 cache:                        1 MiB (4 instances)
L3 cache:                        12 MiB (1 instance)
Flags:                           fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt aes xsave avx f16c rdrand hypervisor lahf_lm abm 3dnowprefetch avx2
```

#### Métricas de arquitectura clave:
- **`Sockets`**: Número de procesadores físicos montados en zócalos de la placa madre.
- **`Core(s) per socket`**: Cantidad de núcleos físicos independientes por procesador.
- **`Thread(s) per core`**: Multiplicador por Hyper-Threading (Intel) o SMT (AMD). En el ejemplo:
  $$\text{Total CPUs Lógicas} = 1 \text{ Socket} \times 4 \text{ Cores} \times 2 \text{ Threads} = 8 \text{ CPUs}$$
- **`Flags` críticas a buscar:**
  - `lm` (*Long Mode*): Soporte nativo para 64 bits.
  - `vmx` (Intel) / `svm` (AMD): Soporte de virtualización asistida por hardware (KVM, Proxmox, VMware).
  - `aes`: Aceleración por hardware para cifrado AES (vital para LUKS, VPNs y TLS).
  - `avx` / `avx2`: Instrucciones vectoriales avanzadas requeridas por bases de datos y motores de IA modernos.

---

### 4. `dmidecode`: Metadatos del Firmware, BIOS y Placa Base (DMI / SMBIOS)

Interroga las tablas **DMI (*Desktop Management Interface*)** y **SMBIOS** directamente desde el firmware. Permite conocer números de serie, fabricante del chasis, versión de BIOS y slots de memoria RAM sin necesidad de reiniciar el equipo ni abrir físicamente el gabinete del servidor.

```bash
# Requiere sudo obligatoriamente para acceder a las tablas SMBIOS
sudo dmidecode
```

#### Consulta por tipos (`-t` o `--type`):
| Tipo | Nombre clave | ¿Qué información extrae? |
| :--- | :--- | :--- |
| **`0`** | `bios` | Fabricante de BIOS/UEFI, versión instalada, fecha de lanzamiento, ROM size. |
| **`1`** | `system` | Fabricante del equipo (Dell, HP, Lenovo), modelo comercial, número de serie, UUID del chasis. |
| **`2`** | `baseboard` | Fabricante y modelo de la placa base (motherboard), versión de revisión, número de serie de placa. |
| **`3`** | `chassis` | Tipo de gabinete (Rack Mount 1U/2U/4U, Blade, Tower). |
| **`4`** | `processor` | Socket, voltaje, velocidad máxima y fabricante del CPU. |
| **`16`** | `memory` | Capacidad máxima de memoria RAM que admite la placa base. |
| **`17`** | `memory` | Detalle ranura por ranura: tecnología (DDR4/DDR5), velocidad real (MHz), capacidad del módulo y slots vacíos. |

#### Ejemplos de uso directo:
```bash
# 1. Obtener información del sistema y número de serie para soporte oficial:
sudo dmidecode -t system

# Salida:
# Handle 0x0001, DMI type 1, 27 bytes
# System Information
# 	Manufacturer: Dell Inc.
# 	Product Name: Latitude E7450
# 	Version: 01
# 	Serial Number: ABCDEFG
# 	UUID: 12345678-1234-5678-90ab-cdef12345678

# 2. Obtener información de la placa base:
sudo dmidecode -t baseboard

# Salida:
# Handle 0x0002, DMI type 2, 15 bytes
# Base Board Information
# 	Manufacturer: Dell Inc.
# 	Product Name: 0NVJ4C
# 	Version: A00
# 	Serial Number: .ABCDE.

# 3. Auditar ranuras de memoria RAM instaladas y vacías:
sudo dmidecode -t 17 | grep -E "Size:|Speed:|Manufacturer:|Locator:"
```

---

### 5. `lshw`: Visión Panorámica del Hardware Completo

`lshw` (*List Hardware*) integra la información de múltiples fuentes (`/proc`, SysFS, DMI, PCI, USB, SCSI) en un reporte único, estructurado y navegable.

```bash
# Resumen general del hardware en formato tabular compacto
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

#### Filtrado por clases de hardware (`-C`):
Evita que la salida sea abrumadora mostrando únicamente la sección de interés:
```bash
# Inspeccionar únicamente la red:
sudo lshw -C network

# Inspeccionar únicamente discos y almacenamiento:
sudo lshw -C disk

# Inspeccionar memoria RAM:
sudo lshw -C memory
```

#### Exportación para CMDB y auditorías automáticas:
```bash
# Generar reporte estructurado en JSON para scripts de automatización:
sudo lshw -json > inventario_hardware.json

# Generar reporte visual en HTML con tablas para auditoría:
sudo lshw -html > inventario_hardware.html
```

---

### 6. `hwinfo`: Información Granular y Altamente Estructurada

A diferencia de `lshw`, `hwinfo` (desarrollado originalmente para openSUSE) realiza un sondeo (*probing*) exhaustivo y devuelve datos normalizados con rutas directas de SysFS y códigos de subfabricante (*SubVendor ID*).

> [!NOTE]
> `hwinfo` no siempre viene instalado por defecto en distros Debian/Ubuntu o RHEL/Rocky. Se instala fácilmente con:
> ```bash
> # Debian / Ubuntu:
> sudo apt-get update && sudo apt-get install -y hwinfo
> 
> # RHEL / Rocky Linux (requiere repositorio EPEL):
> sudo dnf install -y epel-release && sudo dnf install -y hwinfo
> ```

```bash
# Resumen compacto de hardware con hwinfo:
hwinfo --short
```

Ejemplo de salida sobre un controlador Ethernet (`hwinfo --network`):
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

## 🏢 Los 5 Casos de Uso Reales de Producción

En las diapositivas de clase se destacan 5 grandes escenarios en los que la información de hardware es determinante:

### 1. Solución de Problemas (*Troubleshooting de Red y Drivers*)
**Escenario:** El servidor se reinició y la interfaz de red de 10 Gbps no levanta enlace ni recibe configuración IP.
**Procedimiento forense:**
```bash
# 1. ¿El kernel reconoce físicamente la placa en el bus PCIe?
lspci | grep -i ethernet

# 2. ¿Qué driver está usando el kernel y qué módulos alternativos existen?
lspci -k -s $(lspci | grep -i ethernet | awk '{print $1}')
# Si 'Kernel driver in use' está vacío, falta el módulo del kernel.

# 3. ¿El driver arrojó errores al cargar?
dmesg | grep -i -E 'eth|e1000e|i40e|r8169|link'
```

---

### 2. Compatibilidad de Software y Requisitos Mínimos
**Escenario:** Querés desplegar MongoDB 5.0+, Elasticsearch o un hipervisor KVM. Cada uno impone requisitos estrictos de CPU y memoria.
**Procedimiento de validación:**
```bash
# 1. ¿La CPU soporta 64 bits y extensiones vectoriales AVX (exigidas por MongoDB)?
lscpu | grep -E 'Architecture|op-mode|Model name'
lscpu | grep -i flags | grep -o -E '\b(avx|avx2|lm)\b'

# 2. ¿El procesador soporta virtualización asistida por hardware para KVM?
lscpu | grep -i flags | grep -o -E '\b(vmx|svm)\b'
# vmx = Intel VT-x | svm = AMD-V

# 3. ¿Tiene aceleración de cifrado por hardware para LUKS?
lscpu | grep -i flags | grep -o -E '\baes\b'
```

---

### 3. Actualización de Controladores y Firmware
**Escenario:** Un dispositivo no funciona con el controlador genérico y el fabricante te solicita el modelo exacto y el código *Vendor:Device* para entregarte el archivo `.ko` o firmware.
**Procedimiento de identificación:**
```bash
# 1. Para placas internas (PCIe):
lspci -nn | grep -i -E 'network|vga|raid'
# Salida: [8086:1572] -> 8086 = Intel Corp | 1572 = X710 10GbE

# 2. Para periféricos externos (USB):
lsusb
# Salida: ID 045e:0084 -> 045e = Microsoft | 0084 = Basic Optical Mouse
```

---

### 4. Planificación de Actualizaciones y Mejoras (*Capacity Planning*)
**Escenario:** Tu servidor de base de datos se está quedando sin RAM. Antes de comprar memoria, necesitás saber cuántas ranuras están libres, qué tipo de módulo soporta la placa y cuál es la capacidad máxima admitida, **sin abrir el chasis en el datacenter**.
**Procedimiento de consulta DMI:**
```bash
# 1. Ver capacidad máxima admitida por la placa base (Type 16):
sudo dmidecode -t 16 | grep "Maximum Capacity"

# 2. Ver cuántas ranuras existen y cuáles dicen "No Module Installed" (Type 17):
sudo dmidecode -t 17 | grep -E "Locator:|Size:|Speed:|Type:"
```

---

### 5. Auditoría de Seguridad y Gestión de Inventarios (*CMDB / Asset Management*)
**Escenario:** La empresa debe completar una auditoría ISO/SOC2 y certificar el número de serie de todos los servidores físicos en producción.
**Procedimiento de extracción:**
```bash
# 1. Extraer fabricante, modelo y número de serie con dmidecode strings:
sudo dmidecode -s system-manufacturer
sudo dmidecode -s system-product-name
sudo dmidecode -s system-serial-number
sudo dmidecode -s system-uuid

# 2. Exportar el inventario completo en formato JSON para ingestión automática:
sudo lshw -json > /var/log/inventario_hardware_$(hostname).json
```

---

## 🧪 Mini-Laboratorio Práctico de Autoaprendizaje (15 minutos)

Podés ejecutar estos 4 ejercicios guiados en tu terminal para dominar las herramientas:

### Mini-Lab 1: Radiografía express de la CPU
```bash
# 1. Consultar arquitectura y total de CPUs lógicas
lscpu | grep -E "Architecture|CPU\(s\):|Thread|Core|Socket|Model name"

# 2. Calcular matemáticamente: Sockets x Cores x Threads
# ¿Coincide el producto con el número de CPUs lógicas?

# 3. Comprobar soporte de virtualización y cifrado acelerado
lscpu | grep -E "vmx|svm|aes"
```

### Mini-Lab 2: Inspección del Bus PCI y sus Controladores
```bash
# 1. Listar los primeros 5 dispositivos PCI del sistema
lspci | head -n 5

# 2. Filtrar por la tarjeta de red y ver su controlador en uso
lspci -k | grep -A 3 -i ethernet

# 3. Obtener el Vendor y Product ID en formato hexadecimal [xxxx:yyyy]
lspci -nn | grep -i ethernet
```

### Mini-Lab 3: Auditoría de BIOS y Placa Base sin reiniciar
```bash
# 1. Consultar datos del sistema y número de serie
sudo dmidecode -t system

# 2. Consultar modelo de la placa base
sudo dmidecode -t baseboard

# 3. Consultar las ranuras de memoria RAM
sudo dmidecode -t 17 | grep -E "Size:|Speed:|Type:|Locator:"
```

### Mini-Lab 4: Generación de Inventario en JSON
```bash
# 1. Generar reporte estructurado de hardware con lshw
sudo lshw -json > /tmp/reporte_hw.json

# 2. Verificar que el JSON se haya generado correctamente
head -n 20 /tmp/reporte_hw.json
du -h /tmp/reporte_hw.json
```

---

## 🎯 Retos de Autoevaluación ("Ponte a prueba")

<details>
<summary><b>1. Si un servidor físico cuenta con 2 Sockets, 16 Cores por socket y 2 Threads por core, ¿cuántas CPUs reportará <code>lscpu</code>?</b></summary>
<br>
<b>Respuesta:</b> Reportará <b>64 CPUs lógicas</b> ($2 \times 16 \times 2 = 64$). Cada núcleo físico ejecuta 2 hilos mediante Hyper-Threading o SMT.
</details>

<details>
<summary><b>2. Si ejecutás <code>lspci -k</code> sobre una placa de red y la línea <code>Kernel driver in use</code> no aparece, ¿qué significa?</b></summary>
<br>
<b>Respuesta:</b> Significa que el kernel detectó la presencia física del dispositivo en el bus PCIe, pero <b>ningún controlador o módulo del kernel (.ko) está asignado</b> para gestionarlo. El dispositivo no podrá ser utilizado por el sistema operativo hasta que se cargue el driver correspondiente o se instale el firmware requerido.
</details>

<details>
<summary><b>3. ¿Qué comando te permite saber si una placa base admite hasta 128 GB de memoria RAM sin apagar el servidor?</b></summary>
<br>
<b>Respuesta:</b> <code>sudo dmidecode -t 16</code> (o <code>sudo dmidecode -t memory</code>), observando el campo <b>Maximum Capacity</b> provisto por la tabla SMBIOS.
</details>

<details>
<summary><b>4. ¿Cuál es la diferencia de uso entre <code>lshw -short</code> y <code>lshw -json</code>?</b></summary>
<br>
<b>Respuesta:</b> <code>lshw -short</code> está diseñado para la <b>lectura humana rápida</b> en consola en formato de tabla de tres columnas (H/W path, Device, Description). Por el contrario, <code>lshw -json</code> genera un <b>árbol de objetos estructurado</b> ideal para automatización con Python, jq o ingesta directa en bases de datos de inventario (CMDB).
</details>

---

## 🛠️ Demostración Práctica Interactiva (`demo_hardware.sh`)

El repositorio incluye el script didáctico interactivo [`demo_hardware.sh`](demo_hardware.sh) que automatiza y explica en vivo cada una de las herramientas de hardware en tu terminal.

### Ejecución en Terminal:
```bash
cd linux/administrator/hardware
sudo ./demo_hardware.sh
```

### Opciones de ejecución:
- `--auto <segundos>`: Ejecución automatizada con pausas temporizadas para demostraciones en video o CI (ej. `sudo ./demo_hardware.sh --auto 2`).
- `--keep`: Preserva los archivos de inventario generados (`/tmp/lab_demo_hardware/reporte_hardware.json`) para inspección manual post-laboratorio.
- `--help`: Muestra el menú de ayuda y opciones disponibles.
