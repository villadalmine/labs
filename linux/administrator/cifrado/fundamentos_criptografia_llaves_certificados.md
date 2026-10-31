---
id: lab-3.3-fundamentos-criptografia-llaves
title: 'Fundamentos de Criptografía, Llaves y Certificados en Linux: Simétrica vs Asimétrica, Autenticación vs Cifrado (SSH, AWS EC2, OpenVPN, TLS, LUKS, GPG)'
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
- criptografia
- llaves
- simetrica
- asimetrica
- ssh
- ec2
- openvpn
- tls
- luks
- gocryptfs
- gpg
- certificados
tools:
- openssl
- ssh-keygen
- sha256sum
- cryptsetup
- gocryptfs
- gpg
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
  test_date: '2026-10-31'
  notes: Demostración interactiva probada de punta a punta con demo_criptografia_llaves.sh (simétrica, asimétrica, challenge-response SSH y firmas).
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-31'
  notes: Validación de autenticación por llave pública en SSH/cloud-init y comparación con claves en reposo (LUKS/gocryptfs).
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: 'Guía pedagógica maestra y laboratorio práctico sobre los fundamentos de
  criptografía en Linux y la resolución de la confusión sobre el término llaves (keys).
  Diferencia con rigor los tres objetivos de seguridad: Confidencialidad (cifrado),
  Autenticación (identidad) e Integridad/No Repudio (firma digital). Analiza la distinción
  matemática y de rendimiento entre Criptografía Simétrica (AES, ChaCha20) y Criptografía
  Asimétrica (RSA, Ed25519, Curve25519), explicando por qué los protocolos modernos
  (SSH, HTTPS/TLS, OpenVPN, WireGuard) son de naturaleza Híbrida. Contiene una matriz
  comparativa exhaustiva de 10 tecnologías donde se utiliza el concepto de llave (SSH,
  AWS EC2 Key Pairs, HTTPS, OpenVPN PKI/PSK, LUKS2, gocryptfs, GPG, API Keys), diagramas
  de secuencia del mecanismo Challenge-Response y un script interactivo para experimentar
  en terminal cada flujo criptográfico.'
files:
  guide: cifrado/fundamentos_criptografia_llaves_certificados.md
  script: cifrado/demo_criptografia_llaves.sh
  terraform: null
prerequisites:
- lab-1.1-jobs-multiplexores
next_recommended_labs:
- lab-3.3.0-cifrado-arquitecturas-comparativa
- lab-3.3-cifrado-luks
- lab-3.4-cifrado-fuse-gocryptfs
- lab-3.4b-gpg-firmas-repositorios-backups
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Fundamentos de Criptografía, Llaves y Certificados en Linux: El Enigma de las "Keys"

> **¿Por qué uso una "key" para conectarme a AWS EC2 o SSH, otra "key" en mi cliente de OpenVPN, otra "key" en LUKS y gocryptfs, y otra en HTTPS? ¿Son todas lo mismo?**

En el aprendizaje de administración de sistemas, redes y DevOps, pocos términos generan tanta confusión como la palabra **"llave"** (*key*). La razón es un problema de sobrecarga de vocabulario: la industria utiliza la misma palabra para referirse a **mecanismos matemáticos y objetivos de seguridad completamente diferentes**.

Esta guía desmitifica el concepto desde la raíz teórica hasta la práctica en terminal, proporcionando analogías claras, diagramas de flujo y una matriz comparativa definitiva.

---

## 1. Los Tres Objetivos Criptográficos: La Gran Distinción

Antes de hablar de algoritmos o archivos, es fundamental entender que una llave en informática se utiliza para **uno o más de estos tres objetivos independientes**:

```
                       ┌────────────────────────────────────────────────────────┐
                       │          LOS 3 PILARES CRIPTOGRÁFICOS                   │
                       └────────────────────────────────────────────────────────┘
                               /                    │                     \
                              /                     │                      \
                             ▼                      ▼                       ▼
                  ┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐
                  │ 1. CONFIDENCIALIDAD│ │  2. AUTENTICACIÓN  │ │ 3. INTEGRIDAD Y NO │
                  │     (CIFRADO)      │ │    (IDENTIDAD)     │ │      REPUDIO       │
                  ├────────────────────┤ ├────────────────────┤ ├────────────────────┤
                  │ ¿Qué busca?        │ │ ¿Qué busca?        │ │ ¿Qué busca?        │
                  │ Que NADIE pueda    │ │ Demostrar QUIÉN    │ │ Que NADIE pueda    │
                  │ leer los datos     │ │ SOY ante el server │ │ alterar un archivo │
                  │ excepto el dueño.  │ │ sin revelar mi     │ │ y probar quién lo  │
                  │                    │ │ secreto.           │ │ creó.              │
                  ├────────────────────┤ ├────────────────────┤ ├────────────────────┤
                  │ Ejemplos:          │ │ Ejemplos:          │ │ Ejemplos:          │
                  │ - LUKS2 (dm-crypt) │ │ - SSH (id_ed25519) │ │ - Firmas GPG en    │
                  │ - gocryptfs (FUSE) │ │ - AWS EC2 (.pem)   │ │   repositorios APT │
                  │ - Cifrado AES en   │ │ - Clientes OpenVPN │ │ - Git commit       │
                  │   túnel VPN/HTTPS  │ │   (client.crt/key) │ │   signing          │
                  └────────────────────┘ └────────────────────┘ └────────────────────┘
```

> [!IMPORTANT]
> **Regla de oro:**
> - Cuando usas una llave en **LUKS** o **gocryptfs**, estás buscando **Confidencialidad** (cifrar bits en disco).
> - Cuando usas una llave en **SSH**, **AWS EC2** u **OpenVPN**, estás buscando **Autenticación** (probar quién eres para que te dejen entrar).
> - Y cuando navegas en **HTTPS**, estás usando criptografía **Híbrida** para lograr **Autenticación + Confidencialidad** simultáneas.

---

## 2. Las Dos Familias Criptográficas: Simétrica vs Asimétrica

### 2.1 Criptografía Simétrica (La Caja Fuerte con una Única Llave)

En la criptografía simétrica, existe **una sola llave secreta compartida**. La misma llave que se usa para transformar el texto legible (*plaintext*) en texto cifrado (*ciphertext*), es la que se utiliza para revertir el proceso.

```
Texto Plano ("Hola") ──► [ Cifrado AES-256 con Clave 'K' ] ──► Bytes Ilegibles (#$!%&)
                                                                       │
Bytes Ilegibles (#$!%&) ──► [ Descifrado AES-256 con Clave 'K' ] ──► Texto Plano ("Hola")
```

#### 💡 Analogía Didáctica:
Imagina una **caja fuerte clásica con cerradura física**. Tú y tu socio tienen una copia idéntica de la misma llave de bronce. Tú cierras la caja con la llave y se la envías. Tu socio usa su copia para abrirla.

* **Ventajas:**
  - **Velocidad colosal:** Puede procesar gigabytes por segundo con casi 0% de uso de CPU gracias a extensiones de hardware en los procesadores modernos (**AES-NI** en Intel/AMD o criptografía acelerada en ARM).
  - Algoritmos estándar: **AES-256-GCM**, **ChaCha20-Poly1305**, **AES-XTS-512**.
* **El Gran Problema (*Key Distribution Problem*):**
  - ¿Cómo le envías la llave a tu socio si vive en Japón y nunca se vieron en persona? Si se la mandas por correo electrónico o WhatsApp, un espía puede interceptar la llave y abrir la caja fuerte. **La criptografía simétrica no resuelve el intercambio seguro a distancia**.

---

### 2.2 Criptografía Asimétrica (El Candado Abierto y el Buzón Público)

En la criptografía asimétrica, no existe una sola llave, sino un **par matemático inseparable de llaves complementarias**:

1. **Clave Pública (*Public Key*):** Es de libre distribución. Puedes publicarla en tu perfil de GitHub, Twitter o enviarla por email. No compromete la seguridad.
2. **Clave Privada (*Private Key*):** Es estrictamente confidencial. **NUNCA debe abandonar tu computadora**, jamás se envía por la red ni se comparte con administradores.

La matemática subyacente (curvas elípticas Ed25519/Curve25519 o factorización de primos RSA) impone una propiedad asimétrica:

```
[Clave Pública] ────────► Solo CIFRA o VERIFICA
[Clave Privada] ────────► Solo DESCIFRA o FIRMA
```

#### 💡 Analogía Didáctica:
Imagina un **buzón de correos público en la puerta de tu casa**:
- **Clave Pública:** Es la ranura del buzón. Cualquier persona que pase por la calle puede meter una carta adentro. Meter la carta equivale a *cifrar*.
- **Clave Privada:** Es la llave física de la puerta trasera del buzón. Solo tú la tienes en el bolsillo. Nadie en la calle puede sacar las cartas; solo tú puedes abrir la puerta y leerlas.
- **Firma Digital (al revés):** Tú firmas un documento con un sello de lacre único que solo tú posees (Clave Privada). Todo el mundo tiene una foto de cómo debe verse tu sello (Clave Pública). Si alguien ve tu sello intacto en la carta, sabe con 100% de certeza matemática que la escribiste tú y que nadie modificó el contenido.

* **Ventajas:**
  - Resuelve el problema de distribución: No importa si el canal de comunicación es inseguro; puedes entregar tu clave pública a viva voz.
  - Permite **Firmas Digitales** y **Autenticación sin Contraseñas**.
* **Desventajas:**
  - **Extremadamente lenta:** Realizar operaciones matemáticas asimétricas es entre **1.000 y 10.000 veces más lento** que el cifrado simétrico AES.
  - Si intentaras cifrar una película de 4 GB con una clave pública RSA o Ed25519, tu procesador colapsaría por horas y el tamaño del archivo se dispararía.

---

### 2.3 Comparativa Técnica: Simétrica vs Asimétrica

| Propiedad | Criptografía Simétrica | Criptografía Asimétrica |
| :--- | :--- | :--- |
| **Cantidad de Llaves** | **1 sola llave secreta** (compartida). | **2 llaves complementarias** (Pública + Privada). |
| **Algoritmos Comunes** | AES-128/256 (GCM, XTS, CBC), ChaCha20. | RSA (2048/4096), Ed25519, ECDSA, Curve25519. |
| **Velocidad de Cómputo** | **Ultrarrápida** (GB/s con aceleración AES-NI). | **Muy lenta** (adecuada para bloques de bytes minúsculos). |
| **Uso Principal** | Cifrado masivo de datos en reposo y tránsito. | Autenticación de identidad, firmas y acuerdos de claves. |
| **Dónde lo ves en Linux** | `LUKS2`, `gocryptfs`, carga útil de `OpenVPN`/`HTTPS`. | `SSH (id_ed25519)`, `AWS EC2`, `GPG`, certificados TLS. |

---

## 3. El Gran Secreto de Internet: Criptografía Híbrida

¿Cómo hace un servidor web para enviar gigabytes de video cifrado por HTTPS si la criptografía asimétrica es tan lenta y la simétrica no puede compartir claves de forma segura?

La respuesta es la **Criptografía Híbrida**: combinar lo mejor de ambos mundos.

```
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║                               PROTOCOLO HÍBRIDO (TLS / SSH)                                  ║
╠══════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                              ║
║  1. FASE DE APRETÓN DE MANOS (HANDSHAKE) - Lenta, usa Criptografía Asimétrica:              ║
║     Cliente ─────────────── [¿Quién sos? ¿Me das tu Clave Pública?] ─────────────► Servidor  ║
║     Cliente ◄────────────── [Soy banco.com, acá está mi Certificado X.509] ─────── Servidor  ║
║                                                                                              ║
║  2. ACUERDO DE CLAVE EFÍMERA (Diffie-Hellman / ECDH):                                        ║
║     Ambos nodos calculan matemáticamente una CLAVE SIMÉTRICA TEMPORAL ("Session Key")        ║
║     sin enviarla jamás por el cable.                                                         ║
║                                                                                              ║
║  3. FASE DE TRANSFERENCIA DE DATOS (BULK DATA) - Ultrarrápida, usa Criptografía Simétrica:   ║
║     Cliente ═══════════ [Tráfico cifrado a 10 Gbps con AES-256-GCM] ══════════════ Servidor  ║
║                                                                                              ║
║  4. CIERRE DE CONEXIÓN (Forward Secrecy):                                                    ║
║     La clave de sesión simétrica se BORRA de la memoria RAM.                                 ║
╚══════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 4. Matriz Comparativa Definitiva: Las 10 "Keys" de la Infraestructura

Esta tabla responde directamente la duda recurrente de clase: **¿Qué hace exactamente la "llave" en cada tecnología?**

| Tecnología / Herramienta | Tipo de Llave | ¿Qué objetivo cumple la llave? | ¿Dónde vive la llave? | Formato de archivo común | ¿Qué ocurre si la llave privada o secreta se filtra? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SSH (`id_ed25519`)** | Asimétrica (Par) | **Autenticación (Identidad)**. La clave privada firma un desafío para probar quién eres sin enviar la clave. | Privada en cliente (`~/.ssh/id_*`), Pública en servidor (`~/.ssh/authorized_keys`). | OpenSSH private key (`BEGIN OPENSSH PRIVATE KEY`) | Un atacante puede iniciar sesión interactiva como tu usuario en el servidor. |
| **AWS EC2 Key Pair (`.pem`)** | Asimétrica (Par) | **Autenticación SSH (Aprovisionamiento inicial)**. Es exactamente una clave SSH pública inyectada por AWS en `/home/ubuntu/.ssh/authorized_keys` vía `cloud-init`. AWS **nunca almacena tu clave privada**. | Privada en tu PC (`id_ed25519.pem`), Pública registrada en la API de AWS. | PEM (`BEGIN RSA PRIVATE KEY` o `BEGIN OPENSSH PRIVATE KEY`) | Acceso SSH como usuario root/ubuntu a todas las instancias EC2 que compartan esa clave. |
| **HTTPS / TLS (`cert.pem`, `privkey.pem`)** | Asimétrica + PKI (X.509) | **Autenticación del Servidor + Acuerdo de Cifrado Simétrico**. El certificado prueba que el servidor es quien dice ser (avalado por Let's Encrypt o DigiCert). | Privada en servidor (`/etc/letsencrypt/live/...`), Certificado público entregado a todo visitante web. | X.509 PEM (`.crt`, `.pem`, `.cer`) | Ataques *Man-in-the-Middle* (MitM) y suplantación de la identidad del sitio web. |
| **OpenVPN (Mutual TLS / PKI)** | Asimétrica Bidireccional | **Autenticación Mutua**. Tanto el servidor como el cliente tienen un par de claves y certificados firmados por una CA común (`ca.crt`). Ningún cliente no firmado puede conectarse. | En cliente: `client.crt` + `client.key`. En servidor: `server.crt` + `server.key` + `ca.crt`. | `.ovpn` (perfil consolidado con bloques `<cert>`, `<key>`, `<ca>`) | Un atacante puede conectarse a la red VPN interna de la empresa como si fuera un empleado autorizado. |
| **OpenVPN (Static Key / PSK)** | Simétrica pura | **Autenticación y Cifrado Simétrico**. Un único archivo secreto compartido se instala en servidor y clientes. | Archivo con permisos `600` en servidor y cliente (`ta.key` o `secret.key`). | `.key` (2048-bit static OpenVPN key) | Si un solo cliente es comprometido, **toda la VPN queda desprotegida** y debe regenerarse para todos los usuarios. |
| **LUKS2 (dm-crypt)** | Simétrica pura (Master Key binaria) + Keyslots | **Confidencialidad de Almacenamiento en Reposo**. Una *Master Key* simétrica aleatoria de 512 bits cifra los bloques físicos del disco. Tu contraseña o token TPM solo sirve para descifrar esa Master Key en la RAM. | Cabecera del disco (en los sectores de metadatos LUKS2) y memoria RAM del kernel mientras está abierto. | Metadatos binarios en el bloque crudo (`/dev/sdX`). | Acceso forense en frío a todos los datos del disco. |
| **gocryptfs (FUSE)** | Simétrica a nivel de archivo (AES-GCM + EME) | **Confidencialidad en Reposo a nivel de Filesystem**. Una Master Key cifra individualmente los nombres (EME) y los contenidos (GCM) de cada archivo en espacio de usuario. | Archivo `gocryptfs.conf` (cabecera cifrada) y memoria del proceso en espacio de usuario. | `gocryptfs.conf`, `gocryptfs.diriv` | Acceso a los archivos descifrados dentro del directorio protegido. |
| **GPG / PGP (Email, Backups, APT)** | Asimétrica (Clave primaria + Subclaves) | **Confidencialidad (Cifrado asimétrico) Y Firma Digital (Integridad y no repudio)**. Permite cifrar un backup para un sysadmin y firmar paquetes `.deb` para que `apt` valide que no fueron hackeados. | Anillo de claves local (`~/.gnupg/`) y almacén de confianza del sistema (`/etc/apt/keyrings/`). | `.gpg` binario, `.asc` (Armored ASCII) | Lectura de respaldos cifrados o capacidad de emitir paquetes y commits firmados ilegítimamente. |
| **WireGuard** | Asimétrica (Curve25519) + Noise Protocol | **Identidad de Red (Crypto-Key Routing) y Cifrado**. Cada interfaz de red tiene una clave privada; la IP virtual del túnel está matemáticamente asociada a la clave pública del peer. | Archivo de configuración `/etc/wireguard/wg0.conf` (chmod 600). | Cadenas base64 de 32 bytes (44 caracteres) | Tráfico interceptado y suplantación del nodo en la red mesh. |
| **API Keys / Bearer Tokens** | Secreto compartido (Token de aplicación) | **Identificación y Autorización en Capa 7 (HTTP)**. No cifra datos; es simplemente una credencial que viaja en el encabezado `Authorization: Bearer <token>`. Depende 100% de que la capa inferior use HTTPS. | Variables de entorno (`.env`), Secrets Managers (AWS Secrets Manager, HashiCorp Vault). | Strings alfanuméricos / JWT (JSON Web Tokens) | Uso no autorizado de APIs, consumo de saldo en la nube o robo de datos de negocio. |

---

## 5. Análisis Forense de los Casos Clave

### 5.1 Caso 1: ¿Qué pasa cuando ejecutas `ssh -i id_ed25519 ubuntu@54.78.111.148`?

Muchos estudiantes asumen erróneamente que la clave privada `id_ed25519` viaja por la red hacia el servidor. **Esto es falso y rompería el principio fundamental de la criptografía asimétrica.**

El mecanismo real se llama **Challenge-Response (Reto-Respuesta)**:

```
  Tu Máquina (Cliente SSH)                           Servidor SSH (sshd en AWS)
┌────────────────────────────┐                     ┌────────────────────────────┐
│ Clave Privada: id_ed25519  │                     │ Clave Pública autorizada:  │
│ (Permisos 600, NUNCA sale) │                     │ ~/.ssh/authorized_keys     │
└─────────────┬──────────────┘                     └─────────────┬──────────────┘
              │                                                  │
              │  1. "Hola, quiero autenticarme como 'ubuntu'"    │
              ├─────────────────────────────────────────────────►│
              │                                                  │
              │  2. "Perfecto. Te lanzo un RETO: un string       │
              │      aleatorio de 256 bits: 'X9F2#A8!'"          │
              │◄─────────────────────────────────────────────────┤
              │                                                  │
              │  3. El cliente toma el string 'X9F2#A8!' y lo    │
              │     FIRMA criptográficamente con id_ed25519.     │
              │     Envía la firma resultante.                   │
              ├─────────────────────────────────────────────────►│
              │                                                  │
              │                                  4. El servidor busca la clave  │
              │                                     pública en authorized_keys  │
              │                                     y VERIFICA matemáticamente  │
              │                                     la firma del reto.          │
              │                                                  │
              │  5. "Firma válida. Bienvenido a la terminal."    │
              │◄─────────────────────────────────────────────────┤
```

> [!TIP]
> **¿Por qué la clave privada nunca se envía?**
> Porque el servidor no necesita tener tu clave privada para saber que la tienes. Solo necesita que resuelvas un reto matemático que **únicamente el poseedor de la clave privada puede resolver**.

---

### 5.2 Caso 2: ¿Por qué AWS EC2 te obliga a crear un Key Pair `.pem`?

Cuando creas una máquina virtual en AWS EC2:
1. AWS genera un par de claves (o tú subes tu propia clave pública).
2. AWS te entrega el archivo `.pem` (que es la **clave privada**) para que lo descargues **una única vez**. AWS **destruye de sus sistemas su copia de la clave privada**.
3. Al encender la instancia por primera vez, el servicio interno de metadatos de AWS y el demonio **`cloud-init`** inyectan la **clave pública** dentro de `/home/ubuntu/.ssh/authorized_keys`.
4. Cuando haces `ssh -i id_ed25519.pem ubuntu@<IP>`, se ejecuta exactamente el proceso de Challenge-Response del Caso 1.

---

### 5.3 Caso 3: ¿Por qué en OpenVPN hay `ca.crt`, `client.crt` y `client.key`?

A diferencia de SSH, donde cada servidor tiene su lista manual `authorized_keys`, una empresa con 1.000 empleados no puede actualizar un archivo de texto en el servidor cada vez que entra un trabajador nuevo.

OpenVPN resuelve esto utilizando una **Autoridad Certificadora (CA) interna**:

```
                       ┌────────────────────────────────────────┐
                       │     Autoridad Certificadora (CA)       │
                       │             (ca.crt / ca.key)          │
                       └───────────────────┬────────────────────┘
                                          / \
             Firma el certificado del    /   \   Firma el certificado del
             servidor con ca.key        /     \  empleado con ca.key
                                       ▼       ▼
                       ┌────────────────┐     ┌────────────────┐
                       │  Servidor VPN  │     │   Cliente VPN  │
                       │   server.crt   │     │   client.crt   │
                       │   server.key   │     │   client.key   │
                       └────────────────┘     └────────────────┘
```

1. **El cliente se conecta:** El servidor le presenta `server.crt`. El cliente revisa: *"¿Este certificado está firmado por la `ca.crt` de mi empresa? Sí. Entonces estoy conectado al servidor real y no a un impostor"*.
2. **El servidor exige identidad (Mutual TLS):** El servidor le pide `client.crt` al cliente. El servidor revisa: *"¿Este certificado está firmado por la `ca.crt` de mi empresa? Sí. Entonces es un empleado autorizado"*.
3. **El túnel se arma:** Ambas partes intercambian una clave efímera simétrica y todo el tráfico de la VPN viaja cifrado a velocidad nativa con **AES-256-GCM**.

---

### 5.4 Caso 4: ¿Por qué LUKS no cifra el disco con tu contraseña? (La Arquitectura de Keyslots)

Cuando configuras LUKS con `cryptsetup luksFormat /dev/sdb`, muchos creen que el algoritmo AES cifra los sectores usando tu contraseña *"MiClaveSecreta123"*.

**Si fuera así, cambiar tu contraseña requeriría leer, descifrar y volver a escribir 1 Terabyte de disco completo (tardaría 3 horas).**

En realidad, LUKS funciona con **dos niveles de llaves**:

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      DISPOSITIVO CIFRADO CON LUKS                      │
 ├────────────────────────────────────────────────────────────────────────┤
 │ CABECERA DEL DISCO (Metadatos):                                        │
 │                                                                        │
 │  [Keyslot 0] ── Contraseña del Admin ──┐                              │
 │  [Keyslot 1] ── Llave USB de Respaldo ──┼──► Descifra la               │
 │  [Keyslot 2] ── Chip TPM2 / Clevis ────┤    MASTER KEY BINARIA (512b)  │
 │  [Keyslot 3] ── Vacío                  │              │                │
 │  ...                                   │              │                │
 ├────────────────────────────────────────┤              ▼                │
 │ ÁREA DE DATOS DEL DISCO:               │    Cifra y descifra los       │
 │ Sectores físicos (/dev/sdb) ◄──────────┴─── bloques en memoria RAM     │
 │                                             usando AES-XTS-512         │
 └────────────────────────────────────────────────────────────────────────┘
```

1. **La Master Key:** Al formatear, el kernel genera una clave binaria aleatoria de 512 bits de altísima entropía. **Esta es la única clave que realmente cifra los datos.**
2. **Los Keyslots (0 al 31):** Tu contraseña simplemente cifra una copia de la *Master Key*.
3. **Cambiar la clave toma 0.1 segundos:** Cuando cambias tu clave con `luksChangeKey`, LUKS solo descifra la Master Key en memoria, la vuelve a cifrar con tu nueva contraseña y sobrescribe los 4 KB del Keyslot en la cabecera. Los terabytes de datos en el disco no se tocan.

---

## 6. Laboratorio Práctico en Terminal: Experimentando con Criptografía

Para fijar estos conceptos de forma indeleble, dispones del script interactivo [`demo_criptografia_llaves.sh`](demo_criptografia_llaves.sh).

### Ejecución del Laboratorio Educativo:

```bash
# Modo interactivo (pausa explicativa con [ENTER] en cada paso):
./demo_criptografia_llaves.sh

# Modo automático (para ver la demostración corrida):
./demo_criptografia_llaves.sh --auto 3
```

### Qué demuestra el script paso a paso:
1. **Etapa 1: Cifrado Simétrico con OpenSSL (AES-256):** Verás cómo una única clave cifra y descifra un secreto, y cómo alterar un solo bit del archivo cifrado destruye completamente el texto descifrado (*Efecto Avalancha*).
2. **Etapa 2: Criptografía Asimétrica (Par Ed25519 / RSA):** Generación de pares pública/privada, cifrado exclusivo con la clave pública y comprobación de que es matemáticamente imposible descifrarlo sin la clave privada.
3. **Etapa 3: El Mecanismo Challenge-Response de SSH y AWS EC2:** Simulación en vivo en terminal de cómo un servidor genera un desafío aleatorio, el cliente lo firma con su clave privada, y el servidor valida la firma usando únicamente la clave pública de `authorized_keys`.
4. **Etapa 4: Firma Digital y Detección Forense de Manipulación (*Tamper Detection*):** Firma de un archivo con clave privada, modificación fraudulenta de un solo carácter en el archivo, y comprobación de cómo `openssl dgst -verify` detecta el fraude al instante.
5. **Etapa 5: Criptografía Híbrida en Acción:** Simulación de un acuerdo de clave efímera y posterior transferencia ultrarrápida cifrada.

---

## 7. Preguntas de Autoevaluación y Entrevistas Técnicas (SRE / Sysadmin)

1. **¿Por qué nunca se debe subir un archivo `.pem` o `id_rsa` a un repositorio Git ni enviarlo por Slack, pero sí es seguro subir `id_rsa.pub`?**
   - *Respuesta:* Porque la clave privada permite firmar retos y suplantar tu identidad en cualquier servidor. La clave pública solo permite verificar firmas o cifrar mensajes dirigidos a ti; no revela ninguna información sobre la privada.
2. **Si dos personas usan la misma clave privada SSH para entrar a un servidor, ¿puede el administrador saber en los logs quién fue exactamente?**
   - *Respuesta:* No. La criptografía asimétrica autentica la posesión matemática de la clave, no a la persona biológica. Si la clave se comparte, se destruye el **No Repudio**. Por eso cada ingeniero debe tener su propio par de claves y su propia línea en `authorized_keys`.
3. **En OpenVPN, si un empleado renuncia a la empresa, ¿cómo se le revoca el acceso sin cambiar la clave de los demás 500 empleados?**
   - *Respuesta:* En un esquema de PKI con certificados individuales, la Autoridad Certificadora emite una Lista de Revocación de Certificados (**CRL** - *Certificate Revocation List*). El servidor VPN consulta la CRL y rechaza las conexiones de ese certificado específico, sin afectar a los demás.
4. **¿Por qué LUKS usa criptografía simétrica (AES-XTS) en vez de asimétrica (RSA o Ed25519) para proteger los discos rígidos?**
   - *Respuesta:* Por dos motivos críticos: 1) **Rendimiento:** El disco necesita transferir gigabytes por segundo con latencias de microsegundos; RSA sería miles de veces más lento. 2) **Naturaleza del problema:** En un disco local no hay problema de distribución de claves a través de una red hostil; el único que necesita leer y escribir los sectores es el kernel local.

---

## 8. Enlaces de Documentación Oficial

* **OpenSSH Protocol Architecture:** [openssh.com/specs.html](https://www.openssh.com/specs.html)
* **OpenSSL Cryptography Manual:** [openssl.org/docs](https://www.openssl.org/docs/)
* **RFC 8446 - The Transport Layer Security (TLS) Protocol Version 1.3:** [datatracker.ietf.org/doc/html/rfc8446](https://datatracker.ietf.org/doc/html/rfc8446)
* **OpenVPN Security Overview & PKI:** [openvpn.net/community-resources/overview-of-openvpn-security-features/](https://openvpn.net/community-resources/overview-of-openvpn-security-features/)
* **Kernel Device-Mapper Crypt (dm-crypt):** [docs.kernel.org/admin-guide/device-mapper/dm-crypt.html](https://docs.kernel.org/admin-guide/device-mapper/dm-crypt.html)
* **WireGuard Cryptography & Noise Protocol:** [wireguard.com/papers/wireguard.pdf](https://www.wireguard.com/papers/wireguard.pdf)
