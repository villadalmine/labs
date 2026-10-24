---
id: lab-3.7-raid-teoria-comparativa
title: 'RAID desde Cero: Niveles, Metadatos, Caché, Checksums y Comparativa mdadm vs
  LVM vs Btrfs vs ZFS'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.7'
sections:
- '3.7'
- '3'
category: storage
tags:
- storage
- raid
- raid0
- raid1
- raid5
- raid6
- raid10
- paridad
- xor
- striping
- mirroring
- metadatos
- write-hole
- bitmap
- cache
- checksum
- mdadm
- lvm
- btrfs
- zfs
tools:
- bash
- losetup
- mdadm
- lsblk
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-05-20'
  notes: Demo de paridad XOR en bash puro, sin root ni discos reales. Corre igual en
    Docker, VirtualBox o cualquier Linux.
environments:
- WSL2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Laboratorio teórico-práctico de entrada a la serie RAID. Explica qué es
  RAID, striping, mirroring y paridad XOR, los niveles 0/1/5/6/10, capacidad útil y
  tolerancia a fallos, metadatos (superbloque), bitmap y write-hole, cachés de escritura
  y checksums, y compara mdadm, LVM2 RAID, Btrfs y ZFS. Incluye un script en bash que
  demuestra la reconstrucción por XOR sin necesidad de discos ni root.
files:
  guide: raid/raid_teoria.md
  script: raid/demo_raid_teoria.sh
  terraform: null
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
prerequisites:
- lab-3.1-anatomia-filesystems
next_recommended_labs:
- lab-3.8-raid-mdadm
mcp_tools:
- linux-labs-tutor
- bash
---

# Lab 3.7 · RAID desde Cero: la Teoría que Necesitás Antes de Tocar un Disco

> **Serie RAID (de fácil a difícil):** **3.7 Teoría** → 3.8 mdadm → 3.9 LVM RAID → 3.10 Btrfs → 3.11 ZFS → 4.5 Integrador AWS con fallas, recuperación y métricas.

**Objetivo:** entender *qué es* un RAID, *qué problema resuelve y cuál no*, cómo se calculan capacidad y tolerancia en cada nivel, qué son los **metadatos**, el **bitmap**, la **caché** y los **checksums**, y cómo cada herramienta (mdadm, LVM, Btrfs, ZFS) implementa estas ideas.

**Requisitos:** ninguno. El script de esta guía no necesita root ni discos: simula todo en memoria con bash.

---

## 1. ¿Qué es RAID?

**RAID = Redundant Array of Independent Disks.** Combina varios discos en un único dispositivo lógico para lograr alguna de estas metas:

| Meta | Cómo se logra | Técnica |
| :--- | :--- | :--- |
| **Rendimiento** | Leer/escribir en varios discos a la vez | **Striping** (franjas) |
| **Disponibilidad** | Sobrevivir a la rotura de un disco | **Mirroring** (espejo) o **Paridad** |
| **Capacidad** | Juntar discos chicos en un volumen grande | Concatenación / striping |

> ⚠️ **RAID NO es un backup.** Protege contra la falla de *hardware*. No protege contra `rm -rf`, ransomware, corrupción lógica, un error humano ni un incendio. La regla 3-2-1 sigue vigente (ver [Borg](../borg/borg.md)).

### Las tres técnicas fundamentales

```
 STRIPING (RAID 0)         MIRRORING (RAID 1)         PARIDAD (RAID 5)
 datos A B C D E F         datos A B C                datos A B C D E F
 ┌──────┐ ┌──────┐         ┌──────┐ ┌──────┐          ┌──────┐ ┌──────┐ ┌──────┐
 │ A  C │ │ B  D │         │ A  B │ │ A  B │          │ A  B │ │ C  D │ │ P1 P2│
 │ E    │ │ F    │         │ C    │ │ C    │          │ ...  │ │      │ │      │
 └──────┘ └──────┘         └──────┘ └──────┘          └──────┘ └──────┘ └──────┘
 Disco1    Disco2          Disco1    Disco2           P = A xor C xor ... (rota entre discos)
```

---

## 2. Los niveles de RAID, uno por uno

Sea **N** = cantidad de discos y **S** = tamaño del disco más chico.

| Nivel | Mín. discos | Capacidad útil | Tolera fallas | Lectura | Escritura | Uso típico |
| :--- | :---: | :--- | :---: | :---: | :---: | :--- |
| **JBOD / linear** | 1 | N × S (suma) | 0 (pierde solo el disco) | = | = | Juntar discos sin redundancia |
| **RAID 0** | 2 | N × S | **0** (cualquier falla = pérdida total) | ⭐⭐⭐ | ⭐⭐⭐ | Scratch, caché, video temporal |
| **RAID 1** | 2 | S (N copias) | N-1 | ⭐⭐ | ⭐ | SO, bases chicas, `/boot` |
| **RAID 5** | 3 | (N-1) × S | **1** | ⭐⭐⭐ | ⭐⭐ (penalización por paridad) | Archivos, backups, NAS |
| **RAID 6** | 4 | (N-2) × S | **2** | ⭐⭐⭐ | ⭐ | Discos grandes (>4 TB), arreglos de muchos discos |
| **RAID 10** (1+0) | 4 | (N/2) × S | 1 por espejo (hasta N/2) | ⭐⭐⭐ | ⭐⭐⭐ | Bases de datos, virtualización |

### 2.1 RAID 0 — Striping puro
Los datos se parten en *chunks* (ej. 512 KiB) y se reparten en round-robin. Más discos = más velocidad, pero **la probabilidad de falla del conjunto es la suma** de las de cada disco. Un disco muerto = todo perdido.

### 2.2 RAID 1 — Espejo
Cada escritura va a **todos** los discos. Cualquier disco sobreviviente tiene la copia completa. Lecturas pueden repartirse (más rápidas). Costo: 50 % de capacidad con 2 discos.

### 2.3 RAID 5 — Paridad distribuida
Por cada franja de N-1 bloques de datos se guarda **1 bloque de paridad** = XOR de todos. La paridad **rota** entre discos (para no crear un cuello de botella en uno solo).

```
 Franja 1:  D1=A   D2=B   D3=P(A,B)        P = A ⊕ B
 Franja 2:  D1=C   D2=P   D3=D              P = C ⊕ D
 Franja 3:  D1=P   D2=E   D3=F              P = E ⊕ F
```

**¿Por qué XOR recupera datos?** Porque `A ⊕ B = P` implica `A = B ⊕ P`. Si muere el disco con `A`, se recalcula con los demás. Lo vas a ver con bytes reales en el script.

**Penalización de escritura (read-modify-write):** para cambiar un bloque hay que leer el dato viejo y la paridad vieja, calcular la nueva y escribir ambos → **4 I/O por 1 escritura lógica**.

### 2.4 RAID 6 — Doble paridad
Dos bloques de paridad distintos por franja (P = XOR y Q = código Reed-Solomon sobre un cuerpo de Galois). Sobrevive a **2 fallas simultáneas**. Es clave en discos grandes porque durante el *rebuild* de un disco de 16 TB (días) la probabilidad de que falle **otro** es real.

### 2.5 RAID 10 — Espejos + Striping
Se forman pares espejados (RAID 1) y se reparte (RAID 0) entre los pares. Se banca 1 falla **por par**. Reconstruir un espejo es solo *copiar* (sin cálculo de paridad) → rebuild rápido y poco riesgoso.

```
          ┌── RAID1 ──┐   ┌── RAID1 ──┐
 stripe → │ D1  ═  D2 │   │ D3  ═  D4 │     Mueren D1 y D3: OK
          └───────────┘   └───────────┘     Mueren D1 y D2: se pierde todo
```

### 2.6 Árbol de decisión rápido
```
¿Necesito que sobreviva a una falla?
 ├─ No  → RAID 0 (rendimiento) o disco simple
 └─ Sí  → ¿Cuántos discos tengo?
          ├─ 2 → RAID 1
          ├─ 3 → RAID 5  (o RAID 1 + spare)
          ├─ 4+ y escrituras intensas (DB) → RAID 10
          └─ 4+ y discos grandes / datos valiosos → RAID 6 (o RAIDZ2)
```

---

## 3. Conceptos que casi nadie explica (y son el 80 % de los problemas reales)

### 3.1 Metadatos (superbloque)
Para que el kernel sepa que `sdb` y `sdc` forman *juntos* un RAID, cada disco guarda una pequeña **cabecera de metadatos**: UUID del arreglo, nivel, tamaño de chunk, posición del disco, contador de eventos y estado.

| Herramienta | Dónde guarda los metadatos | Ver con |
| :--- | :--- | :--- |
| **mdadm** | Superbloque en cada disco (v1.2 = 4 KiB desde el inicio) | `mdadm --examine /dev/sdX` |
| **LVM2** | Cabecera PV + metadatos VG; cada RAID LV usa sub-LVs `_rmeta` (metadatos) y `_rimage` (datos) | `lvs -a -o+devices` |
| **Btrfs** | Superbloques + árbol de *chunks* y *devices* en el propio FS (perfil `-m raid1` para metadatos) | `btrfs filesystem usage` |
| **ZFS** | Etiquetas **L0-L3** (2 al inicio, 2 al final de cada disco) con el árbol de vdevs | `zdb -l /dev/sdX` |

Consecuencia práctica: **un disco con metadatos viejos o de otro arreglo puede causar desastres** → antes de reutilizar un disco: `mdadm --zero-superblock`, `wipefs -a`, `zpool labelclear`.

### 3.2 El *write hole* (agujero de escritura) y el bitmap
En RAID 5/6, actualizar dato **y** paridad no es atómico. Si se corta la luz entre ambas escrituras, queda una franja **inconsistente** que nadie detecta hasta que un disco falla: la reconstrucción devuelve basura.

Soluciones por herramienta:

| Mecanismo | Qué hace |
| :--- | :--- |
| **Write-intent bitmap** (mdadm, LVM) | Marca en un bitmap qué regiones se están escribiendo; tras un crash solo **resincroniza esas regiones** en vez del disco completo (resync de minutos en lugar de horas). |
| **Journal** (mdadm `--write-journal`, SSD) | Escribe primero en un diario rápido y luego en el arreglo → cierra el write-hole. |
| **Copy-on-Write transaccional** (ZFS RAIDZ) | Nunca sobrescribe: franjas de ancho variable y commit atómico → **no tiene write-hole**. |
| **Btrfs RAID5/6** | ⚠️ Aún con write-hole conocido: **no usar en producción** para RAID5/6. RAID1/10 sí son estables. |

> 📖 **Glosario Técnico:** Para profundizar en el funcionamiento interno del mapa de bits, la analogía de la enciclopedia de 10.000 páginas y la comparativa exhaustiva frente a ZFS y Btrfs, consulta la entrada [Write-Intent Bitmap en el Glosario](../GLOSARIO.md#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura).

### 3.3 Cachés
Hay varias capas y conviene no confundirlas:

| Caché | Dónde vive | Riesgo / uso |
| :--- | :--- | :--- |
| **Page cache** del kernel | RAM | Se pierde en un corte; `sync` la vacía |
| **Write-back del disco** | DRAM del disco | Disco miente en `flush` → corrupción si no hay protección |
| **BBU / cache de controladora** | Controladora RAID HW con batería | Acelera escrituras; sin batería = riesgo |
| **mdadm `stripe_cache_size`** | RAM (RAID 5/6) | Más caché = menos lecturas para parity; consume RAM |
| **LVM cache (dm-cache / `--type cache`)** | SSD rápido delante de HDD lento | Lectura y escritura (writeback/writethrough) |
| **ZFS ARC / L2ARC / SLOG** | RAM / SSD / SSD | ARC = lectura en RAM; L2ARC = lectura en SSD; **SLOG** = log de escrituras síncronas |
| **Btrfs** | Page cache + `bcache`/`dm-cache` externos | No trae caché SSD nativa |

> **Write-through** = confirma cuando llegó al disco (seguro, lento). **Write-back** = confirma al llegar a la caché (rápido, riesgo si falla la energía).

### 3.4 Checksums y *self-healing*
Un RAID clásico (mdadm/LVM) sabe **qué disco murió**, pero **no sabe qué disco miente**. Si un bloque se corrompe en silencio (*bit rot*), RAID 1 lee de un disco al azar y puede devolverte basura sin avisar.

Btrfs y ZFS guardan un **checksum** de cada bloque (en el puntero padre). Al leer:

```
 leer bloque → calcular checksum → ¿coincide?
      ├─ Sí → entregar dato
      └─ No → leer la otra copia/paridad → si es válida: ENTREGAR + REESCRIBIR la mala (self-healing)
```

Se verifica de forma proactiva con **scrub** (`btrfs scrub`, `zpool scrub`, `echo check > /sys/block/md0/md/sync_action`).

### 3.5 Hot spare, rebuild, resync, scrub
| Término | Significado |
| :--- | :--- |
| **Degraded** | El arreglo funciona, pero sin redundancia (con un disco menos) |
| **Hot spare** | Disco de repuesto que entra solo cuando otro falla |
| **Rebuild / recovery** | Reconstruir un disco nuevo a partir de los demás |
| **Resync** | Re-sincronizar espejos tras un apagado sucio |
| **Scrub / check** | Leer todo y verificar consistencia/checksums |
| **URE** | *Unrecoverable Read Error*: error de lectura durante el rebuild (por eso RAID 6/RAIDZ2 con discos grandes) |

---

## 4. Comparativa: ¿Quién implementa qué?

| Característica | **mdadm** | **LVM2 RAID** | **Btrfs** | **ZFS** |
| :--- | :--- | :--- | :--- | :--- |
| Capa | Bloque (`/dev/mdX`) | Bloque lógico (`dm-raid`, usa el código de md) | Filesystem | Filesystem + gestor de volúmenes |
| Niveles | 0,1,4,5,6,10, linear | raid0,1,4,5,6,10 | single, dup, raid0,1,1c3,1c4,10 (5/6 ⚠️) | mirror, raidz1/2/3, stripe |
| Checksums de datos | ❌ | ❌ | ✅ (crc32c, xxhash, sha256, blake2) | ✅ (fletcher4, sha256…) |
| Self-healing | ❌ | ❌ | ✅ (con perfil redundante) | ✅ |
| Snapshots | ❌ | ✅ (básicos, thin) | ✅ CoW instantáneos | ✅ CoW instantáneos |
| Redimensionar en caliente | Complejo (`--grow`) | ✅ Excelente (`lvextend -r`) | ✅ Instantáneo | Agregar vdevs; no quitar RAIDZ |
| Cambiar de nivel en vivo | ✅ (`--grow --level`) | ✅ (`lvconvert`) | ✅ (`balance -dconvert`) | ❌ (limitado) |
| Reemplazar disco | `--fail/--remove/--add` | `lvconvert --repair` | `btrfs replace` | `zpool replace` |
| Monitoreo nativo | `/proc/mdstat`, `mdadm --detail` | `lvs -a -o+health_status` | `btrfs device stats` | `zpool status`, `zpool events` |
| Incluido en kernel Linux | ✅ | ✅ | ✅ | ❌ (módulo OpenZFS, licencia CDDL) |
| Funciona en WSL2 (kernel por defecto) | ✅* | ✅* | ✅* | ❌ (usar VM/EC2) |
| Dificultad | ⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |

\* Según el kernel de WSL2. Ver "Compatibilidad" abajo.

### Cuándo elegir cada uno
* **mdadm:** lo más simple, universal, base de todo lo demás. Ideal para aprender.
* **LVM RAID:** cuando ya usás LVM y querés RAID + snapshots + resize en la misma herramienta.
* **Btrfs:** cuando querés checksums y snapshots integrados en el kernel mainline, en RAID 1/10.
* **ZFS:** cuando los datos son críticos y querés lo más maduro (RAIDZ sin write-hole, caché ARC/L2ARC/SLOG, send/receive).

---

## 5. Compatibilidad del entorno (WSL2, Docker, VirtualBox)

| Entorno | mdadm | LVM RAID | Btrfs | ZFS | Notas |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Ubuntu en WSL2** (kernel MS reciente) | ✅ | ✅ | ✅ | ❌ | Requiere `sudo modprobe md_mod raid1 raid456 dm_raid btrfs`. Los "discos" son **loop devices** sobre archivos sparse. |
| **Docker Desktop (WSL2)** | ✅ | ✅ | ✅ | ❌ | Usar `docker run --privileged` (comparte el kernel de WSL2). |
| **VirtualBox / VM Ubuntu** | ✅ | ✅ | ✅ | ✅ | Kernel Ubuntu completo; se pueden agregar **discos virtuales reales** (VDI) y simular el reemplazo en caliente. |
| **AWS EC2 (lab integrador)** | ✅ | ✅ | ✅ | ✅ | Discos EBS reales, métricas y fallas con Terraform. |

Verificación rápida de tu entorno:
```bash
uname -r
sudo modprobe md_mod raid1 raid456 dm_raid btrfs 2>&1 | sed 's/^/modprobe: /'
ls /proc/mdstat; grep -w btrfs /proc/filesystems; modinfo zfs 2>/dev/null | head -1 || echo "sin ZFS"
```

> **¿No tengo `/proc/mdstat`?** Ejecutá `sudo modprobe md_mod`. Si el módulo no existe en tu kernel, usá una VM de VirtualBox con Ubuntu Server.

### Docker (opcional)
```bash
docker run --rm -it --privileged -v /dev:/dev ubuntu:24.04 bash -c \
  "apt update -qq && apt install -y -qq mdadm lvm2 btrfs-progs kmod util-linux >/dev/null && bash"
```

### VirtualBox con discos reales
```powershell
# Desde Windows (PowerShell): crear y adjuntar 4 discos de 1 GB a la VM "ubuntu-raid"
1..4 | ForEach-Object { VBoxManage createmedium disk --filename "raid$_.vdi" --size 1024 }
1..4 | ForEach-Object { VBoxManage storageattach ubuntu-raid --storagectl "SATA" --port ($_+1) --device 0 --type hdd --medium "raid$_.vdi" }
```

---

## 6. Laboratorio práctico: paridad XOR con bytes reales

Ejecutá el script (no necesita root):

```bash
cd linux/administrator/raid
./demo_raid_teoria.sh            # interactivo
./demo_raid_teoria.sh --auto 2   # automático
```

El script te lleva por:
1. **Striping:** cómo se reparte un mensaje en 2 discos (RAID 0) y qué pasa si uno muere.
2. **Mirroring:** dos copias idénticas (RAID 1) y recuperación.
3. **Paridad:** calcula `P = A ⊕ B ⊕ C` con bytes reales, "rompe" un disco y lo **reconstruye con XOR**.
4. **Calculadora de capacidad** por nivel para N discos de S GB.
5. **Bit rot:** por qué RAID sin checksum no detecta un bit alterado y qué hace distinto un FS con checksums.

### Ejercicios de comprensión
1. Tenés 6 discos de 4 TB. Calculá capacidad útil y fallas toleradas en RAID 5, 6 y 10.
2. ¿Por qué RAID 5 con 8 discos de 16 TB es considerado riesgoso? (pista: URE + tiempo de rebuild)
3. Un corte de luz ocurre mientras se escribe en un RAID 5 de mdadm sin bitmap. ¿Qué dos problemas aparecen?
4. ¿Por qué RAID 1 de mdadm no puede decir cuál de los dos espejos tiene el dato correcto, pero ZFS sí?
5. Un amigo dice "tengo RAID 1, no necesito backup". Respondé con 3 escenarios donde pierde los datos.

<details><summary>Respuestas</summary>

1. RAID 5: 5×4 = **20 TB**, tolera 1. RAID 6: 4×4 = **16 TB**, tolera 2. RAID 10: 3×4 = **12 TB**, tolera 1 por par.
2. Reconstruir 16 TB tarda días con carga; durante ese tiempo se lee *todo* el resto y un solo URE o segunda falla destruye el arreglo.
3. (a) Franjas con paridad inconsistente (write-hole) y (b) un resync completo largo para volver a un estado conocido. El bitmap acota (b); el journal cierra (a).
4. mdadm no guarda checksums por bloque: ambas copias "parecen válidas". ZFS compara el checksum del puntero padre con cada copia.
5. Borrado accidental, ransomware, corrupción lógica del FS / falla del controlador / incendio o robo.
</details>

---

## 7. Qué sigue

➡️ **Lab 3.8 · [RAID con mdadm](raid_mdadm.md)** — armamos RAID 0/1/5/6/10 con loop devices, rompemos un disco y lo reconstruimos mirando `/proc/mdstat`.
