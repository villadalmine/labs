# ==============================================================================
# INFRAESTRUCTURA AWS: Trabajo Integrador Btrfs Avanzado
# - 2 Instancias EC2 Ubuntu 24.04 LTS (t3.micro - Free Tier)
#     * VM Primaria: 3 Discos EBS de 1 GB (Inicial + Hot Add RAID1 + Hot Replace)
#     * VM Replica:  1 Disco EBS de 1 GB (Recepción con btrfs receive)
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
    Name     = "vpc-lab-btrfs"
    Proyecto = "Integrador-Btrfs"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw-lab-btrfs"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "snet-btrfs"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "rt-lab-btrfs"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.rt.id
}

# 3. Security Group
resource "aws_security_group" "sg" {
  name        = "secgroup-lab-btrfs"
  description = "Reglas de firewall para el laboratorio de Btrfs"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH desde cualquier lugar"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Nginx / App"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Comunicacion interna entre nodos Btrfs"
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
    Name = "secgroup-lab-btrfs"
  }
}

# 4. Par de Claves SSH Generado Automáticamente
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab_key" {
  key_name   = "key-lab-btrfs"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa_lab.pem"
  file_permission = "0600"
}

# ------------------------------------------------------------------------------
# 5. Instancia EC2 Primaria Btrfs
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_btrfs_primary" {
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
      Name = "root-btrfs-primary"
    }
  }

  tags = {
    Name = "vm-btrfs-primary-prod"
    Rol  = "Btrfs-Primary"
  }
}

# Disco 1 Primario: Disco base inicial para Btrfs
resource "aws_ebs_volume" "disk_primary_1" {
  availability_zone = aws_instance.vm_btrfs_primary.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-btrfs-pri-1-1gb"
  }
}

resource "aws_volume_attachment" "att_primary_1" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.disk_primary_1.id
  instance_id = aws_instance.vm_btrfs_primary.id
}

# Disco 2 Primario: Para incorporación en caliente y conversión a RAID 1
resource "aws_ebs_volume" "disk_primary_2" {
  availability_zone = aws_instance.vm_btrfs_primary.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-btrfs-pri-2-1gb"
  }
}

resource "aws_volume_attachment" "att_primary_2" {
  device_name = "/dev/sdi"
  volume_id   = aws_ebs_volume.disk_primary_2.id
  instance_id = aws_instance.vm_btrfs_primary.id
}

# Disco 3 Primario: Para reemplazo en caliente (btrfs replace) tras simular daño
resource "aws_ebs_volume" "disk_primary_3" {
  availability_zone = aws_instance.vm_btrfs_primary.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-btrfs-pri-3-1gb"
  }
}

resource "aws_volume_attachment" "att_primary_3" {
  device_name = "/dev/sdj"
  volume_id   = aws_ebs_volume.disk_primary_3.id
  instance_id = aws_instance.vm_btrfs_primary.id
}

# ------------------------------------------------------------------------------
# 6. Instancia EC2 Secundaria Btrfs (Réplica DR)
# ------------------------------------------------------------------------------
resource "aws_instance" "vm_btrfs_replica" {
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
      Name = "root-btrfs-replica"
    }
  }

  tags = {
    Name = "vm-btrfs-replica-dr"
    Rol  = "Btrfs-Replica"
  }
}

# Disco 1 Replica: Para recibir subvolúmenes con btrfs receive
resource "aws_ebs_volume" "disk_replica_1" {
  availability_zone = aws_instance.vm_btrfs_replica.availability_zone
  size              = var.data_disk_size_gb
  type              = "gp3"

  tags = {
    Name = "disk-btrfs-rep-1-1gb"
  }
}

resource "aws_volume_attachment" "att_replica_1" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.disk_replica_1.id
  instance_id = aws_instance.vm_btrfs_replica.id
}
