# ==============================================================================
# INFRAESTRUCTURA AWS: Trabajo Integrador RAID Empresarial & Resiliencia
# - 1 Instancia EC2 Ubuntu 24.04 LTS (t3.micro - Free Tier)
# - 5 Volúmenes EBS de 1 GB (gp3):
#     * Discos 1, 2, 3: Arreglo RAID 5 Base
#     * Disco 4: Hot Spare en caliente
#     * Disco 5: Disco de repuesto físico para reemplazo tras desastre
# - Prometheus Node Exporter + Textfile Collector para telemetría continua
# ==============================================================================

# 1. Obtener la última AMI oficial de Ubuntu 24.04 LTS en AWS
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

# 2. Red: VPC, Subnet e Internet Gateway
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name     = "vpc-lab-raid"
    Proyecto = var.environment_tag
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name     = "igw-lab-raid"
    Proyecto = var.environment_tag
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name     = "snet-lab-raid"
    Proyecto = var.environment_tag
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name     = "rt-lab-raid"
    Proyecto = var.environment_tag
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

# 3. Security Group: SSH, HTTP Nginx y Puerto 9100 Prometheus
resource "aws_security_group" "sg" {
  name        = "secgroup-lab-raid"
  description = "Reglas de firewall para el laboratorio de RAID y Metricas"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH de gestion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Servicio Web HTTP Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus Node Exporter Metrics"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida total a Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name     = "secgroup-lab-raid"
    Proyecto = var.environment_tag
  }
}

# 4. Par de Claves SSH Generado Dinámicamente
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_key" {
  key_name   = "key-lab-raid"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa_lab.pem"
  file_permission = "0600"
}

# 5. Instancia EC2 Principal
resource "aws_instance" "vm_raid_host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet.id
  vpc_security_group_ids      = [aws_security_group.sg.id]
  key_name                    = aws_key_pair.lab_key.key_name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name     = "root-disk-raid-host"
      Proyecto = var.environment_tag
    }
  }

  tags = {
    Name     = "vm-raid-observability-prod"
    Proyecto = var.environment_tag
    Rol      = "RAID-Enterprise-Host"
  }
}

# 6. Volúmenes EBS Adicionales para el Arreglo RAID
locals {
  ebs_disks = [
    { dev = "/dev/sdf", name = "disk-raid-01-data", role = "RAID5-Member-1" },
    { dev = "/dev/sdg", name = "disk-raid-02-data", role = "RAID5-Member-2" },
    { dev = "/dev/sdh", name = "disk-raid-03-data", role = "RAID5-Member-3" },
    { dev = "/dev/sdi", name = "disk-raid-04-spare", role = "RAID-Hot-Spare" },
    { dev = "/dev/sdj", name = "disk-raid-05-replace", role = "RAID-Replacement-Spare" }
  ]
}

resource "aws_ebs_volume" "raid_disks" {
  count             = length(local.ebs_disks)
  availability_zone = aws_instance.vm_raid_host.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name     = local.ebs_disks[count.index].name
    Rol      = local.ebs_disks[count.index].role
    Proyecto = var.environment_tag
  }
}

resource "aws_volume_attachment" "raid_disk_attachments" {
  count       = length(local.ebs_disks)
  device_name = local.ebs_disks[count.index].dev
  volume_id   = aws_ebs_volume.raid_disks[count.index].id
  instance_id = aws_instance.vm_raid_host.id
}
