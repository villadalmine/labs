output "vm_docker_public_ip" {
  description = "Dirección IP pública del servidor Docker y MySQL"
  value       = aws_instance.vm_docker.public_ip
}

output "vm_docker_public_dns" {
  description = "Nombre DNS público del servidor Docker y MySQL"
  value       = aws_instance.vm_docker.public_dns
}

output "ssh_command" {
  description = "Comando directo para conectarse por SSH al servidor"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_docker.public_ip}"
}

output "wordpress_url" {
  description = "URL para acceder al sitio WordPress"
  value       = "http://${aws_instance.vm_docker.public_ip}"
}

output "adminer_url" {
  description = "URL para acceder al gestor web Adminer de MySQL"
  value       = "http://${aws_instance.vm_docker.public_ip}:8080"
}

output "s3_backup_bucket" {
  description = "Nombre del bucket S3 privado para almacenar los backups cifrados"
  value       = aws_s3_bucket.backup_bucket.bucket
}

output "ebs_volumes" {
  description = "Identificadores de los 4 volúmenes EBS creados"
  value = {
    docker_disco_a = aws_ebs_volume.disk_docker_a.id
    docker_disco_b = aws_ebs_volume.disk_docker_b.id
    mysql_disco_a  = aws_ebs_volume.disk_mysql_a.id
    mysql_disco_b  = aws_ebs_volume.disk_mysql_b.id
  }
}
