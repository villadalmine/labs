# Cluster de Monitoreo Centralizado Multi-Nodo en AWS (Prometheus, Grafana, LVM RAID 1 y LUKS2)

Este módulo de Terraform aprovisiona una arquitectura de observabilidad distribuida y almacenamiento empresarial tolerante a desastres sobre **3 instancias EC2** en una VPC dedicada de AWS (`eu-west-1`):

```
                                      ┌──────────────────────────────────────────────────────────┐
                                      │             VPC Dedicada (10.0.0.0/16)                   │
                                      │                                                          │
     🌐 Administrador (Tu IP /32)     │   ┌──────────────────────────────────────────────────┐   │
                │                     │   │   Servidor Central: srv-monitoreo (10.0.1.10)    │   │
                ├────────────────────────►│   - Prometheus :9090 (Scrape PULL cada 5s)       │   │
                │   (Grafana :3000)   │   │   - Grafana :3000 (Dashboard Multi-Nodo)         │   │
                │                     │   └──────────────┬───────────────────┬───────────────┘   │
                │                     │                  │ HTTP PULL         │ HTTP PULL         │
                │                     │                  ▼ :9100             ▼ :9100             │
                │                     │   ┌───────────────────────────┐   ┌──────────────────┐   │
                ├────────────────────────►│ Worker 1: srv-web-lvm     │   │ Worker 2: srv-   │   │
                │   (Nginx HTTP :80)  │   │ (10.0.1.20)               │   │ data-luks        │   │
                │                     │   │ - Nginx Web Server (:80)  │   │ (10.0.1.30)      │   │
                │                     │   │ - LVM RAID 1 Espejado     │   │ - Cifrado LUKS2  │   │
                │                     │   │   (2x EBS gp3 1GB)        │   │   (1x EBS gp3)   │   │
                │                     │   │ - Node Exporter :9100     │   │ - Node Exporter  │   │
                │                     │   │ - Timer Systemd (cada 3s) │   │ - Timer Systemd  │   │
                │                     │   └───────────────────────────┘   └──────────────────┘   │
                │                                                                                │
                └────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📌 Componentes y Nodos del Cluster

1. **`srv-monitoreo` (10.0.1.10):**
   - **Prometheus (:9090):** Configurado con retención y recolección HTTP PULL cada 5 segundos hacia los Workers.
   - **Grafana (:3000):** Dashboard pre-aprovisionado ("Cluster Monitoreo Multi-Nodo") con visualización en tiempo real de nodos UP, estado de espejos LVM, estado de contenedores LUKS, CPU, RAM y latencia.
2. **`srv-web-lvm` (10.0.1.20):**
   - **Nginx Web Server (:80):** Sirve tráfico productivo desde `/var/www/html` montado sobre un volumen lógico espejado (`/dev/vg_web/lv_html`).
   - **Almacenamiento LVM RAID 1:** 2 volúmenes EBS gp3 (`/dev/nvme1n1` y `/dev/nvme2n1`) tolerante a la pérdida de un disco físico (*Zero Downtime*).
   - **Systemd Timer (`lvm-metric.timer`):** Ejecuta cada 3 segundos el script de actualización `/usr/local/bin/update_lvm_metric.sh` con `lvs --readonly` para refrescar `/var/lib/prometheus/node-exporter/lvm_health.prom`.
3. **`srv-data-luks` (10.0.1.30):**
   - **Almacén Cifrado LUKS2 (dm-crypt):** Disco EBS gp3 cifrado con Argon2id montado en `/data/segura`.
   - **Systemd Timer (`luks-metric.timer`):** Ejecuta cada 3 segundos `/usr/local/bin/update_luks_metric.sh` para reportar el estado criptográfico a `/var/lib/prometheus/node-exporter/luks_status.prom`.

---

## 🔒 Elastic IPs Estáticas y Seguridad de Red

- **IPs Públicas Fijas:** Las 3 instancias cuentan con **Elastic IPs (EIP)** asociadas estáticamente. Las direcciones IP no cambian entre ejecuciones de `terraform apply` o reinicios.
- **Firewall Estricto:** Los Security Groups restringen el acceso a los puertos administrativos (SSH `:22`, Prometheus `:9090`, Grafana `:3000`, Nginx `:80`) **exclusivamente a tu dirección IP pública autorizada**.

---

## 🚀 Despliegue Rápido

```bash
# 1. Inicializar providers de Terraform
terraform init

# 2. Planificar el despliegue
terraform plan

# 3. Aplicar y levantar la infraestructura
terraform apply -auto-approve
```

Al finalizar, Terraform genera una tabla con todas las URLs y comandos directos de conexión:

```
Outputs:

1_servicios_web = <<EOT
----------------------------------------------------------------------------------------------------------------
CLUSTER DE MONITOREO CENTRALIZADO EN AWS (PROMETHEUS + GRAFANA + WORKERS)
----------------------------------------------------------------------------------------------------------------
Grafana Dashboard  : http://<IP_SRV_CENTRAL>:3000/d/cluster-monitoreo-multinodo/
Prometheus Server  : http://<IP_SRV_CENTRAL>:9090
Servidor Web (LVM) : http://<IP_SRV_WEB_LVM>/
----------------------------------------------------------------------------------------------------------------
EOT
```

---

## 🔑 Conexión SSH

Terraform genera automáticamente el par de llaves Ed25519 (`id_ed25519` y `id_ed25519.pub`).

> [!TIP]
> **En Windows PowerShell:**
> Si `ssh` reporta advertencias sobre permisos excesivos en `id_ed25519`, ejecutá una sola vez:
> ```powershell
> .\fix_ssh_permissions.bat
> ```

Comandos de conexión directa:
```bash
# Servidor Central
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_SRV_CENTRAL>

# Worker 1 (Web LVM)
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_SRV_WEB_LVM>

# Worker 2 (Datos LUKS)
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_SRV_DATA_LUKS>
```

---

## ⚡ Demostración en Vivo: Inyección de Fallas y Resiliencia

Seguí la guía paso a paso para clase en [**`GUIA_DEMO_EN_VIVO.md`**](../../../../GUIA_DEMO_EN_VIVO.md):

1. **Verificar el Timer de Systemd en Worker 1:**
   ```bash
   systemctl list-timers lvm-metric.timer
   ```
2. **Inyectar Falla de Disco en Caliente:**
   ```bash
   sudo dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=10 conv=notrunc
   ```
3. **Verificar Continuidad del Servicio (Zero Downtime):**
   - El sitio web en `http://<IP_SRV_WEB_LVM>/` responde inmediatamente (HTTP 200).
   - En Grafana, la aguja cae a **ROJO (`0 - DEGRADADO`)** en 3 segundos.
4. **Reparación en Caliente:**
   ```bash
   sudo lvconvert -y --repair vg_web/lv_html
   sudo vgreduce -y --removemissing --force vg_web
   ```
   - La métrica vuelve automáticamente a **VERDE (`1 - SANO`)** sin reiniciar servicios.

---

## 🧹 Destrucción del Cluster

Al terminar la clase, destruí los recursos de AWS para liberar las Elastic IPs y evitar costos no deseados:

```bash
terraform destroy -auto-approve
```
