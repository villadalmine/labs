# Cluster de Monitoreo Centralizado Multi-Nodo en AWS (Prometheus, Grafana, Alertmanager, SRE Alert Hub, ntfy.sh, LVM RAID 1 y LUKS2)

Este módulo de Terraform aprovisiona una arquitectura de observabilidad distribuida, alerta temprana y almacenamiento empresarial tolerante a desastres sobre **3 instancias EC2** en una VPC dedicada de AWS (`eu-west-1`):

```text
                                      ┌──────────────────────────────────────────────────────────────────┐
                                      │                 VPC Dedicada (10.0.0.0/16)                       │
                                      │                                                                  │
     🌐 Administrador (Tu IP /32)     │   ┌──────────────────────────────────────────────────────────┐   │
                │                     │   │   Servidor Central: srv-monitoreo (10.0.1.10)            │   │
                ├────────────────────────►│   - Prometheus :9090 (Scrape PULL + Alert Rules cada 2s) │   │
                │   (Grafana :3000)   │   │   - Alertmanager :9093 (Routing FIRING / RESOLVED)       │   │
                ├────────────────────────►│   - SRE Alert Hub :9999 (Panel NOC Web + Bridge ntfy.sh) │───┼──► 📲 https://ntfy.sh/<topico>
                │   (Alert Hub :9999) │   │   - Grafana :3000 (Dashboard Multi-Nodo Pre-aprovisionado)│   │
                │                     │   └──────────────┬───────────────────────────┬───────────────┘   │
                │                     │                  │ HTTP PULL                 │ HTTP PULL         │
                │                     │                  ▼ :9100                     ▼ :9100             │
                │                     │   ┌───────────────────────────┐   ┌──────────────────────────┐   │
                ├────────────────────────►│ Worker 1: srv-web-lvm     │   │ Worker 2: srv-data-luks  │   │
                │   (Nginx HTTP :80)  │   │ (10.0.1.20)               │   │ (10.0.1.30)              │   │
                │                     │   │ - Nginx Web Server (:80)  │   │ - Cifrado LUKS2          │   │
                │                     │   │ - LVM RAID 1 Espejado     │   │   (1x EBS gp3 1GB)       │   │
                │                     │   │   (2x EBS gp3 1GB)        │   │ - Node Exporter :9100    │   │
                │                     │   │ - Node Exporter :9100     │   │ - Timer Systemd (cada 3s)│   │
                │                     │   │ - Timer Systemd (cada 3s) │   │   (luks-metric.timer)    │   │
                │                     │   │   (lvm-metric.timer)      │   │                          │   │
                │                     │   └───────────────────────────┘   └──────────────────────────┘   │
                └────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📌 Componentes y Nodos del Cluster

1. **`srv-monitoreo` (`10.0.1.10`):**
   - **Prometheus (`:9090`):** Recolección HTTP PULL cada 2 segundos hacia los Workers y evaluación continua de `/etc/prometheus/alert_rules.yml` (`LvmRaid1Degradado`, `LuksContenedorCerrado`, `NodoWorkerCaido`).
   - **Prometheus Alertmanager (`:9093`):** Agrupa y despacha alertas en estado `FIRING` y `RESOLVED` (`send_resolved: true`) hacia el receptor Webhook local.
   - **SRE Alert Hub Web (`:9999`) + Puente `ntfy.sh`:** Servicio `alert-hub.service` en Python que ofrece un panel web estilo *NOC / PagerDuty* con auto-refresh cada 3s y reenvía notificaciones push urgentes a `https://ntfy.sh/lab-sre-monitoreo-aws-dalmine`.
   - **Grafana (`:3000`):** Dashboard pre-aprovisionado (*"Cluster Multi-Nodo: Prometheus Central + Workers"*) con acceso directo como Admin sin contraseña.
2. **`srv-web-lvm` (`10.0.1.20`):**
   - **Nginx Web Server (`:80`):** Sirve tráfico productivo desde `/var/www/html` montado sobre un volumen lógico espejado (`/dev/vg_web/lv_html`).
   - **Almacenamiento LVM RAID 1:** 2 volúmenes EBS gp3 (`/dev/nvme1n1` y `/dev/nvme2n1`) tolerantes a la pérdida física de un disco (*Zero Downtime*).
   - **Systemd Timer (`lvm-metric.timer`):** Ejecuta cada 3 segundos `/usr/local/bin/update_lvm_metric.sh` con `lvs --noheadings -o health_status,attr vg_web/lv_html` y publica `node_lvm_mirror_health` en `/var/lib/prometheus/node-exporter/lvm_health.prom`.
3. **`srv-data-luks` (`10.0.1.30`):**
   - **Almacén Cifrado LUKS2 (`dm-crypt`):** Disco EBS gp3 cifrado con AES-XTS-512 montado en `/data/segura` (`/dev/mapper/datos_seguros`).
   - **Systemd Timer (`luks-metric.timer`):** Ejecuta cada 3 segundos `/usr/local/bin/update_luks_metric.sh` y publica `node_luks_container_active` en `/var/lib/prometheus/node-exporter/luks_status.prom`.

---

## 🎓 Opción A: Ejecución Guiada con Script Interactivo (Recomendado para Clase)

Desde esta misma carpeta podés usar el script **`demo_aws_clase.sh`**, que automatiza el despliegue, espera a `cloud-init`, muestra todas las URLs y te guía paso a paso pausando con `[ENTER]`:

```bash
cd /home/dalmine/Nextcloud/Repos/labs/linux/administrator/monitoreo/centralizado_terraform

# 1. Modo Clase Interactivo (pausa con [ENTER] en cada etapa: Sano -> Caos LVM -> Caos LUKS -> Hot-Repair):
./demo_aws_clase.sh

# 2. Modo Solo Romper (levanta o usa el cluster actual, inyecta las fallas y se detiene dejando las alertas en FIRING):
./demo_aws_clase.sh --auto 2 --break-only

# 3. Modo Solo Reparar (repara en caliente LVM RAID 1 y reabre LUKS2, pasando las alertas a RESOLVED):
./demo_aws_clase.sh --repair-only

# 4. Modo Ciclo Completo Desatendido + Destrucción Final:
./demo_aws_clase.sh --auto 3 --destroy
```

---

## 🛠️ Opción B: Paso a Paso Manual para Mostrar en Clase

### Paso 1: Levantar la Infraestructura con Terraform

```bash
cd /home/dalmine/Nextcloud/Repos/labs/linux/administrator/monitoreo/centralizado_terraform

terraform init
terraform apply -auto-approve
```

Al terminar (aprox. 45 segundos), Terraform imprime la tabla resumen con las **Elastic IPs estáticas** y todas las URLs:
- **Grafana Dashboard (`:3000`):** `http://<IP_CENTRAL>:3000/d/cluster-monitoreo-multinodo/`
- **SRE Alert Hub Web (`:9999`):** `http://<IP_CENTRAL>:9999`
- **Prometheus Alertmanager (`:9093`):** `http://<IP_CENTRAL>:9093`
- **Prometheus Server (`:9090`):** `http://<IP_CENTRAL>:9090/alerts`
- **Canal Push `ntfy.sh`:** `https://ntfy.sh/lab-sre-monitoreo-aws-dalmine`
- **Servidor Web Productivo (`:80`):** `http://<IP_WEB_LVM>/`

> [!NOTE]
> Apenas termina `terraform apply`, `cloud-init` tarda ~60-90 segundos en terminar de instalar paquetes en los 3 nodos. Podés verificar que terminó corriendo:
> ```bash
> ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_CENTRAL> "cloud-init status --wait"
> ```

---

### Paso 2: Mostrar el Estado Inicial Sano (`1 - SANO / ABIERTO`)

1. Abrí en el navegador **Grafana (`:3000`)**, **SRE Alert Hub (`:9999`)**, **`https://ntfy.sh/lab-sre-monitoreo-aws-dalmine`** y la **Web de Producción (`http://<IP_WEB_LVM>`)**.
2. Conectate por SSH al **Worker 1 (`srv-web-lvm`)**:
   ```bash
   ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_WEB_LVM>
   ```
3. Mostrá el espejo LVM RAID 1 sincronizado al 100% y el Timer de Systemd que actualiza la métrica cada 3 segundos:
   ```bash
   sudo lvs -a -o lv_name,vg_name,attr,health_status,copy_percent,devices vg_web
   systemctl list-timers lvm-metric.timer
   cat /var/lib/prometheus/node-exporter/lvm_health.prom
   ```

---

### Paso 3: Inyectar Caos 1 — Romper un Disco del Espejo LVM RAID 1 en Caliente

Dentro del **Worker 1 (`srv-web-lvm`)**, destruí los primeros 10 MB (cabecera PV y sectores) del primer disco EBS:

```bash
sudo dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=10 conv=notrunc
```

**Qué mostrar inmediatamente a los alumnos:**
1. **Resiliencia Web (*Zero Downtime*):** Recargá `http://<IP_WEB_LVM>/` en el navegador (`F5`). Sigue respondiendo **`HTTP 200 OK`** sin caída porque `dm-raid` sirve desde el segundo disco (`/dev/nvme2n1`).
2. **Diagnóstico en consola de Worker 1:**
   ```bash
   sudo lvs -o lv_name,vg_name,attr,health_status vg_web/lv_html
   cat /var/lib/prometheus/node-exporter/lvm_health.prom
   ```
   *(El atributo muestra `rwi-aor-p-`, estado `partial` y la métrica cambió de `1` a `0`).*
3. **En Grafana (`:3000`):** En 3 segundos el panel **"Salud Espejo LVM RAID 1"** cae a **ROJO (`DEGRADADO (FALLA)`)**.
4. **En SRE Alert Hub (`:9999`) y `ntfy.sh`:** Aparece la tarjeta roja **`🚨 FIRING (ACTIVA) — LvmRaid1Degradado`** con el comando de reparación.

---

### Paso 4: Inyectar Caos 2 — Cierre de Emergencia de la Bóveda Cifrada LUKS2

Conectate por SSH al **Worker 2 (`srv-data-luks`)**:

```bash
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_DATA_LUKS>
```

1. Mostrá que el disco físico `/dev/nvme1n1` es un contenedor `crypto_LUKS` y que los datos están montados en `/data/segura`:
   ```bash
   sudo cryptsetup status datos_seguros
   cat /data/segura/datos_clientes.db
   ```
2. Desmontá y cerrá la bóveda criptográfica en vivo:
   ```bash
   sudo umount /data/segura
   sudo cryptsetup close datos_seguros
   ```
3. **Qué mostrar inmediatamente:**
   - En **Grafana (`:3000`)**, el panel **"Estado Cifrado LUKS2"** cae a **ROJO (`CERRADO (BLOQUEADO)`)**.
   - En **SRE Alert Hub (`:9999`) y `ntfy.sh`**, salta la segunda alerta urgente **`🚨 FIRING — LuksContenedorCerrado`**.

---

### Paso 5: Reparación en Caliente (*Hot-Repair*) y Autorresolución (`RESOLVED`)

1. **En Worker 1 (`srv-web-lvm`), reparar el espejo LVM RAID 1 en caliente:**
   ```bash
   sudo vgreduce -y --removemissing --force vg_web
   sudo pvcreate -y -ff /dev/nvme1n1
   sudo vgextend vg_web /dev/nvme1n1
   sudo lvconvert -y --repair vg_web/lv_html
   sudo lvs -o lv_name,vg_name,attr,health_status,copy_percent vg_web/lv_html
   ```
2. **En Worker 2 (`srv-data-luks`), reabrir y montar la bóveda LUKS2:**
   ```bash
   sudo cryptsetup open --key-file /root/luks.key /dev/nvme1n1 datos_seguros
   sudo mount /dev/mapper/datos_seguros /data/segura
   ```
3. **Qué mostrar en el navegador:**
   - En **Grafana (`:3000`)**, ambos indicadores vuelven automáticamente a **VERDE (`1 - SANO / ABIERTO`)**.
   - En **SRE Alert Hub (`:9999`) y `ntfy.sh`**, llegan automáticamente las tarjetas verdes **`✅ RESOLVED (RESUELTA)`** cerrando el ciclo de incidente.

---

## 🧹 Paso 6: Destrucción del Cluster (Fin de Clase - Costo $0)

Al terminar la clase, destruí los 22 recursos de AWS (instancias, volúmenes EBS, Elastic IPs y VPC):

```bash
terraform destroy -auto-approve
```
