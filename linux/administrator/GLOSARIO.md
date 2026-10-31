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
| [**Hard Link vs Soft Link (Enlaces en Filesystems)**](#hard-link-vs-soft-link-enlaces-en-filesystems) | VFS, ext4, XFS, Btrfs, `ln`, `find`, `rsync` | [Lab 3.12](filesystems/enlaces_hard_soft_links.md) |

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

---

### Hard Link vs Soft Link (Enlaces en Filesystems)

La arquitectura de archivos en sistemas Unix/Linux implementa una separación estricta entre el **nombre visible** del archivo (`dentry` o entrada de directorio) y la **estructura de almacenamiento real** (`inodo` y bloques de datos).

* **Hard Link (Enlace Duro):** Es una segunda entrada de directorio (`dentry`) que apunta de manera directa y equivalente al **mismo número de inodo** dentro del mismo sistema de archivos. No duplica datos, no consume espacio en disco y está gobernado por el contador `nlink`. Al borrar un archivo con `rm`, el kernel únicamente llama a `unlink()`; los bloques de datos físicos solo se devuelven al bitmap libre cuando `nlink == 0` y ningún proceso en ejecución mantiene el descriptor de archivo abierto.
  - *Restricciones:* No puede cruzar fronteras de particiones (`EXDEV`) ni apuntar a directorios para prevenir bucles cíclicos en el grafo del VFS.
* **Soft Link (Enlace Simbólico o Symlink):** Es un archivo independiente de tipo `l` (`S_IFLNK`) con su propio inodo, cuyo contenido de datos es la cadena de texto con la ruta hacia el destino.
  - *Ventajas y Riesgos:* Puede cruzar cualquier sistema de archivos, montajes remotos y enlazar carpetas completas. Si el destino se borra o renombra, el symlink queda en estado **roto (*dangling*)**, retornando el error `ENOENT`.
* 💡 **Casos de Producción:** Despliegues **Zero-Downtime** mediante switches atómicos con `ln -sfn`, versionado de bibliotecas dinámicas (`.so` SONAME), y deduplicación masiva en respaldos instantáneos con `rsync --link-dest`.
* 📖 [Ver guía teórica completa y laboratorio práctico en Lab 3.12](filesystems/enlaces_hard_soft_links.md).

---

### LUKS2 & Argon2id (Cifrado de Bloques)

* **LUKS2 (Linux Unified Key Setup v2):** Estándar de facto moderno para el cifrado de datos en reposo a nivel de bloques (*Full Disk Encryption* o FDE) en el kernel de Linux a través del subsistema `dm-crypt`. A diferencia de LUKS1, incorpora una cabecera basada en JSON extensible, cabeceras redundantes primarias y secundarias con detección de auto-curación (*auto-repair*), y soporte para hasta 32 ranuras de claves (*keyslots*).
* **Argon2id (KDF):** Función de derivación de claves por defecto en LUKS2, diseñada específicamente para neutralizar ataques masivos de fuerza bruta con clústeres de GPUs y ASICs al ser intensiva en memoria RAM (*memory-hard*).
* 📖 [Ver guía de cifrado LUKS2 en Lab 3.3](luks/luks.md) y [Comparativa de Arquitecturas de Cifrado](cifrado/cifrado_arquitecturas_comparativa.md).

---

### Keyslots y Desbloqueo Moderno (TPM 2.0 & Clevis/Tang)

* **Keyslots (Ranuras de Claves):** Esquema criptográfico de dos niveles donde una clave maestra aleatoria de 256 bits (que cifra los bloques físicos) se encuentra cifrada de forma independiente en múltiples ranuras. Esto permite revocar o rotar contraseñas de administradores mediante `luksKillSlot` sin necesidad de recifrar los datos del disco.
* **TPM 2.0 (`systemd-cryptenroll`):** Desbloqueo automático del volumen cifrado durante el arranque mediante el chip de seguridad físico de la placa base, sellado a los registros de configuración de plataforma (PCR 0, 2, 7 para Secure Boot). Si el firmware o el kernel son alterados, el TPM se niega a liberar la clave.
* **NBDE (Network-Bound Disk Encryption - Clevis/Tang):** Arquitectura para centros de datos donde un oráculo en red (servidor Tang) suministra la clave de desbloqueo al cliente (Clevis) a través de la LAN corporativa. Si el servidor o disco físico es retirado de las instalaciones, el volumen no puede desbloquearse.
* 📖 [Ver sección de automatización en Lab 3.3](luks/luks.md#5-el-escenario-moderno-automatización-con-tpm-20-y-clevistang).

---

### GnuPG (GPG) y Firmas de Repositorios / Backups Asimétricos

* **Criptografía Asimétrica:** Paradigma criptográfico basado en un par de claves: una **clave pública** (ampliamente distribuida) y una **clave privada** (mantenida bajo estricta custodia).
* **Subclaves OpenPGP:** Estructura jerárquica donde la clave primaria posee la capacidad de certificación `[C]`, delegando las operaciones diarias en subclaves operativas de firma `[S]` y de cifrado `[E]`.
* **APT `[signed-by=...]`:** Estándar moderno de repositorios en Debian/Ubuntu que confina la clave binaria desarmada (`gpg --dearmor`) bajo `/etc/apt/keyrings/`, reemplazando el inseguro e histórico `apt-key add` global.
* **Backups Asimétricos:** Técnica de seguridad donde los servidores de base de datos o web solo almacenan la **clave pública** para cifrar respaldos automáticos en cron. Si el servidor es atacado, el adversario no puede descifrar los backups históricos porque la clave privada no existe en esa máquina.
* 📖 [Ver laboratorio completo de GPG y backups en Lab 3.4b](gpg/gpg_firmas_repositorios_backups.md).

---

### Estrategias de Backup, Resiliencia y Deduplicación

* **RPO (Recovery Point Objective):** Métrica de negocio que cuantifica la cantidad máxima de datos que la organización tolera perder ante un desastre, expresada en tiempo (ej: 1 hora de transacciones).
* **RTO (Recovery Time Objective):** Métrica que define el tiempo límite permitido desde que ocurre la catástrofe hasta que el servicio vuelve a estar 100% operativo (tiempo de restauración).
* **Regla 3-2-1:** Estándar de oro de respaldos: mantener **3** copias de los datos, en **2** medios o tecnologías diferentes, con **1** copia fuera de sitio (*offsite* o en la nube).
* **Backup Completo (Full):** Respaldo de la totalidad de los archivos o bloques seleccionados en un instante dado. RTO mínimo (extracción directa), pero máximo consumo de espacio y tiempo de generación.
* **Backup Incremental:** Respaldo exclusivo de los datos creados o modificados desde el **último backup** (sea Full o Incremental). Ahorro masivo de espacio, pero exige restaurar el Full inicial y la cadena completa de incrementales.
* **Backup Diferencial:** Respaldo acumulativo de todas las modificaciones producidas desde el **último backup completo**. La restauración solo requiere el Full inicial y el último diferencial.
* **CDP (Continuous Data Protection):** Captura continua de cambios en tiempo real o micro-intervalos (segundos/minutos) mediante eventos del kernel (`inotify`) o replicación de logs de transacciones (WAL/binlog). RPO cercano a cero.
* **Deduplicación por Hard Links (`rsync --link-dest`):** Técnica clásica en sistemas de archivos POSIX donde `rsync` compara con el backup previo y crea enlaces duros (inodos compartidos con `nlink > 1`) para los archivos idénticos. Cada día aparenta ser un árbol completo pero solo consume los bytes modificados.
* **Deltas Inversos (`rdiff-backup`):** Paradigma donde el directorio de destino es un espejo exacto del estado más reciente (archivos planos directamente legibles sin descompresión), mientras los deltas matemáticos para retroceder en el tiempo se almacenan hacia atrás en `rdiff-backup-data/`.
* **Zero-Trust Cloud Backup (`duplicity`):** Respaldo incremental basado en `librsync` pero con cifrado asimétrico GnuPG obligatorio antes de abandonar el host local. Protege los datos y nombres de archivos contra operadores de almacenamiento remoto (SFTP, S3).
* **Snapshots Copy-on-Write (LVM CoW):** Congelamiento atómico de metadatos en microsegundos a nivel de bloques. Permite respaldar bases de datos y sistemas de archivos activos en producción de forma 100% consistente sin detener el servicio ni incurrir en escrituras corruptas en caliente.
* 📖 [Ver guía comparativa completa en Lab 3.5.0](backup/backup_arquitecturas_comparativa.md).


---

### Monitoreo, Telemetría y Observabilidad

* **Modelo PULL vs PUSH:** En el modelo **PULL** (Prometheus), el servidor central inicia peticiones periódicas HTTP GET hacia `/metrics` de los nodos, garantizando detección instantánea de caídas y control de tráfico de red. En el modelo **PUSH** (Datadog, Telegraf, StatsD), los clientes transmiten proactivamente sus métricas, ideal para Serverless y redes con NAT cerrado.
* **TSDB (Time Series Database):** Base de datos optimizada exclusivamente para almacenar secuencias de pares `(timestamp, float64)` indexadas por etiquetas multidimensionales clave-valor.
* **PromQL (Prometheus Query Language):** Lenguaje funcional para filtrar, agregar y calcular tasas de cambio instantáneas (`rate()`, `increase()`, `sum()`) sobre series temporales.
* **Textfile Collector:** Módulo de Node Exporter que lee archivos con extensión `.prom` generados atómicamente por scripts locales en `/var/lib/node_exporter/textfile_collector/` y los expone en `/metrics` junto a la telemetría del kernel.
* **OpenMetrics:** Estándar neutral de la Cloud Native Computing Foundation (CNCF) que formaliza la sintaxis de texto plano de métricas de Prometheus (`# HELP`, `# TYPE`, etiquetas y marcas de tiempo).
* **Distributed Tracing (Trazas Distribuidas):** Seguimiento del ciclo de vida completo de una petición a través de múltiples microservicios mediante identificadores de traza (*TraceID*) y bloques de tiempo (*Spans*), implementado con OpenTelemetry o Jaeger.
* **Monitoreo Sintético (Sondas / Probes):** Verificación activa de disponibilidad desde el exterior simulando el comportamiento de un usuario final (ej: verificar que una URL devuelva HTTP 200 y que su certificado TLS sea válido con Blackbox Exporter).
* 📖 [Ver taller integrador con telemetría en Lab 3.16](monitoreo/taller_integrador_web_lvm_monitoreo.md).


---

### AI SRE, Agentes Autónomos y Remediación (Self-Healing)

* **AI SRE (Site Reliability Engineering con IA):** Integración de modelos de inteligencia artificial y agentes cognitivos con los sistemas de observabilidad (Prometheus, Grafana, OpenTelemetry) para realizar detección de anomalías, investigación causal de fallas y autorremediación sin intervención humana en incidentes estándar.
* **Patrón ReAct (Reasoning + Acting):** Paradigma cognitivo donde el agente alterna secuencialmente entre formular una hipótesis de razonamiento (*Thought*), invocar una herramienta del sistema operativo (*Action / Tool Call*) e inspeccionar la respuesta obtenida (*Observation*) hasta arribar a un diagnóstico probado.
* **Model Context Protocol (MCP):** Estándar abierto cliente-servidor JSON-RPC 2.0 desarrollado para desacoplar de forma segura a los modelos de lenguaje de las herramientas de infraestructura. Permite que un agente invoque comandos o consulte métricas únicamente a través de un catálogo de herramientas autorizadas expuestas por un servidor MCP.
* **Guardrails de Seguridad (Safety Guardrails):** Mecanismos de contención que restringen las acciones que un agente autónomo puede ejecutar en producción, basados en listas blancas de acciones permitidas (*allowlists*), bloqueo de patrones peligrosos (*denylists*) y contención del radio de explosión (*blast radius*).
* **Human-in-the-Loop (HITL):** Esquema de operación donde el agente autónomo investiga la causa raíz y prepara el plan detallado de remediación con comandos exactos, pero requiere la autorización explícita de un operador humano antes de aplicar cualquier mutación en el sistema.
* **Self-Healing (Autorremediación):** Capacidad de una infraestructura para detectar fallas en tiempo real, aislar componentes degradados y ejecutar acciones correctivas (como el reinicio de servicios caídos o la reparación de arreglos RAID espejados) cerrando automáticamente el ciclo de alerta sin intervención humana.
* 📖 [Ver guía y laboratorio interactivo de AI SRE en Lab 3.6.3](monitoreo/ai_sre_agentes_observabilidad.md) y [Comparativa de Arquitecturas de Monitoreo](monitoreo/monitoreo_arquitecturas_comparativa.md#9-la-nueva-frontera-ai-sre-agentes-autónomos-y-remediación-en-observabilidad).
