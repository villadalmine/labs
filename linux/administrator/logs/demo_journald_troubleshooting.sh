#!/usr/bin/env bash
# ==============================================================================
# DEMOSTRACIÓN EDUCATIVA: Journald y Troubleshooting Forense con journalctl
# Laboratorio: linux/administrator/logs/journald_journalctl_troubleshooting.md (Lab 3.20)
#
# Cubre:
#  - Configuración con drop-in /etc/systemd/journald.conf.d/*.conf y systemd-analyze
#  - Filtros journalctl (-n, -b, _PID, --since/--until, -p emerg..err, -o json)
#  - Incidente real 1: Apache/HTTP falla por puerto ocupado -> ss -tulpn -> fix
#  - Incidente real 2: sshd aislado con logins Accepted y Failed/Invalid + jq SOC
#
# Uso:
#   sudo ./demo_journald_troubleshooting.sh [--auto <segundos>] [--keep] [--clean] [--help]
# ==============================================================================

set -uo pipefail

if [ -n "${TMUX:-}" ]; then
    tmux set -g mouse on 2>/dev/null || true
fi

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[0;36m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}[ERROR] Este script requiere privilegios de superusuario (sudo) para gestionar unidades systemd y leer el diario completo.${C_RESET}"
    exit 1
fi

AUTO_MODE=false
AUTO_DELAY=3
KEEP_FILES=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            AUTO_DELAY="${2:-3}"
            shift 2
            ;;
        --keep)
            KEEP_FILES=true
            shift
            ;;
        --clean|--limpiar)
            CLEAN_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Uso: sudo ./demo_journald_troubleshooting.sh [--auto <segundos>] [--keep] [--clean|--limpiar] [--help]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

pause_step() {
    local mensaje="${1:-Presioná [ENTER] para continuar al siguiente paso...}"
    if [ "$AUTO_MODE" = true ]; then
        echo -e "\n${C_YELLOW}⏳ [MODO AUTO] Esperando ${AUTO_DELAY}s: ${mensaje}${C_RESET}"
        sleep "$AUTO_DELAY"
    else
        echo -e "\n${C_BOLD}${C_GREEN}▶ ${mensaje}${C_RESET}"
        read -r </dev/tty 2>/dev/null || read -r
    fi
}

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
    echo -e "\n${C_BOLD}${C_YELLOW}❓ Pregunta para la clase / autoaprendizaje: ${pregunta}${C_RESET}"
    if [ -n "$respuesta" ]; then
        if [ "$AUTO_MODE" = true ]; then
            sleep "$AUTO_DELAY"
        else
            echo -en "${C_DIM}   [Presioná ENTER para ver la respuesta esperada...]${C_RESET} "
            read -r </dev/tty 2>/dev/null || read -r
        fi
        echo -e "   ${C_BOLD}${C_CYAN}✔ Respuesta esperada:${C_RESET} ${respuesta}\n"
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
        echo -e "${C_YELLOW}(El comando finalizó exitosamente sin imprimir texto en stdout/stderr)${C_RESET}"
    else
        echo -e "${output}"
    fi
    echo -e "${C_BOLD}${C_BLUE}└───────────────────────────────────────────────────────────────────────────────────┘${C_RESET}"
}

DIR_LAB="/tmp/lab_demo_journald"
DROPIN_FILE="/etc/systemd/journald.conf.d/99-lab-demo.conf"
UNIT_WEB="/etc/systemd/system/lab-web-prod.service"
UNIT_SSH="/etc/systemd/system/lab-sshd-audit.service"
ROGUE_PID=""

cleanup() {
    if [ "$KEEP_FILES" = true ] && [ "$CLEAN_ONLY" = false ]; then
        echo -e "\n${C_GREEN}[INFO] Se preservan las unidades y archivos en ${DIR_LAB} por opción --keep.${C_RESET}"
        echo -e "Para limpiar luego ejecutá: sudo ./limpiar_journald_troubleshooting.sh\n"
        return
    fi
    echo -e "\n${C_YELLOW}🧹 [LIMPIEZA] Deteniendo unidades temporales, drop-in y procesos auxiliares...${C_RESET}"
    if [ -n "$ROGUE_PID" ] && kill -0 "$ROGUE_PID" 2>/dev/null; then
        kill "$ROGUE_PID" 2>/dev/null || true
    fi
    pkill -f "http.server 18080" 2>/dev/null || true
    systemctl stop lab-web-prod.service lab-sshd-audit.service 2>/dev/null || true
    rm -f "$UNIT_WEB" "$UNIT_SSH" "$DROPIN_FILE"
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed lab-web-prod.service lab-sshd-audit.service 2>/dev/null || true
    systemctl restart systemd-journald 2>/dev/null || true
    rm -rf "$DIR_LAB"
    echo -e "${C_GREEN}✔ Limpieza completada sin rastros residuales.${C_RESET}\n"
}

if [ "$CLEAN_ONLY" = true ]; then
    cleanup
    exit 0
fi
trap cleanup EXIT INT TERM

mkdir -p "${DIR_LAB}/www" "${DIR_LAB}/httpd_run" "${DIR_LAB}/ssh" /etc/systemd/journald.conf.d
chmod 755 "${DIR_LAB}" "${DIR_LAB}/www" "${DIR_LAB}/httpd_run"
clear 2>/dev/null || true
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_GREEN} 📓 DEMOSTRACIÓN EN VIVO: JOURNALD Y TROUBLESHOOTING FORENSE CON JOURNALCTL${C_RESET}"
echo -e "${C_BOLD}${C_GREEN}===============================================================================${C_RESET}"

# ==============================================================================
# PASO 1: CONFIGURACIÓN DE SYSTEMD-JOURNALD (DROP-IN)
# ==============================================================================
step_banner "1" "Configuración de systemd-journald (/etc/systemd/journald.conf.d)"
explain "systemd-journald consolida logs del kernel, init y servicios en un diario binario indexado. Las modificaciones limpias se colocan en drop-ins *.conf dentro de /etc/systemd/journald.conf.d/."

cat <<'EOF' > "$DROPIN_FILE"
[Journal]
Storage=auto
Compress=yes
SystemMaxUse=500M
RuntimeMaxUse=100M
EOF

run_and_show "cat ${DROPIN_FILE}"
run_and_show "systemctl restart systemd-journald"
run_and_show "systemd-analyze cat-config systemd/journald.conf | grep -v '^#' | grep -v '^$'"
run_and_show "journalctl --disk-usage && journalctl --list-boots | tail -n 5"

pie_clase "¿Qué diferencia existe entre /run/log/journal/<id>/ y /var/log/journal/<id>/?" \
          "/run/log/journal vive en tmpfs (RAM) y se borra al reiniciar (Storage=volatile); /var/log/journal vive en disco y persiste entre reinicios (Storage=persistent)."
pause_step

# ==============================================================================
# PASO 2: FILTROS ESENCIALES DE JOURNALCTL Y FORMATO JSON
# ==============================================================================
step_banner "2" "Filtros Profesionales de journalctl (-n, -b, _PID, --since, -p, -o json)"
explain "journalctl permite filtrar por número de líneas, arranque (-b), PID confiable (_PID), rango de fechas (--since/--until), severidad (-p) y exportar en JSON."

run_and_show "journalctl -n 6 --no-pager"
run_and_show "journalctl -b --since '-10 minutes' -p emerg..warning -n 8 --no-pager"
run_and_show "journalctl -n 2 -o json --no-pager | head -c 500 && echo ''"

pie_clase "Si un usuario sin privilegios ejecuta 'journalctl' y ve solo sus propios logs con un 'Hint:', ¿a qué grupos debe añadirse?" \
          "A los grupos 'adm' o 'systemd-journal' (usermod -aG systemd-journal usuario) para poder leer los diarios del sistema."
pause_step

# ==============================================================================
# PASO 3: INCIDENTE REAL 1 -> SERVICIO WEB BLOQUEADO POR PUERTO OCUPADO
# ==============================================================================
step_banner "3" "Incidente Real 1 (Caso Apache/HTTP): Conflicto de Puerto y Resolución"
explain "Reproducimos el escenario clásico de falla al iniciar Apache: otro proceso ocupa el puerto 18080. Diagnosticaremos con systemctl status + journalctl -xeu y resolveremos con ss."

echo "<h1>Lab 3.20 Web Server OK</h1>" > "${DIR_LAB}/www/index.html"
chmod 644 "${DIR_LAB}/www/index.html"

HTTP_BIN=""
if command -v httpd &>/dev/null; then
    HTTP_BIN=$(command -v httpd)
elif command -v apache2 &>/dev/null; then
    HTTP_BIN=$(command -v apache2)
fi

if [ -n "$HTTP_BIN" ]; then
    WEB_USER="nobody"
    WEB_GROUP="nogroup"
    if id www-data &>/dev/null; then
        WEB_USER="www-data"
        WEB_GROUP="www-data"
    elif id apache &>/dev/null; then
        WEB_USER="apache"
        WEB_GROUP="apache"
    fi

    # Construir httpd.conf mínimo autocontenido compatible con Fedora/RHEL y Debian/Ubuntu
    MPM_LINE=""
    for m in /etc/httpd/modules/mod_mpm_event.so /usr/lib64/httpd/modules/mod_mpm_event.so /usr/lib/apache2/modules/mod_mpm_event.so /etc/httpd/modules/mod_mpm_prefork.so /usr/lib/apache2/modules/mod_mpm_prefork.so; do
        if [ -f "$m" ]; then
            MPM_LINE="LoadModule mpm_event_module ${m}"
            [[ "$m" == *prefork* ]] && MPM_LINE="LoadModule mpm_prefork_module ${m}"
            break
        fi
    done
    UNIXD_LINE=""
    for u in /etc/httpd/modules/mod_unixd.so /usr/lib64/httpd/modules/mod_unixd.so /usr/lib/apache2/modules/mod_unixd.so; do
        if [ -f "$u" ]; then
            UNIXD_LINE="LoadModule unixd_module ${u}"
            break
        fi
    done
    AUTHZ_LINE=""
    for a in /etc/httpd/modules/mod_authz_core.so /usr/lib64/httpd/modules/mod_authz_core.so /usr/lib/apache2/modules/mod_authz_core.so; do
        if [ -f "$a" ]; then
            AUTHZ_LINE="LoadModule authz_core_module ${a}"
            break
        fi
    done
    DIR_LINE=""
    for d in /etc/httpd/modules/mod_dir.so /usr/lib64/httpd/modules/mod_dir.so /usr/lib/apache2/modules/mod_dir.so; do
        if [ -f "$d" ]; then
            DIR_LINE="LoadModule dir_module ${d}"
            break
        fi
    done
    cat <<EOF > "${DIR_LAB}/httpd.conf"
ServerRoot ${DIR_LAB}/httpd_run
DefaultRuntimeDir ${DIR_LAB}/httpd_run
ServerName localhost
User ${WEB_USER}
Group ${WEB_GROUP}
Listen 0.0.0.0:18080
PidFile ${DIR_LAB}/httpd_run/httpd.pid
ErrorLog ${DIR_LAB}/httpd_run/error.log
DocumentRoot ${DIR_LAB}/www
${MPM_LINE}
${UNIXD_LINE}
${AUTHZ_LINE}
${DIR_LINE}
DirectoryIndex index.html
<Directory "${DIR_LAB}/www">
    Require all granted
</Directory>
EOF
    EXEC_WEB="${HTTP_BIN} -DFOREGROUND -f ${DIR_LAB}/httpd.conf"
else
    EXEC_WEB="$(command -v python3) -m http.server 18080 --directory ${DIR_LAB}/www"
fi

cat <<EOF > "$UNIT_WEB"
[Unit]
Description=Lab 3.20 Servidor Web de Produccion Simulado
After=network.target

[Service]
Type=simple
ExecStart=${EXEC_WEB}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
# Lanzar proceso usurpador ocupando puerto 18080
python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 18080))
s.listen(5)
time.sleep(120)
" &
ROGUE_PID=$!
sleep 1

run_and_show "systemctl start lab-web-prod.service"
sleep 1
run_and_show "systemctl status lab-web-prod.service --no-pager"
run_and_show "journalctl -xeu lab-web-prod.service -n 20 --no-pager"
run_and_show "ss -tulpn | grep 18080 || ss -tlpn | grep 18080"

explain "Vemos el error exacto en journalctl ('Address already in use') y 'ss' confirma que el PID ${ROGUE_PID} está ocupando el puerto 18080. Eliminamos el proceso intruso y reintentamos."
run_and_show "kill ${ROGUE_PID} && sleep 1 && systemctl start lab-web-prod.service"
ROGUE_PID=""
sleep 1
run_and_show "systemctl is-active lab-web-prod.service && curl --noproxy '*' -sI http://127.0.0.1:18080 | head -n 5"

pie_clase "¿Por qué 'systemctl status' y 'journalctl -xeu' son más rápidos que buscar a ciegas en /var/log/?" \
          "Porque filtran directamente por el _SYSTEMD_UNIT del servicio fallido, saltan al final (-e) y muestran la causa raíz exacta junto con el exit code."
pause_step

# ==============================================================================
# PASO 4: INCIDENTE REAL 2 -> AUDITORÍA DE LOGINS SSH Y LOGIND
# ==============================================================================
step_banner "4" "Incidente Real 2 (Caso SSH & Logind): Auditoría de Logins Exitosos y Fallidos"
explain "Levantamos un servidor sshd aislado en puerto 22229 bajo systemd, ejecutamos logins reales exitosos y fallidos (fuerza bruta), y auditamos los eventos con journalctl y jq."

SSHD_BIN=$(command -v sshd || echo "/usr/sbin/sshd")
if [ -x "$SSHD_BIN" ]; then
    mkdir -p /run/sshd && chmod 0755 /run/sshd
    ssh-keygen -q -t ed25519 -N "" -f "${DIR_LAB}/ssh/ssh_host_ed25519_key"
    ssh-keygen -q -t ed25519 -N "" -f "${DIR_LAB}/ssh/client_ed25519"
    cp "${DIR_LAB}/ssh/client_ed25519.pub" "${DIR_LAB}/ssh/authorized_keys"
    chmod 700 "${DIR_LAB}/ssh"
    chmod 600 "${DIR_LAB}/ssh/ssh_host_ed25519_key" "${DIR_LAB}/ssh/client_ed25519" "${DIR_LAB}/ssh/authorized_keys"

    cat <<EOF > "${DIR_LAB}/ssh/sshd_config"
Port 22229
ListenAddress 127.0.0.1
HostKey ${DIR_LAB}/ssh/ssh_host_ed25519_key
AuthorizedKeysFile ${DIR_LAB}/ssh/authorized_keys
PidFile ${DIR_LAB}/ssh/sshd.pid
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
UsePAM no
StrictModes no
LogLevel INFO
SyslogFacility AUTH
EOF

    cat <<EOF > "$UNIT_SSH"
[Unit]
Description=Lab 3.20 Servidor SSH de Auditoria
After=network.target

[Service]
Type=simple
ExecStart=${SSHD_BIN} -D -e -f ${DIR_LAB}/ssh/sshd_config

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    run_and_show "systemctl start lab-sshd-audit.service && systemctl is-active lab-sshd-audit.service"
    sleep 1

    # 2 logins exitosos reales
    run_and_show "ssh -F /dev/null -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${DIR_LAB}/ssh/client_ed25519 -p 22229 root@127.0.0.1 'id && uname -n'"
    run_and_show "ssh -F /dev/null -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${DIR_LAB}/ssh/client_ed25519 -p 22229 root@127.0.0.1 'uptime'"

    # 3 intentos fallidos reales simulando ataque (pty envía contraseña errónea para usuario inválido)
    explain "Simulando 3 intentos de fuerza bruta SSH con usuario inválido 'admin_ataque'..."
    python3 -c '
import os, pty, select, time
for _ in range(3):
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("ssh", [
            "ssh", "-F", "/dev/null", "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null", "-o", "PubkeyAuthentication=no",
            "-o", "PreferredAuthentications=password", "-o", "NumberOfPasswordPrompts=1",
            "-o", "ConnectTimeout=3", "-p", "22229", "admin_ataque@127.0.0.1"
        ])
    else:
        deadline = time.time() + 3.0
        sent = False
        while time.time() < deadline:
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    data = os.read(fd, 1024)
                    if not data:
                        break
                    if not sent and b"password" in data.lower():
                        os.write(fd, b"WrongPass123!\n")
                        sent = True
                except OSError:
                    break
        os.close(fd)
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
'
    sleep 1

    run_and_show "journalctl -u lab-sshd-audit.service --no-pager | grep -E 'Accepted|Failed|Invalid'"
    run_and_show "journalctl -u systemd-logind.service -n 8 --no-pager | grep -E 'New session|Removed session' || echo '(Sin eventos recientes de systemd-logind en este contenedor)'"

    # Paso 5: Análisis estructurado SOC con jq
    step_banner "5" "Reporte Forense Estructurado SOC desde journalctl -o json"
    if command -v jq &>/dev/null; then
        run_and_show "journalctl -u lab-sshd-audit.service -o json --no-pager | jq -r '.MESSAGE' | grep -E 'Accepted|Failed|Invalid' | awk '{if (\$0 ~ /Accepted/) ok++; else fail++} END {printf \"Resumen SOC -> Logins Exitosos: %d | Intentos Fallidos/Invalidos: %d\\n\", ok+0, fail+0}'"
    else
        run_and_show "journalctl -u lab-sshd-audit.service -o cat --no-pager | grep -E 'Accepted|Failed|Invalid' | wc -l"
    fi
else
    explain "sshd no está instalado en este entorno; omitiendo simulación SSH en vivo."
fi

pie_clase "¿Por qué es clave correlacionar los logs de ssh.service con systemd-logind.service ante una sospecha de intrusión?" \
          "ssh.service revela quién entró por red, desde qué IP y con qué método; systemd-logind confirma si la sesión realmente se abrió, el ID de sesión y cuándo terminó (incluyendo accesos por consola local)."
echo -e "\n${C_BOLD}${C_GREEN}🎉 ¡Laboratorio 3.20 completado con éxito!${C_RESET}"
