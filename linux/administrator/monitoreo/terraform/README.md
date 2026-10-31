# Infraestructura Terraform: Taller Integrador Web sobre LVM RAID 1 y Monitoreo

Este módulo aprovisiona en **AWS (Free Tier eligible)** la infraestructura completa para desplegar el laboratorio:

- **1 Instancia EC2** (Ubuntu 24.04 LTS `t3.micro`).
- **2 Volúmenes EBS gp3** (1 GB cada uno) dedicados para el espejo **LVM RAID 1**.
- **Security Group** con todos los puertos de telemetría y servicio expuestos:
  - Puerto `22`: SSH.
  - Puerto `8080`: Servidor Web HTTP corporativo.
  - Puerto `9100`: Node Exporter (`/metrics`).
  - Puerto `9090`: Prometheus Server.
  - Puerto `3000`: Grafana.
- **Aprovisionamiento automático rápido vía APT**: instala `lvm2`, `prometheus-node-exporter`, `prometheus` y `grafana`.

---

## Despliegue Rápido

```bash
# 1. Inicializar Terraform
terraform init

# 2. Planificar y revisar recursos
terraform plan

# 3. Aplicar y desplegar
terraform apply -auto-approve

# 4. Conectarse por SSH usando la clave generada
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_PUBLICA>
```

---

## Destrucción de Recursos

Al finalizar la demostración, destruí toda la infraestructura para no incurrir en costos de nube:

```bash
terraform destroy -auto-approve
```
