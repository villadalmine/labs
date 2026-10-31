variable "aws_region" {
  description = "Región de AWS donde se desplegarán las instancias"
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
  description = "Prefijo para los nombres de los recursos del cluster de monitoreo"
  type        = string
  default     = "lab-monitoreo-centralizado"
}

variable "allowed_cidr" {
  description = "CIDR autorizado para acceder a SSH, Prometheus, Grafana y Web. Por defecto está vacío (''), lo que bloquea el firewall a nivel de Security Group exclusivamente a tu IP pública actual (/32) detectada automáticamente. Si durante la clase querés abrir Grafana y la Web a los alumnos para que naveguen ellos mismos, pasás: -var='allowed_cidr=0.0.0.0/0'."
  type        = string
  default     = ""
}
