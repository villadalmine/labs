# ==============================================================================
# INFRAESTRUCTURA EN AWS (Free Tier): Trabajo Integrador de Linux y Almacenamiento
# - VM 1: Servidor Web de Producción con 3 discos EBS adicionales de 1 GB
# - VM 2: Servidor de Backup Remoto (BorgBackup)
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
    Name     = "vpc-lab-integrador"
    Proyecto = "Integrador-Linux"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw-lab-integrador"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "snet-servidores"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "rt-lab-integrador"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

# 3. Security Group (Permite SSH 22, HTTP 80 y tráfico interno)
resource "aws_security_group" "sg" {
  name        = "secgroup-lab-integrador"
  description = "Reglas de firewall para el Trabajo Integrador"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH desde cualquier lugar"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Nginx desde cualquier lugar"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Trafico interno completo entre instancias de la VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-lab-integrador"
  }
}

# 4. Par de Claves SSH Generado Automáticamente
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_key" {
  key_name   = "key-lab-integrador"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa_lab.pem"
  file_permission = "0600"
}

# ------------------------------------------------------------------------------
# 5. VM 1: Servidor Web de Producción (con 3 discos EBS de 1 GB)
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet.id
  vpc_security_group_ids      = [aws_security_group.sg.id]
  key_name                    = aws_key_pair.lab_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "root-web-prod"
    }
  }

  tags = {
    Name = "vm-web-prod"
    Rol  = "Servidor-Web"
  }
}

# 3 Discos EBS de 1 GB adicionales
resource "aws_ebs_volume" "disk_raid_a" {
  availability_zone = aws_instance.vm_web.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-web-raid-a"
  }
}

resource "aws_volume_attachment" "att_raid_a" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.disk_raid_a.id
  instance_id = aws_instance.vm_web.id
}

resource "aws_ebs_volume" "disk_raid_b" {
  availability_zone = aws_instance.vm_web.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-web-raid-b"
  }
}

resource "aws_volume_attachment" "att_raid_b" {
  device_name = "/dev/sdi"
  volume_id   = aws_ebs_volume.disk_raid_b.id
  instance_id = aws_instance.vm_web.id
}

resource "aws_ebs_volume" "disk_crypto" {
  availability_zone = aws_instance.vm_web.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-web-crypto"
  }
}

resource "aws_volume_attachment" "att_crypto" {
  device_name = "/dev/sdj"
  volume_id   = aws_ebs_volume.disk_crypto.id
  instance_id = aws_instance.vm_web.id
}

# ------------------------------------------------------------------------------
# 6. VM 2: Servidor de Backup Remoto (BorgBackup)
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_backup" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet.id
  vpc_security_group_ids      = [aws_security_group.sg.id]
  key_name                    = aws_key_pair.lab_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "root-backup-repo"
    }
  }

  tags = {
    Name = "vm-backup-repo"
    Rol  = "Servidor-Backup"
  }
}
