output "resumen_cluster" {
  description = "Tabla resumen con toda la infraestructura, IPs públicas estáticas, URLs y comandos SSH"
  value       = <<-EOT

========================================================================================================================
                                🚀 CLUSTER DE MONITOREO CENTRALIZADO MULTI-NODO EN AWS
========================================================================================================================
  FIREWALL: Restringido exclusivamente a tu IP pública: ${local.admin_cidr}
  NOTA: Las IPs públicas son ELASTIC IPs ESTÁTICAS. NUNCA cambiarán al correr terraform o reiniciar las máquinas.

  ----------------------------------------------------------------------------------------------------------------------
  ROL                    IP PÚBLICA (ESTÁTICA)   IP INTERNA   PUERTOS       ACCESO WEB / MÉTRICAS
  ----------------------------------------------------------------------------------------------------------------------
  Servidor Central       ${format("%-23s", aws_eip.eip_central.public_ip)} 10.0.1.10    3000, 9090    Grafana:    http://${aws_eip.eip_central.public_ip}:3000/d/cluster-monitoreo-multinodo/
                                                                            Prometheus: http://${aws_eip.eip_central.public_ip}:9090
  Worker 1 (Web LVM)     ${format("%-23s", aws_eip.eip_web.public_ip)} 10.0.1.20    80, 8080      Servicio:   http://${aws_eip.eip_web.public_ip}
  Worker 2 (Datos LUKS)  ${format("%-23s", aws_eip.eip_luks.public_ip)} 10.0.1.30    (VPC only)    Contenedor Cifrado Activo (/data/segura)
  ----------------------------------------------------------------------------------------------------------------------

  COMANDOS SSH (Listos para copiar y pegar desde tu terminal):
  Central:   ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_eip.eip_central.public_ip}
  Worker 1:  ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_eip.eip_web.public_ip}
  Worker 2:  ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_eip.eip_luks.public_ip}
========================================================================================================================
  EOT
}

output "security_firewall_allowed_cidr" {
  description = "Dirección IP / CIDR autorizada en los Security Groups para acceder a Grafana, Prometheus, Web y SSH"
  value       = local.admin_cidr
}

output "grafana_url" {
  description = "URL del Dashboard de Grafana en el Servidor Central"
  value       = "http://${aws_eip.eip_central.public_ip}:3000/d/cluster-monitoreo-multinodo/f4ce508?from=now-15m&to=now&timezone=browser&refresh=5s"
}

output "prometheus_url" {
  description = "URL de la interfaz de Prometheus en el Servidor Central"
  value       = "http://${aws_eip.eip_central.public_ip}:9090"
}

output "web_service_url" {
  description = "URL del servicio Web en el Worker 1 (montado sobre LVM RAID 1)"
  value       = "http://${aws_eip.eip_web.public_ip}"
}

output "ssh_srv_central" {
  description = "Comando SSH para conectarse al Servidor Central de Monitoreo"
  value       = "ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_eip.eip_central.public_ip}"
}

output "ssh_srv_web_lvm" {
  description = "Comando SSH para conectarse al Worker 1 (Web + LVM RAID 1)"
  value       = "ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_eip.eip_web.public_ip}"
}

output "ssh_srv_data_luks" {
  description = "Comando SSH para conectarse al Worker 2 (Datos Cifrados LUKS)"
  value       = "ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@${aws_eip.eip_luks.public_ip}"
}

output "internal_network_topology" {
  description = "Mapa de IPs internas de la VPC para scrape PULL de Prometheus"
  value = {
    "srv-monitoreo"  = "10.0.1.10 (Prometheus :9090, Grafana :3000)",
    "srv-web-lvm"    = "10.0.1.20 (Node Exporter :9100, Nginx :80)",
    "srv-data-luks"  = "10.0.1.30 (Node Exporter :9100, LUKS Container)"
  }
}
