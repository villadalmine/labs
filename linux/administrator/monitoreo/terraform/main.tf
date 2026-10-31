# ==============================================================================
# INFRAESTRUCTURA AWS: Taller Integrador Web sobre LVM RAID 1 y Monitoreo
# Instancia EC2 con 2 discos EBS adicionales para LVM RAID 1 y puertos expuestos
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

# 4. Security Group con todos los puertos expuestos para el laboratorio
resource "aws_security_group" "sg" {
  name        = "${var.project_name}-sg"
  description = "Reglas de firewall para Servidor Web, LVM, Node Exporter, Prometheus y Grafana"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "HTTP Web Standard"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "HTTP Web Lab"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Node Exporter PULL Metrics"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Prometheus Server UI & API"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  ingress {
    description = "Grafana Dashboards"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  egress {
    description = "Salida completa a Internet para instalacion de paquetes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# 5. Instancia EC2
resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.kp.key_name
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.sg.id]

  root_block_device {
    volume_size           = 15
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Provisionamiento inicial rápido usando APT nativo
  user_data = <<-EOF
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq
              apt-get install -y -qq lvm2 curl git htop prometheus-node-exporter prometheus grafana
              
              # Configurar textfile collector en Node Exporter nativo
              mkdir -p /var/lib/node_exporter/textfile_collector
              chown -R prometheus:prometheus /var/lib/node_exporter/textfile_collector 2>/dev/null || true
              
              # Habilitar y arrancar servicios
              systemctl enable --now prometheus-node-exporter 2>/dev/null || true
              systemctl enable --now prometheus 2>/dev/null || true
              systemctl enable --now grafana-server 2>/dev/null || true
              EOF

  tags = {
    Name = "${var.project_name}-server"
  }
}

# 6. Discos EBS gp3 adicionales para LVM RAID 1 (1 GB cada uno)
resource "aws_ebs_volume" "disk_a" {
  availability_zone = aws_instance.server.availability_zone
  size              = 1
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-ebs-disk1"
  }
}

resource "aws_ebs_volume" "disk_b" {
  availability_zone = aws_instance.server.availability_zone
  size              = 1
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-ebs-disk2"
  }
}

resource "aws_volume_attachment" "attach_disk_a" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.disk_a.id
  instance_id = aws_instance.server.id
}

resource "aws_volume_attachment" "attach_disk_b" {
  device_name = "/dev/sdg"
  volume_id   = aws_ebs_volume.disk_b.id
  instance_id = aws_instance.server.id
}
