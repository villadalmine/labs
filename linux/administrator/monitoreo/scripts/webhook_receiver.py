#!/usr/bin/env python3
"""
==============================================================================
RECEPTOR WEBHOOK LOCAL EDUCATIVO PARA ALERTMANAGER (Terminal / Stdout)
==============================================================================
Propósito:
  Permite probar y ver alertas de Alertmanager en tiempo real directamente
  en tu terminal, sin necesidad de configurar servidores SMTP, contraseñas
  de correo, canales de Slack ni servicios web externos.

Uso:
  python3 webhook_receiver.py [puerto]
  (Puerto por defecto: 9999)

Configuración en alertmanager.yml:
  receivers:
    - name: 'terminal-local'
      webhook_configs:
        - url: 'http://127.0.0.1:9999/alert'
          send_resolved: true
==============================================================================
"""

import sys
import json
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

# Colores ANSI para terminal
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_RED = "\033[1;31m"
C_GREEN = "\033[1;32m"
C_YELLOW = "\033[1;33m"
C_CYAN = "\033[1;36m"
C_DIM = "\033[2m"

class AlertManagerHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Desactivamos el log verboso por defecto del HTTP server para mantener limpia la consola
        return

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        try:
            payload = json.loads(post_data.decode('utf-8'))
        except Exception as e:
            print(f"{C_RED}[ERROR] Payload no es JSON válido: {e}{C_RESET}")
            self.send_response(400)
            self.end_headers()
            return

        # Responder 200 OK inmediatamente a Alertmanager
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b"OK\n")

        # Procesar y formatear la notificación recibida
        status_global = payload.get('status', 'unknown').upper()
        alerts = payload.get('alerts', [])
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        print(f"\n{C_CYAN}╔══════════════════════════════════════════════════════════════════════════════╗{C_RESET}")
        if status_global == 'FIRING':
            print(f"{C_CYAN}║{C_RESET} {C_RED}{C_BOLD}🚨 [ALERTMANAGER NOTIFICACIÓN: DISPARADA / FIRING]{C_RESET} — {now_str}")
        else:
            print(f"{C_CYAN}║{C_RESET} {C_GREEN}{C_BOLD}✅ [ALERTMANAGER NOTIFICACIÓN: RESUELTA / RESOLVED]{C_RESET} — {now_str}")
        print(f"{C_CYAN}╠══════════════════════════════════════════════════════════════════════════════╝{C_RESET}")

        for idx, alert in enumerate(alerts, 1):
            st = alert.get('status', '').upper()
            labels = alert.get('labels', {})
            annotations = alert.get('annotations', {})
            
            alert_name = labels.get('alertname', 'AlertaSinNombre')
            severity = labels.get('severity', 'warning').upper()
            mountpoint = labels.get('mountpoint', labels.get('instance', 'N/A'))
            fstype = labels.get('fstype', 'N/A')
            summary = annotations.get('summary', 'Sin resumen')
            description = annotations.get('description', 'Sin descripción')
            starts_at = alert.get('startsAt', 'N/A')

            sev_color = C_RED if severity == 'CRITICAL' else C_YELLOW
            icon = "🔥" if st == 'FIRING' else "✔️"

            print(f"{C_BOLD}  #{idx} {icon} Alerta:{C_RESET} {C_BOLD}{alert_name}{C_RESET}  |  {C_BOLD}Severidad:{C_RESET} {sev_color}{severity}{C_RESET}")
            print(f"     {C_DIM}• Estado:{C_RESET}      {C_BOLD}{st}{C_RESET}")
            print(f"     {C_DIM}• Montaje:{C_RESET}     {mountpoint} (FS: {fstype})")
            print(f"     {C_DIM}• Resumen:{C_RESET}     {summary}")
            print(f"     {C_DIM}• Detalle:{C_RESET}     {description}")
            print(f"     {C_DIM}• Iniciada:{C_RESET}    {starts_at}")
            print(f"{C_CYAN}────────────────────────────────────────────────────────────────────────────────{C_RESET}")

def run(port=9999):
    server_address = ('127.0.0.1', port)
    httpd = HTTPServer(server_address, AlertManagerHandler)
    print(f"{C_BOLD}{C_GREEN}==============================================================================={C_RESET}")
    print(f"{C_BOLD}{C_GREEN} 🔔 RECEPTOR DE ALERTAS DE ALERTMANAGER ACTIVO EN PUERTO {port}                {C_RESET}")
    print(f"{C_BOLD}{C_GREEN}==============================================================================={C_RESET}")
    print(f" • Escuchando en: {C_CYAN}http://127.0.0.1:{port}/alert{C_RESET}")
    print(f" • Esperando alertas de Prometheus Alertmanager...")
    print(f" • Presiona {C_BOLD}Ctrl+C{C_RESET} para detener.\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print(f"\n{C_YELLOW}[INFO] Receptor de alertas detenido por el usuario.{C_RESET}")
        httpd.server_close()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9999
    run(port)
