# 📚 Glosario Técnico de Almacenamiento, Sistemas de Archivos & Resiliencia en Linux

Este glosario funciona como un **compendio de referencia e índice conceptual cruzado** para los laboratorios de administración de sistemas Linux. Cada término incluye su definición técnica formal, analogías pedagógicas, funcionamiento interno en cada subsistema del kernel y enlaces directos a las prácticas donde se utiliza.

---

## 🧭 Índice Temático y Alfabético

| Término | Tecnologías Relacionadas | Laboratorios de Aplicación |
| :--- | :--- | :--- |
| [**Write-Intent Bitmap**](#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura) | `mdadm`, `lvmraid` (`_rmeta`), ZFS, Btrfs | [Lab 3.7](raid/raid_teoria.md), [Lab 3.8](raid/raid_mdadm.md), [Lab 3.9](raid/raid_lvm.md), [Lab 4.5](raid/integrador_aws/trabajo_integrador_raid.md) |
| [**Write-Hole (Agujero de Escritura)**](#write-hole-agujero-de-escritura) | RAID 4/5/6, `mdadm`, LVM, Btrfs | [Lab 3.7](raid/raid_teoria.md), [Lab 3.11](raid/raid_zfs.md) |
| [**Copy-on-Write (CoW)**](#copy-on-write-cow-copia-en-escritura) | ZFS, Btrfs, LVM Snapshots | [Lab 3.1](filesystems/anatomia_ext4_xfs_btrfs.md), [Lab 3.10](raid/raid_btrfs.md), [Lab 3.11](raid/raid_zfs.md), [Integrador Btrfs](trabajo_integrador_btrfs/trabajo_integrador_btrfs.md) |
| [**Dirty Time Logs (DTL) / TXG**](#dirty-time-logs-dtl--transaction-groups-txg) | OpenZFS | [Lab 3.11](raid/raid_zfs.md), [Integrador ZFS](trabajo_integrador_zfs/trabajo_integrador_zfs.md) |
| [**ZIL (ZFS Intent Log) & SLOG**](#zil-zfs-intent-log--slog-separate-intent-log) | OpenZFS, NVMe | [Lab 3.11](raid/raid_zfs.md) |
| [**Hot Spare**](#hot-spare-disco-de-reserva-en-caliente) | `mdadm`, LVM, ZFS | [Lab 3.8](raid/raid_mdadm.md), [Lab 4.5](raid/integrador_aws/trabajo_integrador_raid.md) |
| [**Scrubbing y Resilvering**](#scrubbing-y-resilvering) | `mdadm`, Btrfs, ZFS | [Lab 3.8](raid/raid_mdadm.md), [Lab 3.10](raid/raid_btrfs.md), [Lab 3.11](raid/raid_zfs.md), [Lab 4.5](raid/integrador_aws/trabajo_integrador_raid.md) |

---

## Conceptos Técnicos en Profundidad

---

### Write-Intent Bitmap (Mapa de Bits de Intención de Escritura)

Un **write-intent bitmap** (mapa de bits de intención de escritura) es un mecanismo de seguimiento que registra qué regiones de un disco están a punto de ser modificadas antes de que ocurra la escritura real. 

Su propósito principal es **evitar la reconstrucción completa de un arreglo de discos tras un corte de energía o una desconexión temporal**: al reiniciar, el sistema consulta el mapa de bits y sincroniza únicamente los bloques que quedaron a medias (*"sucios"*).

Para explicarlo de forma clara, la distinción fundamental está entre los **gestores de bloques tradicionales (RAID / LVM)**, que sobrescriben datos en el mismo lugar y necesitan este mapa como salvavidas, y los **sistemas de archivos Copy-on-Write (ZFS / Btrfs)**, que por su diseño arquitectónico no lo necesitan.

---

#### 💡 La Analogía para Explicarlo Rápido

Imagina que estás editando una enciclopedia impresa de 10,000 páginas y tienes un clon exacto de respaldo en otra habitación:

* **Sin bitmap:** Si se corta la luz mientras editas, al volver no sabes en qué página estabas trabajando. Tienes que comparar las 10,000 páginas una por una para asegurarte de que ambos libros sean idénticos (horas de escaneo inútil).
* **Con Write-Intent Bitmap (RAID/LVM):** Antes de tocar una página, anotas en un post-it: *"Voy a modificar el Capítulo 4"*. Escribes el cambio y luego borras el post-it. Si se corta la luz en medio, al volver solo miras el post-it y revisas únicamente el Capítulo 4. Sincronizar toma segundos en lugar de horas.
* **Enfoque Copy-on-Write (ZFS/Btrfs):** Nunca borras ni escribes encima de una página existente. Escribes la versión nueva en una hoja en blanco y, solo cuando terminas, actualizas el índice general. Si se va la luz a mitad de camino, el índice sigue apuntando a la hoja vieja intacta; no hay nada desincronizado que buscar.

---

#### ⚙️ Cómo Funciona en Cada Tecnología

##### 1. RAID por software (`mdadm`)

Es el caso de uso clásico. En un RAID 1, 5, 6 o 10, el arreglo se divide en regiones o *chunks* (por ejemplo, de 64 MB). Cada región está representada por un solo **bit** en el bitmap (almacenado en una zona interna del disco con `--bitmap=internal` o en un archivo externo):

```
                   ESTRUCTURA DEL DISCO EN MDADM
┌─────────────────────────────────┬─────────────────────────────────┐
│     Superbloque v1.2 (4 KiB)    │    Write-Intent Bitmap Interno  │
│  [UUID, Nivel, Eventos, Chunks] │     [ 0 | 0 | 1 | 0 | 1 | 0 ]   │
└─────────────────────────────────┴─────────────────────────────────┘
                                           │         │
                   Region 2 (Limpia) ──────┘         │
                   Region 3 (Escritura en curso) ────┘ (Bit = 1)
```

1. **Antes de escribir:** El bit de esa región pasa de `0` a `1` (indicando "escritura en curso").
2. **Durante la escritura:** Los datos y la paridad se escriben en todos los discos del RAID.
3. **Al finalizar:** Cuando el sistema confirma que todos los discos escribieron el dato exitosamente, el bit vuelve a `0` (normalmente con un ligero retraso para agrupar operaciones contiguas y evitar desgaste del disco).

* **El beneficio:** Si un disco se desconecta por un cable flojo durante 5 minutos o el servidor sufre un apagón, al volver `mdadm` lee los bits en `1` y solo resincroniza esos fragmentos específicos.
* **El costo:** Añade una pequeña penalización de rendimiento en escrituras aleatorias intensivas porque debe actualizar el bitmap antes de volcar el dato al disco.

> 🔬 **Práctica en laboratorio:**
> - Creación con bitmap: `mdadm --create /dev/md0 --bitmap=internal ...` ([Lab 3.8](raid/raid_mdadm.md#4-laboratorio-principal-raid-5--hot-spare--bitmap))
> - Inspección forense: `mdadm --examine-bitmap /dev/sdX` ([Lab 3.8](raid/raid_mdadm.md#5-inspección-forense-superbloque-y-bitmap))

##### 2. LVM (Logical Volume Manager / `lvmraid`)

En LVM (`lvm.conf`), cuando creas volúmenes espejados o con paridad (como `raid1`, `raid5`, `raid6`), LVM utiliza por debajo el mismo motor del kernel que `mdadm` (el driver `md-mod`).

En la terminología de LVM, este write-intent bitmap se gestiona de forma transparente a través de los **Sub-LVs de metadatos** (`_rmeta`):

```
      Logical Volume RAID5: lv_prod [10 GB]
     ┌──────────────────────┬──────────────────────┬──────────────────────┐
     ▼                      ▼                      ▼
  Disco PV 1             Disco PV 2             Disco PV 3
┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐
│  lv_prod_rmeta_0   │ │  lv_prod_rmeta_1   │ │  lv_prod_rmeta_2   │  <-- Superbloque MD +
│  (1 PE = 4 MiB)    │ │  (1 PE = 4 MiB)    │ │  (1 PE = 4 MiB)    │      Write-Intent Bitmap
├────────────────────┤ ├────────────────────┤ ├────────────────────┤
│  lv_prod_rimage_0  │ │  lv_prod_rimage_1  │ │  lv_prod_rimage_2  │  <-- Bloques de datos y
│  (Franja de datos) │ │  (Franja de datos) │ │  (Franja Paridad)  │      paridad XOR
└────────────────────┘ └────────────────────┘ └────────────────────┘
```

Cumple exactamente la misma función: llevar el registro de qué regiones (*regions*) están siendo modificadas para evitar resincronizaciones completas tras un cierre inesperado, o para saber qué bloques cambiaron mientras un disco estuvo temporalmente ausente.

> 🔬 **Práctica en laboratorio:**
> - Arquitectura de Sub-LVs: `lvs -a -o+devices` ([Lab 3.9](raid/raid_lvm.md#1-arquitectura-cómo-combina-lvm2-su-propia-metáfora-con-md-del-kernel))

##### 3. ZFS y Btrfs (Por qué es diferente aquí)

Si alguien pregunta cómo configurar un *write-intent bitmap* en ZFS o Btrfs, la respuesta técnica es que **no usan write-intent bitmaps tradicionales** porque son sistemas **Copy-on-Write (CoW)** transaccionales que integran el gestor de volúmenes y el sistema de archivos en una sola capa.

* **Por qué no sufren el problema de raíz:** En RAID clásico y LVM, si un bloque se sobrescribe a medias durante un apagón, los discos quedan con datos distintos en la misma posición física (fenómeno conocido como [*write hole*](#write-hole-agujero-de-escritura)). En ZFS y Btrfs nunca se sobrescribe un bloque activo; los datos nuevos se escriben en espacio libre y el árbol de metadatos se actualiza de forma atómica al final. Si hay un apagón, la transacción incompleta simplemente se descarta y el sistema sigue siendo 100% consistente.
* **Qué pasa si un disco se desconecta temporalmente:** Como ZFS y Btrfs conocen la estructura del árbol de archivos y cada bloque tiene un **número de transacción** (llamado `TXG` en ZFS o `generation` en Btrfs) además de sumas de verificación (*checksums*), si un disco se desconecta unos minutos y vuelve, el sistema no necesita un bitmap de regiones brutas: simplemente recorre el árbol de metadatos buscando qué transacciones son más recientes que la última registrada en ese disco y copia solo esos bloques exactos (en ZFS esto se conoce como [*DTL - Dirty Time Logs*](#dirty-time-logs-dtl--transaction-groups-txg)).
* **No confundir con el ZIL (ZFS Intent Log):** A veces se confunde el *write-intent bitmap* con el **ZIL** de ZFS (o el *log tree* de Btrfs). Aunque ambos tienen la palabra *"intent"*, el ZIL no es un mapa de bits de regiones sucias, sino un diario (*journal*) donde se guardan los datos completos de las escrituras síncronas para confirmarlas rápido al cliente antes de volcarlas definitivamente al pool en el siguiente commit de TXG.

---

#### 📊 Tabla Comparativa Resumen

| Tecnología | ¿Usa Write-Intent Bitmap? | Mecanismo ante un apagón o desconexión breve | Nivel en el que opera |
| :--- | :---: | :--- | :--- |
| **RAID (`mdadm`)** | **Sí** (Interno o externo) | Revisa los bits en `1` y copia solo esos segmentos de disco (*chunks*) de un disco a otro. | Bloques ciegos (no sabe si hay archivos o espacio vacío). |
| **LVM (`lvmraid`)** | **Sí** (En volúmenes `_rmeta`) | Igual que `mdadm`: sincroniza únicamente las regiones marcadas como sucias en el bitmap. | Bloques lógicos (*Logical Extents*). |
| **ZFS** | **No** (Usa CoW + DTL) | Transacciones atómicas (CoW) evitan corrupción por apagón. Si un disco vuelve tras caer, usa *Dirty Time Logs* (TXGs) para enviar solo bloques nuevos. | Sistema de archivos y bloques integrados (con *checksums* de 256 bits). |
| **Btrfs** | **No** (Usa CoW + Generation Trees) | Transacciones atómicas (CoW). Sincroniza basándose en el número de generación de los árboles de metadatos y valida con *checksums*. | Sistema de archivos y bloques integrados (con *checksums*). |

---

### Write-Hole (Agujero de Escritura)

El **write-hole** es un defecto estructural inherente a los arreglos RAID 4, 5 y 6 tradicionales basados en paridad que operan a nivel de bloques independientes. Ocurre cuando se interrumpe la alimentación eléctrica en el microsegundo exacto entre la escritura del nuevo bloque de datos y la escritura del bloque de paridad correspondiente. 

Como el sistema tradicional no tiene transacciones atómicas, la paridad calculada deja de coincidir matemáticamente con los datos de la franja (*stripe*). El desastre se manifiesta silenciosamente cuando más adelante un disco falla: al intentar reconstruir el disco ausente aplicando la fórmula XOR sobre los discos restantes, los datos calculados resultan corrompidos.

* **Mitigaciones tradicionales:** [Write-Intent Bitmap](#write-intent-bitmap-mapa-de-bits-de-intención-de-escritura) (acota el tiempo de resincronización), diarios en SSD rápido (`mdadm --write-journal`), o baterías BBU en controladoras hardware.
* **Eliminación arquitectónica:** ZFS elimina por diseño el write-hole usando *RAIDZ* con bandas de ancho variable y asignación [Copy-on-Write](#copy-on-write-cow-copia-en-escritura).
* 📖 [Ver explicación en Lab 3.7: RAID Teoría (Sección 3.2)](raid/raid_teoria.md#32-el-write-hole-agujero-de-escritura-y-el-bitmap).

---

### Copy-on-Write (CoW / Copia en Escritura)

Estrategia de gestión de almacenamiento donde los bloques de datos existentes nunca son sobrescritos *in-place*. Cuando un bloque se modifica:
1. El sistema asigna un bloque libre nuevo en otra parte física del disco.
2. Escribe los nuevos datos en ese nuevo bloque.
3. Actualiza el puntero en el árbol de metadatos para que apunte a la nueva ubicación mediante un commit transaccional atómico.
4. Si la operación se interrumpe antes de la confirmación final, el árbol sigue apuntando al bloque anterior, garantizando cero corrupción.

Habilita snapshots instantáneos $O(1)$, clones de cero copias (*reflinks*) y elimina la necesidad de bitmaps de rescate.
* 📖 [Ver implementación en Lab 3.10: Btrfs](raid/raid_btrfs.md) y [Lab 3.11: OpenZFS](raid/raid_zfs.md).

---

### Dirty Time Logs (DTL) / Transaction Groups (TXG)

Mecanismo interno de **OpenZFS** para el rastreo de desincronizaciones entre miembros de un vdev espejo o RAIDZ. En lugar de un bitmap de bloques físicos, ZFS asigna un identificador secuencial monótono a cada grupo de transacciones (**TXG**). 

Si un disco se desconecta temporalmente, ZFS registra en los *Dirty Time Logs* el rango de TXGs que ese disco se perdió. Cuando el disco se reconecta, ZFS examina únicamente los bloques cuyo TXG pertenezca a ese intervalo y realiza un *resilvering dirigido*, sin tener que escanear todo el pool.
* 📖 [Ver arquitectura OpenZFS en Lab 3.11](raid/raid_zfs.md).

---

### ZIL (ZFS Intent Log) & SLOG (Separate Intent Log)

Área de almacenamiento temporal transaccional utilizada exclusivamente por OpenZFS para garantizar la persistencia de **escrituras síncronas** (`O_SYNC`, bases de datos, NFS) sin esperar el intervalo de commit regular del pool (que típicamente ocurre cada 5 segundos por TXG).

* **Diferencia con el Bitmap:** No marca regiones sucias para sincronizar más tarde; almacena la carga útil (*payload*) completa del dato de forma transaccional.
* **SLOG:** Cuando el ZIL se coloca en un dispositivo de almacenamiento ultrarrápido dedicado (como un disco NVMe o Intel Optane), se denomina SLOG (*Separate Log*).
* 📖 [Ver sección SLOG/ZIL en Lab 3.11](raid/raid_zfs.md).

---

### Hot Spare (Disco de Reserva en Caliente)

Unidad de almacenamiento conectada físicamente al sistema e integrada en la configuración del arreglo RAID que permanece en estado de reposo (*idle* o *standby*). 

Si uno de los discos activos experimenta un fallo irrecuperable o es expulsado por errores de I/O, el subsistema (kernel `md` o demonio `mdmonitor`/ZFS) detecta la anomalía e **inicia de inmediato la reconstrucción sobre el disco de reserva de manera 100% desatendida**, minimizando la ventana de vulnerabilidad del arreglo.
* 📖 [Ver configuración en Lab 3.8: mdadm](raid/raid_mdadm.md#4-laboratorio-principal-raid-5--hot-spare--bitmap) y [Lab 4.5: Integrador AWS](raid/integrador_aws/trabajo_integrador_raid.md#fase-1-creación-del-arreglo-y-servicio-web).

---

### Scrubbing y Resilvering

* **Scrub (Auditoría de Paridad):** Proceso periódico en segundo plano que lee exhaustivamente todos los bloques del arreglo para verificar que los datos coincidan con su paridad o checksum. Si encuentra inconsistencias, las repara automáticamente tomando los bloques válidos del resto de discos.
* **Resilvering / Rebuild (Reconstrucción):** Proceso de regeneración y copia de datos hacia un disco nuevo que reemplaza a uno averiado. En RAID tradicional (`mdadm`) se reconstruye el espacio completo del dispositivo; en ZFS/Btrfs solo se reconstruyen los bloques asignados y referenciados.
* 📖 [Ver procedimientos de Scrub en Lab 3.8](raid/raid_mdadm.md#8-scrub-auditoría-de-paridad-en-segundo-plano), [Lab 3.10](raid/raid_btrfs.md) y [Lab 3.11](raid/raid_zfs.md).
