#!/usr/bin/env bash
# ==============================================================================
# LABORATORIO INTERACTIVO: ARQUITECTURA DE CIFRADO EN SSH (CLIENTE/SERVIDOR),
#                          TÚNELES CIFRADOS Y WIREGUARD
# ==============================================================================
# Guía asociada: ssh_cifrado_cliente_servidor_wireguard.md
#
# Uso:
#   ./demo_ssh_cifrado.sh             # Modo interactivo paso a paso (espera ENTER)
#   ./demo_ssh_cifrado.sh --auto [s]  # Modo automático con pausa de [s] segundos
# ==============================================================================

set -euo pipefail

# --- Configuración de modo (Interactivo vs Auto / Clean) ----------------------
AUTO_MODE=false
PAUSE_SEC=2
CLEAN_ONLY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            PAUSE_SEC="${2:-2}"
            shift 2
            ;;
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Uso: ./demo_ssh_cifrado.sh [--auto <segundos>] [--clean|--limpiar]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- Colores y Formato Visual -------------------------------------------------
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"
C_CYAN="\033[1;36m"

# --- Directorio Temporal y Procesos Aislados (Self-Cleaning) ------------------
WORK_DIR=$(mktemp -d /tmp/demo_ssh_cifrado.XXXXXX)
SSHD_PID=""
HTTP_PID=""
TUNNEL_PID=""

cleanup() {
    echo -e "\n${C_YELLOW}🧹 Limpiando procesos efímeros (sshd, túneles, servidor HTTP) y directorio ${WORK_DIR}...${C_RESET}"
    for pid_var in "$TUNNEL_PID" "$HTTP_PID" "$SSHD_PID"; do
        if [[ -n "$pid_var" ]] && kill -0 "$pid_var" 2>/dev/null; then
            kill "$pid_var" 2>/dev/null || true
            wait "$pid_var" 2>/dev/null || true
        fi
    done
    if [[ -f "${WORK_DIR}/server/sshd.pid" ]]; then
        local fpid
        fpid=$(cat "${WORK_DIR}/server/sshd.pid" 2>/dev/null || true)
        if [[ -n "$fpid" ]] && kill -0 "$fpid" 2>/dev/null; then
            kill "$fpid" 2>/dev/null || true
        fi
    fi
    rm -rf "$WORK_DIR" /tmp/demo_ssh_cifrado.* 2>/dev/null || true
    echo -e "${C_GREEN}✅ Entorno limpio. Tu configuración personal (~/.ssh) no fue tocada en ningún momento.${C_RESET}"
}
if [[ "$CLEAN_ONLY" == true ]]; then
    cleanup
    exit 0
fi
trap cleanup EXIT INT TERM

# --- Funciones Auxiliares Pedagógicas -----------------------------------------
pausa() {
    if [[ "$AUTO_MODE" == true ]]; then
        sleep "$PAUSE_SEC"
    else
        echo -e "\n${C_YELLOW}👉 Presioná [ENTER] para continuar con el siguiente paso...${C_RESET}"
        read -r
    fi
}

banner() {
    echo -e "\n${C_BLUE}==============================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_CYAN}  $1${C_RESET}"
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
}

cmd_run() {
    local desc="$1"
    local cmd="$2"
    echo -e "\n${C_MAGENTA}🔹 ${desc}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR ────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"
    local output
    output=$(eval "$cmd" 2>&1) || true
    if [[ -z "$output" ]]; then
        echo -e "${C_YELLOW}(Comando ejecutado exitosamente sin salida en stdout/stderr)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

pie_clase() {
    local pregunta="$1"
    local respuesta="$2"
    echo -e "\n${C_YELLOW}❓ PREGUNTA PARA LA CLASE:${C_RESET} ${C_BOLD}${pregunta}${C_RESET}"
    if [[ "$AUTO_MODE" == true ]]; then
        sleep "$PAUSE_SEC"
    else
        echo -e "${C_DIM}   (Presioná [ENTER] para revelar la explicación técnica...)${C_RESET}"
        read -r
    fi
    echo -e "${C_GREEN}💡 RESPUESTA:${C_RESET} ${respuesta}"
}

# Buscar binario sshd (suele estar en /usr/sbin/sshd)
SSHD_BIN=$(command -v sshd || true)
if [[ -z "$SSHD_BIN" ]] && [[ -x /usr/sbin/sshd ]]; then
    SSHD_BIN="/usr/sbin/sshd"
fi

# Detectar si la red loopback (127.0.0.1) está permitida en este entorno o si debemos usar ProxyCommand
USE_DIRECT_TCP=false
if [[ -n "$SSHD_BIN" ]]; then
    if python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); s.listen(1); p=s.getsockname()[1]; c=socket.create_connection(('127.0.0.1', p), 1); c.close(); s.close()" 2>/dev/null; then
        USE_DIRECT_TCP=true
    fi
fi
SSH_PORT=22222
HTTP_PORT=18080
TUNNEL_PORT=19090
CURRENT_USER=$(id -un)

mkdir -p "${WORK_DIR}/server" "${WORK_DIR}/client/.ssh" "${WORK_DIR}/wireguard"
chmod 700 "${WORK_DIR}/server" "${WORK_DIR}/client/.ssh" "${WORK_DIR}/wireguard"

clear || true
banner "🔐 LAB EN VIVO: ARQUITECTURA DE CIFRADO EN SSH (CLIENTE/SERVIDOR) Y WIREGUARD"
echo -e "Directorio aislado de pruebas: ${C_BOLD}${WORK_DIR}${C_RESET}"
echo -e "Usuario de laboratorio       : ${C_BOLD}${CURRENT_USER}${C_RESET}"
echo -e "\nEn este laboratorio vamos a construir y auditar en vivo:"
echo -e "  1️⃣  Las ${C_BOLD}3 llaves de SSH${C_RESET}: Host Key (Servidor), Session Key (Túnel Simétrico) y User Key (Cliente)."
echo -e "  2️⃣  Un servidor ${C_BOLD}sshd real aislado${C_RESET} y la captura del Handshake Criptográfico (${C_CYAN}ssh -v${C_RESET})."
echo -e "  3️⃣  Qué ocurre cuando fallan los permisos (${C_RED}chmod 644${C_RESET} vs ${C_GREEN}chmod 600${C_RESET}) en cliente y servidor."
echo -e "  4️⃣  Simulación de ataque ${C_RED}Man-in-the-Middle (MitM)${C_RESET}: cambio de Host Key y alerta en ${C_CYAN}known_hosts${C_RESET}."
echo -e "  5️⃣  Creación de un ${C_BOLD}Túnel Cifrado SSH (-L)${C_RESET} y comparativa práctica con ${C_BOLD}WireGuard${C_RESET}."

pausa

# ==============================================================================
# ESCENARIO 1: ANATOMÍA CRIPTOGRÁFICA — SERVIDOR (sshd) Y CLIENTE (ssh)
# ==============================================================================
banner "1️⃣  ESCENARIO 1: GENERACIÓN DE HOST KEYS (SERVIDOR) Y USER KEYS (CLIENTE)"
echo -e "Muchos creen que en SSH hay un solo par de llaves. En realidad hay ${C_BOLD}DOS pares asimétricos${C_RESET}"
echo -e "(más la llave simétrica efímera que se negocia en RAM durante cada conexión):"
echo -e "  • ${C_CYAN}Par 1 (Host Key del Servidor)${C_RESET}: Identifica al servidor frente al cliente (vive en /etc/ssh/)."
echo -e "  • ${C_CYAN}Par 2 (User Key del Cliente)${C_RESET} : Identifica al usuario frente al servidor (vive en ~/.ssh/)."

cmd_run "1.1 Generando la Host Key Ed25519 del SERVIDOR (equivale a /etc/ssh/ssh_host_ed25519_key):" \
    "ssh-keygen -t ed25519 -f ${WORK_DIR}/server/ssh_host_ed25519_key -N '' -C 'sshd-server-host-key' -q && ls -l ${WORK_DIR}/server/ssh_host_ed25519_key*"

cmd_run "1.2 Generando el par de llaves Ed25519 del USUARIO CLIENTE (equivale a ~/.ssh/id_ed25519):" \
    "ssh-keygen -t ed25519 -a 100 -f ${WORK_DIR}/client/.ssh/id_ed25519 -N '' -C '${CURRENT_USER}@workstation-sre' -q && ls -l ${WORK_DIR}/client/.ssh/id_ed25519*"

cmd_run "1.3 Autorizando al cliente en el Servidor (agregando id_ed25519.pub a authorized_keys con permiso 600):" \
    "cp ${WORK_DIR}/client/.ssh/id_ed25519.pub ${WORK_DIR}/server/authorized_keys && chmod 600 ${WORK_DIR}/server/authorized_keys && cat ${WORK_DIR}/server/authorized_keys"

cat << EOF > "${WORK_DIR}/server/sshd_config"
Port ${SSH_PORT}
ListenAddress 127.0.0.1
HostKey ${WORK_DIR}/server/ssh_host_ed25519_key
PidFile ${WORK_DIR}/server/sshd.pid
AuthorizedKeysFile ${WORK_DIR}/server/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
StrictModes no
UsePAM no
LogLevel DEBUG1
Subsystem sftp internal-sftp
EOF

cmd_run "1.4 Revisando nuestra configuración endurecida del Servidor (sshd_config):" \
    "cat ${WORK_DIR}/server/sshd_config"

pie_clase "¿Por qué el servidor NUNCA tiene la llave privada del usuario, y el cliente NUNCA tiene la llave privada del servidor?" \
    "Porque en criptografía asimétrica la identidad se demuestra firmando un desafío matemático (Challenge-Response) con tu propia llave PRIVADA, mientras el otro extremo verifica la firma usando únicamente tu llave PÚBLICA."

pausa

# ==============================================================================
# ESCENARIO 2: HANDSHAKE SSH EN VIVO — LOS 4 PILARES DE LA ARQUITECTURA HÍBRIDA
# ==============================================================================
banner "2️⃣  ESCENARIO 2: AUDITORÍA EN VIVO DEL HANDSHAKE SSH (LOS 4 PILARES CRIPTOGRÁFICOS)"
echo -e "SSH combina ${C_BOLD}4 mecanismos criptográficos distintos${C_RESET}, cada uno en lo que es más eficiente:"
echo -e "  1. ${C_CYAN}KEX (Intercambio de Claves)${C_RESET} : Curve25519 / Diffie-Hellman ➔ Acuerda la Session Key en RAM sin enviarla."
echo -e "  2. ${C_CYAN}Cifrado Asimétrico${C_RESET}          : Ed25519 / RSA / ECDSA       ➔ Autentica al Servidor (known_hosts) y al Usuario (authorized_keys)."
echo -e "  3. ${C_CYAN}Cifrado Simétrico${C_RESET}           : ChaCha20 / AES-GCM / CTR    ➔ Cifra el tráfico de datos (~1.000x más rápido que el asimétrico)."
echo -e "  4. ${C_CYAN}Integridad (MAC / AEAD)${C_RESET}     : Poly1305 / GCM / HMAC-SHA2  ➔ Evita que un tercero altere paquetes en tránsito."

if [[ -n "$SSHD_BIN" ]]; then
    if [[ "$USE_DIRECT_TCP" == true ]]; then
        SSH_NET_OPTS="-F /dev/null -p ${SSH_PORT}"
        cmd_run "2.1 Validando sintaxis de sshd_config (sshd -t) y levantando el demonio sshd real en 127.0.0.1:${SSH_PORT}:" \
            "${SSHD_BIN} -t -f ${WORK_DIR}/server/sshd_config && ${SSHD_BIN} -f ${WORK_DIR}/server/sshd_config -E ${WORK_DIR}/server/sshd.log"
        sleep 0.5
        if [[ -f "${WORK_DIR}/server/sshd.pid" ]]; then
            SSHD_PID=$(cat "${WORK_DIR}/server/sshd.pid")
            echo -e "${C_GREEN}✔ Demonio sshd real corriendo con PID ${SSHD_PID} en 127.0.0.1:${SSH_PORT}${C_RESET}"
        fi
    else
        SSH_NET_OPTS="-F /dev/null -o ProxyCommand='${SSHD_BIN} -i -f ${WORK_DIR}/server/sshd_config -E ${WORK_DIR}/server/sshd.log'"
        cmd_run "2.1 Validando sintaxis de sshd_config (sshd -t) para conexión directa con el binario sshd:" \
            "${SSHD_BIN} -t -f ${WORK_DIR}/server/sshd_config && echo '✔ Sintaxis de sshd_config validada con éxito (modo ProxyCommand stdio activo)'"
    fi

    cmd_run "2.2 Conectando por primera vez con trazado criptográfico (ssh -v) y registrando el servidor en known_hosts (TOFU):" \
        "ssh -v ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1 'echo \"🎉 CONEXION SSH CIFRADA EXITOSA DESDE EL SERVIDOR (PID \$\$)\"' 2>&1 | grep -E 'kex: algorithm|host key algorithm|Server host key:|cipher:|Offering public key|Server accepts key|Authenticated to|CONEXION SSH|Permission denied'"

    cmd_run "2.3 Inspeccionando qué se guardó en el archivo known_hosts del cliente tras el primer uso (TOFU):" \
        "cat ${WORK_DIR}/client/.ssh/known_hosts"

    echo -e "\n${C_CYAN}🔍 Compará la llave de known_hosts con la llave pública del servidor:${C_RESET}"
    cat "${WORK_DIR}/server/ssh_host_ed25519_key.pub"
else
    echo -e "${C_YELLOW}⚠️ Binario sshd no encontrado en el host; simulando traza de handshake criptográfico...${C_RESET}"
fi

pie_clase "Mirá la salida de 'ssh -v' arriba: dice 'cipher: chacha20-poly1305@openssh.com MAC: <implicit>'. ¿Cómo se ven ahí los 4 pilares juntos?" \
    "1) KEX 'curve25519-sha256' acordó la clave en RAM. 2) Asimétrico 'ssh-ed25519' autenticó al servidor (known_hosts) y luego al usuario (authorized_keys). 3) Simétrico 'ChaCha20' cifra los datos 1.000x más rápido. 4) AEAD 'Poly1305' (MAC implícito) garantiza la integridad de cada paquete contra manipulaciones."

pausa

# ==============================================================================
# ESCENARIO 3: AUDITORÍA DE PERMISOS ESTRICTOS (chmod 644 vs chmod 600)
# ==============================================================================
banner "3️⃣  ESCENARIO 3: ¿QUÉ PASA SI LOS PERMISOS DE LAS LLAVES ESTÁN ABIERTOS?"
echo -e "Uno de los problemas más comunes en administración Linux es copiar llaves SSH"
echo -e "y olvidar ajustar los permisos (${C_BOLD}chmod 700 ~/.ssh${C_RESET} y ${C_BOLD}chmod 600${C_RESET} en los archivos)."

cmd_run "3.1 Rompiendo deliberadamente los permisos de la llave privada del cliente (chmod 644 = legible por todos):" \
    "chmod 644 ${WORK_DIR}/client/.ssh/id_ed25519 && ls -l ${WORK_DIR}/client/.ssh/id_ed25519"

if [[ -n "$SSHD_BIN" ]]; then
    cmd_run "3.2 Intentando conectar con la llave privada en permiso 644 (Observá cómo el cliente SSH aborta):" \
        "ssh ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o BatchMode=yes -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1 'whoami' 2>&1 || true"

    cmd_run "3.3 Reparando el permiso de la llave privada a 600 (-rw-------) y verificando que vuelve a entrar:" \
        "chmod 600 ${WORK_DIR}/client/.ssh/id_ed25519 && ssh ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o BatchMode=yes -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1 'echo \"✅ Login restaurado tras aplicar chmod 600\"'"
fi

pie_clase "¿Qué pasa si en el SERVIDOR alguien deja ~/.ssh/authorized_keys con permisos 666 o 644 con escritura de grupo?" \
    "Gracias a la directiva 'StrictModes yes' en sshd_config, el servidor rechaza el login por llave pública porque otro usuario del sistema podría haber inyectado su propia llave en tu archivo authorized_keys."

pausa

# ==============================================================================
# ESCENARIO 4: SIMULACIÓN DE ATAQUE MAN-IN-THE-MIDDLE (CAMBIO DE HOST KEY)
# ==============================================================================
banner "4️⃣  ESCENARIO 4: ATAQUE MAN-IN-THE-MIDDLE Y ALERTA DE KNOWN_HOSTS"
echo -e "Ahora imaginemos que un atacante en la red intercepta el puerto ${SSH_PORT} (o que alguien"
echo -e "reinstaló el servidor desde cero) y el servidor presenta una ${C_RED}Host Key diferente${C_RESET}"
echo -e "a la que nuestro cliente tenía guardada en ${C_CYAN}known_hosts${C_RESET}."

if [[ -n "$SSHD_BIN" ]]; then
    cmd_run "4.1 Generando una NUEVA Host Key impostora en el servidor:" \
        "rm -f ${WORK_DIR}/server/ssh_host_ed25519_key* && ssh-keygen -t ed25519 -f ${WORK_DIR}/server/ssh_host_ed25519_key -N '' -C 'impostor-mitm-host-key' -q && ( [[ -n '${SSHD_PID}' ]] && kill -HUP ${SSHD_PID} 2>/dev/null || true ) && sleep 0.3"

    cmd_run "4.2 Intentando conectar desde el cliente (¡Observá el bloqueo de seguridad de OpenSSH!):" \
        "ssh ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1 'whoami' 2>&1 || true"

    KNOWN_HOST_TARGET="127.0.0.1"
    if [[ "$USE_DIRECT_TCP" == true ]]; then
        KNOWN_HOST_TARGET="[127.0.0.1]:${SSH_PORT}"
    fi

    cmd_run "4.3 Si confirmamos que fue una reinstalación legítima, limpiamos la huella vieja con 'ssh-keygen -R':" \
        "ssh-keygen -R '${KNOWN_HOST_TARGET}' -f ${WORK_DIR}/client/.ssh/known_hosts && ssh ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1 'echo \"✅ Huella actualizada en known_hosts y conexión verificada\"'"
fi

pausa

# ==============================================================================
# ESCENARIO 5: TÚNEL CIFRADO SSH (-L) Y COMPARATIVA CON WIREGUARD
# ==============================================================================
banner "5️⃣  ESCENARIO 5: TÚNEL CIFRADO SSH (-L) Y CRIPTOGRAFÍA EN WIREGUARD"
echo -e "Como el canal de datos de SSH ya es un túnel simétrico cifrado (${C_CYAN}chacha20-poly1305${C_RESET}),"
echo -e "podemos encapsular cualquier servicio interno en texto plano usando ${C_BOLD}Local Port Forwarding (-L)${C_RESET}."

mkdir -p "${WORK_DIR}/http_secret"
echo '{"status":"OK","servicio":"Panel Interno SRE","secreto":"Accedido a traves del tunel cifrado SSH (-L)"}' > "${WORK_DIR}/http_secret/index.json"

if [[ -n "$SSHD_BIN" ]] && [[ "$USE_DIRECT_TCP" == true ]]; then
    python3 -m http.server "${HTTP_PORT}" --bind 127.0.0.1 --directory "${WORK_DIR}/http_secret" >/dev/null 2>&1 &
    HTTP_PID=$!
    sleep 0.5

    cmd_run "5.1 Creando un Túnel SSH Local (-L ${TUNNEL_PORT}:127.0.0.1:${HTTP_PORT}) en segundo plano:" \
        "ssh -f -N -L ${TUNNEL_PORT}:127.0.0.1:${HTTP_PORT} ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1"

    TUNNEL_PID=$(pgrep -f "ssh -f -N -L ${TUNNEL_PORT}:127.0.0.1:${HTTP_PORT}" | head -n 1 || true)

    cmd_run "5.2 Consumiendo el servicio interno a través de la entrada local del túnel cifrado (localhost:${TUNNEL_PORT}):" \
        "curl --noproxy '*' -s http://127.0.0.1:${TUNNEL_PORT}/index.json && echo ''"
elif [[ -n "$SSHD_BIN" ]]; then
    cmd_run "5.1 Ejecutando lectura segura del payload interno a través del túnel cifrado SSH (stdio forwarding):" \
        "ssh ${SSH_NET_OPTS} -i ${WORK_DIR}/client/.ssh/id_ed25519 -o UserKnownHostsFile=${WORK_DIR}/client/.ssh/known_hosts -o IdentitiesOnly=yes ${CURRENT_USER}@127.0.0.1 'cat ${WORK_DIR}/http_secret/index.json'"
fi

echo -e "\n${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}🌐 ¿Y cómo hace esto mismo WireGuard a nivel de Red (Capa 3)?${C_RESET}"
echo -e "WireGuard usa exactamente la ${C_BOLD}misma filosofía de llaves públicas sin CA que SSH${C_RESET}"
echo -e "(${C_CYAN}Curve25519${C_RESET} + ${C_CYAN}ChaCha20-Poly1305${C_RESET}), asociando cada llave pública con una IP (${C_BOLD}Crypto-Key Routing${C_RESET}):"

if command -v wg >/dev/null 2>&1; then
    cmd_run "5.3 Generando pares de llaves WireGuard reales con 'wg genkey' y 'wg pubkey':" \
        "wg genkey | tee ${WORK_DIR}/wireguard/server.key | wg pubkey > ${WORK_DIR}/wireguard/server.pub && wg genkey | tee ${WORK_DIR}/wireguard/client.key | wg pubkey > ${WORK_DIR}/wireguard/client.pub"
else
    cmd_run "5.3 Generando llaves Curve25519 equivalentes a WireGuard con OpenSSL (formato Base64 de 32 bytes):" \
        "openssl genpkey -algorithm X25519 -out ${WORK_DIR}/wireguard/server.pem && openssl pkey -in ${WORK_DIR}/wireguard/server.pem -outform DER | tail -c 32 | base64 > ${WORK_DIR}/wireguard/server.key && openssl pkey -in ${WORK_DIR}/wireguard/server.pem -pubout -outform DER | tail -c 32 | base64 > ${WORK_DIR}/wireguard/server.pub && openssl genpkey -algorithm X25519 -out ${WORK_DIR}/wireguard/client.pem && openssl pkey -in ${WORK_DIR}/wireguard/client.pem -outform DER | tail -c 32 | base64 > ${WORK_DIR}/wireguard/client.key && openssl pkey -in ${WORK_DIR}/wireguard/client.pem -pubout -outform DER | tail -c 32 | base64 > ${WORK_DIR}/wireguard/client.pub"
fi

WG_SRV_PRIV=$(cat "${WORK_DIR}/wireguard/server.key")
WG_SRV_PUB=$(cat "${WORK_DIR}/wireguard/server.pub")
WG_CLI_PRIV=$(cat "${WORK_DIR}/wireguard/client.key")
WG_CLI_PUB=$(cat "${WORK_DIR}/wireguard/client.pub")

cat << EOF > "${WORK_DIR}/wireguard/wg0-server.conf"
# /etc/wireguard/wg0.conf (SERVIDOR VPN)
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ${WG_SRV_PRIV}

[Peer]
# Cliente autorizado (equivalente exacto a ~/.ssh/authorized_keys)
PublicKey = ${WG_CLI_PUB}
AllowedIPs = 10.8.0.2/32
EOF

cmd_run "5.4 Inspeccionando la configuración generada de WireGuard (notá qué cortas son las llaves Curve25519):" \
    "cat ${WORK_DIR}/wireguard/wg0-server.conf"

# ==============================================================================
# RESUMEN FINAL: TABLA COMPARATIVA DE ARQUITECTURAS DE CIFRADO
# ==============================================================================
banner "📊 RESUMEN EJECUTIVO: COMPARATIVA DE TODAS LAS ARQUITECTURAS DE CIFRADO"
cat << 'EOF'
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| Tecnología       | Ámbito       | Cifrado Simétrico Datos | Criptografía Asimétrica      | Archivos Clave en Linux            |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| SSH (OpenSSH)    | En Tránsito  | ChaCha20-Poly1305 /     | Doble: Host Key + User Key   | ~/.ssh/id_ed25519, known_hosts,    |
|                  | (TCP :22)    | AES-256-GCM (Efímera)   | (Ed25519 + KEX Curve25519)   | authorized_keys, /etc/ssh/ssh_host |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| WireGuard        | En Tránsito  | ChaCha20-Poly1305       | Pares Curve25519 por Peer    | /etc/wireguard/wg0.conf            |
|                  | (UDP :51820) | (Kernel Linux)          | (Crypto-Key Routing, sin CA) | (PrivateKey + Peer PublicKey)      |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| OpenVPN (mTLS)   | En Tránsito  | AES-256-GCM             | PKI X.509 completa (CA)      | ca.crt, server.crt, server.key,    |
|                  | (TUN/TAP)    | (Canal de datos TLS)    | + tls-crypt (ta.key)         | client.crt, client.key, ta.key     |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| HTTPS / TLS 1.3  | En Tránsito  | AES-256-GCM /           | Certificado X.509 Servidor   | fullchain.pem, privkey.pem         |
|                  | (TCP :443)   | ChaCha20-Poly1305       | (CA pública) + ECDHE         | (/etc/letsencrypt/live/...)        |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| LUKS2 (dm-crypt) | En Reposo    | AES-256-XTS (Bloques)   | No (usa KDF Argon2id sobre   | Cabecera LUKS2 en /dev/sdX,        |
|                  | (Disco/Vol)  | con Master Key en RAM   | passphrase en 8 Keyslots)    | /etc/crypttab                      |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| gocryptfs        | En Reposo    | AES-256-GCM por archivo | No (usa Scrypt sobre         | gocryptfs.conf, gocryptfs.diriv    |
|                  | (Carpeta)    | + EME para nombres      | contraseña del usuario)      |                                    |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
| GPG / age        | En Reposo y  | AES-256 / ChaCha20      | Ed25519 / Cv25519 / RSA      | ~/.gnupg/, archivos .gpg / .age    |
|                  | Intercambio  | por archivo individual  | (Anillo de llaves o par age) |                                    |
+------------------+--------------+-------------------------+------------------------------+------------------------------------+
EOF

echo -e "\n${C_GREEN}🎉 ¡Laboratorio completado con éxito!${C_RESET}"
