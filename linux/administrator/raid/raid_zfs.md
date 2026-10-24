---
id: lab-3.11-raid-zfs
title: 'RAID con ZFS (OpenZFS): Pools, RAIDZ sin Write-Hole, ARC/SLOG, Self-Healing
  y Resilvering'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.11'
sections:
- '3.11'
- '3'
category: storage
tags:
- storage
- raid
- zfs
- openzfs
- raidz
- raidz2
- arc
- slog
- zil
- self-healing
- resilver
- scrub
- uberblock
- loop-devices
tools:
- zpool
- zfs
- losetup
- dd
- sha256sum
- sync
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 1024
  min_disks: 0
tested_environments:
- environment: Bare-Metal
  type: local
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Probado con loop devices sobre Ubuntu 24.04 con paquete zfsutils-linux en
    VirtualBox / Bare-Metal. En WSL2 requiere kernel custom o ejecutar en VM/EC2.
environments:
- Bare-Metal
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Guía técnica completa sobre almacenamiento empresarial de alta disponibilidad
  con OpenZFS. Analiza la arquitectura de Storage Pools y Virtual Devices (vdevs),
  el funcionamiento matemático de RAIDZ (paridad dinámica que elimina el clásico write-hole
  mediante franjas de ancho variable), la jerarquía de memoria y cachés multinivel
  (ARC en RAM, L2ARC en SSD y SLOG/ZIL para escrituras síncronas), la auto-reparación
  matemática contra corrupción silenciosa (self-healing con checksums Fletcher4 de
  256 bits) y el proceso de reconstrucción (resilvering) tras sustituciones de discos
  en caliente.
files:
  guide: raid/raid_zfs.md
  script: raid/demo_raid_zfs.sh
  terraform: null
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
prerequisites:
- lab-3.7-raid-teoria-comparativa
- lab-3.8-raid-mdadm
- lab-3.9-raid-lvm
- lab-3.10-raid-btrfs
next_recommended_labs:
- integrador-4.5-resiliencia-raid-metricas-aws
mcp_tools:
- linux-labs-tutor
- bash
---

# Lab 3.11 · RAID con OpenZFS: Pools, RAIDZ sin Write-Hole, Cachés y Resilvering

> **Serie RAID (de fácil a difícil):** 3.7 Teoría → 3.8 mdadm → 3.9 LVM RAID → 3.10 Btrfs → **3.11 ZFS** → 4.5 Integrador AWS con fallas, recuperación y métricas.

**Objetivo:** dominar el estándar de oro del almacenamiento empresarial y la integridad de datos: **OpenZFS**. Aprenderás cómo ZFS revoluciona el concepto de RAID mediante **vdevs**, cómo su diseño Copy-on-Write transaccional **elimina por completo el write-hole** sin requerir bitmaps ni diarios auxiliares, cómo opera la jerarquía de cachés (**ARC, L2ARC y SLOG/ZIL**), cómo auto-repara silenciosamente bloques corruptos (*self-healing*) y cómo gestiona la reconstrucción acelerada (*resilvering*) ante fallos de hardware.

**Requisitos:** permisos de root y soporte de OpenZFS (`zfsutils-linux`). Debido a la licencia CDDL de OpenZFS, el módulo no se incluye por defecto en el kernel estándar provisto por Microsoft en WSL2; se recomienda ejecutar en una VM de Ubuntu en VirtualBox, en una instancia EC2 de AWS o en Linux Bare-Metal.

---

## 1. Arquitectura: La Filosofía de OpenZFS

En los sistemas tradicionales existe una jerarquía rígida y fragmentada:
1. Una controladora RAID o `mdadm` crea un dispositivo de bloques `/dev/md0`.
2. LVM agrupa esos bloques en un Volume Group y crea Logical Volumes.
3. Un sistema de archivos (ext4/XFS) formatea el volumen lógico.

**ZFS destruye esa separación:** es simultáneamente el **controlador de volumen físico, el subsistema RAID y el sistema de archivos transaccional**.

```
                SISTEMAS DE ARCHIVOS Y VOLÚMENES LÓGICOS
          tank/db (lz4, atime=off)       tank/vms (volumen zvol)
  ──────────────────────────────────────────────────────────────────
                       ZFS STORAGE POOL (zpool)
       Pool unificado de almacenamiento compartido y dinámico
  ──────────────────────────────────────────────────────────────────
                    VIRTUAL DEVICES (vdevs)
       ┌──────────────────────────────┐    ┌──────────────────────┐
       │   vdev RAIDZ1 (3 discos)     │    │   vdev SLOG (ZIL)    │
       │  disk1    disk2    disk3     │    │   NVMe ultrarrápido  │
       └──────────────────────────────┘    └──────────────────────┘
```

### 1.1 Etiquetas de Disco (Labels L0 a L3) y Uberblocks

Para evitar desastres por fallas de metadatos, cada disco perteneciente a un zpool guarda **4 etiquetas idénticas (Labels L0, L1, L2, L3)**:
- Dos etiquetas en los primeros 512 KiB del disco.
- Dos etiquetas en los últimos 512 KiB del disco.

Cada etiqueta contiene un anillo rotativo de **128 Uberblocks** (la raíz de todo el árbol de punteros del pool). Al escribir datos, ZFS nunca sobrescribe el uberblock activo; escribe uno nuevo y solo si la transacción fue 100% exitosa, avanza el puntero de secuencia. Esto garantiza que un corte repentino de energía nunca corrompa el sistema de archivos.

### 1.2 ¿Por qué RAIDZ no sufre de "Write-Hole"?

En RAID 5 clásico (`mdadm`/HW RAID), las franjas de datos tienen un tamaño fijo predeterminado. Modificar un archivo pequeño implica leer el dato viejo, leer la paridad vieja, recalcular y reescribir. Si la energía falla en el medio, la paridad queda desincronizada.

**En ZFS RAIDZ:**
- El sistema es estrictamente **Copy-on-Write (CoW)**.
- **Las franjas tienen ancho variable:** ZFS solo escribe la cantidad exacta de bloques que el archivo necesita, calculando la paridad en el mismo commit atómico. Nunca se sobrescribe nada existente.
- Ergo: **El write-hole es matemáticamente imposible en ZFS**.

### 1.3 Jerarquía de Rendimiento: ARC, L2ARC y SLOG

| Capa | Nombre | Dónde reside | Misión |
| :--- | :--- | :--- | :--- |
| **Caché L1 (RAM)** | **ARC** (*Adaptive Replacement Cache*) | Memoria RAM del host | Algoritmo predictivo que retiene los datos leídos con mayor frecuencia y mayor recencia. Muy superior al LRU tradicional. |
| **Caché L2 (Lectura SSD)** | **L2ARC** | SSDs / NVMe secundarios | Extensión del ARC para lecturas que no entraron en RAM. |
| **Acelerador de Escritura Síncrona** | **SLOG** (*Separate ZIL*) | Dispositivo NVMe de bajísima latencia / PLP | Recibe las transacciones síncronas (`O_SYNC`, `fsync`, bases de datos) al vuelo para confirmar de inmediato a la aplicación sin esperar al disco rotativo. |

---

## 2. Preparación y Verificación del Entorno

Si estás en Ubuntu Server (VirtualBox, Bare-Metal o AWS EC2):

```bash
# 1. Instalar utilitarios de ZFS
sudo apt update -qq && sudo apt install -y zfsutils-linux

# 2. Cargar módulo de kernel
sudo modprobe zfs

# 3. Crear 4 discos simulados de 256 MiB
sudo mkdir -p /tmp/raidlab
cd /tmp/raidlab
for i in {1..4}; do
    sudo truncate -s 256M "disk_zfs${i}.img"
    sudo losetup -f --show "disk_zfs${i}.img"
done

# Confirmar
lsblk | grep disk_zfs
```

---

## 3. Creación del Storage Pool (zpool) con RAIDZ y Hot Spare

Vamos a crear el pool `tank_lab` configurando 3 discos en paridad simple distribuida (**RAIDZ1**) y asignando el cuarto disco como **Hot Spare** de reserva:

```bash
sudo zpool create -f tank_lab \
    raidz /dev/loop0 /dev/loop1 /dev/loop2 \
    spare /dev/loop3
```

### Inspección de la Topología con `zpool status`
```bash
sudo zpool status tank_lab
```

Salida esperada:
```
  pool: tank_lab
 state: ONLINE
  scan: none requested
config:

	NAME        STATE     READ WRITE CKSUM
	tank_lab    ONLINE       0     0     0
	  raidz1-0  ONLINE       0     0     0
	    loop0   ONLINE       0     0     0
	    loop1   ONLINE       0     0     0
	    loop2   ONLINE       0     0     0
	spares
	  loop3     AVAIL   
```

---

## 4. Creación de Dataset con Compresión Nativa LZ4

En ZFS no se crean particiones. Se crean **Datasets**, que heredan o definen sus propias propiedades de compresión, límites y cuotas:

```bash
# Crear dataset con compresión transparente LZ4 y sin actualización de tiempos de acceso
sudo zfs create -o compression=lz4 -o atime=off tank_lab/datos

# Escribir 30 MiB de datos de prueba
sudo dd if=/dev/urandom of=/tank_lab/datos/basedatos.db bs=1M count=30 status=none
sha256sum /tank_lab/datos/basedatos.db | tee /tmp/sha_zfs.txt

# Consultar propiedades de compresión y uso real
sudo zfs get used,referenced,compressratio tank_lab/datos
```

---

## 5. El Gran Test: Auto-Curación Matemática ante Bit-Rot

Vamos a demostrar la superioridad de ZFS frente a los errores silenciosos de medios físicos:

```bash
# 1. Asegurar buffers bajados a disco
sudo sync

# 2. Inyectar basura aleatoria directamente sobre los sectores físicos de /dev/loop0
sudo dd if=/dev/urandom of=/dev/loop0 bs=4k count=2 seek=8000 conv=notrunc status=none
sudo sync

# 3. Leer el archivo inmediatamente
sha256sum /tank_lab/datos/basedatos.db
cat /tmp/sha_zfs.txt
```

¡El hash es idéntico!

### ¿Cómo lo resolvió ZFS?
Cada bloque en ZFS tiene un hash **Fletcher4** almacenado en el puntero de su bloque padre. Al leer el bloque dañado en `/dev/loop0`:
1. El cálculo del hash falló.
2. ZFS no devolvió error ni datos corruptos; recalculó el bloque sano usando la paridad XOR de los discos restantes.
3. Entregó el dato sano a la aplicación.
4. Ejecutó una auto-reparación en segundo plano.

Para auditar y reparar proactivamente todos los bloques del pool:
```bash
sudo zpool scrub tank_lab
sudo zpool status tank_lab
```

En la salida de `zpool status` verás:
`loop0 ONLINE 0 0 1` -> **1 error de checksum detectado y reparado con 0 errores persistentes**.

---

## 6. Falla Catastrófica de Disco y Resilvering con Hot Spare

Simulamos la destrucción total del disco `/dev/loop1`:

```bash
# Sobrescribir con ceros simulando disco muerto
sudo dd if=/dev/zero of=/dev/loop1 bs=1M count=30 conv=notrunc status=none
sudo sync

# Forzar escaneo de integridad
sudo zpool scrub tank_lab
sudo zpool status tank_lab
```

El estado del pool cambia a **`DEGRADED`**:
```
state: DEGRADED
status: One or more devices could not be used because the label is missing or invalid.
action: Replace the device using 'zpool replace'.
```

Aun en estado degradado, los datos continúan 100% operativos:
```bash
sha256sum /tank_lab/datos/basedatos.db
```

### Reemplazo y Reconstrucción en Caliente (Resilver)
Le ordenamos al pool que reemplace el disco caído utilizando el hot spare (`/dev/loop3`):

```bash
sudo zpool replace tank_lab /dev/loop1 /dev/loop3
sudo zpool status tank_lab
```

Verás la sección `resilver in progress`:
```
  scan: resilver in progress since Sat Oct 24 10:15:20 2026
        15.2M scanned at 30.4M/s, 10.1M issued at 20.2M/s, 30.5M total
        10.1M resilvered, 33.11% done
```

A diferencia de un rebuild tradicional que recorre sectores vacíos durante horas, el **resilvering de ZFS solo recorre los bloques asignados a archivos reales**, minimizando drásticamente la ventana de vulnerabilidad.

Al terminar:
```bash
sudo zpool status tank_lab
```
El pool vuelve a figurar en estado `ONLINE`.

---

## 7. Script Automatizado

El laboratorio incluye el script completo con autodetección de entorno:

```bash
cd linux/administrator/raid
chmod +x demo_raid_zfs.sh

# Modo interactivo
sudo ./demo_raid_zfs.sh

# Modo automático
sudo ./demo_raid_zfs.sh --auto 3
```

---

## 8. Ejercicios Prácticos de Autoevaluación

1. **¿Por qué ZFS almacena los checksums en el puntero del bloque padre y no en el propio bloque de datos?**
2. **¿Qué diferencia fundamental existe entre un vdev de tipo `raidz1` y un vdev de tipo `raidz2`?**
3. **¿Cómo evita ZFS el problema del write-hole en comparación con mdadm?**
4. **Si se cae la energía en un servidor con ZFS que no tiene SLOG (ZIL dedicado), ¿se corrompe el pool de almacenamiento?**

<details><summary>Ver Respuestas Comentadas</summary>

1. Si el checksum estuviera en el mismo bloque, una falla catastrófica de escritura podría alterar tanto los datos como el checksum simultáneamente, haciendo que la corrupción parezca "válida". Al guardarlo en el puntero padre, ningún bloque puede mentir sobre su contenido.
2. `raidz1` almacena 1 bloque de paridad por franja y tolera la caída de **1 disco**. `raidz2` almacena 2 bloques de paridad distintos por franja (usando aritmética de Galois) y tolera la caída simultánea de **2 discos**, haciéndolo imprescindible para discos modernos de más de 4 TB.
3. Mediante su diseño Copy-on-Write transaccional con **franjas de ancho variable**: ZFS nunca actualiza datos in-situ. Cada escritura es un nuevo árbol atómico con su paridad recién calculada. Si se corta la corriente, el commit nunca se marca como finalizado y el pool regresa al uberblock previo consistente.
4. **No.** El pool principal nunca se corrompe gracias a Copy-on-Write. Las escrituras asíncronas no confirmadas simplemente se descartan (como en cualquier sistema de archivos), pero la integridad estructural del pool permanece 100% sana.
</details>

---

## 9. Qué sigue

➡️ **Lab 4.5 · [Proyecto Integrador en AWS](integrador_aws/trabajo_integrador_raid.md)** — Despliegue en la nube con Terraform, inyección de fallas en discos EBS reales, auto-recuperación y métricas de observabilidad con Node Exporter y Prometheus.
