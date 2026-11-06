# ⚡ Guía Maestra de Demostración en Vivo: Cluster AWS, Resiliencia LVM RAID 1, LUKS2 y Alertas en Tiempo Real (`Alertmanager` + `SRE Alert Hub` + `ntfy.sh`)

> [!IMPORTANT]
> **ARQUITECTURA DEL LABORATORIO EN AWS (`eu-west-1`):**
> - **3 Instancias EC2 (`t3.micro`) con Elastic IPs estáticas** en una VPC dedicada (`10.0.0.0/16`).
> - **Firewall (Security Groups):** Restringido automáticamente a tu IP pública actual (`/32`).
> - **Ciclo Completo de Observabilidad y Respuesta a Incidentes:**
>   1. **Timers de Systemd (cada 3s)** en los Workers publican el estado real de **LVM RAID 1** y **LUKS2** hacia Node Exporter (`:9100`).
>   2. **Prometheus (`:9090`)** recolecta métricas cada 2s y evalúa reglas de alerta (`/etc/prometheus/alert_rules.yml`).
>   3. **Alertmanager (`:9093`)** despacha incidentes `FIRING` y `RESOLVED` en tiempo real.
>   4. **SRE Alert Hub (`:9999`) + `ntfy.sh`** muestran el panel NOC de incidentes en vivo y envían notificaciones push al navegador/celular en **[https://ntfy.sh/lab-sre-monitoreo-aws-dalmine](https://ntfy.sh/lab-sre-monitoreo-aws-dalmine)**.

---

## 🚀 Modos de Ejecución Rápida (Script Automatizado para Clase)

Ubicación del laboratorio:
```bash
cd /home/dalmine/Nextcloud/Repos/labs/linux/administrator/monitoreo/centralizado_terraform
```

Podés conducir toda la demostración con **`./demo_aws_clase.sh`** o ejecutar los comandos manualmente:

| Comando | Qué hace | Cuándo usarlo |
| :--- | :--- | :--- |
| **`./demo_aws_clase.sh`** | Levanta AWS (si no está activo), imprime las URLs y frena con **`[ENTER]`** en cada etapa: **1. Sano ➔ 2. Romper LVM RAID 1 ➔ 3. Cerrar LUKS2 ➔ 4. Reparar ambos en caliente**. | **Ideal para dictar la clase en vivo paso a paso.** |
| **`./demo_aws_clase.sh --auto 2 --break-only`** | Levanta o usa el cluster actual, **rompe LVM RAID 1 y cierra LUKS2**, y se detiene dejando todo en **ROJO (`FIRING`)**. | Cuando querés dejar las pantallas en alerta activa para explicar el incidente. |
| **`./demo_aws_clase.sh --repair-only`** | Ejecuta únicamente la **reparación en caliente** de LVM RAID 1 y la reapertura de LUKS2, pasando las alertas a **VERDE (`RESOLVED`)**. | Después de haber usado `--break-only`. |
| **`terraform destroy -auto-approve`** | Destruye los 22 recursos en AWS (EC2, EBS, Elastic IPs, VPC) dejando **costo $0.00**. | Al finalizar la clase. |

---

## 📌 Tabla de Servicios y Puertos del Cluster

Al ejecutar `terraform apply -auto-approve` o `./demo_aws_clase.sh`, Terraform muestra tus IPs públicas fijas (`<IP_CENTRAL>`, `<IP_WEB_LVM>`, `<IP_DATA_LUKS>`):

| Rol del Nodo | IP Interna (VPC) | Puerto | Servicio / URL | Qué muestra en clase |
| :--- | :--- | :--- | :--- | :--- |
| **Servidor Central** | `10.0.1.10` | `:3000` | `http://<IP_CENTRAL>:3000/d/cluster-monitoreo-multinodo/` | **Grafana Dashboard** (3 nodos UP, Salud LVM RAID 1, Estado LUKS2, CPU/RAM). |
| **Servidor Central** | `10.0.1.10` | `:9999` | `http://<IP_CENTRAL>:9999` | **🔔 SRE Alert Hub Web (Panel NOC)** con auto-refresh cada 3s (`🚨 FIRING` / `✅ RESOLVED`). |
| **Servidor Central** | `10.0.1.10` | `:9093` | `http://<IP_CENTRAL>:9093` | **Prometheus Alertmanager UI**. |
| **Servidor Central** | `10.0.1.10` | `:9090` | `http://<IP_CENTRAL>:9090/alerts` | **Prometheus UI y Estado de Reglas de Alerta**. |
| **Notificación Push** | Externo | `HTTPS` | **[https://ntfy.sh/lab-sre-monitoreo-aws-dalmine](https://ntfy.sh/lab-sre-monitoreo-aws-dalmine)** | **Canal Push en Vivo (`ntfy.sh`)** para navegador y app móvil. |
| **Worker 1 (Web LVM)** | `10.0.1.20` | `:80` | `http://<IP_WEB_LVM>` | **Sitio Web de Producción en Nginx** montado sobre `/dev/vg_web/lv_html` (RAID 1). |
| **Worker 2 (Datos LUKS)** | `10.0.1.30` | `:9100` | Solo red interna VPC | **Bóveda Cifrada LUKS2 (`dm-crypt`)** montada en `/data/segura`. |

---

## 🖥️ Paso 1: Levantar el Entorno y Abrir las Pantallas

1. En tu terminal:
   ```bash
   cd /home/dalmine/Nextcloud/Repos/labs/linux/administrator/monitoreo/centralizado_terraform
   ./demo_aws_clase.sh
   ```
   *(O manualmente con `terraform apply -auto-approve`).*
2. Abrí en pestañas de tu navegador:
   - **Grafana (`:3000`):** Muestra `3/3 UP`, `Salud Espejo LVM RAID 1 = SANO (ÓPTIMO)` y `Estado Cifrado LUKS2 = ABIERTO (ACTIVO)`.
   - **SRE Alert Hub (`:9999`):** Muestra *"✅ Sin incidentes registrados"*.
   - **`ntfy.sh` (`https://ntfy.sh/lab-sre-monitoreo-aws-dalmine`):** Listo para recibir alertas push.
   - **Web Productiva (`http://<IP_WEB_LVM>`):** Muestra `ESTADO: ONLINE (HTTP 200 OK)`.

---

## 💥 Paso 2: DEMO DE CAOS 1 — Romper un Disco de LVM RAID 1 en Caliente (Worker 1)

### 1. Conectarse por SSH al Worker 1 (`srv-web-lvm`):
```bash
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_WEB_LVM>
```

### 2. Mostrar el espejo sano y el Timer de Systemd:
```bash
# A. Espejo RAID 1 sincronizado al 100% entre /dev/nvme1n1 y /dev/nvme2n1
sudo lvs -a -o lv_name,vg_name,attr,health_status,copy_percent,devices vg_web

# B. Timer de Systemd que ejecuta /usr/local/bin/update_lvm_metric.sh cada 3 segundos
systemctl list-timers lvm-metric.timer
cat /var/lib/prometheus/node-exporter/lvm_health.prom
```

### 3. Inyectar la rotura física destruyendo sectores del primer disco EBS:
```bash
sudo dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=10 conv=notrunc
```

### 4. Qué mostrar inmediatamente en vivo:
1. **En la Web (`http://<IP_WEB_LVM>`):** Refrescá con `F5`. **¡La web NO se cae!** Devuelve `HTTP 200 OK` porque `dm-raid` sigue operando desde `/dev/nvme2n1` (*Zero Downtime*).
2. **En la terminal del Worker 1:**
   ```bash
   sudo lvs -o lv_name,vg_name,attr,health_status vg_web/lv_html
   cat /var/lib/prometheus/node-exporter/lvm_health.prom
   ```
   *Verán que `Attr` cambió a `rwi-aor-p-` (`partial`) y `node_lvm_mirror_health` pasó a `0`.*
3. **En Grafana (`:3000`):** El panel **Salud Espejo LVM RAID 1** se pone en **ROJO (`DEGRADADO (FALLA)`)**.
4. **En SRE Alert Hub (`:9999`) y `ntfy.sh`:** Salta la alerta crítica:
   > `🚨 [FIRING] LvmRaid1Degradado (srv-web-lvm) — Espejo LVM RAID 1 DEGRADADO en Worker 1` (incluyendo los comandos del *runbook* de reparación).

---

## 🔐 Paso 3: DEMO DE CAOS 2 — Demostrar y Bloquear el Cifrado LUKS2 (Worker 2)

### 1. Conectarse por SSH al Worker 2 (`srv-data-luks`):
```bash
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@<IP_DATA_LUKS>
```

### 2. Demostrar a los alumnos que el disco físico está cifrado con LUKS2:
```bash
# A. Verificar firma criptográfica en el disco crudo
sudo blkid /dev/nvme1n1
sudo cryptsetup status datos_seguros
lsblk

# B. Intentar montar el disco físico directamente sin descifrar (falla por diseño)
sudo mount /dev/nvme1n1 /mnt

# C. Leer los datos confidenciales a través del mapper descifrado
cat /data/segura/datos_clientes.db
```

### 3. Simular bloqueo de seguridad / cierre de bóveda en vivo:
```bash
sudo umount /data/segura
sudo cryptsetup close datos_seguros
```

### 4. Qué mostrar inmediatamente en vivo:
1. **En Grafana (`:3000`):** El panel **Estado Cifrado LUKS2** cae a **ROJO (`CERRADO (BLOQUEADO)`)**.
2. **En SRE Alert Hub (`:9999`) y `ntfy.sh`:** Salta la segunda alerta urgente:
   > `🔐 [FIRING] LuksContenedorCerrado (srv-data-luks) — Bóveda Cifrada LUKS2 CERRADA en Worker 2`.
3. **En la terminal del Worker 2:** `cat /data/segura/datos_clientes.db` ya no existe; los datos quedaron protegidos en reposo.

---

## 🛠️ Paso 4: Reparación en Caliente (*Hot-Repair*) y Autorresolución (`RESOLVED`)

### 1. En Worker 1 (`srv-web-lvm`) — Reconstruir el espejo LVM RAID 1 sin apagar Nginx:
```bash
sudo vgreduce -y --removemissing --force vg_web
sudo pvcreate -y -ff /dev/nvme1n1
sudo vgextend vg_web /dev/nvme1n1
sudo lvconvert -y --repair vg_web/lv_html

# Verificar que volvió a rwi-aor--- y Cpy%Sync: 100.00
sudo lvs -o lv_name,vg_name,attr,health_status,copy_percent vg_web/lv_html
```

### 2. En Worker 2 (`srv-data-luks`) — Reabrir la bóveda LUKS2 con su llave:
```bash
sudo cryptsetup open --key-file /root/luks.key /dev/nvme1n1 datos_seguros
sudo mount /dev/mapper/datos_seguros /data/segura
cat /data/segura/datos_clientes.db
```

### 3. Qué mostrar en vivo tras la reparación:
- **En Grafana (`:3000`):** Ambos paneles vuelven automáticamente a **VERDE (`1 - SANO / ABIERTO`)**.
- **En SRE Alert Hub (`:9999`) y `ntfy.sh`:** Aparecen las 2 notificaciones en **VERDE (`✅ RESOLVED`)**:
  - `✅ [RESOLVED] LvmRaid1Degradado (srv-web-lvm)`
  - `✅ [RESOLVED] LuksContenedorCerrado (srv-data-luks)`

---

## 🧹 Paso 5: Destrucción Total del Entorno (Fin de Clase - Costo $0)

Al terminar la clase, ejecutá desde `linux/administrator/monitoreo/centralizado_terraform`:

```bash
terraform destroy -auto-approve
```
*(Elimina las 3 instancias EC2, los 3 volúmenes EBS, libera las 3 Elastic IPs estáticas y borra la VPC).*
