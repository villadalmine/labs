# Despliegue de Infraestructura AWS: Trabajo Integrador RAID & Observabilidad

Este directorio contiene las definiciones de **Terraform** para levantar un entorno de laboratorio completo en **AWS (apto para Free Tier)**:

- **1 Instancia EC2** Ubuntu 24.04 LTS (`t3.micro`).
- **5 Volúmenes EBS** de 1 GB (`gp3`) dedicados a almacenamiento empresarial:
  - 3 Discos para el RAID 5 base.
  - 1 Disco asignado como **Hot Spare** automático.
  - 1 Disco asignado para reemplazo físico tras contingencias.
- **Servicio Web Nginx** y **Prometheus Node Exporter** (puerto 9100) preconfigurado con recolector de métricas de telemetría RAID por Systemd Timer.
- **Perfil AWS:** `personal` por defecto (configurable en `variables.tf`).

---

## 🚀 Despliegue Paso a Paso

### 1. Prerrequisitos y Configuración de Credenciales AWS
- Cuenta de AWS activa y credenciales configuradas (`aws configure`).
- Terraform >= 1.5.0 instalado.

> [!IMPORTANT]
> **Configuración del perfil de AWS (`aws_profile`)**:
> El provider de AWS en `providers.tf` utiliza la variable `aws_profile` (con valor por defecto `"personal"`).
> Si en tu entorno local utilizas el perfil estándar `default` u otro diferente:
> 1. Modificá `variables.tf` cambiando `default = "default"` en `aws_profile`, o
> 2. Copiá `terraform.tfvars.example` a `terraform.tfvars` y definí tu perfil:
>    ```hcl
>    aws_profile = "default"
>    ```
> 3. O bien pásalo como argumento en la ejecución:
>    ```bash
>    terraform apply -var="aws_profile=default" -auto-approve
>    ```
> Esto evitará errores de autenticación como `InvalidClientTokenId`.

### 2. Inicializar y Aplicar
```bash
terraform init
terraform apply -auto-approve
```

### 3. Conectarse a la Instancia
Terraform genera automáticamente la clave SSH `id_rsa_lab.pem`. Conectate usando el output provisto:

```bash
# Permisos seguros para la clave privada
chmod 400 id_rsa_lab.pem

# Conexión SSH
ssh -i id_rsa_lab.pem -o StrictHostKeyChecking=no ubuntu@<IP_PUBLICA>
```

### 4. Ejecución del Laboratorio
Una vez conectado por SSH, ejecutá el script integrador de la serie:

```bash
# Subir o clonar el repo en la instancia y ejecutar:
sudo ./demo_integrador_raid.sh
```

### 5. Destrucción de Recursos al Finalizar
Para evitar costos residuales en AWS:
```bash
terraform destroy -auto-approve
```
