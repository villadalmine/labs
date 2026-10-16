# ==============================================================================
# INFRAESTRUCTURA AWS: Trabajo Integrador ZFS Activo-Pasivo + Load Balancer
# - 2 Instancias EC2 Ubuntu 24.04 LTS (t3.micro - Free Tier)
#     * VM Activa:  2 Discos EBS de 1 GB (Inicial + Espejo en caliente)
#     * VM Pasiva:  1 Disco EBS de 1 GB (Recepción remota de réplica)
# - 1 AWS Application Load Balancer (ALB) con Target Group y Health Check en /health
# - Red multizona (2 Subnets en AZs distintas para soportar ALB)
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

# 2. Red: VPC, 2 Subnets en AZs diferentes e Internet Gateway
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name     = "vpc-lab-zfs"
    Proyecto = "Integrador-ZFS-HA"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw-lab-zfs"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "snet-zfs-a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "snet-zfs-b"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "rt-lab-zfs"
  }
}

resource "aws_route_table_association" "rta_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "rta_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.rt.id
}

# 3. Security Groups
# Security Group para el Application Load Balancer
resource "aws_security_group" "sg_alb" {
  name        = "secgroup-zfs-alb"
  description = "Permitir trafico HTTP publico hacia el Load Balancer"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "HTTP desde Internet"
    from_port   = 80
    to_port     = 80
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
    Name = "secgroup-zfs-alb"
  }
}

# Security Group para las instancias EC2
resource "aws_security_group" "sg_instances" {
  name        = "secgroup-zfs-instances"
  description = "Reglas de firewall para nodos ZFS"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH desde cualquier lugar"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "HTTP desde el Load Balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_alb.id]
  }

  ingress {
    description = "Comunicacion interna entre nodos ZFS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secgroup-zfs-instances"
  }
}

# 4. Par de Claves SSH Generado Automáticamente
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_key" {
  key_name   = "key-lab-zfs"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa_lab.pem"
  file_permission = "0600"
}

# ------------------------------------------------------------------------------
# 5. Instancia EC2 Nodo Activo (Subnet A)
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_active" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet_a.id
  vpc_security_group_ids      = [aws_security_group.sg_instances.id]
  key_name                    = aws_key_pair.lab_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "root-zfs-active"
    }
  }

  tags = {
    Name = "vm-zfs-active-prod"
    Rol  = "ZFS-Active-Node"
  }
}

# Disco 1 de la VM Activa (Disco base del zpool)
resource "aws_ebs_volume" "disk_active_1" {
  availability_zone = aws_instance.vm_active.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-zfs-active-1-1gb"
  }
}

resource "aws_volume_attachment" "att_active_1" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.disk_active_1.id
  instance_id = aws_instance.vm_active.id
}

# Disco 2 de la VM Activa (Para conversión a espejo en caliente)
resource "aws_ebs_volume" "disk_active_2" {
  availability_zone = aws_instance.vm_active.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-zfs-active-2-1gb"
  }
}

resource "aws_volume_attachment" "att_active_2" {
  device_name = "/dev/sdi"
  volume_id   = aws_ebs_volume.disk_active_2.id
  instance_id = aws_instance.vm_active.id
}

# ------------------------------------------------------------------------------
# 6. Instancia EC2 Nodo Pasivo / Standby (Subnet B)
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_passive" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet_b.id
  vpc_security_group_ids      = [aws_security_group.sg_instances.id]
  key_name                    = aws_key_pair.lab_key.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "root-zfs-passive"
    }
  }

  tags = {
    Name = "vm-zfs-passive-standby"
    Rol  = "ZFS-Passive-Node"
  }
}

# Disco 1 de la VM Pasiva (Destino de la replicación ZFS)
resource "aws_ebs_volume" "disk_passive_1" {
  availability_zone = aws_instance.vm_passive.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-zfs-passive-1-1gb"
  }
}

resource "aws_volume_attachment" "att_passive_1" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.disk_passive_1.id
  instance_id = aws_instance.vm_passive.id
}

# ------------------------------------------------------------------------------
# 7. Application Load Balancer (ALB) y Target Group con Sonda de Salud
# ------------------------------------------------------------------------------
resource "aws_lb" "alb" {
  name               = "alb-lab-zfs-ha"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg_alb.id]
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  tags = {
    Name = "alb-lab-zfs"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "tg-zfs-active-passive"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  # Sonda de salud en /health: responde 200 OK en activo y 503 en pasivo
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "tg-zfs-active-passive"
  }
}

# Registrar ambas instancias en el Target Group
resource "aws_lb_target_group_attachment" "att_active" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.vm_active.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "att_passive" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.vm_passive.id
  port             = 80
}

# Listener en puerto 80 que reenvía el tráfico al Target Group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
