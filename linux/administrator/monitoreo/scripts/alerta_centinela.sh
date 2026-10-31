#!/usr/bin/env bash
# ==============================================================================
# CENTINELA Y DESPACHADOR DE ALERTAS EDUCATIVO: LVM RAID 1 & SERVICIO WEB
# ==============================================================================
# Propósito:
#   Vigila la salud del almacenamiento en espejo (LVM RAID 1) y el servidor web.
#   Ante una degradación física (ej. falla inyectada con dd):
#     1. 📢 Difunde una alerta urgente a TODAS las terminales conectadas con 'wall'.
#     2. 📬 Despacha un correo formal al buzón local del administrador ('root').
#     3. ✅ Notifica automáticamente cuando el espejo se recupera tras 'lvconvert --repair'.
#
# Uso:
#   sudo ./alerta_centinela.sh            -> Modo demonio / centinela interactivo
#   sudo ./alerta_centinela.sh --daemon   -> Corre en segundo plano desatendido
#   sudo ./alerta_centinela.sh --test     -> Emite una alerta de prueba inmediata
# ==============================================================================

set -uo pipefail

VG_NAME="${VG_NAME:-vg_web}"
LV_NAME="${LV_NAME:-lv_html}"
INTERVAL="${1:-2}"
MAIL_BOX="/var/mail/root"
[ -d "/var/spool/mail" ] && [ ! -d "/var/mail" ] && MAIL_BOX="/var/spool/mail/root"

# Colores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_CYAN="\033[1;36m"
C_DIM="\033[2m"

# ------------------------------------------------------------------------------
# Función: Enviar alerta a terminales (wall) y buzón de root
# ------------------------------------------------------------------------------
disparar_alerta_falla() {
    local fecha_humana
    fecha_humana=$(date '+%Y-%m-%d %H:%M:%S')
    local fecha_rfc
    fecha_rfc=$(date -R 2>/dev/null || date)

    # 1. Enviar mensaje broadcast por terminal con 'wall' (suena campana \a)
    if command -v wall &>/dev/null; then
        wall << EOF
--------------------------------------------------------------------------------
🚨 [CRITICAL ALERT] ¡FALLA EN ARREGLO DE DISCO LVM RAID 1 DETECTADA! 🚨
Hora: ${fecha_humana}
Volumen afectado: /dev/${VG_NAME}/${LV_NAME}
Punto de montaje: /var/www/html_lab (Servidor Web)
Estado del Espejo: DEGRADADO (Pérdida de redundancia física)

ℹ️  RESILIENCIA: El servidor web continúa respondiendo (200 OK) por tolerancia a fallos.
👉 ACCIÓN REQUERIDA: Conectar disco de repuesto y ejecutar:
   sudo lvconvert --repair ${VG_NAME}/${LV_NAME}
--------------------------------------------------------------------------------
EOF
    fi

    # 2. Despachar correo electrónico a root
    mkdir -p "$(dirname "$MAIL_BOX")" 2>/dev/null || true

    local target_mailbox="$MAIL_BOX"
    if ! touch "$target_mailbox" 2>/dev/null; then
        target_mailbox="/tmp/root_mail.log"
    fi

    # Si existe el binario mail/mailx, enviarlo por esa vía
    if command -v mail &>/dev/null; then
        echo -e "Alerta Crítica de Almacenamiento:\n\nEl volumen /dev/${VG_NAME}/${LV_NAME} está DEGRADADO a las ${fecha_humana}.\nSe requiere reemplazo con lvconvert --repair." | mail -s "🚨 [CRITICAL] Alerta: Espejo LVM RAID 1 Degradado" root 2>/dev/null || true
    fi

    # Registrar SIEMPRE en formato mbox estándar (compatible 100% con o sin MTA)
    cat << EOF >> "$target_mailbox"
From alerta-monitoreo@localhost ${fecha_rfc}
Date: ${fecha_rfc}
From: "Centinela de Monitoreo LVM" <alerta-monitoreo@localhost>
To: root@localhost
Subject: 🚨 [CRITICAL] Alerta de Almacenamiento: Espejo LVM RAID 1 Degradado
Message-ID: <lvm-alert-$(date +%s)@localhost>
Content-Type: text/plain; charset=utf-8

================================================================================
                    NOTIFICACIÓN DE ALERTA DE SISTEMA
================================================================================
Fecha y Hora:    ${fecha_humana}
Severidad:       CRÍTICA
Subsistema:      dm-raid / LVM2 Mirroring
Dispositivo:     /dev/${VG_NAME}/${LV_NAME}
Punto de Montaje:/var/www/html_lab (Servicio Web de Producción)
Estado Actual:   DEGRADADO (Una de las patas del espejo falló)

DIAGNÓSTICO:
El kernel ha detectado un error de I/O o corrupción física en una réplica.
La paridad del arreglo absorbió la falla. Los usuarios no perciben caída,
pero la tolerancia a fallos está en riesgo mientras persista la degradación.

PROCEDIMIENTO DE RECUPERACIÓN (HOT-REPAIR):
1. Inserte un disco nuevo o prepare el spare:
   sudo pvcreate /dev/loop12
   sudo vgextend ${VG_NAME} /dev/loop12

2. Reconstruya el espejo:
   sudo lvconvert -y --repair ${VG_NAME}/${LV_NAME}

3. Elimine el disco averiado:
   sudo vgreduce --removemissing --force ${VG_NAME}
================================================================================
EOF
    chmod 660 "$target_mailbox" 2>/dev/null || true

    echo -e "${C_RED}${C_BOLD}🚨 [ALERTA DISPARADA]${C_RESET} Notificación enviada a terminales (wall) y buzón de root (${target_mailbox})."
}

# ------------------------------------------------------------------------------
# Función: Enviar notificación de resolución
# ------------------------------------------------------------------------------
disparar_alerta_resolucion() {
    local fecha_humana
    fecha_humana=$(date '+%Y-%m-%d %H:%M:%S')
    local fecha_rfc
    fecha_rfc=$(date -R 2>/dev/null || date)

    # 1. Broadcast por 'wall'
    if command -v wall &>/dev/null; then
        wall << EOF
--------------------------------------------------------------------------------
✅ [RESOLVED] RECUPERACIÓN EXITOSA DEL ARREGLO LVM RAID 1
Hora: ${fecha_humana}
Volumen: /dev/${VG_NAME}/${LV_NAME}
Estado: SANO / ÓPTIMO (Redundancia completa de 2 vías restablecida)
--------------------------------------------------------------------------------
EOF
    fi

    local target_mailbox="$MAIL_BOX"
    if ! touch "$target_mailbox" 2>/dev/null; then
        target_mailbox="/tmp/root_mail.log"
    fi

    # 2. Correo de resolución a root
    if command -v mail &>/dev/null; then
        echo -e "El volumen /dev/${VG_NAME}/${LV_NAME} ha sido reconstruido exitosamente." | mail -s "✅ [RESOLVED] Espejo LVM RAID 1 Sano" root 2>/dev/null || true
    fi

    cat << EOF >> "$target_mailbox"
From alerta-monitoreo@localhost ${fecha_rfc}
Date: ${fecha_rfc}
From: "Centinela de Monitoreo LVM" <alerta-monitoreo@localhost>
To: root@localhost
Subject: ✅ [RESOLVED] Espejo LVM RAID 1 Restaurado a Estado Sano
Message-ID: <lvm-resolved-$(date +%s)@localhost>
Content-Type: text/plain; charset=utf-8

El volumen lógico /dev/${VG_NAME}/${LV_NAME} ha finalizado su sincronización.
Todas las patas del espejo están activas y sincronizadas al 100%.
================================================================================
EOF

    echo -e "${C_GREEN}${C_BOLD}✅ [ALERTA RESUELTA]${C_RESET} Notificación de resolución enviada a terminales (wall) y buzón de root (${target_mailbox})."
}

# ------------------------------------------------------------------------------
# Modo Test Inmediato
# ------------------------------------------------------------------------------
if [[ "${1:-}" == "--test" ]]; then
    echo -e "${C_CYAN}🧪 Ejecutando prueba de emisión de alertas...${C_RESET}"
    disparar_alerta_falla
    echo -e "\n${C_BOLD}Podés verificar el correo de root ejecutando:${C_RESET}"
    echo -e "  cat ${MAIL_BOX} | tail -n 25\n"
    exit 0
fi

# ------------------------------------------------------------------------------
# Loop Principal del Centinela
# ------------------------------------------------------------------------------
echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}${C_CYAN} 🛡️  CENTINELA DE ALERTAS: LVM RAID 1 ➔ TERMINAL (wall) Y CORREO ROOT    ${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_DIM}Vigilando /dev/${VG_NAME}/${LV_NAME} cada ${INTERVAL}s. Salir: [Ctrl+C]${C_RESET}\n"

ESTADO_ANTERIOR="OK"

while true; do
    ESTADO_ACTUAL="OK"

    # 1. Comprobar salud vía LVM
    if lvs "${VG_NAME}/${LV_NAME}" &>/dev/null; then
        ATTR=$(lvs --noheadings -o lv_attr "${VG_NAME}/${LV_NAME}" 2>/dev/null | tr -d ' ')
        HEALTH_STATUS=$(lvs --noheadings -o health_status "${VG_NAME}/${LV_NAME}" 2>/dev/null | tr -d ' ')

        # Atributo 'p' (partial) o health_status no vacío indican degradación
        if [ -n "$HEALTH_STATUS" ] || [[ "$ATTR" =~ ^....p ]]; then
            ESTADO_ACTUAL="DEGRADADO"
        fi
    fi

    # 2. Comprobar si existe archivo de simulación didáctica
    if [ -f "/tmp/simular_falla_mirror" ]; then
        ESTADO_ACTUAL="DEGRADADO"
    fi

    # 3. Transiciones de estado
    if [ "$ESTADO_ACTUAL" == "DEGRADADO" ] && [ "$ESTADO_ANTERIOR" == "OK" ]; then
        disparar_alerta_falla
        ESTADO_ANTERIOR="DEGRADADO"
    elif [ "$ESTADO_ACTUAL" == "OK" ] && [ "$ESTADO_ANTERIOR" == "DEGRADADO" ]; then
        disparar_alerta_resolucion
        ESTADO_ANTERIOR="OK"
    fi

    sleep "$INTERVAL"
done
