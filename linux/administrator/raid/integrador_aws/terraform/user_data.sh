#!/usr/bin/env bash
# ==============================================================================
# Script de aprovisionamiento Cloud-Init para la Instancia EC2
# Configura herramientas de RAID, Nginx y Prometheus Node Exporter con métricas RAID
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [1/4] Actualizando paquetes e instalando dependencias ==="
apt-get update -qq
apt-get install -y -qq \
    mdadm \
    lvm2 \
    btrfs-progs \
    prometheus-node-exporter \
    nginx \
    jq \
    curl \
    util-linux

echo "=== [2/4] Configurando Prometheus Node Exporter Textfile Collector ==="
mkdir -p /var/lib/prometheus/node-exporter
chown -R prometheus:prometheus /var/lib/prometheus/node-exporter 2>/dev/null || true

# Configurar argumentos de Node Exporter en Ubuntu (/etc/default/prometheus-node-exporter)
cat << 'EOF' > /etc/default/prometheus-node-exporter
ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"
EOF

systemctl daemon-reload
systemctl restart prometheus-node-exporter
systemctl enable prometheus-node-exporter

echo "=== [3/4] Creando servicio de telemetría de métricas RAID ==="
cat << 'EOF' > /usr/local/bin/update_raid_metrics.sh
#!/usr/bin/env bash
PROM_FILE="/var/lib/prometheus/node-exporter/raid.prom"
TMP_FILE="${PROM_FILE}.tmp"

# Valores por defecto
STATUS_NUM=1
ACTIVE_DISKS=0
FAILED_DISKS=0
SPARE_DISKS=0
SYNC_PERCENT=100

MD_DEV=$(ls -d /sys/block/md* 2>/dev/null | head -1 || true)

if [ -n "$MD_DEV" ] && [ -d "$MD_DEV/md" ]; then
    DEGRADED=$(cat "$MD_DEV/md/degraded" 2>/dev/null || echo 0)
    SYNC_ACTION=$(cat "$MD_DEV/md/sync_action" 2>/dev/null || echo "idle")
    
    if [ "$DEGRADED" -eq 1 ]; then
        STATUS_NUM=0
    else
        STATUS_NUM=1
    fi
    
    # Extraer contadores desde mdadm si el dispositivo existe
    DEV_NAME="/dev/$(basename "$MD_DEV")"
    if [ -b "$DEV_NAME" ]; then
        DETAIL=$(mdadm --detail "$DEV_NAME" 2>/dev/null || true)
        ACTIVE_DISKS=$(echo "$DETAIL" | awk '/Active Devices :/ {print $4}')
        FAILED_DISKS=$(echo "$DETAIL" | awk '/Failed Devices :/ {print $4}')
        SPARE_DISKS=$(echo "$DETAIL" | awk '/Spare Devices :/ {print $4}')
        
        # Sincronización o recuperación
        if grep -q "recovery =" /proc/mdstat; then
            SYNC_PERCENT=$(grep "recovery =" /proc/mdstat | awk '{print $4}' | tr -d '%')
        elif grep -q "resync =" /proc/mdstat; then
            SYNC_PERCENT=$(grep "resync =" /proc/mdstat | awk '{print $4}' | tr -d '%')
        fi
    fi
fi

ACTIVE_DISKS=${ACTIVE_DISKS:-0}
FAILED_DISKS=${FAILED_DISKS:-0}
SPARE_DISKS=${SPARE_DISKS:-0}
SYNC_PERCENT=${SYNC_PERCENT:-100}

cat << METRICS > "$TMP_FILE"
# HELP raid_healthy Estado de salud del arreglo RAID (1 = Clean/Healthy, 0 = Degraded)
# TYPE raid_healthy gauge
raid_healthy $STATUS_NUM
# HELP raid_active_disks Cantidad de discos activos sirviendo datos
# TYPE raid_active_disks gauge
raid_active_disks $ACTIVE_DISKS
# HELP raid_failed_disks Cantidad de discos en estado de falla
# TYPE raid_failed_disks gauge
raid_failed_disks $FAILED_DISKS
# HELP raid_spare_disks Cantidad de unidades de repuesto (hot spare) disponibles
# TYPE raid_spare_disks gauge
raid_spare_disks $SPARE_DISKS
# HELP raid_sync_percent Porcentaje de resincronización o reconstrucción
# TYPE raid_sync_percent gauge
raid_sync_percent $SYNC_PERCENT
METRICS

mv "$TMP_FILE" "$PROM_FILE"
EOF

chmod +x /usr/local/bin/update_raid_metrics.sh
/usr/local/bin/update_raid_metrics.sh

# Crear Systemd Timer de alta resolución para actualizar métricas cada 5 segundos
cat << 'EOF' > /etc/systemd/system/raid-metrics.service
[Unit]
Description=Publicador de metricas RAID para Prometheus Textfile Collector

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update_raid_metrics.sh
EOF

cat << 'EOF' > /etc/systemd/system/raid-metrics.timer
[Unit]
Description=Ejecutar recolector de metricas RAID periodicamente

[Timer]
OnBootSec=10s
OnUnitActiveSec=5s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now raid-metrics.timer

echo "=== [4/4] Inicialización completada exitosamente ==="
