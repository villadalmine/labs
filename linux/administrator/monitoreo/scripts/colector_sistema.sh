#!/usr/bin/env bash
# ==============================================================================
# SCRIPT COLECTOR EDUCATIVO: Tráfico de Red, Peticiones y Sesiones de Usuario
# Escribe métricas en formato estándar de Prometheus para Node Exporter
# ==============================================================================
set -euo pipefail

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${TEXTFILE_DIR}/sistema_trafico.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

mkdir -p "$TEXTFILE_DIR"

# 1. Sesiones de terminal activas (who y ss)
SSH_CONEXIONES=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | grep -v Recv-Q | wc -l || echo 0)
USUARIOS_LOGUEADOS=$(who 2>/dev/null | wc -l || echo 0)

# 2. Conexiones HTTP concurrentes en puerto 80 / 8080
HTTP_CONEXIONES=$(ss -tn state established '( dport = :80 or sport = :80 or dport = :8080 or sport = :8080 )' 2>/dev/null | grep -v Recv-Q | wc -l || echo 0)

# 3. Peticiones HTTP totales acumuladas (si existe log de Nginx o log simulado del lab)
HTTP_REQUESTS_TOTAL=0
if [ -f /var/log/nginx/access.log ]; then
    HTTP_REQUESTS_TOTAL=$(wc -l < /var/log/nginx/access.log)
elif [ -f /tmp/lab_http_requests.count ]; then
    HTTP_REQUESTS_TOTAL=$(cat /tmp/lab_http_requests.count)
fi

cat <<EOF > "$TMP_FILE"
# HELP server_active_ssh_sessions Conexiones TCP establecidas en puerto SSH (22)
# TYPE server_active_ssh_sessions gauge
server_active_ssh_sessions ${SSH_CONEXIONES}

# HELP server_logged_users Cantidad de terminales/usuarios logueados en el sistema
# TYPE server_logged_users gauge
server_logged_users ${USUARIOS_LOGUEADOS}

# HELP http_active_connections Conexiones activas concurrentes a servicios web
# TYPE http_active_connections gauge
http_active_connections ${HTTP_CONEXIONES}

# HELP http_incoming_requests_total Contador total acumulativo de peticiones web recibidas
# TYPE http_incoming_requests_total counter
http_incoming_requests_total ${HTTP_REQUESTS_TOTAL}
EOF

mv "$TMP_FILE" "$OUTPUT_FILE"
