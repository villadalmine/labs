# Despliegue de Infraestructura ZFS Activo-Pasivo + AWS ALB

Este directorio contiene la definición en Terraform para desplegar el laboratorio de **Alta Disponibilidad con ZFS y Balanceador de Carga** en **AWS**:
- **ALB (Application Load Balancer):** Punto de entrada público HTTP con sonda de salud en `/health`.
- **Nodo Activo (`vm-zfs-active-prod`):** Instancia EC2 `t3.micro` con 2 discos EBS de 1 GB (para demostrar creación de zpool y hot-attach de espejo).
- **Nodo Pasivo (`vm-zfs-passive-standby`):** Instancia EC2 `t3.micro` con 1 disco EBS de 1 GB (para recibir los snapshots incrementales de ZFS).
- **Red Multizona:** 2 subnets en zonas de disponibilidad distintas (`eu-west-1a` y `eu-west-1b`) requeridas por el ALB.
- **Clave SSH:** Generada automáticamente en `id_rsa_lab.pem`.

---

## Instrucciones de Despliegue

Desde tu terminal de **PowerShell** en Windows:

```powershell
cd linux\administrator\trabajo_integrador_zfs\terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

Al terminar, Terraform imprimirá la URL del Load Balancer y los comandos SSH:
```bash
ssh -i id_rsa_lab.pem ubuntu@<IP_ACTIVA>
ssh -i id_rsa_lab.pem ubuntu@<IP_PASIVA>
```

---

## Destrucción del Laboratorio

Para no dejar recursos en tu cuenta de AWS al terminar la clase:
```powershell
terraform destroy -auto-approve
```
