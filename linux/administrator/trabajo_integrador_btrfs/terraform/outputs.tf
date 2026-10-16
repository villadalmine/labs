output "vm_primary_public_ip" {
  description = "IP pública del servidor Btrfs Primario"
  value       = aws_instance.vm_btrfs_primary.public_ip
}

output "vm_primary_private_ip" {
  description = "IP privada del servidor Btrfs Primario"
  value       = aws_instance.vm_btrfs_primary.private_ip
}

output "ssh_primary" {
  description = "Comando SSH para conectarse al servidor Btrfs Primario"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_btrfs_primary.public_ip}"
}

output "vm_replica_public_ip" {
  description = "IP pública del servidor Btrfs Réplica"
  value       = aws_instance.vm_btrfs_replica.public_ip
}

output "vm_replica_private_ip" {
  description = "IP privada del servidor Btrfs Réplica"
  value       = aws_instance.vm_btrfs_replica.private_ip
}

output "ssh_replica" {
  description = "Comando SSH para conectarse al servidor Btrfs Réplica"
  value       = "ssh -i id_rsa_lab.pem ubuntu@${aws_instance.vm_btrfs_replica.public_ip}"
}

output "ebs_volumes" {
  description = "Discos EBS adjuntos"
  value = {
    primary_disk_1 = aws_ebs_volume.disk_primary_1.id
    primary_disk_2 = aws_ebs_volume.disk_primary_2.id
    primary_disk_3 = aws_ebs_volume.disk_primary_3.id
    replica_disk_1 = aws_ebs_volume.disk_replica_1.id
  }
}
