#!/usr/bin/env bash
# ==============================================================================
# SCRIPT COLECTOR EDUCATIVO: Métricas de Disco, Filesystem e Inodos
# Escribe métricas en formato estándar OpenMetrics/Prometheus para Node Exporter
# Textfile Collector.
#
# Métricas expuestas:
#  - custom_disk_bytes_total          (Capacidad total en bytes)
#  - custom_disk_bytes_used           (Espacio ocupado en bytes)
#  - custom_disk_bytes_free           (Espacio disponible en bytes)
#  - custom_disk_usage_percent        (Porcentaje de uso de bloques: 0-100)
#  - custom_disk_inodes_total         (Total de inodos del filesystem)
#  - custom_disk_inodes_used          (Inodos actualmente ocupados)
#  - custom_disk_inodes_free          (Inodos libres para nuevos archivos)
#  - custom_disk_inodes_usage_percent (Porcentaje de inodos ocupados: 0-100)
#
# Etiquetas (Labels):
#  - device="..."      (Dispositivo físico o lógico, ej: /dev/sda1, /dev/mapper/vg-lv)
#  - mountpoint="..."  (Punto de montaje, ej: /, /home, /mnt/datos)
#  - fstype="..."      (Tipo de sistema de archivos, ej: ext4, xfs, btrfs)
# ==============================================================================
set -euo pipefail

TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
OUTPUT_FILE="${TEXTFILE_DIR}/custom_disk_health.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

# Validación de privilegios si se usa el directorio del sistema
if [ "$EUID" -ne 0 ] && [ "$TEXTFILE_DIR" = "/var/lib/node_exporter/textfile_collector" ]; then
    echo "❌ Error: Se requieren permisos de superusuario (root) para escribir en $TEXTFILE_DIR" >&2
    echo "Ejecutá: sudo $0" >&2
    exit 1
fi

mkdir -p "$TEXTFILE_DIR"

# 1. Cabeceras OpenMetrics (HELP y TYPE para cada métrica expuesta)
cat << 'EOF' > "$TMP_FILE"
# HELP custom_disk_bytes_total Capacidad total del sistema de archivos en bytes
# TYPE custom_disk_bytes_total gauge
# HELP custom_disk_bytes_used Espacio en disco actualmente utilizado en bytes
# TYPE custom_disk_bytes_used gauge
# HELP custom_disk_bytes_free Espacio libre disponible para usuarios no privilegiados en bytes
# TYPE custom_disk_bytes_free gauge
# HELP custom_disk_usage_percent Porcentaje de ocupacion del espacio en disco (0 a 100)
# TYPE custom_disk_usage_percent gauge
# HELP custom_disk_inodes_total Total de inodos indexables soportados por el filesystem
# TYPE custom_disk_inodes_total gauge
# HELP custom_disk_inodes_used Cantidad de inodos actualmente consumidos por archivos
# TYPE custom_disk_inodes_used gauge
# HELP custom_disk_inodes_free Inodos disponibles para crear nuevos archivos
# TYPE custom_disk_inodes_free gauge
# HELP custom_disk_inodes_usage_percent Porcentaje de consumo de inodos (0 a 100)
# TYPE custom_disk_inodes_usage_percent gauge
EOF

# 2. Recolección de sistemas de archivos reales
# Usamos df -PT -B1 para obtener valores en bytes exactos y salida estándar POSIX de 1 línea por mount.
# Excluimos pseudo-filesystems de kernel o memoria (tmpfs, devtmpfs, squashfs, overlay).
df -PT -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2 | while read -r dev fstype total used avail pcent mount; do
    # Descartar entradas vacías o dispositivos virtuales sin almacenamiento persistente
    [ -z "$mount" ] && continue
    
    # Remover el signo de porcentaje para obtener un entero
    pcent_num="${pcent%\%}"
    [[ "$pcent_num" =~ ^[0-9]+$ ]] || pcent_num=0

    # 3. Recolección de Inodos para este punto de montaje específico (-i)
    read -r itotal iused ifree ipcent < <(df -PTi "$mount" 2>/dev/null | tail -n 1 | awk '{print $3, $4, $5, $6}')
    ipcent_num="${ipcent%\%}"

    # Sanitizar valores en filesystems que no asignan inodos estáticos (ej. Btrfs, ZFS o algunos montajes de red)
    [[ "$itotal" =~ ^[0-9]+$ ]] || itotal=0
    [[ "$iused" =~ ^[0-9]+$ ]] || iused=0
    [[ "$ifree" =~ ^[0-9]+$ ]] || ifree=0
    [[ "$ipcent_num" =~ ^[0-9]+$ ]] || ipcent_num=0

    # 4. Escribir series temporales con etiquetas semánticas
    cat << EOF >> "$TMP_FILE"
custom_disk_bytes_total{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${total}
custom_disk_bytes_used{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${used}
custom_disk_bytes_free{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${avail}
custom_disk_usage_percent{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${pcent_num}
custom_disk_inodes_total{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${itotal}
custom_disk_inodes_used{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${iused}
custom_disk_inodes_free{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${ifree}
custom_disk_inodes_usage_percent{device="${dev}",mountpoint="${mount}",fstype="${fstype}"} ${ipcent_num}
EOF
done

# 5. Reemplazo atómico y permisos para lectura de Node Exporter
mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"

echo "✔ Métricas de disco exportadas exitosamente en: $OUTPUT_FILE"
