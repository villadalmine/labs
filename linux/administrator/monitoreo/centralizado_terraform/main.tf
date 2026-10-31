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

  user_data = <<-CENTRAL_BOOTSTRAP
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
              apt-get install -y -qq apt-transport-https software-properties-common wget curl jq prometheus gpg

              mkdir -p /etc/apt/keyrings/
              wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
              echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
              apt-get update -qq
              apt-get install -y -qq grafana

              # 2. Configuración centralizada de Prometheus hacia los dos workers
              cat << 'PCONF' > /etc/prometheus/prometheus.yml
              global:
                scrape_interval: 2s
                evaluation_interval: 2s

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
              ${file("${path.module}/../dashboards/dashboard_centralizado_multinodo.json")}
              JSONDASH
              chown -R grafana:grafana /var/lib/grafana/dashboards

              systemctl restart prometheus
              systemctl enable --now prometheus
              systemctl restart grafana-server
              systemctl enable --now grafana-server
              CENTRAL_BOOTSTRAP

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
              HEALTH=$(lvs --noheadings --readonly -o health_status vg_web/lv_html 2>/dev/null | tr -d ' ' || true)
              ATTR=$(lvs --noheadings --readonly -o attr vg_web/lv_html 2>/dev/null | tr -d ' ' || true)
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
