variable "aws_region" {
  type        = string
  description = "Región de AWS para el despliegue"
  default     = "eu-west-1"
}

variable "aws_profile" {
  type        = string
  description = "Perfil de AWS CLI configurado en tu máquina"
  default     = "personal"
}

variable "instance_type" {
  type        = string
  description = "Tipo de instancia EC2 (Free Tier en eu-west-1)"
  default     = "t3.micro"
}

variable "data_disk_size_gb" {
  type        = number
  description = "Tamaño en GB de cada disco EBS adicional (1 GB para cada volumen)"
  default     = 1
}
