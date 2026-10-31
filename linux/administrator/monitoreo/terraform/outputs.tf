output "security_firewall_allowed_cidr" {
  description = "Dirección IP / CIDR autorizada en los Security Groups para acceder a Grafana, Prometheus, Web y SSH"
  value       = local.admin_cidr
}

output "ssh_command" {
  description = "Comando para conectarse a la instancia por SSH"
  value       = "ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_instance.server.public_ip}"
}

output "public_ip" {
  description = "Dirección IP pública de la instancia"
  value       = aws_instance.server.public_ip
}

output "web_url" {
  description = "URL del Servidor Web del laboratorio"
  value       = "http://${aws_instance.server.public_ip}:8080"
}

output "node_exporter_metrics_url" {
  description = "URL de telemetría PULL de Node Exporter"
  value       = "http://${aws_instance.server.public_ip}:9100/metrics"
}

output "prometheus_url" {
  description = "URL del servidor Prometheus"
  value       = "http://${aws_instance.server.public_ip}:9090"
}

output "grafana_url" {
  description = "URL del servidor Grafana"
  value       = "http://${aws_instance.server.public_ip}:3000"
}

output "ebs_disks_info" {
  description = "Identificadores de los discos físicos EBS para LVM RAID 1"
  value       = "En instancias AWS Nitro (t3.micro), los discos /dev/sdf y /dev/sdg se mapean en el kernel como /dev/nvme1n1 y /dev/nvme2n1 (o /dev/xvdf y /dev/xvdg en instancias Xen). Podés inicializarlos con: sudo pvcreate /dev/nvme1n1 /dev/nvme2n1"
}
