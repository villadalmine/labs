#!/usr/bin/env bash
# ==============================================================================
# SCRIPT EDUCATIVO: Tarea Batch de Backup con Emisión PUSH de Métricas
# Genera métricas de timestamp, estado de salida, duración y tamaño en bytes
# ==============================================================================
set -euo pipefail

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${TEXTFILE_DIR}/backup_status.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

DEST_DIR="${1:-/var/backups/lab}"
FORCE_ERROR="${2:-false}"
mkdir -p "$TEXTFILE_DIR" "$DEST_DIR" 2>/dev/null || true

JOB_NAME="mysql_lab_backup"
START_TIME=$(date +%s)
TIMESTAMP_FORMAT=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${DEST_DIR}/backup_${TIMESTAMP_FORMAT}.tar.gz"

echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Iniciando Backup ($JOB_NAME) ==="

if [ "$FORCE_ERROR" = "true" ]; then
    echo "(!) Simulando falla catastrófica de backup (ej: disco destino sin espacio o fallo de red S3)..."
    STATUS=0
    FILE_SIZE=0
    DURATION=2
    sleep 1
else
    # Respaldar /etc o archivos de prueba
    if tar -czf "$BACKUP_FILE" /etc/hosts /etc/issue /etc/os-release 2>/dev/null; then
        STATUS=1
        FILE_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null || echo 1024)
        END_TIME=$(date +%s)
        DURATION=$(( END_TIME - START_TIME ))
        echo "✓ Backup completado exitosamente: $BACKUP_FILE ($FILE_SIZE bytes en ${DURATION}s)"
    else
        STATUS=0
        FILE_SIZE=0
        END_TIME=$(date +%s)
        DURATION=$(( END_TIME - START_TIME ))
        echo "✗ Error al ejecutar tar para el backup"
    fi
fi

FINISH_TIME=$(date +%s)

# PUSH LOCAL: Escribir métricas para Node Exporter
cat <<EOF > "$TMP_FILE"
# HELP backup_last_run_timestamp_seconds Fecha unix del ultimo backup ejecutado
# TYPE backup_last_run_timestamp_seconds gauge
backup_last_run_timestamp_seconds{job="${JOB_NAME}"} ${FINISH_TIME}

# HELP backup_last_status Codigo de estado del ultimo backup (1 = OK/Exitoso, 0 = Fallo)
# TYPE backup_last_status gauge
backup_last_status{job="${JOB_NAME}"} ${STATUS}

# HELP backup_last_size_bytes Tamano en bytes del ultimo archivo de backup generado
# TYPE backup_last_size_bytes gauge
backup_last_size_bytes{job="${JOB_NAME}"} ${FILE_SIZE}

# HELP backup_duration_seconds Duracion en segundos de la operacion de backup
# TYPE backup_duration_seconds gauge
backup_duration_seconds{job="${JOB_NAME}"} ${DURATION}
EOF

mv "$TMP_FILE" "$OUTPUT_FILE"
echo "✓ Métricas de backup actualizadas en: $OUTPUT_FILE"
