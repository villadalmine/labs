# ==============================================================================
# INFRAESTRUCTURA AWS: Trabajo Integrador Docker Engine + MySQL LVM RAID 1
# - 1 Instancia EC2 Ubuntu 24.04 LTS (t2.micro - Free Tier)
# - 4 Discos EBS de 1 GB para simular separación de almacenamiento y alta disponibilidad:
#     * Disco Docker A: Almacenamiento inicial para /var/lib/docker
#     * Disco Docker B: Incorporación en caliente para espejo (RAID 1) de Docker
#     * Disco MySQL A:  Pata 1 del RAID 1 de MySQL
#     * Disco MySQL B:  Pata 2 del RAID 1 de MySQL
# - 1 Bucket S3 Privado y Cifrado (SSE-S3 / AES256) para backups seguros de base de datos
# - 1 Rol IAM e Instance Profile para permitir a la EC2 comunicarse con S3 sin credenciales estáticas
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
    Name     = "vpc-lab-docker"
    Proyecto = "Integrador-Docker-LVM"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw-lab-docker"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "snet-docker"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "rt-lab-docker"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

# 3. Security Group
resource "aws_security_group" "sg" {
  name        = "secgroup-lab-docker"
  description = "Reglas de firewall para el Trabajo Integrador Docker"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH desde cualquier lugar"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Nginx / WordPress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Adminer / Interfaz Web de Base de Datos"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secgroup-lab-docker"
  }
}

# 4. Par de Claves SSH Generado Automáticamente
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_key" {
  key_name   = "key-lab-docker"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa_lab.pem"
  file_permission = "0600"
}

# ------------------------------------------------------------------------------
# 5. Bucket S3 para Backups Cifrados y Configuración de IAM
# ------------------------------------------------------------------------------
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backup_bucket" {
  bucket        = "lab-docker-backup-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Name     = "lab-docker-backup"
    Proyecto = "Integrador-Docker-LVM"
  }
}

resource "aws_s3_bucket_public_access_block" "backup_pab" {
  bucket = aws_s3_bucket.backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_encryption" {
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Rol IAM para que la instancia EC2 pueda interactuar con el bucket S3 sin claves estáticas
resource "aws_iam_role" "ec2_s3_role" {
  name = "role-lab-docker-s3-${random_id.bucket_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "policy-lab-docker-s3-${random_id.bucket_suffix.hex}"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backup_bucket.arn,
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "profile-lab-docker-s3-${random_id.bucket_suffix.hex}"
  role = aws_iam_role.ec2_s3_role.name
}

# ------------------------------------------------------------------------------
# 6. Instancia EC2: Servidor Docker y MySQL
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_docker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet.id
  vpc_security_group_ids      = [aws_security_group.sg.id]
  key_name                    = aws_key_pair.lab_key.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "root-docker-prod"
    }
  }

  tags = {
    Name = "vm-docker-mysql-prod"
    Rol  = "Docker-LVM-RAID1"
  }
}

# ------------------------------------------------------------------------------
# 7. Cuatro Discos EBS de 1 GB dedicados
# ------------------------------------------------------------------------------

# Disco 1: Inicial para /var/lib/docker
resource "aws_ebs_volume" "disk_docker_a" {
  availability_zone = aws_instance.vm_docker.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-docker-a-1gb"
  }
}

resource "aws_volume_attachment" "att_docker_a" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.disk_docker_a.id
  instance_id = aws_instance.vm_docker.id
}

# Disco 2: Segundo disco para espejo en caliente de /var/lib/docker
resource "aws_ebs_volume" "disk_docker_b" {
  availability_zone = aws_instance.vm_docker.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-docker-b-1gb"
  }
}

resource "aws_volume_attachment" "att_docker_b" {
  device_name = "/dev/sdi"
  volume_id   = aws_ebs_volume.disk_docker_b.id
  instance_id = aws_instance.vm_docker.id
}

# Disco 3: Pata 1 para LVM RAID 1 de MySQL
resource "aws_ebs_volume" "disk_mysql_a" {
  availability_zone = aws_instance.vm_docker.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-mysql-a-1gb"
  }
}

resource "aws_volume_attachment" "att_mysql_a" {
  device_name = "/dev/sdj"
  volume_id   = aws_ebs_volume.disk_mysql_a.id
  instance_id = aws_instance.vm_docker.id
}

# Disco 4: Pata 2 para LVM RAID 1 de MySQL
resource "aws_ebs_volume" "disk_mysql_b" {
  availability_zone = aws_instance.vm_docker.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-mysql-b-1gb"
  }
}

resource "aws_volume_attachment" "att_mysql_b" {
  device_name = "/dev/sdk"
  volume_id   = aws_ebs_volume.disk_mysql_b.id
  instance_id = aws_instance.vm_docker.id
}
