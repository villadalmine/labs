# Despliegue de Infraestructura con Terraform (AWS Free Tier)

Este directorio contiene la definición en Terraform para levantar el laboratorio del **Trabajo Integrador** en **AWS**:
- **VM 1 (`vm-web-prod`):** Instancia EC2 `t2.micro` (Ubuntu 24.04 LTS) con IP pública y **3 discos EBS de 1 GB** (`/dev/sdh`, `/dev/sdi`, `/dev/sdj`).
- **VM 2 (`vm-backup-repo`):** Instancia EC2 `t2.micro` (Ubuntu 24.04 LTS) con IP pública y privada en la misma VPC, dedicada a recibir los backups de Borg por SSH.
- **Seguridad:** Security Group abriendo los puertos **22 (SSH)** y **80 (HTTP)** hacia Internet, y comunicación total interna.
- **Clave SSH:** Genera automáticamente el par de claves RSA y guarda la clave privada en `id_rsa_lab.pem`.
- **Región:** `eu-west-1` (Irlanda).
- **Perfil AWS:** `personal` (configurable en `variables.tf`).

---

## Paso a paso para desplegar

Desde tu terminal de PowerShell en Windows:

### 1. Inicializar Terraform
```powershell
cd linux\administrator\terraform
terraform init
```

### 2. Revisar el plan
```powershell
terraform plan
```

### 3. Aplicar y desplegar
```powershell
terraform apply -auto-approve
```

Al terminar, Terraform mostrará las IPs públicas y los comandos para conectarte por SSH con el usuario `ubuntu`:
```bash
ssh -i id_rsa_lab.pem ubuntu@<IP_PUBLICA_WEB>
ssh -i id_rsa_lab.pem ubuntu@<IP_PUBLICA_BACKUP>
```

---

## Destruir los recursos al terminar la clase

Para no dejar nada corriendo en tu cuenta de AWS:

```powershell
terraform destroy -auto-approve
```
