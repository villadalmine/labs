---
id: lab-3.3.0-cifrado-arquitecturas-comparativa
title: 'Arquitecturas de Cifrado en Linux: Bloques (LUKS2), Filesystems (gocryptfs)
  y Aplicación (GPG/age)'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.3'
sections:
- '3.3'
- '3'
category: security
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
tags:
- security
- cifrado
- luks
- gocryptfs
- gpg
- age
- fde
- dm-crypt
- comparativa
- arquitectura
tools:
- cryptsetup
- gocryptfs
- gpg
- lsblk
- df
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Rocky Linux 10.2
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-10-30'
  notes: Comparativa y validación conceptual de capas de cifrado en Linux sobre discos
    loop y espacio de usuario.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-30'
  notes: Compatible con volúmenes EBS gp3 y almacenamiento S3.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
- Rocky Linux 10.2
status: PASSED
rag_summary: 'Guía introductoria y comparativa sobre las arquitecturas de cifrado
  de datos en reposo en Linux. Analiza y contrasta los tres niveles fundamentales
  de protección criptográfica: cifrado de bloques o disco completo (FDE con LUKS2
  y dm-crypt), cifrado a nivel de sistema de archivos en espacio de usuario (gocryptfs
  vía FUSE) y cifrado a nivel de archivo o aplicación (GnuPG y age). Evalúa vectores
  de ataque, filtración de metadatos (nombres, tamaños, estructura de directorios
  y timestamps), impacto de rendimiento con aceleración por hardware AES-NI, requerimientos
  de privilegios root y compatibilidad con sincronización en la nube (S3, Dropbox)
  y respaldos incrementales.'
files:
  guide: cifrado/cifrado_arquitecturas_comparativa.md
  script: null
  terraform: null
prerequisites:
- lab-3.1-anatomia-filesystems
next_recommended_labs:
- lab-3.3-cifrado-luks
- lab-3.4-cifrado-fuse-gocryptfs
- lab-3.4b-gpg-firmas-repositorios-backups
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Arquitecturas de Cifrado en Linux: Bloques (LUKS2), Filesystems (gocryptfs) y Aplicación (GPG / age)

El cifrado de datos en reposo (*Data at Rest Encryption*) es un requisito no negociable en la administración moderna de infraestructura: desde laptops de ingenieros y servidores físicos en datacenters (*Bare-Metal*) hasta volúmenes en la nube (AWS EBS, Google Cloud Persistent Disks).

Sin embargo, uno de los errores más comunes al diseñar la seguridad de un servidor es asumir que "cifrar" es una solución única. En Linux existen **tres niveles arquitecturales completamente distintos** de cifrado, cada uno diseñado para resolver una amenaza específica, con diferentes impactos en rendimiento, privilegios y facilidad de respaldo.

---

## 🗺️ Mapa de las 3 Capas de Cifrado en Linux

```
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                                NIVELES DE CIFRADO EN EL STACK LINUX                               │
│                                                                                                   │
│  1. CIFRADO A NIVEL DE APLICACIÓN / ARCHIVO ESTÁTICO (GnuPG, age, OpenSSL enc)                    │
│     - Opera sobre archivos aislados (.tar.gz, .sql, secretos).                                    │
│     - No requiere privilegios de root. Criptografía asimétrica o simétrica.                       │
│     - Casos: Backups no interactivos en cron, firma de repositorios APT/RPM, secretos en Git.     │
│                                                                                                   │
│  2. CIFRADO A NIVEL DE FILESYSTEM / FUSE (gocryptfs, fscrypt, eCryptfs)                           │
│     - Opera en espacio de usuario o VFS archivo por archivo.                                      │
│     - Cada archivo se cifra individualmente (contenido + nombre de archivo).                      │
│     - Casos: Carpetas personales, sincronización en nube (Dropbox, S3, Nextcloud), backups delta. │
│                                                                                                   │
│  3. CIFRADO DE BLOQUES / FULL DISK ENCRYPTION (dm-crypt + LUKS2)                                  │
│     - Opera en el Kernel debajo del sistema de archivos (capa de bloques /dev/mapper).            │
│     - Cifra sectores crudos: oculta datos, inodos, nombres, tamaños y metadatos del filesystem.   │
│     - Casos: Discos completos del SO, laptops, particiones de bases de datos, volúmenes de SAN.   │
+───────────────────────────────────────────────────────────────────────────────────────────────────+
```

---

## ⚖️ Tabla Comparativa Definitiva

| Criterio de Comparación | Nivel 1: Bloques (`LUKS2 / dm-crypt`) | Nivel 2: Filesystem (`gocryptfs`) | Nivel 3: Archivo / App (`GPG / age`) |
| :--- | :--- | :--- | :--- |
| **Capa del sistema operativo** | Kernel (`drivers/md/dm-crypt.c`) | Espacio de Usuario (`FUSE`) | Espacio de Usuario (Binario CLI / Lib) |
| **¿Qué se oculta?** | **Todo:** contenido, nombres, inodos, árbol de directorios y espacio libre. | Contenido y nombres de archivo. | Solo el archivo o stream cifrado. |
| **¿Qué metadatos se filtran?** | Nada (solo el tamaño total de la partición y la cabecera LUKS). | Cantidad de archivos, tamaños aproximados y marcas de tiempo (`mtime`). | Nombre del archivo contenedor y tamaño del payload. |
| **¿Requiere privilegios `root`?** |  **Sí obligatorio** (para mapear `/dev/mapper`). | ❌ No (ejecuta con usuario estándar vía FUSE). | ❌ No (ejecuta con cualquier usuario). |
| **Flexibilidad de almacenamiento** | Rígido: Requiere partición o loop device con tamaño fijo. | Dinámico: Crece y decrece según los archivos almacenados. | Archivo por archivo bajo demanda. |
| **Impacto en Backups y Nube** | **Pesado:** Modificar 1 archivo altera el volumen; sincronizar a S3 exige subir bloques o imágenes completas. | **Óptimo:** Cada archivo cifrado es independiente; ideal para `rsync`, Rclone o AWS S3. | **Ideal para Archival:** Dumps de DB o tarballs autocontenidos. |
| **Rendimiento de I/O** | **Máximo** (acelerado por instrucciones CPU AES-NI en kernel). | Medio (overhead por cambios de contexto en FUSE). | Rápido para archivos estáticos; costoso en streaming masivo. |
| **Mecanismo de Desbloqueo** | Contraseña, Keyfile, **TPM 2.0 (`systemd-cryptenroll`)**, FIDO2 o Tang/Clevis. | Contraseña maestra o llave de recuperación. | Clave privada asimétrica (RSA/ECC) o passphrase simétrica. |

---

## 🔍 Análisis Detallado de Cada Arquitectura

---

### 1. Cifrado de Bloques: LUKS2 (`dm-crypt`)

Es el estándar de facto de la industria para **cifrado de disco completo (*Full Disk Encryption - FDE*)**.

```
  [ Aplicación / Usuario ]
            │
            ▼
    [ Filesystem (ext4, XFS) ]
            │
            ▼
  [ /dev/mapper/datos_seguros ]  <--- Dispositivo virtual descifrado
            │
            ▼
    [ Kernel: dm-crypt (AES-XTS-PLAIN64) ]
            │
            ▼
    [ /dev/sda2 o /dev/loop0 ]  <--- Dispositivo físico cifrado
```

#### ¿Cómo opera?
El módulo del kernel `dm-crypt` se interpone entre el sistema de archivos y el disco físico. Cuando el contenedor está abierto, expone un dispositivo de bloques virtual en `/dev/mapper/`. El sistema de archivos (ext4, XFS) se crea y monta sobre ese dispositivo virtual.

#### Fortalezas:
- **Cero fuga de metadatos:** Un atacante con acceso físico al disco no puede saber si tenés 1 archivo de 100 GB o 10.000 fotos pequeñas, ni qué nombres tienen, ni qué filesystem utilizás.
- **Rendimiento casi nativo:** Al operar dentro del kernel con optimizaciones criptográficas directas por hardware (AES-NI), la penalización de CPU es típicamente inferior al 2-3%.

#### Debilidades:
- **Incompatible con sincronización granular:** No podés sincronizar fácilmente un disco LUKS de 500 GB a Google Drive o S3 sin subir la imagen entera cada vez.
- **Requiere privilegios de root:** Solo el superusuario puede formatear, abrir y cerrar dispositivos con `cryptsetup`.

👉 **Laboratorio Práctico Dedicado:** [`luks/luks.md`](../luks/luks.md)

---

### 2. Cifrado de Filesystem en Espacio de Usuario: `gocryptfs`

Diseñado para resolver el problema del almacenamiento cifrado en la **nube y entornos multiusuario**.

```
  [ Aplicación / Usuario ]
            │
            ▼
  [ Directorio Visible: ~/datos_visibles ]  (Punto de montaje FUSE)
            │
            ▼
  [ Binario gocryptfs en Espacio de Usuario (AES-GCM / EME) ]
            │
            ▼
  [ Directorio Cifrado: ~/datos_cifrados ]  (Archivos individuales cifrados en disco)
```

#### ¿Cómo opera?
A través del subsistema FUSE (*Filesystem in Userspace*), `gocryptfs` crea una correspondencia 1 a 1 entre una carpeta con archivos en claro y una carpeta con archivos cifrados. Cada archivo tiene su nombre cifrado con algoritmo EME y su contenido cifrado en bloques de 4 KiB con AES-GCM o XChaCha20-Poly1305.

#### Fortalezas:
- **Sincronización perfecta con la nube:** Si modificás un documento de texto de 5 KB dentro de una carpeta de 200 GB, solo se altera **un único archivo cifrado** de 5 KB en el disco. Herramientas como Dropbox, Nextcloud o `rsync` solo transmiten ese delta.
- **No requiere root:** Cualquier usuario sin privilegios puede crear y montar su propia carpeta cifrada en su `$HOME`.

#### Debilidades:
- **Fuga de metadatos estructurales:** Un atacante que acceda al disco puede ver la cantidad exacta de archivos y carpetas, sus tamaños aproximados y las marcas de tiempo de modificación.
- **Overhead de FUSE:** Cada lectura y escritura cruza la frontera entre el espacio de usuario y el kernel, lo que reduce el rendimiento en cargas de I/O intensivas (como bases de datos).

👉 **Laboratorio Práctico Dedicado:** [`gocryptfs/gocryptfs.md`](../gocryptfs/gocryptfs.md)

---

### 3. Cifrado a Nivel de Aplicación: GnuPG (`gpg`) y `age`

Diseñado para el **intercambio seguro, la firma digital y el archivado de copias de seguridad**.

```
  [ Proceso de Backup / DB Dump ]
            │
            ▼ (Pipe stdout)
  [ mysqldump ... | gzip ]
            │
            ▼ (Pipe)
  [ gpg --encrypt --recipient backup-key@empresa.com ]
            │
            ▼
  [ /backups/db_20261030.sql.gz.gpg ]  <--- Archivo cifrado autónomo
```

#### ¿Cómo opera?
No cifra discos ni carpetas montadas. Toma un archivo o un flujo de datos (*stream* por tubería) y genera un archivo binario cifrado autónomo utilizando criptografía asimétrica (claves pública y privada) o simétrica.

#### Fortalezas:
- **Seguridad asimétrica en producción:** En un servidor web podés almacenar únicamente la **clave pública** del bot de respaldos. El servidor puede cifrar todos los días, pero si es vulnerado, el atacante **no tiene forma humana de descifrar los backups anteriores** porque la clave privada reside fuera del servidor (en frío o HSM).
- **Firmas digitales de autenticidad:** Es el estándar mundial para firmar paquetes de software en distribuciones Linux (APT `signed-by`, RPM/DNF) y commits en Git.

#### Debilidades:
- **No es transparente:** El archivo cifrado no se puede consultar directamente; debe ser descifrado en su totalidad antes de ser leído por una aplicación.

👉 **Laboratorio Práctico Dedicado:** [`gpg/gpg_firmas_repositorios_backups.md`](../gpg/gpg_firmas_repositorios_backups.md)

---

## 🎯 Matriz de Decisión Operativa

```
¿Qué necesitás proteger?
│
├── ¿Un servidor completo, laptop corporativa o partición de base de datos?
│   └── ► Usá LUKS2 / dm-crypt (Cifrado de Bloques FDE).
│
├── ¿Carpetas que se sincronizan con AWS S3, Dropbox o discos compartidos multiusuario?
│   └── ► Usá gocryptfs (Cifrado de Filesystem FUSE).
│
├── ¿Respaldos automatizados generados por cron o firmas de paquetes/commits?
│   └── ► Usá GnuPG (gpg) o age (Cifrado de Aplicación / Archivo Estático).
│
└── ¿Canales de comunicación entre servidores a través de Internet?
    └── ► Usá WireGuard, IPsec o TLS (Cifrado en Tránsito).
```


---

## 🔗 Enlaces Oficiales de Documentación y Proyectos

A continuación se detallan las fuentes primarias de documentación técnica y estándares para las tecnologías analizadas:

| Tecnología | Rol en la Arquitectura | Documentación Oficial y Repositorio Upstream |
| :--- | :--- | :--- |
| **`cryptsetup` / LUKS2** | Cifrado de bloques de disco completo (FDE) | [GitLab Oficial de cryptsetup](https://gitlab.com/cryptsetup/cryptsetup) · [LUKS2 On-Disk Format Specification](https://gitlab.com/cryptsetup/cryptsetup/-/wikis/LUKS-standard/on-disk-format.pdf) |
| **`dm-crypt` (Linux Kernel)** | Módulo del kernel para cifrado transparente | [Kernel.org dm-crypt Documentation](https://docs.kernel.org/admin-guide/device-mapper/dm-crypt.html) · [Arch Linux dm-crypt Guide](https://wiki.archlinux.org/title/Dm-crypt) |
| **`gocryptfs`** | Cifrado a nivel de sistema de archivos en espacio de usuario | [Sitio Oficial de gocryptfs](https://nuetzlich.net/gocryptfs/) · [Repositorio GitHub rfjakob/gocryptfs](https://github.com/rfjakob/gocryptfs) · [Security Design & Audit](https://nuetzlich.net/gocryptfs/security/) |
| **`GnuPG` (GPG)** | Criptografía asimétrica, firmas de paquetes y backups | [Sitio Oficial de The GNU Privacy Guard](https://gnupg.org/) · [RFC 4880 - OpenPGP Message Format](https://www.rfc-editor.org/rfc/rfc4880) · [RFC 9580 - OpenPGP Crypto](https://www.rfc-editor.org/rfc/rfc9580) |
| **`age` (Actually Good Encryption)** | Cifrado moderno y simple de archivos | [Sitio Oficial age-encryption.org](https://age-encryption.org/) · [Repositorio GitHub FiloSottile/age](https://github.com/FiloSottile/age) |
| **`Clevis` & `Tang` (NBDE)** | Desbloqueo en red para centros de datos | [Repositorio GitHub Latchset Clevis](https://github.com/latchset/clevis) · [Repositorio GitHub Latchset Tang](https://github.com/latchset/tang) |
| **`systemd-cryptenroll`** | Desbloqueo automático con hardware (TPM 2.0 / FIDO2) | [Manual de systemd-cryptenroll (freedesktop.org)](https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html) · [TPM 2.0 Library Specification (TCG)](https://trustedcomputinggroup.org/resource/tpm-library-specification/) |
| **`fscrypt` (Linux Kernel VFS)** | Cifrado nativo de directorios en ext4 / f2fs | [Kernel.org fscrypt Documentation](https://docs.kernel.org/filesystems/fscrypt.html) · [Google fscrypt Userspace Tool](https://github.com/google/fscrypt) |

---

## 📖 Glosario Técnico de Tecnologías de Cifrado

* **FDE (Full Disk Encryption):** Cifrado de disco completo. Técnica que cifra cada sector físico de almacenamiento por debajo del sistema de archivos, garantizando que si el disco es sustraído físicamente, ningún dato ni metadato sea legible sin la clave.
* **LUKS (Linux Unified Key Setup):** Estándar abierto de especificación de cabeceras de cifrado de disco para Linux. Su versión moderna (**LUKS2**) incorpora verificación de integridad de metadatos, soporte para múltiples keyslots y algoritmos modernos de derivación de claves.
* **dm-crypt:** Subsistema del Device Mapper en el kernel de Linux que proporciona cifrado transparente de dispositivos de bloques utilizando la API criptográfica del kernel y aceleración por hardware (AES-NI).
* **Argon2id:** Algoritmo ganador de la *Password Hashing Competition* (PHC) adoptado como función de derivación de claves (KDF) por defecto en LUKS2. Es altamente resistente a ataques por fuerza bruta basados en GPUs y ASICs al exigir un consumo configurable de memoria RAM además de CPU.
* **PBKDF2:** Función histórica de derivación de claves basada en iteraciones de funciones hash (SHA-256). Aunque fue el estándar de LUKS1, es susceptible a ataques masivos paralelos en tarjetas gráficas modernas.
* **AES-XTS (XEX Tweakable Block Cipher with Ciphertext Stealing):** Modo de operación estándar del algoritmo AES diseñado específicamente para cifrado de almacenamiento de bloques, inmune a ataques de manipulación de patrones repetitivos.
* **gocryptfs:** Sistema de archivos apilado (*overlay*) en espacio de usuario desarrollado en Go que utiliza **FUSE**. Cada archivo individual en texto plano se transforma en un archivo cifrado con GCM-SIV en el disco subyacente, preservando la granularidad de archivos para sincronización en la nube.
* **FUSE (Filesystem in Userspace):** Mecanismo del kernel de Linux que permite a programas sin privilegios root implementar sistemas de archivos completos ejecutándose enteramente en espacio de usuario.
* **GnuPG (GPG):** Implementación completa y libre del estándar OpenPGP. Utiliza criptografía de clave pública (asimétrica) permitiendo cifrar datos para un destinatario utilizando únicamente su clave pública, garantizando que solo el poseedor de la clave privada pueda descifrarlo.
* **age:** Herramienta y formato de cifrado moderno, minimalista y seguro creado por Filippo Valsorda como alternativa a GnuPG para cifrado de archivos, eliminando la complejidad histórica de OpenPGP y adoptando curvas elípticas modernas (X25519) y claves SSH.
* **TPM 2.0 (Trusted Platform Module):** Microcontrolador criptográfico seguro soldado a la placa base que almacena claves criptográficas y mide la integridad del proceso de arranque de la máquina mediante registros de configuración de plataforma (**PCRs**).
* **NBDE (Network-Bound Disk Encryption):** Arquitectura que permite a servidores en centros de datos desbloquear volúmenes LUKS automáticamente durante el arranque a través de la red local mediante la combinación de **Clevis** (cliente en el host) y **Tang** (servidor oráculo de claves en la LAN). Si el disco es extraído de las instalaciones, no puede descifrarse.
