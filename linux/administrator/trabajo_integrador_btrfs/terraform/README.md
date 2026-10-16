# Despliegue de Infraestructura Btrfs Avanzado con Terraform

Este directorio contiene la definición en Terraform para desplegar el laboratorio de **Btrfs Avanzado** en **AWS**:
- **VM Primaria (`vm-btrfs-primary-prod`):** Instancia EC2 `t3.micro` con 3 discos EBS de 1 GB:
  - `disk_primary_1` (`/dev/sdh`): Disco inicial formateado con Btrfs y subvolúmenes.
  - `disk_primary_2` (`/dev/sdi`): Disco para incorporación en caliente y conversión a RAID 1 con `btrfs balance`.
  - `disk_primary_3` (`/dev/sdj`): Disco para reemplazo en caliente con `btrfs replace` tras simular fallo.
- **VM Réplica (`vm-btrfs-replica-dr`):** Instancia EC2 `t3.micro` con 1 disco EBS de 1 GB para recibir subvolúmenes por SSH con `btrfs receive`.
- **Clave SSH:** Generada automáticamente en `id_rsa_lab.pem`.

---

## Instrucciones de Despliegue

Desde tu terminal de **PowerShell** en Windows:

```powershell
cd linux\administrator\trabajo_integrador_btrfs\terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

---

## Destrucción del Laboratorio

Para no incurrir en costos en AWS al finalizar la clase:
```powershell
terraform destroy -auto-approve
```
