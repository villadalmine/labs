variable "aws_region" {
  description = "Región de AWS para el despliegue del laboratorio"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (apta para Free Tier de AWS)"
  type        = string
  default     = "t3.micro"
}

variable "data_disk_size_gb" {
  description = "Tamaño en GB de cada volumen EBS para el arreglo RAID"
  type        = number
  default     = 1
}

variable "environment_tag" {
  description = "Etiqueta identificadora del proyecto y ambiente"
  type        = string
  default     = "Lab-Integrador-RAID-Resilience"
}
