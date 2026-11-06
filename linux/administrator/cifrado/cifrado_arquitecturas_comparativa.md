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
- ssh
- wireguard
- openvpn
- fde
- dm-crypt
- comparativa
- arquitectura
tools:
- cryptsetup
- gocryptfs
- gpg
- ssh
- wg
- openvpn
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
- lab-3.3-ssh-cifrado-cliente-servidor
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

## 🗺️ Mapa de las Capas de Cifrado en el Stack Linux (En Reposo y En Tránsito)

```
+───────────────────────────────────────────────────────────────────────────────────────────────────+
│                                NIVELES DE CIFRADO EN EL STACK LINUX                               │
│                                                                                                   │
│  0. CIFRADO EN TRÁNSITO Y ACCESO REMOTO (OpenSSH, WireGuard, OpenVPN, TLS)                        │
│     - Opera sobre conexiones TCP/UDP o interfaces virtuales de red (L3/L4/L7).                    │
│     - Criptografía Híbrida: Asimétrica (Ed25519/Curve25519/X.509) + Simétrica Efímera (ChaCha20). │
│     - Casos: Administración remota (ssh/sshd), túneles (-L/-R), VPNs entre datacenters y nube.    │
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

## ⚖️ Tabla Comparativa Definitiva (Datos en Reposo y en Tránsito)

| Criterio de Comparación | Nivel 1: Bloques (`LUKS2 / dm-crypt`) | Nivel 2: Filesystem (`gocryptfs`) | Nivel 3: Archivo / App (`GPG / age`) | Nivel 4: Sesión y Túneles (`SSH / OpenSSH`) | Nivel 5: Red VPN (`WireGuard / OpenVPN`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Ámbito de Protección** | **En Reposo** (Disco completo / Partición) | **En Reposo** (Directorio / Nube) | **En Reposo e Intercambio** (Archivo único) | **En Tránsito** (Shell, SFTP y Túneles TCP `:22`) | **En Tránsito** (Red L3/L2 entre nodos `:51820` / `:1194`) |
| **Capa del Sistema Operativo** | Kernel (`drivers/md/dm-crypt.c`) | Espacio de Usuario (`FUSE`) | Espacio de Usuario (CLI) | Espacio de Usuario (`ssh` cliente ↔ `sshd` servidor) | Kernel Linux (`wireguard.ko`) o Userspace (`openvpn` TUN) |
| **Cifrado Simétrico (Datos)** | `AES-256-XTS` (con Master Key en RAM) | `AES-256-GCM` por archivo + `EME` nombres | `AES-256` o `ChaCha20-Poly1305` por paquete | `ChaCha20-Poly1305` o `AES-256-GCM` (Session Key efímera) | `ChaCha20-Poly1305` (WireGuard) o `AES-256-GCM` (OpenVPN) |
| **Criptografía Asimétrica** | ❌ No (usa KDF `Argon2id` en 8 Keyslots) | ❌ No (usa KDF `scrypt`) | ✅ Sí (`Ed25519` / `Cv25519` / `RSA`) | ✅ **Doble:** Host Key (`known_hosts`) + User Key (`authorized_keys`) + KEX `curve25519` | ✅ Sí: Pares `Curve25519` (*Crypto-Key Routing*) o PKI X.509 (`ca.crt`) |
| **¿Qué se oculta?** | **Todo en el disco:** contenido, nombres, inodos y espacio libre. | Contenido y nombres de cada archivo. | Solo el archivo o stream cifrado. | Comandos, salida de terminal, archivos SFTP y puertos tunelizados (`-L`/`-R`). | Todo el tráfico IP entre los nodos/subredes conectados a la VPN. |
| **¿Requiere privilegios `root`?** | ✅ **Sí obligatorio** (para mapear `/dev/mapper`). | ❌ No (ejecuta vía FUSE). | ❌ No (cualquier usuario). | Cliente: ❌ No · Servidor `sshd` en `:22`: ✅ Sí. | ✅ Sí (para levantar interfaces `wg0` o `tun0` y rutas). |
| **Archivos Clave en Linux** | Cabecera binaria en `/dev/sdX`, `/etc/crypttab` | `gocryptfs.conf`, `gocryptfs.diriv` | `~/.gnupg/`, archivos `.gpg` / `.age` | `~/.ssh/id_ed25519`, `known_hosts`, `authorized_keys`, `/etc/ssh/sshd_config` | `/etc/wireguard/wg0.conf` (o `ca.crt`, `server.crt`, `ta.key`) |
| **Laboratorio y Demo Interactiva** | [`luks/luks.md`](../luks/luks.md) · [`demo_luks.sh`](../luks/demo_luks.sh) | [`gocryptfs/gocryptfs.md`](../gocryptfs/gocryptfs.md) · [`demo_gocryptfs.sh`](../gocryptfs/demo_gocryptfs.sh) | [`gpg/gpg_firmas_repositorios_backups.md`](../gpg/gpg_firmas_repositorios_backups.md) · [`demo_gpg.sh`](../gpg/demo_gpg.sh) | [`ssh_cifrado_cliente_servidor_wireguard.md`](ssh_cifrado_cliente_servidor_wireguard.md) · [`demo_ssh_cifrado.sh`](demo_ssh_cifrado.sh) | [`ssh_cifrado_cliente_servidor_wireguard.md`](ssh_cifrado_cliente_servidor_wireguard.md) · [`demo_criptografia_llaves.sh`](demo_criptografia_llaves.sh) |

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

### 4. Cifrado en Tránsito: SSH (Cliente/Servidor), WireGuard y OpenVPN

Mientras que LUKS2, `gocryptfs` y GPG protegen los datos almacenados en un disco o carpeta (**Data at Rest**), en cuanto un dato sale por la placa de red hacia otro servidor necesita **Cifrado en Tránsito (*Data in Transit*)**.

```
  [ Cliente SSH (ssh) ]                                [ Servidor SSH (sshd :22) ]
   ~/.ssh/id_ed25519 (User Priv)                        /etc/ssh/ssh_host_ed25519_key (Host Priv)
   ~/.ssh/known_hosts (Verifica Host)                   ~/.ssh/authorized_keys (Verifica User)
            │                                                        │
            +───────► 1. KEX: Intercambio de Claves (Curve25519 / DH)◄+
                      2. Asimétrico: Identidad Host + Usuario (Ed25519/RSA)
                      3. Simétrico: Tráfico 1000x veloz (ChaCha20 / AES-GCM)
                      4. Integridad: Anti-manipulación (Poly1305 / HMAC-SHA2)
```

#### ¿Cómo operan SSH y WireGuard?
- **OpenSSH (`ssh` / `sshd`) — Arquitectura Híbrida en 4 Etapas:** No elige una sola forma de cifrado, sino que combina cuatro mecanismos para la tarea en la que cada uno es más eficiente:
  1. **Intercambio de Claves (KEX):** `Curve25519` o `diffie-hellman-group14/16-sha256/512` para acordar una *Session Key* efímera en RAM sin transmitirla por la red (*Perfect Forward Secrecy*).
  2. **Cifrado Asimétrico (`Ed25519`, `RSA`, `ECDSA`):** Exclusivo para **autenticación de identidades** (el cliente valida la *Host Key* del servidor en `~/.ssh/known_hosts` y el servidor valida la *User Key* del cliente en `~/.ssh/authorized_keys`).
  3. **Cifrado Simétrico (`ChaCha20-Poly1305`, `AES-256-GCM`, `AES-128-CTR`):** Cifra masivamente todo el tráfico de la sesión (comandos, PTY, SFTP y túneles `-L`/`-R`) porque es **~1.000 veces más rápido** que el asimétrico.
  4. **Integridad y Autenticación de Mensajes (`MAC / AEAD`):** `HMAC-SHA2-256/512` o autenticación integrada AEAD (`AES-GCM` / `ChaCha20-Poly1305`) para garantizar que ningún paquete sea alterado en tránsito.
- **WireGuard (`wg`):** Lleva el mismo modelo de llaves públicas sin Autoridad Certificadora de SSH directamente al **Kernel de Linux (Capa 3 IP)**. Cada nodo tiene una llave privada `Curve25519` y una lista de `[Peer]` con sus llaves públicas e IPs permitidas (*Crypto-Key Routing*), cifrando y autenticando todos los paquetes UDP a velocidad de línea con `ChaCha20-Poly1305` (AEAD).
- **OpenVPN (`openvpn`):** Opera en espacio de usuario (`tun0`) apoyándose en una infraestructura PKI completa de certificados X.509 (`ca.crt`, `server.crt`, `client.crt`) y canales de datos TLS (`AES-256-GCM`).

👉 **Laboratorio Práctico Dedicado (Paso a Paso Cliente/Servidor + WireGuard):** [`ssh_cifrado_cliente_servidor_wireguard.md`](ssh_cifrado_cliente_servidor_wireguard.md) · Script: [`demo_ssh_cifrado.sh`](demo_ssh_cifrado.sh)

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
├── ¿Administración remota de servidores, copia de archivos o tunelizar un puerto interno?
│   └── ► Usá OpenSSH (ssh / sshd / scp / sftp / ssh -L) con llaves Ed25519.
│
└── ¿Redes privadas permanentes entre servidores, datacenters o clientes remotos?
    └── ► Usá WireGuard (Kernel VPN con Crypto-Key Routing) u OpenVPN (mTLS X.509).
```

---

## 🗺️ Hoja de Ruta de Laboratorios Prácticos de Cifrado

Para llevar estos conceptos a la práctica en terminal (WSL2 o Linux nativo), seguí la secuencia de laboratorios y scripts didácticos del repositorio:

1. **Fundamentos Criptográficos y Gestión de Llaves:**
   - 📖 Guía: [`fundamentos_criptografia_llaves_certificados.md`](fundamentos_criptografia_llaves_certificados.md)
   - 💻 Script Didáctico: [`demo_criptografia_llaves.sh`](demo_criptografia_llaves.sh) (6 etapas: AES-256, RSA/Ed25519, Challenge-Response SSH/EC2, Firmas Digitales y Criptografía Híbrida ECDH).
2. **Arquitectura de Cifrado en SSH (Cliente/Servidor), Túneles y WireGuard:**
   - 📖 Guía: [`ssh_cifrado_cliente_servidor_wireguard.md`](ssh_cifrado_cliente_servidor_wireguard.md)
   - 💻 Script Didáctico: [`demo_ssh_cifrado.sh`](demo_ssh_cifrado.sh) (Servidor `sshd` real aislado, auditoría de las 3 capas con `ssh -v`, permisos `chmod 600`, ataque MitM en `known_hosts`, túneles `ssh -L` y llaves WireGuard).
3. **Cifrado de Bloques y FDE (Nivel 1):**
   - 📖 Guía: [`../luks/luks.md`](../luks/luks.md)
   - 💻 Script Didáctico: [`../luks/demo_luks.sh`](../luks/demo_luks.sh) (Aprovisionamiento dm-crypt, formateo LUKS2, mapeo `/dev/mapper`, keyslots de rescate y benchmarks).
4. **Cifrado de Filesystems en Espacio de Usuario con FUSE (Nivel 2):**
   - 📖 Guía: [`../gocryptfs/gocryptfs.md`](../gocryptfs/gocryptfs.md)
   - 💻 Script Didáctico: [`../gocryptfs/demo_gocryptfs.sh`](../gocryptfs/demo_gocryptfs.sh) (Cifrado transparente para nubes como S3/Dropbox, modo reverse y gestión sin root).
5. **Firmas Digitales, Repositorios y Backups Asimétricos (Nivel 3):**
   - 📖 Guía: [`../gpg/gpg_firmas_repositorios_backups.md`](../gpg/gpg_firmas_repositorios_backups.md)
   - 💻 Script Didáctico: [`../gpg/demo_gpg.sh`](../gpg/demo_gpg.sh) (Generación de llaves OpenPGP, firma de commits y paquetes APT, y backups desatendidos asimétricos).
6. **Laboratorios Integradores y Producción en la Nube:**
   - 📖 Trabajo Integrador de Almacenamiento y Cifrado: [`../trabajo_integrador/trabajo_integrador.md`](../trabajo_integrador/trabajo_integrador.md)
   - 📖 Clúster Multi-nodo en AWS EC2 con LVM, LUKS y Monitoreo: [`../monitoreo/monitoreo_centralizado_multinodo.md`](../monitoreo/monitoreo_centralizado_multinodo.md)

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
