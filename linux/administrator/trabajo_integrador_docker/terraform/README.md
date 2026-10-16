# Despliegue de Infraestructura con Terraform: Docker + MySQL LVM RAID 1

Este directorio contiene la definición en Terraform para desplegar el laboratorio del **Trabajo Integrador 2** en **AWS**:
- **VM (`vm-docker-mysql-prod`):** Instancia EC2 `t2.micro` (Ubuntu 24.04 LTS) con IP pública.
- **4 Discos EBS dedicados de 1 GB cada uno:**
  - `disk_docker_a` (`/dev/sdh`): Disco inicial para `/var/lib/docker`.
  - `disk_docker_b` (`/dev/sdi`): Segundo disco para conversión en caliente a RAID 1 de Docker.
  - `disk_mysql_a` (`/dev/sdj`): Pata 1 del RAID 1 para base de datos MySQL.
  - `disk_mysql_b` (`/dev/sdk`): Pata 2 del RAID 1 para base de datos MySQL.
- **Seguridad:** Security Group abriendo los puertos **22 (SSH)**, **80 (HTTP)** y **8080 (Adminer Web UI)**.
- **Clave SSH:** Genera automáticamente el par de claves RSA 4096-bit y guarda la clave privada en `id_rsa_lab.pem`.
- **Región:** `eu-west-1` (Irlanda).
- **Perfil AWS:** `personal` (utiliza las credenciales activas en tu PowerShell).

---

## Instrucciones de Despliegue

Ejecuta estos comandos en tu terminal de **PowerShell** en Windows:

### 1. Inicializar Terraform
```powershell
cd linux\administrator\trabajo_integrador_docker\terraform
terraform init
```

### 2. Validar y ver el plan
```powershell
terraform validate
terraform plan
```

### 3. Aplicar y crear los recursos en AWS
```powershell
terraform apply -auto-approve
```

Al finalizar la creación, Terraform imprimirá en pantalla:
- La IP pública de la máquina.
- El comando SSH para ingresar con el archivo `id_rsa_lab.pem`.
- La URL de Adminer (`http://<IP>:8080`).

Para conectarte desde PowerShell:
```powershell
ssh -i id_rsa_lab.pem ubuntu@<IP_PUBLICA>
```
*(Nota en Windows: Si SSH se queja de permisos sobre el archivo `.pem`, ejecuta: `icacls.exe id_rsa_lab.pem /reset ; icacls.exe id_rsa_lab.pem /grant:r "$($env:USERNAME):(R)" ; icacls.exe id_rsa_lab.pem /inheritance:r`)*

---

## Destrucción del Laboratorio

Para no incurrir en costos ni dejar recursos huérfanos en tu cuenta de AWS, ejecuta al terminar la práctica:

```powershell
terraform destroy -auto-approve
```
