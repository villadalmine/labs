output "instance_public_ip" {
  description = "Dirección IP pública de la instancia EC2"
  value       = aws_instance.vm_raid_host.public_ip
}

output "ssh_command" {
  description = "Comando rápido para conectarse por SSH utilizando la clave generada"
  value       = "ssh -i id_rsa_lab.pem -o StrictHostKeyChecking=no ubuntu@${aws_instance.vm_raid_host.public_ip}"
}

output "node_exporter_metrics_url" {
  description = "Endpoint HTTP de métricas en tiempo real de Prometheus Node Exporter"
  value       = "http://${aws_instance.vm_raid_host.public_ip}:9100/metrics"
}

output "web_service_url" {
  description = "URL del servicio web Nginx respaldado por el arreglo RAID 5"
  value       = "http://${aws_instance.vm_raid_host.public_ip}/"
}

output "ebs_volume_ids" {
  description = "IDs de los volúmenes EBS creados para el arreglo RAID"
  value       = aws_ebs_volume.raid_disks[*].id
}
