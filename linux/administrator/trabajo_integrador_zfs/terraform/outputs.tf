output "alb_dns_name" {
  description = "Nombre DNS público del Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "alb_url" {
  description = "URL para acceder al sitio web a través del Load Balancer"
  value       = "http://${aws_lb.alb.dns_name}"
}

output "vm_active_public_ip" {
  description = "IP pública del Nodo Activo ZFS"
  value       = aws_instance.vm_active.public_ip
}

output "vm_active_private_ip" {
  description = "IP privada del Nodo Activo ZFS"
  value       = aws_instance.vm_active.private_ip
}

output "ssh_active" {
  description = "Comando SSH para conectarse al Nodo Activo"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_active.public_ip}"
}

output "vm_passive_public_ip" {
  description = "IP pública del Nodo Pasivo ZFS"
  value       = aws_instance.vm_passive.public_ip
}

output "vm_passive_private_ip" {
  description = "IP privada del Nodo Pasivo ZFS"
  value       = aws_instance.vm_passive.private_ip
}

output "ssh_passive" {
  description = "Comando SSH para conectarse al Nodo Pasivo"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_passive.public_ip}"
}

output "ebs_volumes" {
  description = "Volúmenes EBS asociados"
  value = {
    active_disk_1  = aws_ebs_volume.disk_active_1.id
    active_disk_2  = aws_ebs_volume.disk_active_2.id
    passive_disk_1 = aws_ebs_volume.disk_passive_1.id
  }
}
