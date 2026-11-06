# ==============================================================================
# CLUSTER DE MONITOREO CENTRALIZADO MULTI-NODO EN AWS
# - Servidor 1 (Central): Prometheus (:9090) + Grafana (:3000)
# - Servidor 2 (Worker 1): Servidor Web + LVM RAID 1 + Node Exporter (:9100)
# - Servidor 3 (Worker 2): Servidor de Datos Cifrados LUKS + Node Exporter (:9100)
# ==============================================================================

# 1. Clave SSH generada automáticamente
resource "tls_private_key" "ssh_key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "kp" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_openssh
  filename        = "${path.module}/id_ed25519"
  file_permission = "0600"
}

# 2. AMI Oficial de Ubuntu 24.04 LTS (Noble Numbat)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Detección dinámica de la IP pública del operador si no se especifica allowed_cidr
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  # Si el usuario no especifica allowed_cidr, se auto-detecta la IP pública del operador y se restringe a /32
  detected_ip = chomp(data.http.my_ip.response_body)
  admin_cidr  = var.allowed_cidr != "" ? var.allowed_cidr : "${local.detected_ip}/32"
}

# 3. Red: VPC, Subnet e Internet Gateway
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-rt"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

# 4. Security Groups: Separación de Central y Nodos Productivos
resource "aws_security_group" "sg_central" {
  name        = "${var.project_name}-sg-central"
  description = "Reglas para el Servidor Central de Monitoreo (Prometheus y Grafana)"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH hacia Servidor Central"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Prometheus UI y API"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Grafana Web Dashboards"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Prometheus Alertmanager UI"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Alert Hub Web en Vivo (Receptor Webhook + Panel NOC + Bridge ntfy.sh)"
    from_port   = 9999
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Trafico interno completo dentro de la VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Salida total a Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-central"
  }
}

resource "aws_security_group" "sg_workers" {
  name        = "${var.project_name}-sg-workers"
  description = "Reglas para los Nodos Productivos (Web y Storage)"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH hacia Workers"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "HTTP Web (Worker 1)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "HTTP Web Lab alternativo"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Node Exporter PULL permitido exclusivamente desde la VPC interna"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Salida total a Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-workers"
  }
}

# 5. Instancia Central: Prometheus + Grafana (IP Fija 10.0.1.10)
resource "aws_instance" "srv_central" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.kp.key_name
  subnet_id              = aws_subnet.subnet.id
  private_ip             = "10.0.1.10"
  vpc_security_group_ids = [aws_security_group.sg_central.id]

  root_block_device {
    volume_size           = 15
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(<<-CENTRAL_BOOTSTRAP
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive

              # 0. Crear Swapfile de 2GB para garantizar estabilidad de Grafana en instancias t3.micro
              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # 1. Instalar dependencias y repositorio oficial de Grafana
              apt-get update -qq
              apt-get install -y -qq apt-transport-https software-properties-common wget curl jq prometheus prometheus-alertmanager python3 gpg

              mkdir -p /etc/apt/keyrings/
              wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
              echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
              apt-get update -qq
              apt-get install -y -qq grafana

              # 2. Reglas de Alerta de Prometheus (LVM RAID 1, LUKS2 y Caída de Nodos)
              cat << 'ARULES' > /etc/prometheus/alert_rules.yml
              groups:
                - name: cluster_resilience_and_security_alerts
                  interval: 2s
                  rules:
                    - alert: LvmRaid1Degradado
                      expr: node_lvm_mirror_health == 0
                      for: 2s
                      labels:
                        severity: critical
                        subsystem: lvm-raid1
                      annotations:
                        summary: "🚨 Espejo LVM RAID 1 DEGRADADO en Worker 1 (srv-web-lvm)"
                        description: "Se detectó pérdida de redundancia física en /dev/vg_web/lv_html (10.0.1.20). El sitio web sigue ONLINE (HTTP 200) por tolerancia a fallos. Ejecutar hot-repair: vgreduce --removemissing --force vg_web && pvcreate -ff -y /dev/nvme1n1 && vgextend vg_web /dev/nvme1n1 && lvconvert -y --repair vg_web/lv_html"

                    - alert: LuksContenedorCerrado
                      expr: node_luks_container_active == 0
                      for: 2s
                      labels:
                        severity: critical
                        subsystem: luks2-dmcrypt
                      annotations:
                        summary: "🔐 Bóveda Cifrada LUKS2 CERRADA en Worker 2 (srv-data-luks)"
                        description: "El volumen criptográfico /dev/mapper/datos_seguros (10.0.1.30) fue desmontado o bloqueado. Datos en /data/segura inaccesibles."

                    - alert: NodoWorkerCaido
                      expr: up == 0
                      for: 5s
                      labels:
                        severity: critical
                        subsystem: node-availability
                      annotations:
                        summary: "⚠️ Nodo {{ $labels.job }} ({{ $labels.instance }}) INALCANZABLE"
                        description: "Prometheus no puede recolectar métricas del nodo {{ $labels.job }} desde hace más de 5 segundos."
              ARULES

              # 2b. Configuración centralizada de Prometheus hacia los dos workers + Alertmanager
              cat << 'PCONF' > /etc/prometheus/prometheus.yml
              global:
                scrape_interval: 2s
                evaluation_interval: 2s

              alerting:
                alertmanagers:
                  - static_configs:
                      - targets: ['localhost:9093']

              rule_files:
                - '/etc/prometheus/alert_rules.yml'

              scrape_configs:
                - job_name: 'srv-monitoreo-central'
                  static_configs:
                    - targets: ['localhost:9090']

                - job_name: 'srv-web-lvm'
                  static_configs:
                    - targets: ['10.0.1.20:9100']
                      labels:
                        role: 'web-storage'
                        storage: 'lvm-raid1'
                        env: 'produccion'

                - job_name: 'srv-data-luks'
                  static_configs:
                    - targets: ['10.0.1.30:9100']
                      labels:
                        role: 'secure-database'
                        storage: 'luks2-encrypted'
                        env: 'produccion'
              PCONF

              # 2c. Configurar Prometheus Alertmanager (:9093) -> Webhook hacia Alert Hub (:9999)
              cat << 'AMCONF' > /etc/prometheus/alertmanager.yml
              global:
                resolve_timeout: 1m

              route:
                group_by: ['alertname', 'job']
                group_wait: 1s
                group_interval: 2s
                repeat_interval: 1h
                receiver: 'alert-hub-and-ntfy'

              receivers:
                - name: 'alert-hub-and-ntfy'
                  webhook_configs:
                    - url: 'http://127.0.0.1:9999/webhook'
                      send_resolved: true
              AMCONF

              # 2d. Crear Servicio Alert Hub Web (:9999) + Puente automático hacia ntfy.sh
              cat << 'HUBPY' > /usr/local/bin/alert_hub.py
              #!/usr/bin/env python3
              import json
              import os
              import urllib.request
              from datetime import datetime, timezone
              from http.server import HTTPServer, BaseHTTPRequestHandler

              NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "lab-sre-monitoreo-aws-dalmine")
              EVENTS = []

              def strip_emojis(text):
                  return text.encode("ascii", "ignore").decode("ascii").strip()

              def push_ntfy(title, message, priority="default", tags="warning"):
                  if not NTFY_TOPIC:
                      return
                  try:
                      req = urllib.request.Request(
                          f"https://ntfy.sh/{NTFY_TOPIC}",
                          data=message.encode("utf-8"),
                          headers={
                              "Title": strip_emojis(title),
                              "Priority": priority,
                              "Tags": tags,
                          },
                          method="POST"
                      )
                      urllib.request.urlopen(req, timeout=5)
                  except Exception as e:
                      print(f"[WARN] Error enviando a ntfy.sh: {e}", flush=True)

              class HubHandler(BaseHTTPRequestHandler):
                  def log_message(self, fmt, *args):
                      return

                  def do_POST(self):
                      length = int(self.headers.get("Content-Length", 0))
                      raw = self.rfile.read(length)
                      try:
                          payload = json.loads(raw.decode("utf-8"))
                      except Exception:
                          self.send_response(400)
                          self.end_headers()
                          return

                      now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
                      for alert in payload.get("alerts", []):
                          status = alert.get("status", "firing").upper()
                          labels = alert.get("labels", {})
                          ann = alert.get("annotations", {})
                          name = labels.get("alertname", "Alert")
                          job = labels.get("job", labels.get("instance", "cluster"))
                          severity = labels.get("severity", "critical").upper()
                          summary = ann.get("summary", name)
                          desc = ann.get("description", "")

                          event = {
                              "time": now,
                              "status": status,
                              "name": name,
                              "job": job,
                              "severity": severity,
                              "summary": summary,
                              "description": desc,
                          }
                          EVENTS.insert(0, event)
                          del EVENTS[50:]

                          if status == "FIRING":
                              push_ntfy(
                                  title=f"[FIRING] {name} ({job})",
                                  message=f"{summary}\n\n{desc}\nHora: {now}",
                                  priority="urgent",
                                  tags="rotating_light,skull"
                              )
                          else:
                              push_ntfy(
                                  title=f"[RESOLVED] {name} ({job})",
                                  message=f"Incidente resuelto y servicio normalizado.\n{summary}\nHora: {now}",
                                  priority="high",
                                  tags="white_check_mark,tada"
                              )

                      self.send_response(200)
                      self.send_header("Content-Type", "application/json")
                      self.end_headers()
                      self.wfile.write(b'{"status":"ok"}')

                  def do_GET(self):
                      if self.path.startswith("/api/events"):
                          self.send_response(200)
                          self.send_header("Content-Type", "application/json")
                          self.end_headers()
                          self.wfile.write(json.dumps({"ntfy_topic": NTFY_TOPIC, "events": EVENTS}).encode("utf-8"))
                          return

                      self.send_response(200)
                      self.send_header("Content-Type", "text/html; charset=utf-8")
                      self.end_headers()
                      rows = ""
                      if not EVENTS:
                          rows = '<div style="padding:30px;text-align:center;color:#a6adc8;background:#181825;border-radius:10px;border:1px dashed #45475a;">✅ Sin incidentes registrados. Todos los sistemas (LVM RAID 1 y LUKS2) operando normalmente.</div>'
                      else:
                          for ev in EVENTS:
                              is_firing = ev["status"] == "FIRING"
                              border = "#f38ba8" if is_firing else "#a6e3a1"
                              bg = "rgba(243, 139, 168, 0.12)" if is_firing else "rgba(166, 227, 161, 0.12)"
                              badge_bg = "#f38ba8" if is_firing else "#a6e3a1"
                              badge_txt = "🚨 FIRING (ACTIVA)" if is_firing else "✅ RESOLVED (RESUELTA)"
                              rows += f'''
                              <div style="background:{bg};border-left:6px solid {border};padding:18px 22px;border-radius:8px;margin-bottom:14px;border:1px solid {border};">
                                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                                  <span style="background:{badge_bg};color:#11111b;font-weight:800;padding:4px 10px;border-radius:6px;font-size:0.85em;">{badge_txt}</span>
                                  <span style="color:#bac2de;font-family:monospace;font-size:0.9em;">{ev["time"]} | Nodo: {ev["job"]}</span>
                                </div>
                                <div style="font-size:1.15em;font-weight:700;color:#cdd6f4;margin-bottom:6px;">{ev["summary"]}</div>
                                <div style="color:#bac2de;font-size:0.95em;line-height:1.45;font-family:monospace;">{ev["description"]}</div>
                              </div>'''

                      html = f'''<!DOCTYPE html>
                      <html lang="es">
                      <head>
                        <meta charset="UTF-8">
                        <meta http-equiv="refresh" content="3">
                        <title>SRE Alert Hub & ntfy.sh Bridge</title>
                      </head>
                      <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#11111b;color:#cdd6f4;margin:0;padding:30px;">
                        <div style="max-width:920px;margin:0 auto;">
                          <div style="display:flex;justify-content:space-between;align-items:center;background:#1e1e2e;padding:20px 28px;border-radius:12px;border:1px solid #313244;margin-bottom:24px;">
                            <div>
                              <h1 style="margin:0 0 6px 0;color:#cba6f7;font-size:1.5em;">🔔 SRE Alert Hub — Centro de Incidentes en Vivo</h1>
                              <div style="color:#a6adc8;font-size:0.92em;">Conectado a <b>Prometheus Alertmanager (:9093)</b> y reenviando push en vivo a <a href="https://ntfy.sh/{NTFY_TOPIC}" target="_blank" style="color:#89b4fa;font-weight:bold;">https://ntfy.sh/{NTFY_TOPIC}</a></div>
                            </div>
                            <div style="text-align:right;">
                              <span style="display:inline-block;padding:6px 12px;background:#313244;border-radius:20px;font-size:0.82em;color:#a6e3a1;">● Auto-Refresh 3s</span>
                            </div>
                          </div>
                          {rows}
                        </div>
                      </body>
                      </html>'''
                      self.wfile.write(html.encode("utf-8"))

              if __name__ == "__main__":
                  HTTPServer(("0.0.0.0", 9999), HubHandler).serve_forever()
              HUBPY
              chmod +x /usr/local/bin/alert_hub.py

              cat << 'HUBSVC' > /etc/systemd/system/alert-hub.service
              [Unit]
              Description=SRE Alert Hub Web & ntfy.sh Webhook Bridge
              After=network.target

              [Service]
              Type=simple
              Environment="NTFY_TOPIC=${var.ntfy_topic}"
              ExecStart=/usr/bin/python3 /usr/local/bin/alert_hub.py
              Restart=always
              RestartSec=2

              [Install]
              WantedBy=multi-user.target
              HUBSVC

              # 3. Configurar Grafana: Acceso Anónimo como Admin (Apertura inmediata sin contraseña)
              cat << 'GCONF' >> /etc/grafana/grafana.ini
              [auth.anonymous]
              enabled = true
              org_role = Admin

              [security]
              allow_embedding = true
              admin_password = admin
              GCONF

              # 4. Auto-aprovisionar Datasource Prometheus
              mkdir -p /etc/grafana/provisioning/datasources
              cat << 'DSCONF' > /etc/grafana/provisioning/datasources/prometheus.yaml
              apiVersion: 1
              datasources:
                - name: Prometheus
                  type: prometheus
                  uid: prometheus
                  access: proxy
                  url: http://localhost:9090
                  isDefault: true
                  editable: true
              DSCONF

              # 5. Auto-aprovisionar Dashboards en Grafana
              mkdir -p /etc/grafana/provisioning/dashboards
              cat << 'DBCONF' > /etc/grafana/provisioning/dashboards/dashboards.yaml
              apiVersion: 1
              providers:
                - name: 'default'
                  orgId: 1
                  folder: ''
                  type: file
                  disableDeletion: false
                  updateIntervalSeconds: 5
                  options:
                    path: /var/lib/grafana/dashboards
              DBCONF

              mkdir -p /var/lib/grafana/dashboards
              cat << 'JSONDASH' > /var/lib/grafana/dashboards/cluster.json
              ${replace(file("${path.module}/../dashboards/dashboard_centralizado_multinodo.json"), "\n", "\n              ")}
              JSONDASH
              chown -R grafana:grafana /var/lib/grafana/dashboards

              systemctl daemon-reload
              systemctl enable --now alert-hub.service
              systemctl restart prometheus-alertmanager
              systemctl enable --now prometheus-alertmanager
              systemctl restart prometheus
              systemctl enable --now prometheus
              systemctl restart grafana-server
              systemctl enable --now grafana-server
              CENTRAL_BOOTSTRAP
  )

  tags = {
    Name = "${var.project_name}-srv-monitoreo"
    Role = "Central-Monitoring"
  }
}

# 6. Instancia Worker 1: srv-web-lvm (IP Fija 10.0.1.20) con 2 discos EBS para LVM RAID 1
resource "aws_instance" "srv_web_lvm" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.kp.key_name
  subnet_id              = aws_subnet.subnet.id
  private_ip             = "10.0.1.20"
  vpc_security_group_ids = [aws_security_group.sg_workers.id]

  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-WEB_BOOTSTRAP
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq
              apt-get install -y -qq lvm2 prometheus-node-exporter nginx curl

              # Esperar a que los 2 discos EBS gp3 adicionales se adjunten
              sleep 12
              DISKS=($(lsblk -dnpo NAME,TYPE | grep "disk" | grep -v "nvme0n1\|xvda\|sda" | awk '{print $1}'))
              D1="$${DISKS[0]:-/dev/nvme1n1}"
              D2="$${DISKS[1]:-/dev/nvme2n1}"

              if [ -b "$D1" ] && [ -b "$D2" ]; then
                  pvcreate -y -ff "$D1" "$D2"
                  vgcreate -y vg_web "$D1" "$D2"
                  lvcreate -y --type raid1 -m 1 -L 800M -n lv_html vg_web "$D1" "$D2"
                  mkfs.ext4 -F -q /dev/vg_web/lv_html
                  mkdir -p /var/www/html
                  mount /dev/vg_web/lv_html /var/www/html
                  echo "/dev/mapper/vg_web-lv_html /var/www/html ext4 defaults,nofail 0 2" >> /etc/fstab
              fi

              echo 'charset utf-8;' > /etc/nginx/conf.d/charset.conf
              systemctl reload nginx

              cat << 'HTML' > /var/www/html/index.html
              <!DOCTYPE html>
              <html lang="es">
              <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>Servidor Web de Producción - LVM RAID 1</title>
              </head>
              <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; text-align: center; padding: 60px 20px; background: #11111b; color: #cdd6f4;">
                <div style="max-width: 600px; margin: 0 auto; background: #1e1e2e; padding: 40px; border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.5); border: 1px solid #313244;">
                  <h1 style="color: #a6e3a1; margin-bottom: 20px;">🚀 SERVIDOR WEB DE PRODUCCIÓN EN AWS</h1>
                  <p style="font-size: 1.1em; line-height: 1.6; margin-bottom: 15px;">
                    Almacenamiento: <strong style="color: #89b4fa;">LVM RAID 1 Espejado (/dev/vg_web/lv_html)</strong>
                  </p>
                  <p style="color: #a6adc8; font-size: 0.95em;">
                    Tolerancia activa con <code>dm-raid</code>. Conectado al Servidor Central en <code>10.0.1.10</code>.
                  </p>
                  <div style="margin-top: 30px; display: inline-block; padding: 8px 16px; background: rgba(166, 227, 161, 0.15); border: 1px solid #a6e3a1; border-radius: 20px; color: #a6e3a1; font-weight: bold;">
                    ● ESTADO: ONLINE (HTTP 200 OK)
                  </div>
                </div>
              </body>
              </html>
              HTML

              # Configurar Textfile Collector en Node Exporter nativo de Ubuntu
              mkdir -p /var/lib/prometheus/node-exporter
              chmod 755 /var/lib/prometheus/node-exporter
              echo 'ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"' > /etc/default/prometheus-node-exporter

              # Script puntual (oneshot) para telemetría de LVM en tiempo real
              cat << 'EOF' > /usr/local/bin/update_lvm_metric.sh
              #!/bin/bash
              VAL=1
              HEALTH=$(lvs --noheadings -o health_status vg_web/lv_html 2>/dev/null | tr -d ' ' || true)
              ATTR=$(lvs --noheadings -o attr vg_web/lv_html 2>/dev/null | tr -d ' ' || true)
              if [ -n "$HEALTH" ] || [[ "$ATTR" =~ p ]] || [[ "$ATTR" =~ d ]]; then
                  VAL=0
              fi
              TMP_FILE="/var/lib/prometheus/node-exporter/lvm_health.prom.tmp.$$"
              cat << PROM > "$TMP_FILE"
              # HELP node_lvm_mirror_health Estado de redundancia del espejo LVM (1=Sano, 0=Degradado)
              # TYPE node_lvm_mirror_health gauge
              node_lvm_mirror_health{vg="vg_web",lv="lv_html"} $VAL
              PROM
              chmod 644 "$TMP_FILE"
              mv -f "$TMP_FILE" /var/lib/prometheus/node-exporter/lvm_health.prom
              EOF
              chmod +x /usr/local/bin/update_lvm_metric.sh

              # Ejecución inicial inmediata para que la métrica exista desde el inicio
              /usr/local/bin/update_lvm_metric.sh || true

              # Unidad de servicio Systemd (Type=oneshot)
              cat << 'EOF' > /etc/systemd/system/lvm-metric.service
              [Unit]
              Description=LVM Mirror Health Metric Collector
              After=network.target

              [Service]
              Type=oneshot
              ExecStart=/usr/local/bin/update_lvm_metric.sh
              TimeoutSec=5
              EOF

              # Unidad de Timer Systemd (ejecución periódica cada 3 segundos)
              cat << 'EOF' > /etc/systemd/system/lvm-metric.timer
              [Unit]
              Description=Timer para actualizar telemetria LVM cada 3 segundos
              After=network.target

              [Timer]
              OnBootSec=5s
              OnUnitActiveSec=3s
              AccuracySec=100ms

              [Install]
              WantedBy=timers.target
              EOF

              systemctl daemon-reload
              systemctl enable --now lvm-metric.timer
              systemctl restart prometheus-node-exporter
              systemctl enable --now prometheus-node-exporter
              systemctl restart nginx
              systemctl enable --now nginx
              WEB_BOOTSTRAP

  tags = {
    Name = "${var.project_name}-srv-web-lvm"
    Role = "Web-LVM-Worker"
  }
}

resource "aws_ebs_volume" "disk_web_1" {
  availability_zone = aws_instance.srv_web_lvm.availability_zone
  size              = 1
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-web-ebs-disk1"
  }
}

resource "aws_ebs_volume" "disk_web_2" {
  availability_zone = aws_instance.srv_web_lvm.availability_zone
  size              = 1
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-web-ebs-disk2"
  }
}

resource "aws_volume_attachment" "attach_web_1" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.disk_web_1.id
  instance_id = aws_instance.srv_web_lvm.id
}

resource "aws_volume_attachment" "attach_web_2" {
  device_name = "/dev/sdg"
  volume_id   = aws_ebs_volume.disk_web_2.id
  instance_id = aws_instance.srv_web_lvm.id
}

# 7. Instancia Worker 2: srv-data-luks (IP Fija 10.0.1.30) con 1 disco EBS para LUKS
resource "aws_instance" "srv_data_luks" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.kp.key_name
  subnet_id              = aws_subnet.subnet.id
  private_ip             = "10.0.1.30"
  vpc_security_group_ids = [aws_security_group.sg_workers.id]

  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-LUKS_BOOTSTRAP
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq
              apt-get install -y -qq cryptsetup prometheus-node-exporter curl

              # Esperar a que el disco EBS gp3 de 1 GB se adjunte
              sleep 12
              DISKS=($(lsblk -dnpo NAME,TYPE | grep "disk" | grep -v "nvme0n1\|xvda\|sda" | awk '{print $1}'))
              D_LUKS="$${DISKS[0]:-/dev/nvme1n1}"

              if [ -b "$D_LUKS" ]; then
                  KEY_FILE="/root/luks.key"
                  openssl rand -base64 32 > "$KEY_FILE"
                  chmod 0400 "$KEY_FILE"
                  cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 --batch-mode --key-file "$KEY_FILE" "$D_LUKS"
                  cryptsetup open --key-file "$KEY_FILE" "$D_LUKS" datos_seguros
                  mkfs.ext4 -F -q /dev/mapper/datos_seguros
                  mkdir -p /data/segura
                  mount /dev/mapper/datos_seguros /data/segura
                  echo "CONFIDENTIAL_PRODUCTION_DATA_2026" > /data/segura/datos_clientes.db
                  echo "datos_seguros $D_LUKS $KEY_FILE luks" >> /etc/crypttab
                  echo "/dev/mapper/datos_seguros /data/segura ext4 defaults,nofail 0 2" >> /etc/fstab
              fi

              # Configurar Textfile Collector en Node Exporter nativo de Ubuntu
              mkdir -p /var/lib/prometheus/node-exporter
              chmod 755 /var/lib/prometheus/node-exporter
              echo 'ARGS="--collector.textfile.directory=/var/lib/prometheus/node-exporter"' > /etc/default/prometheus-node-exporter

              # Script puntual (oneshot) para telemetría de LUKS
              cat << 'EOF' > /usr/local/bin/update_luks_metric.sh
              #!/bin/bash
              VAL=0
              if cryptsetup status datos_seguros 2>/dev/null | grep -q "is active"; then
                  VAL=1
              fi
              TMP_FILE="/var/lib/prometheus/node-exporter/luks_status.prom.tmp.$$"
              cat << PROM > "$TMP_FILE"
              # HELP node_luks_container_active Estado del contenedor LUKS (1=Abierto, 0=Cerrado)
              # TYPE node_luks_container_active gauge
              node_luks_container_active{device="datos_seguros"} $VAL
              PROM
              chmod 644 "$TMP_FILE"
              mv -f "$TMP_FILE" /var/lib/prometheus/node-exporter/luks_status.prom
              EOF
              chmod +x /usr/local/bin/update_luks_metric.sh

              # Ejecución inicial inmediata para que la métrica exista desde el inicio
              /usr/local/bin/update_luks_metric.sh || true

              # Unidad de servicio Systemd (Type=oneshot)
              cat << 'EOF' > /etc/systemd/system/luks-metric.service
              [Unit]
              Description=LUKS Container Status Metric Collector
              After=network.target

              [Service]
              Type=oneshot
              ExecStart=/usr/local/bin/update_luks_metric.sh
              TimeoutSec=5
              EOF

              # Unidad de Timer Systemd (ejecución periódica cada 3 segundos)
              cat << 'EOF' > /etc/systemd/system/luks-metric.timer
              [Unit]
              Description=Timer para actualizar telemetria LUKS cada 3 segundos
              After=network.target

              [Timer]
              OnBootSec=5s
              OnUnitActiveSec=3s
              AccuracySec=100ms

              [Install]
              WantedBy=timers.target
              EOF

              systemctl daemon-reload
              systemctl enable --now luks-metric.timer
              systemctl restart prometheus-node-exporter
              systemctl enable --now prometheus-node-exporter
              LUKS_BOOTSTRAP

  tags = {
    Name = "${var.project_name}-srv-data-luks"
    Role = "Data-LUKS-Worker"
  }
}

resource "aws_ebs_volume" "disk_luks" {
  availability_zone = aws_instance.srv_data_luks.availability_zone
  size              = 1
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-luks-ebs-disk"
  }
}

resource "aws_volume_attachment" "attach_luks" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.disk_luks.id
  instance_id = aws_instance.srv_data_luks.id
}

# 8. Elastic IPs (IPs Públicas Estáticas que NUNCA cambian al correr Terraform o reiniciar instancias)
resource "aws_eip" "eip_central" {
  instance = aws_instance.srv_central.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip-central"
  }
}

resource "aws_eip" "eip_web" {
  instance = aws_instance.srv_web_lvm.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip-web"
  }
}

resource "aws_eip" "eip_luks" {
  instance = aws_instance.srv_data_luks.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip-luks"
  }
}
