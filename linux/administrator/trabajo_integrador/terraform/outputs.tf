# ==============================================================================
# SALIDAS TERRAFORM (AWS)
# ==============================================================================

output "vm_web_public_ip" {
  description = "Dirección IP pública del Servidor Web"
  value       = aws_instance.vm_web.public_ip
}

output "vm_web_ssh_command" {
  description = "Comando para conectar por SSH al Servidor Web"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_web.public_ip}"
}

output "web_url" {
  description = "URL para acceder al sitio Nginx en el navegador"
  value       = "http://${aws_instance.vm_web.public_ip}"
}

output "vm_backup_public_ip" {
  description = "Dirección IP pública del Servidor de Backup"
  value       = aws_instance.vm_backup.public_ip
}

output "vm_backup_private_ip" {
  description = "Dirección IP privada del Servidor de Backup (para la réplica interna con Borg)"
  value       = aws_instance.vm_backup.private_ip
}

output "vm_backup_ssh_command" {
  description = "Comando para conectar por SSH al Servidor de Backup"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_backup.public_ip}"
}
