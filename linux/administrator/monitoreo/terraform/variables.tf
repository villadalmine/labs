variable "aws_region" {
  description = "Región de AWS donde se desplegarán los recursos"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "Perfil de credenciales de AWS CLI"
  type        = string
  default     = "personal"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (compatible con Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Prefijo para los nombres de los recursos"
  type        = string
  default     = "lab-web-lvm-monitoreo"
}

variable "allowed_cidr" {
  description = "CIDR autorizado para acceder a SSH, Prometheus, Grafana y Web. Por defecto vacío (''), lo que restringe el acceso de forma 100% automática y exclusiva a tu dirección IP pública actual (/32). Si durante la clase querés abrirlo a los alumnos, podés pasar -var='allowed_cidr=0.0.0.0/0'."
  type        = string
  default     = ""
}
