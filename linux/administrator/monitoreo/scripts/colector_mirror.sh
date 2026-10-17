#!/usr/bin/env bash
# ==============================================================================
# SCRIPT COLECTOR EDUCATIVO: Estado de Salud de Espejos (LVM RAID 1 / Mirrors)
# Escribe métricas en formato estándar de Prometheus para Node Exporter
# ==============================================================================
set -euo pipefail

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="${TEXTFILE_DIR}/storage_mirror.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

# Crear directorio si no existe
mkdir -p "$TEXTFILE_DIR"

# Variable de salud: 1 = Saludable, 0 = Degradado/Falla
HEALTH=1
VG_TARGET="${1:-vg_mysql}"
LV_TARGET="${2:-lv_mysql}"

# Comprobar si existe el LV especificado
if lvs "${VG_TARGET}/${LV_TARGET}" &>/dev/null; then
    ATTR=$(lvs --noheadings -o lv_attr "${VG_TARGET}/${LV_TARGET}" 2>/dev/null | tr -d ' ')
    HEALTH_STATUS=$(lvs --noheadings -o health_status "${VG_TARGET}/${LV_TARGET}" 2>/dev/null | tr -d ' ')
    
    # Si reporta health_status no vacío o atributo 'partial' (p), está degradado
    if [ -n "$HEALTH_STATUS" ] || [[ "$ATTR" =~ ^....p ]]; then
        HEALTH=0
    else
        HEALTH=1
    fi
elif [ -f /tmp/simular_falla_mirror ]; then
    # Soporte para modo de simulación didáctica
    HEALTH=0
else
    HEALTH=1
fi

# Escribir la métrica con Help y Type
cat <<EOF > "$TMP_FILE"
# HELP lvm_mirror_health Estado de salud del arreglo de disco espejado (1 = OK, 0 = Degradado)
# TYPE lvm_mirror_health gauge
lvm_mirror_health{vg="${VG_TARGET}",lv="${LV_TARGET}"} ${HEALTH}
EOF

# Reemplazo atómico para evitar lecturas incompletas por parte de Node Exporter
mv "$TMP_FILE" "$OUTPUT_FILE"
