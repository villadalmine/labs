---
id: integrador-4.5-resiliencia-raid-metricas-aws
title: 'Trabajo Integrador 5: Almacenamiento Empresarial RAID en AWS, Inyección de
  Fallas, Recuperación y Observabilidad con Métricas'
difficulty_level: 4
difficulty_label: 'Nivel 4: Proyectos Integradores en la Nube (AWS Free Tier con Terraform)'
section: '4.5'
sections:
- '4.5'
- '4'
category: cloud-iac
tags:
- cloud-iac
- storage
- raid
- mdadm
- ebs
- aws
- ec2
- terraform
- prometheus
- node-exporter
- observabilidad
- hot-spare
- rebuild
- resync
- scrub
- chaos-engineering
tools:
- terraform
- mdadm
- prometheus-node-exporter
- curl
- mkfs.ext4
- lsblk
- sha256sum
requirements:
  root_required: true
  cloud_required: true
  min_ram_mb: 1024
  min_disks: 5
  cloud_provider: AWS
tested_environments:
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-24'
  notes: Despliegue en AWS con Terraform (1 EC2 t3.micro, 5 discos EBS gp3, Prometheus
    Node Exporter con Textfile Collector, script demo_integrador_raid.sh, falla inducida,
    rebuild con hot spare y reemplazo físico).
environments:
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Proyecto integrador capstone de almacenamiento empresarial y observabilidad
  en AWS desplegado con Terraform. Aprovisiona una instancia EC2 con 5 volúmenes EBS gp3
  independientes, configura un arreglo RAID 5 con write-intent bitmap y hot spare automático,
  expone datos para Nginx, e implementa un pipeline de observabilidad con Prometheus
  Node Exporter (Textfile Collector) que reporta en tiempo real métricas de salud (raid_healthy,
  raid_failed_disks, raid_spare_disks). Incluye inyección de caos con fallas de disco en vivo,
  demostración de tolerancia a desastres sin corte de servicio, reconstrucción automática
  y sustitución física de hardware.
files:
  guide: raid/integrador_aws/trabajo_integrador_raid.md
  script: raid/integrador_aws/demo_integrador_raid.sh
  terraform: raid/integrador_aws/terraform
resource_type: cloud_project
has_guide: true
has_interactive_script: true
has_terraform: true
execution_mode: terraform_apply
prerequisites:
- lab-3.7-raid-teoria-comparativa
- lab-3.8-raid-mdadm
- lab-3.6-monitoreo-metricas
- integrador-4.1-servidor-web-raid-luks-borg
mcp_tools:
- linux-labs-tutor
- terraform
- aws
---

# Trabajo Integrador 5: Almacenamiento Empresarial RAID en AWS, Inyección de Fallas, Recuperación y Observabilidad con Métricas

Este proyecto integrador de nivel profesional representa el **capstone de la serie de almacenamiento y tolerancia a fallos**. Aprenderás a orquestar con **Terraform** una arquitectura resistente en **AWS EC2** con **5 volúmenes EBS dedicados**, desplegar un arreglo **RAID 5 con Write-Intent Bitmap y Hot Spare**, instrumentar un sistema de observabilidad y métricas con **Prometheus Node Exporter**, inyectar fallas de hardware en caliente (*Chaos Engineering*), verificar la continuidad de servicio de una aplicación web y ejecutar el procedimiento formal de reemplazo físico de unidades y auditoría de paridad (*scrubbing*).

---

## 🏗️ Arquitectura de la Solución en la Nube

```
    ┌────────────────────────────────────────────────────────────────────────┐
    │                       AWS VPC (10.0.0.0/16)                            │
    │                                                                        │
    │  Instancia EC2 Ubuntu 24.04 (t3.micro): vm-raid-observability-prod    │
    │  IP Pública: 54.x.x.x  |  Puertos: 22 (SSH), 80 (HTTP), 9100 (Metrics) │
    │                                                                        │
    │  ┌──────────────────────────────────────────────────────────────────┐  │
    │  │                        CAPA DE APLICACIÓN                        │  │
    │  │    Nginx Web Server  ──>  /srv/storage_raid/database.dat         │  │
    │  │    Prometheus Node Exporter (Puerto 9100)                        │  │
    │  │    Systemd Timer: update_raid_metrics.sh -> raid.prom (Textfile) │  │
    │  └──────────────────────────────────────────────────────────────────┘  │
    │                                  │                                     │
    │  ┌──────────────────────────────────────────────────────────────────┐  │
    │  │                      CAPA LÓGICA RAID (md0)                      │  │
    │  │       RAID 5 (Paridad Distribuida) + Write-Intent Bitmap         │  │
    │  └──────────────────────────────────────────────────────────────────┘  │
    │         │                   │                   │          │           │
    │         ▼                   ▼                   ▼          ▼           │
    │     [EBS 1: 1GB]        [EBS 2: 1GB]        [EBS 3: 1GB]  [EBS 4: 1GB] │
    │     /dev/nvme1n1        /dev/nvme2n1        /dev/nvme3n1  /dev/nvme4n1 │
    │     (Datos Activo)     💥 (Falla Caos)     (Datos Activo)  (HOT SPARE) │
    │                                                                        │
    │                                                     [EBS 5: 1GB]       │
    │                                                     /dev/nvme5n1       │
    │                                                     (Drive Swap Nuevo) │
    └────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Pipeline de Métricas y Telemetría en Tiempo Real

El sistema incorpora un colector de métricas de alta resolución que actualiza `/var/lib/prometheus/node-exporter/raid.prom` cada 5 segundos mediante un **Systemd Timer**. Las métricas expuestas en `:9100/metrics` son:

| Métrica | Tipo | Significado | Estado Normal | Estado en Falla |
| :--- | :--- | :--- | :---: | :---: |
| **`raid_healthy`** | Gauge | 1 = Clean/Healthy, 0 = Degraded | **`1`** | **`0` (Alerta)** |
| **`raid_active_disks`** | Gauge | Cantidad de discos activos sirviendo datos | **`3`** | **`2`** |
| **`raid_failed_disks`** | Gauge | Cantidad de discos con falla reportada | **`0`** | **`1`** |
| **`raid_spare_disks`** | Gauge | Unidades Hot Spare en reserva | **`1`** | **`0`** (durante rebuild) |
| **`raid_sync_percent`** | Gauge | Porcentaje de avance de rebuild/resync | **`100`** | **`0` a `100`** |

---

## 🚀 Despliegue de la Infraestructura con Terraform

### Paso 1: Inicialización y Aplicación
```bash
cd linux/administrator/raid/integrador_aws/terraform

terraform init
terraform apply -auto-approve
```

Terraform provisionará:
1. La red VPC y Subnet con Internet Gateway.
2. Security Group permitiendo SSH (22), HTTP (80) y Node Exporter (9100).
3. La instancia EC2 t3.micro con la clave SSH generada automáticamente `id_rsa_lab.pem`.
4. Los 5 volúmenes EBS gp3 adjuntados dinámicamente a la máquina.
5. El script `user_data.sh` que instala herramientas y activa el timer de métricas.

### Paso 2: Conexión SSH
```bash
chmod 400 id_rsa_lab.pem
ssh -i id_rsa_lab.pem -o StrictHostKeyChecking=no ubuntu@$(terraform output -raw instance_public_ip)
```

---

## 🧪 Ejecución del Laboratorio en la Instancia AWS

Una vez dentro de la máquina virtual en AWS, ejecutá el script interactivo del integrador:

```bash
# Si clonaste el repo en la instancia:
cd linux/administrator/raid/integrador_aws
sudo ./demo_integrador_raid.sh
```

> 💡 **¿Querés probarlo localmente sin cuenta de AWS?**
> Podés ejecutar `sudo ./demo_integrador_raid.sh` directamente en tu máquina **Ubuntu en WSL2, Docker o VirtualBox**. El script detecta si no hay discos EBS y crea automáticamente 5 loop devices de prueba para emular todo el comportamiento idénticamente.

---

## 🔬 Fases del Trabajo Integrador

### Fase 1: Creación del Arreglo y Servicio Web
El arreglo `/dev/md0` se ensambla utilizando 3 discos activos de 1 GB, 1 disco de hot spare y el write-intent bitmap interno:

```bash
sudo mdadm --create /dev/md0 \
    --run --level=5 --raid-devices=3 --spare-devices=1 \
    --bitmap=internal --name=raid_prod \
    /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1

sudo mkfs.ext4 -L raid_data /dev/md0
sudo mkdir -p /srv/storage_raid
sudo mount /dev/md0 /srv/storage_raid
```

Se escriben datos críticos (`database.dat`) y se calcula su hash de integridad SHA-256 de referencia.

### Fase 2: Comprobación de Métricas en Producción
Consultá el endpoint de métricas de Prometheus:
```bash
curl -s http://localhost:9100/metrics | grep "^raid_"
```
Salida:
```
raid_healthy 1
raid_active_disks 3
raid_failed_disks 0
raid_spare_disks 1
raid_sync_percent 100
```

### Fase 3: Inyección de Falla (Caos de Hardware)
Provocamos la muerte súbita del segundo disco EBS:
```bash
sudo mdadm /dev/md0 --fail /dev/nvme2n1
```

Inmediatamente, la telemetría refleja la contingencia:
```
raid_healthy 0
raid_active_disks 2
raid_failed_disks 1
```

**Verificación de Resiliencia:** Mientras el arreglo está degradado, consultamos los datos del servidor web:
```bash
sha256sum /srv/storage_raid/database.dat
```
El hash coincide al 100%. La paridad XOR del kernel garantiza que el servicio nunca se interrumpa.

### Fase 4: Reconstrucción Automática con Hot Spare
Sin que el operador deba tocar nada, el kernel toma el disco `/dev/nvme4n1` (Hot Spare) y arranca el **Recovery**:
```bash
cat /proc/mdstat
```
Verás la barra de progreso: `recovery = 42.5%`. Al terminar:
- `raid_healthy` vuelve a marcar **`1`**.
- `raid_spare_disks` marca **`0`** (porque el spare se convirtió en disco activo).

### Fase 5: Sustitución Física de Hardware (Drive Swap)
El disco quemado sigue en la bahía en estado `(F)`. Procedemos a su retiro y agregamos el 5º volumen EBS (`/dev/nvme5n1`):
```bash
# Expulsar disco dañado
sudo mdadm /dev/md0 --remove /dev/nvme2n1

# Conectar el nuevo disco físico
sudo mdadm /dev/md0 --add /dev/nvme5n1
```

Las métricas confirman:
`raid_spare_disks 1` -> La infraestructura vuelve a contar con un escudo preventivo ante futuras fallas.

### Fase 6: Auditoría de Paridad (Scrubbing)
Para certificar que no existen inconsistencias latentes:
```bash
echo check | sudo tee /sys/block/md0/md/sync_action
sudo mdadm --wait /dev/md0
cat /sys/block/md0/md/mismatch_cnt
```
Un resultado de `0` certifica que el arreglo es 100% matemáticamente consistente.

---

## 🧹 Limpieza y Destrucción de la Infraestructura

Al terminar la práctica, regresá al directorio de Terraform en tu máquina local y destruí los recursos creados para no incurrir en consumos:

```bash
cd linux/administrator/raid/integrador_aws/terraform
terraform destroy -auto-approve
```

---

## 🎯 Conclusión Pedagógica

Este proyecto integrador concluye la serie RAID demostrando cómo las diferentes capas de la ingeniería de sistemas convergen en el mundo real:
1. **Infraestructura como Código (Terraform):** Aprovisionamiento declarativo y reproducible de almacenamiento en la nube.
2. **Resiliencia del Kernel (RAID 5 & dm/md):** Protección continua ante pérdida física de medios de almacenamiento.
3. **Observabilidad Moderna (Prometheus):** Métricas claras de telemetría que alertan a los equipos SRE antes de que un desastre cause indisponibilidad.
