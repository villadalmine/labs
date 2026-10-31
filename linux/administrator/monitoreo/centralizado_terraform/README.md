# Cluster de Monitoreo Centralizado Multi-Nodo en AWS

Este módulo aprovisiona una topología de observabilidad y almacenamiento empresarial distribuida en **3 instancias EC2**:

1. **`srv-monitoreo` (10.0.1.10):**
   - Servidor central de métricas (**Prometheus :9090**).
   - Servidor central de visualización (**Grafana :3000**).
   - Realiza consultas HTTP PULL cada 5 segundos hacia los nodos productivos.
2. **`srv-web-lvm` (10.0.1.20):**
   - Servidor Web (Nginx / HTTP).
   - **2 volúmenes EBS gp3** (1 GB c/u) para configurar un arreglo espejado **LVM RAID 1**.
   - **Node Exporter :9100** con recolector textfile para la salud del espejo LVM.
3. **`srv-data-luks` (10.0.1.30):**
   - Servidor de almacenamiento seguro con cifrado de bloques **LUKS2 (dm-crypt)**.
   - **1 volumen EBS gp3** (1 GB) dedicado para el contenedor cifrado.
   - **Node Exporter :9100** con recolector textfile para el estado del contenedor criptográfico.

---

## Despliegue Rápido

```bash
# 1. Inicializar providers
terraform init

# 2. Planificar
terraform plan

# 3. Desplegar el cluster
terraform apply -auto-approve

# 4. Conectarse a las instancias por SSH
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_SRV_CENTRAL>
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_SRV_WEB_LVM>
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_SRV_DATA_LUKS>
```

---

## Destrucción del Cluster

Al finalizar la demostración, destruí toda la infraestructura para no incurrir en costos de nube:

```bash
terraform destroy -auto-approve
```
