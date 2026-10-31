# ⚡ Guía Maestra de Demostración en Vivo: Cluster, Resiliencia y Cifrado en Tiempo Real

> [!IMPORTANT]
> **ESTADO DEL ENTORNO EN AWS (`eu-west-1`):**
> El cluster ya se encuentra **100% desplegado, configurado y operativo**.
> Las 3 IPs públicas son **Elastic IPs Estáticas** gestionadas por Terraform. **NUNCA cambiarán**, ni al reiniciar máquinas ni al reejecutar comandos.
> El Firewall (Security Groups) restringe el acceso **exclusivamente a tu IP pública (`81.207.69.100/32`)**.
> **No necesitas tocar Terraform durante la clase**, solo seguir los pasos de esta guía.

---

## 📌 Datos de Conexión del Cluster (IPs Fijas)

| Rol del Nodo | IP Pública (Estática) | IP Interna (VPC) | Servicios / Puertos | Enlaces y Estado |
| :--- | :--- | :--- | :--- | :--- |
| **Servidor Central** | `108.129.58.36` | `10.0.1.10` | Grafana (3000), Prometheus (9090) | 👉 [Abrir Grafana Dashboard](http://108.129.58.36:3000/d/cluster-monitoreo-multinodo/)<br>👉 [Abrir Prometheus UI](http://108.129.58.36:9090) |
| **Worker 1 (Web LVM)** | `52.51.148.219` | `10.0.1.20` | Nginx Web (80), Exporter (9100) | 👉 [Abrir Servidor Web](http://52.51.148.219) |
| **Worker 2 (Datos LUKS)** | `54.73.199.14` | `10.0.1.30` | Exporter (9100), Almacén Cifrado | Almacenamiento seguro `/data/segura` |

> [!TIP]
> **Si estás en Windows y `ssh` te advierte sobre permisos de clave:**
> Ejecutá una sola vez desde la carpeta `centralizado_terraform`:
> ```powershell
> .\fix_ssh_permissions.bat
> ```

---

## 🖥️ Paso 1: Mostrar la Arquitectura en Pantalla (Grafana en Vivo)

Abrí en tu navegador:
👉 **[http://108.129.58.36:3000/d/cluster-monitoreo-multinodo/](http://108.129.58.36:3000/d/cluster-monitoreo-multinodo/)** *(Acceso directo sin contraseña)*

### Elementos a destacar a los alumnos:
1. **Nodos Activos en Cluster:** Marca `3/3 UP` en verde (Prometheus Central descubre y scrapea a los 2 Workers vía VPC interna).
2. **Salud LVM RAID 1:** Marca `1 - SANO (ÓPTIMO)` en verde (espejo activo entre 2 discos EBS).
3. **Estado Contenedor Cifrado (LUKS2):** Marca `1 - ABIERTO (SEGURO)` en verde.
4. **Métricas en Vivo:** Gráficos de CPU, RAM y uso de disco actualizándose cada 5 segundos.

---

## 🌐 Paso 2: Mostrar el Servicio Web en Producción

Abrí en otra pestaña:
👉 **[http://52.51.148.219](http://52.51.148.219)**

* Verán la página de producción servida por Nginx desde el Logical Volume `/dev/vg_web/lv_html` montado sobre `/var/www/html`.

---

## 💥 Paso 3: DEMO DE CAOS 1 — Romper el Disco de LVM RAID 1 en Caliente (Worker 1)

### 1. Conexión SSH a Worker 1:
Abrí tu terminal en la carpeta del lab y conectate:
```bash
cd linux/administrator/monitoreo/centralizado_terraform
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@52.51.148.219
```

### 2. Mostrar a los alumnos el espejo perfecto y el Systemd Timer:
```bash
# A. Salud LVM: Cpy%Sync: 100.00 con dos discos sincronizados (/dev/nvme1n1 y /dev/nvme2n1)
sudo lvs -a -o lv_name,vg_name,copy_percent,devices

# B. Observar el Systemd Timer que refresca la telemetría para Node Exporter cada 3 segundos:
systemctl list-timers lvm-metric.timer
```

### 3. Inyectar la rotura física destruyendo sectores del primer disco:
```bash
sudo dd if=/dev/zero of=/dev/nvme1n1 bs=1M count=10 conv=notrunc
```

### 4. Qué mostrar inmediatamente en vivo:
1. **En Grafana:** En solo 2 a 4 segundos, el panel **"Salud LVM RAID 1"** cae a **ROJO (`0 - DEGRADADO`)**.
2. **En la Web (`http://52.51.148.219`):** Refrescá la página (`F5`). **¡LA WEB NO SE CAE!** Responde con HTTP 200 OK inmediatamente porque el driver de LVM redirige las peticiones al disco sano (`/dev/nvme2n1`). Cero pérdida de servicio (*Zero Downtime*).
3. **En la terminal de Worker 1:**
   ```bash
   sudo lvs -o lv_name,attr,health_status vg_web
   ```
   *Verán el estado de salud como `degraded`.*

### 5. Reparación en caliente (*Hot-Repair*) en vivo:
En la misma terminal del Worker 1, simulá la recuperación expulsando el disco roto:
```bash
sudo lvconvert -y --repair vg_web/lv_html
sudo vgreduce -y --removemissing --force vg_web
```
* **En Grafana:** La aguja vuelve automáticamente a **VERDE (`1 - SANO`)** sin haber reiniciado ningún servicio ni desconectado a los usuarios.

---

## 🔐 Paso 4: DEMO 2 — Cómo Explicar y Demostrar el Cifrado LUKS2 (Worker 2)

> [!NOTE]
> **¿Por qué parece un disco normal si solo miro `df -h`?**
> En Linux, la arquitectura de cifrado **dm-crypt (LUKS)** opera en **2 capas superpuestas**:
> 1. **Capa Física (Raw Device):** El disco físico crudo `/dev/nvme1n1`. Contiene bytes cifrados inaccesibles.
> 2. **Capa Lógica (Device Mapper):** El dispositivo descifrado `/dev/mapper/datos_seguros`. El kernel de Linux se interpone entre el filesystem y el disco, descifrando los bloques en memoria RAM en tiempo real con cifrado AES-XTS-512.
>
> Para el sistema operativo, el punto de montaje `/data/segura` parece un filesystem estándar, pero físicamente en el disco todo está completamente cifrado.

### 1. Conexión SSH a Worker 2:
Abrí otra terminal y conectate:
```bash
cd linux/administrator/monitoreo/centralizado_terraform
ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@54.73.199.14
```

### 2. Comandos para demostrar a los alumnos que es LUKS y NO un disco normal:

#### A. Demostrar que el disco físico crudo está cifrado y bloqueado:
```bash
sudo file -s /dev/nvme1n1
```
*Salida:* `LUKS encrypted file, ver 2, algo sha256... [aes, xts-plain64, sha256] UUID: ...`

```bash
sudo blkid /dev/nvme1n1
```
*Salida:* `TYPE="crypto_LUKS"` *(El kernel reconoce que NO es un disco normal; es una bóveda LUKS)*.

#### B. Intentar montar el disco físico directamente (demostración forense):
```bash
sudo mount /dev/nvme1n1 /mnt
```
*Salida:* **Error inmediato:** `mount: /mnt: unknown filesystem type 'crypto_LUKS'`.
> Explicar a los alumnos: *Si un atacante roba este volumen de AWS o extrae el disco físico, es 100% imposible leer o montar los datos sin la clave criptográfica.*

#### C. Inspeccionar los metadatos y la cabecera criptográfica del contenedor:
```bash
sudo cryptsetup status datos_seguros
```
*Salida:*
```text
/dev/mapper/datos_seguros is active and is in use.
  type:    LUKS2
  cipher:  aes-xts-plain64
  keysize: 512 bits
  device:  /dev/nvme1n1
```

```bash
sudo cryptsetup luksDump /dev/nvme1n1 | head -n 25
```
*Muestra los metadatos de grado militar: LUKS versión 2, cifrado AES-XTS de 512 bits, hash SHA256 y Keyslot 0 activo.*

#### D. Ver la estructura en árbol (`lsblk`):
```bash
lsblk
```
*Salida visual clara:*
```text
nvme1n1         259:0    0    1G  0 disk  
└─datos_seguros 252:0    0 1008M  0 crypt /data/segura
```
*(Se observa claramente cómo el dispositivo `crypt` `datos_seguros` se monta sobre el disco base `nvme1n1`).*

#### E. Leer los datos confidenciales actualmente descifrados:
```bash
cat /data/segura/datos_clientes.db
```
*Salida:* `CONFIDENTIAL_PRODUCTION_DATA_2026`

---

### 3. Inyectar fallo de seguridad en vivo (Cierre de Bóveda):

Ejecutá en Worker 2 para simular una revocación de seguridad o sabotaje:
```bash
sudo umount /data/segura
sudo cryptsetup close datos_seguros
```

#### 💥 QUÉ MOSTRAR EN VIVO:
1. **En Grafana:** En menos de 2 segundos, el panel **"Estado Contenedor Cifrado (LUKS2)"** cae a **ROJO (`0 - CERRADO / ALERTA`)**.
2. **En la terminal de Worker 2:**
   - Si ejecutás `lsblk`, el mapper `datos_seguros` **desapareció**.
   - Si ejecutás `cat /data/segura/datos_clientes.db`, **el archivo no existe**, la carpeta está completamente vacía y los datos quedaron inaccesibles.

---

### 4. Recuperación y reapertura de la bóveda con la clave:
Ejecutá en Worker 2:
```bash
sudo cryptsetup open --key-file /root/luks_key.bin /dev/nvme1n1 datos_seguros
sudo mount /dev/mapper/datos_seguros /data/segura
```

* **En Grafana:** El panel vuelve instantáneamente a **VERDE (`1 - ABIERTO`)**.
* **En Worker 2:** Los datos confidenciales vuelven a ser legibles:
  ```bash
  cat /data/segura/datos_clientes.db
  ```

---

## 🛑 Paso 5: Destrucción Total del Entorno (Fin de Clase - Costo $0)

> [!IMPORTANT]
> **¿Qué pasa con las IPs fijas (Elastic IPs) al destruir?**
> Como las 3 Elastic IPs fueron declaradas como recursos en Terraform (`aws_eip.eip_central`, `aws_eip.eip_web`, `aws_eip.eip_luks`), **Terraform las libera automáticamente devolviéndolas a la pool de AWS**.
> No queda ninguna IP retenida ni cobrando. Todo se elimina al 100%.

Cuando termine la clase, abrí tu terminal en tu máquina Windows y ejecutá:
```powershell
cd C:\Users\rino\Documents\GitHub\labs\linux\administrator\monitoreo\centralizado_terraform
terraform destroy -auto-approve
```

### Qué elimina este comando:
1. Libera las 3 Elastic IPs fijas (`aws_eip`).
2. Termina y destruye las 3 instancias EC2 (`srv_central`, `srv_web_lvm`, `srv_data_luks`).
3. Destruye los volúmenes EBS adicionales de LVM y LUKS.
4. Elimina la clave SSH `aws_key_pair`.
5. Elimina los Security Groups, Subnet, Internet Gateway, Route Tables y la VPC.
6. **Costo remanente en AWS: $0.00**.
