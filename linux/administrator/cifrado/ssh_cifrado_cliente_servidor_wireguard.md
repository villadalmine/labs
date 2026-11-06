---
id: lab-3.3-ssh-cifrado-cliente-servidor
title: Arquitectura de Cifrado en SSH (Cliente y Servidor), Túneles Cifrados y WireGuard
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.3'
sections:
- '3.3'
- '3'
category: security
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- security
- ssh
- sshd
- ed25519
- known_hosts
- authorized_keys
- ssh-keygen
- ssh-agent
- port-forwarding
- wireguard
- openvpn
- chacha20-poly1305
- curve25519
- mitm
- tofu
tools:
- ssh
- sshd
- ssh-keygen
- ssh-agent
- ssh-add
- ssh-copy-id
- openssl
- wg
requirements:
  root_required: false
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
  test_date: '2026-11-06'
  notes: Laboratorio interactivo validado con instancia sshd aislada, auditoría de
    handshake ssh -v, permisos 600, simulación MitM en known_hosts, túneles SSH -L
    y llaves WireGuard.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-06'
  notes: Validado en nodos cloud EC2 con autenticación por llave pública Ed25519,
    hardening de sshd_config y túneles locales.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
- Debian 12
status: PASSED
rag_summary: 'Guía práctica paso a paso sobre cómo funciona el cifrado en SSH a nivel
  cliente y servidor (las 3 capas criptográficas del protocolo: Host Keys/TOFU en
  known_hosts, KEX efímero Diffie-Hellman curve25519-sha256 con túnel simétrico ChaCha20-Poly1305/AES-GCM
  y autenticación de usuario por Challenge-Response contra authorized_keys), administración
  completa (ssh-keygen, permisos estrictos StrictModes 700/600, ssh-agent, ~/.ssh/config,
  hardening de sshd_config y túneles SSH -L/-R/-D) y comparativa práctica con WireGuard
  (Crypto-Key Routing) y OpenVPN.'
files:
  guide: cifrado/ssh_cifrado_cliente_servidor_wireguard.md
  script: cifrado/demo_ssh_cifrado.sh
  terraform: null
prerequisites:
- lab-3.3.0-cifrado-arquitecturas-comparativa
- lab-3.3-fundamentos-criptografia-llaves
next_recommended_labs:
- lab-3.3-cifrado-luks
- lab-3.4-cifrado-fuse-gocryptfs
- lab-3.4b-gpg-firmas-repositorios-backups
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# 🔐 Arquitectura de Cifrado en SSH (Cliente y Servidor), Túneles y WireGuard

En las presentaciones y guías de arquitecturas de cifrado analizamos cómo proteger datos en reposo (**LUKS2**, **gocryptfs**, **GPG/age**) y redes privadas (**OpenVPN**, **WireGuard**). Sin embargo, la herramienta criptográfica que un SysAdmin o SRE utiliza **decenas de veces todos los días** es **OpenSSH (`ssh` / `sshd`)**.

Un error conceptual muy frecuente es pensar que *"cuando me conecto por SSH, mis comandos viajan cifrados con mi llave `~/.ssh/id_ed25519`"*. **Eso es falso.** En SSH intervienen **dos pares de llaves asimétricas distintas** (una del Servidor y otra del Usuario) más **una llave simétrica efímera de sesión**.

Esta guía explica paso a paso cómo funciona el cifrado de SSH por dentro, cómo configurarlo y auditarlo a **nivel Cliente** y a **nivel Servidor**, cómo crear **túneles cifrados**, y cómo se compara con **WireGuard** y **OpenVPN**.

> 💡 **Laboratorio Interactivo:** Podés ejecutar toda esta guía en vivo (levantando un servidor `sshd` real aislado en un puerto local, auditando el handshake criptográfico, provocando un fallo de permisos, simulando un ataque *Man-in-the-Middle* y creando un túnel cifrado) corriendo:
> ```bash
> cd linux/administrator/cifrado
> ./demo_ssh_cifrado.sh
> ```

---

## 1. ¿Cómo funciona el Cifrado en SSH? Las 3 Capas Criptográficas

El protocolo SSH (definido en los RFC 4251, 4252 y 4253) no es un simple login remoto: establece un **túnel criptográfico híbrido en tres fases secuenciales**.

```
💻 CLIENTE (ssh)                                          🖥️ SERVIDOR (sshd :22)
================                                          ======================

FASE 1: CAPA DE TRANSPORTE (KEX + Identidad del Servidor)
---------------------------------------------------------
1. Negociación de algoritmos (KexAlgorithms, Ciphers) ──►
2. Intercambio Diffie-Hellman Efímero (curve25519)    ◄─► Calculan ambos la MISMA
                                                          Session Key Simétrica en RAM
                                                          (sin transmitirla por la red)
3. Verifica huella en ~/.ssh/known_hosts (TOFU)       ◄── Envía su Host Key Pública
   (¡Protege contra ataques Man-in-the-Middle!)           (/etc/ssh/ssh_host_ed25519_key.pub)
                                                          + Firma del intercambio con su
                                                          Host Key Privada

FASE 2: TÚNEL SIMÉTRICO ACTIVO (Cifrado de Tráfico / Bulk Encryption)
---------------------------------------------------------------------
🔒 ========= TÚNEL CIFRADO CON chacha20-poly1305 O aes256-gcm ========= 🔒
   (A partir de este milisegundo, TODO paquete viaja cifrado con la
    Session Key simétrica efímera. Si roban tu disco mañana, no pueden
    descifrar el tráfico de hoy: Perfect Forward Secrecy - PFS).

FASE 3: CAPA DE AUTENTICACIÓN DEL USUARIO (Dentro del túnel ya cifrado)
-----------------------------------------------------------------------
4. "Soy el usuario 'deploy', quiero autenticarme      ──► Busca la llave pública en:
    con la llave pública ID_PUB"                          ~/.ssh/authorized_keys
5. Firma el Session ID con su llave privada           ◄── Envía Desafío (Challenge)
   (~/.ssh/id_ed25519 en el cliente, que                  si la llave pública está autorizada
    JAMÁS sale por la red)                            ──► Verifica la firma matemática
                                                      ◄── ✅ Acceso Concedido (Shell/Túnel)
```

### Resumen de las 3 Llaves que participan en cada conexión SSH

| Tipo de Llave | ¿Dónde vive la Privada? | ¿Dónde vive la Pública? | ¿Para qué sirve exactamente? |
| :--- | :--- | :--- | :--- |
| **1. Host Key (Identidad del Servidor)** | Servidor: `/etc/ssh/ssh_host_ed25519_key` | Servidor: `/etc/ssh/ssh_host_ed25519_key.pub` <br> Cliente: `~/.ssh/known_hosts` | **Autenticar al Servidor frente al Cliente.** Evita que un atacante en la red suplante al servidor (*Man-in-the-Middle*). |
| **2. Session Key (Cifrado del Tráfico)** | **Solo en RAM** (ambos extremos, efímera por sesión) | No existe (es **Simétrica**, calculada vía Diffie-Hellman `curve25519-sha256`) | **Cifrar todos los datos, comandos y archivos** que viajan por el túnel a alta velocidad (`chacha20-poly1305` o `aes256-gcm`). |
| **3. User Key (Identidad del Usuario)** | Cliente: `~/.ssh/id_ed25519` | Cliente: `~/.ssh/id_ed25519.pub` <br> Servidor: `~/.ssh/authorized_keys` | **Autenticar al Usuario frente al Servidor** mediante firma matemática (*Challenge-Response*) sin enviar contraseñas. |

---

## 2. El Modelo TOFU (`known_hosts`) y la Alerta de Man-in-the-Middle

A diferencia de HTTPS (donde tu navegador confía automáticamente en una Autoridad Certificadora como Let's Encrypt), SSH utiliza por defecto el modelo **TOFU (*Trust On First Use* / Confianza en el Primer Uso)**:

1. **Primera conexión a un servidor nuevo:**
   El cliente `ssh` recibe la llave pública del servidor (`/etc/ssh/ssh_host_ed25519_key.pub`), calcula su huella SHA256 y te pregunta:
   ```text
   The authenticity of host '10.0.1.50 (10.0.1.50)' can't be established.
   ED25519 key fingerprint is SHA256:4bX9...kL2p.
   Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```
2. **Guardado en `~/.ssh/known_hosts`:**
   Al escribir `yes`, el cliente guarda esa asociación (`IP/Host` + `Host Public Key`) en tu archivo local `~/.ssh/known_hosts`.
3. **Conexiones futuras (Verificación automática):**
   Cada vez que volvés a conectarte, el servidor debe demostrar que posee la llave privada correspondiente a esa llave pública guardada en tu `known_hosts`.
4. **¿Qué pasa si cambia la llave del servidor?**
   Si alguien intercepta tu tráfico (ataque **MitM**) o si reinstalaron el servidor desde cero, `ssh` bloquea la conexión con este cartel famoso:
   ```text
   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
   IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
   Someone could be eavesdropping on you right now (man-in-the-middle attack)!
   ```
   * **Acción de SysAdmin:** Si sabés con certeza que vos reinstalaste el servidor, eliminás la huella vieja con:
     ```bash
     ssh-keygen -R 10.0.1.50
     ```
     Si **no** reinstalaste el servidor, **no te conectes**: estás ante una suplantación de red o un cambio no autorizado de infraestructura.

---

## 3. Guía Paso a Paso — Nivel Cliente (`ssh`)

### Paso 1: Generar tu par de llaves de usuario con `ssh-keygen`

Hoy el estándar recomendado para todo entorno moderno es **Ed25519** (curva elíptica de 256 bits: llaves cortas, ultrarrápidas y resistentes a ataques de canal lateral).

```bash
# -t ed25519 : Algoritmo de curva elíptica moderno
# -a 100     : 100 rondas de KDF (bcrypt) para proteger tu llave privada en disco
# -C "..."   : Comentario identificatorio (quién sos y desde qué equipo)
ssh-keygen -t ed25519 -a 100 -C "admin@workstation-sre" -f ~/.ssh/id_ed25519
```

> ⚠️ **Sobre la Passphrase:** Cuando `ssh-keygen` te pide una *passphrase*, esa frase **NO viaja nunca al servidor**. Sirve únicamente para **cifrar simétricamente el archivo `~/.ssh/id_ed25519` en el disco de tu notebook** (en reposo). Si un malware o ladrón copia tu archivo `id_ed25519` sin tener la passphrase, no puede usar la llave.

Esto genera dos archivos en tu máquina cliente:
* `~/.ssh/id_ed25519` ➔ **Llave PRIVADA.** Jamás se comparte ni se sube a ningún servidor.
* `~/.ssh/id_ed25519.pub` ➔ **Llave PÚBLICA.** Es una sola línea de texto (`ssh-ed25519 AAAAC3NzaC... admin@workstation-sre`) que vas a copiar a los servidores.

### Paso 2: Copiar tu llave pública al Servidor (`ssh-copy-id`)

Para autorizar tu llave en un servidor remoto (mientras todavía tiene acceso por contraseña o mediante otra llave previa):

```bash
# Opción A: Automática (crea ~/.ssh, ajusta permisos 700/600 y agrega la llave)
ssh-copy-id -i ~/.ssh/id_ed25519.pub usuario@10.0.1.50

# Opción B: Manual (útil en servidores cloud, contenedores o user_data de Terraform)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Paso 3: Usar `ssh-agent` para no tipear la passphrase cada vez

Para mantener tu llave privada cifrada en disco con passphrase pero no tener que escribirla en cada conexión, usás el demonio en memoria **`ssh-agent`**:

```bash
# 1. Iniciar el agente en tu sesión actual (si tu distro no lo inició ya)
eval "$(ssh-agent -s)"

# 2. Desbloquear tu llave privada en la RAM del agente por 4 horas (14400 seg)
ssh-add -t 14400 ~/.ssh/id_ed25519

# 3. Verificar qué llaves están cargadas en memoria
ssh-add -l
```

### Paso 4: Automatizar tus conexiones con `~/.ssh/config`

Un administrador profesional no escribe `ssh -i ~/.ssh/llave_prod -p 2222 ubuntu@54.210.11.99` cada vez. Configura el archivo `~/.ssh/config` (con permisos `chmod 600 ~/.ssh/config`):

```ssh-config
# ~/.ssh/config — Configuración del Cliente SSH

# Bastión de entrada (Jump Host)
Host bastion
    HostName 54.210.11.99
    User ubuntu
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Servidor privado en subred interna (salta automáticamente por el bastión)
Host db-prod
    HostName 10.20.1.15
    User admin
    ProxyJump bastion
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Reglas globales de seguridad y keep-alive para todos los hosts
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    HashKnownHosts yes
```
Con esto configurado, conectarse a la base de datos privada a través del bastión se reduce a:
```bash
ssh db-prod
```

---

## 4. Guía Paso a Paso — Nivel Servidor (`sshd`) y Permisos Estrictos

Del lado del servidor corre el demonio **`sshd`** (OpenSSH Daemon), cuya configuración vive en `/etc/ssh/sshd_config` y sus llaves de identidad del host viven en `/etc/ssh/ssh_host_*_key`.

### Regla de Oro: Tabla de Permisos Estrictos (`StrictModes yes`)

Por diseño de seguridad, tanto el cliente `ssh` como el servidor `sshd` **se niegan a funcionar** si los archivos de llaves pueden ser leídos o modificados por otros usuarios del sistema:

| Ruta | En dónde | Permiso Octal | Comando | ¿Qué pasa si está más abierto (ej. `644` o `777`)? |
| :--- | :--- | :---: | :--- | :--- |
| `~/.ssh/` | Cliente y Servidor | **`700`** (`drwx------`) | `chmod 700 ~/.ssh` | `sshd` ignora `authorized_keys` por riesgo de inyección de llaves por terceros. |
| `~/.ssh/id_ed25519` | Cliente | **`600`** (`-rw-------`) | `chmod 600 ~/.ssh/id_ed25519` | El cliente aborta con: `WARNING: UNPROTECTED PRIVATE KEY FILE! Permissions 0644 are too open.` |
| `~/.ssh/authorized_keys` | Servidor | **`600`** (`-rw-------`) | `chmod 600 ~/.ssh/authorized_keys` | `sshd` rechaza el login por llave en silencio y cae a pedir password (`Authentication refused: bad ownership or modes`). |
| `~/.ssh/config` | Cliente | **`600`** (`-rw-------`) | `chmod 600 ~/.ssh/config` | `ssh` aborta con `Bad owner or permissions on ~/.ssh/config`. |
| `~/.ssh/id_ed25519.pub` | Cliente | **`644`** (`-rw-r--r--`) | `chmod 644 ~/.ssh/id_ed25519.pub` | Es pública, puede ser `644` o `600`. |
| `/etc/ssh/ssh_host_*_key` | Servidor | **`600`** (`-rw-------`) | `sudo chmod 600 /etc/ssh/ssh_host_*_key` | `sshd` no arranca si sus llaves privadas de host son legibles por usuarios comunes. |

### Hardening de `/etc/ssh/sshd_config` en Producción

Una vez que verificaste que podés entrar con tu llave SSH (`ssh usuario@servidor`), endurecés el servidor editando `/etc/ssh/sshd_config` (o creando `/etc/ssh/sshd_config.d/99-hardening.conf`):

```ssh-config
# /etc/ssh/sshd_config.d/99-hardening.conf

# 1. Autenticación: Solo llaves asimétricas, PROHIBIDO contraseñas por red
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

# 2. Control de Root y permisos estrictos
PermitRootLogin no
StrictModes yes
MaxAuthTries 3

# 3. Criptografía Moderna (Deshabilitar cifrados débiles o legacy)
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

### Flujo seguro para aplicar cambios en `sshd` (¡Sin quedarte afuera!)

1. **Nunca cierres tu terminal actual** mientras editás `sshd_config`.
2. **Validá siempre la sintaxis antes de recargar:**
   ```bash
   sudo sshd -t
   ```
   *(Si no devuelve ninguna salida y su código de retorno es `0`, la configuración es válida).*
3. **Recargá el demonio sin cortar sesiones activas:**
   ```bash
   sudo systemctl reload ssh    # En Debian/Ubuntu (o 'sshd' en RHEL/Rocky)
   ```
4. **Abrí una SEGUNDA terminal** en tu máquina y probá conectarte de nuevo antes de cerrar la primera.

---

## 5. Auditoría Forense y Túneles Cifrados con SSH

### Auditar en vivo qué cifrado se negoció (`ssh -v`)

Cuando ejecutás `ssh -v usuario@servidor`, podés leer exactamente las 3 capas criptográficas en tiempo real:

```text
debug1: kex: algorithm: curve25519-sha256                              <-- Fase 1: KEX Diffie-Hellman Efímero
debug1: kex: host key algorithm: ssh-ed25519                           <-- Fase 1: Identidad del Servidor
debug1: Server host key: ssh-ed25519 SHA256:7xP...                     <-- Fase 1: Huella verificada en known_hosts
debug1: kex: server->client cipher: chacha20-poly1305@openssh.com      <-- Fase 2: Cifrado Simétrico del Túnel
debug1: kex: client->server cipher: chacha20-poly1305@openssh.com      <-- Fase 2: Cifrado Simétrico del Túnel
debug1: Offering public key: ~/.ssh/id_ed25519 ED25519 SHA256:9mK...   <-- Fase 3: Oferta de llave pública de usuario
debug1: Server accepts key: ~/.ssh/id_ed25519 ED25519 SHA256:9mK...    <-- Fase 3: Servidor la encuentra en authorized_keys
Authenticated to servidor ([10.0.1.50]:22) using "publickey".          <-- Fase 3: Firma Challenge-Response exitosa
```

### Túneles Cifrados SSH (Port Forwarding)

Dado que la Fase 2 de SSH construye un **túnel simétrico cifrado** (`chacha20-poly1305` o `aes256-gcm`), podés usar SSH como una "micro-VPN instantánea" para envolver con cifrado cualquier protocolo que viaje en texto plano (como HTTP interno, Redis, PostgreSQL o paneles de monitoreo que escuchan solo en `127.0.0.1` del servidor):

| Tipo de Túnel | Comando | Caso de Uso Típico |
| :--- | :--- | :--- |
| **Local Port Forwarding (`-L`)** | `ssh -N -L 8080:127.0.0.1:9090 user@servidor` | Traer a tu `localhost:8080` un servicio interno del servidor (`127.0.0.1:9090`, ej. Prometheus o una DB) viajando 100% cifrado por SSH. |
| **Remote Port Forwarding (`-R`)** | `ssh -N -R 9000:127.0.0.1:3000 user@servidor` | Exponer un puerto de tu máquina local (`:3000`) en un puerto del servidor remoto (`:9000`). |
| **Dynamic SOCKS5 Proxy (`-D`)** | `ssh -N -D 1080 user@servidor` | Crear un proxy SOCKS5 cifrado en tu `:1080` local para que tu navegador salga a la red a través del servidor SSH. |

---

## 6. WireGuard Paso a Paso: El Estándar Moderno de VPN (y cómo se compara con SSH)

Cuando en lugar de conectar una terminal o tunelizar un puerto específico necesitás **conectar redes enteras o servidores de forma permanente (Capa 3 IP)**, entran en juego las VPNs: **OpenVPN** y **WireGuard**.

### ¿Por qué WireGuard revolucionó el cifrado en tránsito en Linux?

Mientras que **OpenVPN** necesita una Autoridad Certificadora (PKI con `ca.crt`, `server.crt`, `client.crt`) y corre en espacio de usuario (~100.000 líneas de código), **WireGuard** está integrado directamente dentro del **Kernel de Linux** (~4.000 líneas de código) y copia la simplicidad de **SSH**:

* **No usa certificados X.509 ni CA:** Cada nodo genera un simple par de llaves asimétricas (`Curve25519`) exactamente igual que `ssh-keygen` + `authorized_keys`.
* **Crypto-Key Routing:** Asocia directamente cada llave pública de un par (*Peer*) con las direcciones IP permitidas (`AllowedIPs`).
* **Criptografía fija de última generación:** Usa `Curve25519` para intercambio de llaves y `ChaCha20-Poly1305` para cifrar los paquetes IP en tránsito (la misma dupla criptográfica que usa OpenSSH moderno).

### Paso a Paso Rápido de WireGuard (`wg`)

```bash
# 1. Generar la llave privada y derivar la pública (en el Servidor y en el Cliente)
umask 077
wg genkey | tee private.key | wg pubkey > public.key

# 2. Archivo de configuración /etc/wireguard/wg0.conf en el Servidor
cat << 'EOF' > /etc/wireguard/wg0.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = <CONTENIDO_DE_SERVER_PRIVATE_KEY>

[Peer]
# Cliente autorizado (igual que una línea en ~/.ssh/authorized_keys)
PublicKey = <CONTENIDO_DE_CLIENT_PUBLIC_KEY>
AllowedIPs = 10.8.0.2/32
EOF

# 3. Levantar la interfaz cifrada wg0
sudo wg-quick up wg0
sudo wg show
```

---

## 7. Tabla Comparativa Global de Arquitecturas de Cifrado (En Reposo y En Tránsito)

Para consolidar todos los temas de cifrado del curso en un único mapa mental, esta tabla compara las tecnologías de **Cifrado en Reposo (Data-at-Rest)** y **Cifrado en Tránsito (Data-in-Transit)**:

| Tecnología | Ámbito | Capa donde opera | Cifrado Simétrico (Datos) | Criptografía Asimétrica (Identidad / KEX) | Archivos Clave en Linux | Caso de Uso Ideal |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **SSH (OpenSSH)** | **En Tránsito** | Aplicación / Sesión TCP (`:22`) | **Sí** (`ChaCha20-Poly1305` o `AES-256-GCM` con *Session Key* efímera) | **Doble:** Host Key del servidor + User Key del cliente (`Ed25519` + KEX `Curve25519`) | Cliente: `~/.ssh/id_ed25519`, `~/.ssh/known_hosts`<br>Servidor: `/etc/ssh/ssh_host_*`, `~/.ssh/authorized_keys` | Administración remota segura, transferencia de archivos (`scp`/`sftp`/`rsync`) y túneles puntuales de puertos (`ssh -L`). |
| **WireGuard** | **En Tránsito** | Red L3 (Módulo del Kernel Linux, UDP `:51820`) | **Sí** (`ChaCha20-Poly1305` con llaves efímeras rotativas) | **Sí** (Pares de llaves `Curve25519` por nodo vía *Crypto-Key Routing*, sin CA) | `/etc/wireguard/wg0.conf` (`PrivateKey` local + `PublicKey` de cada `[Peer]`) | VPN de alto rendimiento entre servidores, nodos cloud/on-prem y acceso remoto de baja latencia. |
| **OpenVPN (mTLS)** | **En Tránsito** | Red L2/L3 (Espacio de usuario `tun0`/`tap0`) | **Sí** (`AES-256-GCM` por canal de datos TLS) | **Sí** (PKI completa con Certificados X.509 firmados por una CA + `tls-crypt`) | `ca.crt`, `server.crt`, `server.key`, `client.crt`, `client.key`, `ta.key` | VPN corporativa con muchos usuarios donde se requiere revocación centralizada de certificados (CRL) o TCP fallback. |
| **HTTPS / TLS 1.3** | **En Tránsito** | Transporte / Aplicación (`:443`) | **Sí** (`AES-256-GCM` o `ChaCha20-Poly1305` por sesión) | **Sí** (Certificado X.509 del servidor firmado por CA pública + ECDHE) | `/etc/letsencrypt/live/<dominio>/fullchain.pem` y `privkey.pem` | Tráfico web público, APIs REST/gRPC, ingress controllers y microservicios. |
| **LUKS2 (`dm-crypt`)** | **En Reposo** | Bloque de Disco / Kernel (`dm-crypt`) | **Sí** (`AES-256-XTS` con Master Key protegida por Argon2id) | **No** (salvo desbloqueo automático con chip TPM2 / Clevis) | Cabecera binaria en la partición (`/dev/sdX`) y `/etc/crypttab` | Cifrado completo de discos, laptops, volúmenes de bases de datos y servidores físicos/cloud. |
| **gocryptfs / fscrypt** | **En Reposo** | Sistema de Archivos (Directorio FUSE / VFS) | **Sí** (`AES-256-GCM` por archivo individual + nombres cifrados) | **No** | `gocryptfs.conf` y `gocryptfs.diriv` dentro de la carpeta cifrada | Sincronización segura de carpetas en la nube (Nextcloud, S3, Dropbox) o directorios multiusuario. |
| **GPG (`gpg`) / `age`** | **En Reposo (y Envío)** | Archivo Individual / Paquete | **Sí** (`AES-256` o `ChaCha20` con clave de sesión por archivo) | **Sí** (`Ed25519`/`Cv25519` o `RSA` para cifrar la clave del archivo y firmar) | `~/.gnupg/` o archivos `.gpg` / `.age` / `.asc` | Backups exportables, envío de secretos a terceros, firma de commits de Git y paquetes `.deb`/`.rpm`. |

---

## 8. Práctica Guiada en Vivo (`demo_ssh_cifrado.sh`)

Para experimentar todos estos mecanismos en tu propia terminal sin tocar la configuración real de tu sistema, ejecutá el script interactivo incluido en este directorio:

```bash
cd linux/administrator/cifrado
./demo_ssh_cifrado.sh
```

El laboratorio ejecuta **5 escenarios reales paso a paso** en un entorno temporal aislado (`/tmp/demo_ssh_*`) y limpia todos los procesos al salir:
1. **Anatomía Criptográfica (Servidor y Cliente):** Genera las *Host Keys* de un servidor (`ssh_host_ed25519_key`) y las *User Keys* de un cliente (`id_ed25519`), e inicia un demonio **`sshd` real aislado** en un puerto local alto.
2. **Auditoría del Handshake en Vivo (`ssh -v`):** Realiza una conexión SSH real contra ese `sshd` capturando las 3 fases (TOFU en `known_hosts`, KEX `curve25519-sha256`, cifrado simétrico `chacha20-poly1305` y autenticación `publickey` contra `authorized_keys`).
3. **Fallo Real por Permisos Abiertos (`chmod 644`):** Rompe deliberadamente los permisos de la llave privada y de `authorized_keys` para observar cómo SSH bloquea la autenticación (`UNPROTECTED PRIVATE KEY FILE!`) y lo repara con `chmod 600`.
4. **Simulación de Ataque Man-in-the-Middle (Cambio de Host Key):** Reemplaza la llave de identidad del servidor `sshd` para disparar en vivo la alerta `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` y muestra cómo auditarla y resolverla con `ssh-keygen -R`.
5. **Túnel Cifrado SSH (`ssh -L`) y Criptografía WireGuard:** Levanta un microservicio HTTP interno, construye un túnel cifrado SSH Local Port Forwarding para consumirlo de forma segura, y genera una configuración par-a-par de **WireGuard** (`Curve25519` + `ChaCha20-Poly1305`) comparándola con SSH.
