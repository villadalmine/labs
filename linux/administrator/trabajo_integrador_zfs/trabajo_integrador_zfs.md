---
id: integrador-4.4-zfs-ha-activo-pasivo-alb
title: 'Trabajo Integrador 4: ZFS Enterprise HA Activo-Pasivo, Replicación Remota
  y AWS ALB Failover'
difficulty_level: 4
difficulty_label: 'Nivel 4: Proyectos Integradores en la Nube (AWS Free Tier con Terraform)'
section: '4.4'
sections:
- '4.4'
- '4'
category: cloud-iac
tags:
- cloud-iac
- storage
- zfs
- zpool
- vdev
- ha
- activo-pasivo
- failover
- replicacion
- alb
- aws
- ec2
- terraform
- scrub
- self-healing
tools:
- terraform
- zpool
- zfs
- ssh
- curl
- dd
requirements:
  root_required: true
  cloud_required: true
  min_ram_mb: 1024
  min_disks: 3
  cloud_provider: AWS
tested_environments:
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Despliegue multi-AZ en AWS con Terraform (2 EC2 t3.micro, 3 discos EBS, Application
    Load Balancer ALB con health check HTTP, replicación zfs send/receive y conmutación
    por error).
environments:
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: VERIFIED
rag_summary: Proyecto integrador de alta disponibilidad empresarial utilizando OpenZFS
  en Linux y balanceo de carga en AWS. Enseña a crear zpools con VDEVs espejados en
  caliente, configurar datasets con compresión LZ4, automatizar la replicación periódica
  de snapshots incrementales por SSH (zfs send | ssh zfs receive), orquestar el tráfico
  web con un AWS ALB mediante sondas de salud dinámicas (/health) y ejecutar procedimientos
  de conmutación por error (failover) en segundos sin pérdida de consistencia.
files:
  guide: trabajo_integrador_zfs/trabajo_integrador_zfs.md
  script: trabajo_integrador_zfs/demo_integrador_zfs.sh
  terraform: trabajo_integrador_zfs/terraform
resource_type: cloud_project
has_guide: true
has_interactive_script: true
has_terraform: true
execution_mode: terraform_apply
prerequisites:
- lab-3.1-anatomia-filesystems
- integrador-4.3-btrfs-subvolumes-reflinks-raid1
mcp_tools:
- linux-labs-tutor
- terraform
- aws
---

# Trabajo Integrador 3: Alta Disponibilidad con ZFS Replicación Remota Activo-Pasivo y AWS Application Load Balancer

Este laboratorio avanzado de nivel profesional enseña a administrar **ZFS en Linux**, entender **Copy-on-Write (CoW)**, gestionar **VDEVs y Zpools**, realizar **ampliaciones de discos y espejos en caliente**, automatizar la **replicación remota por red con `zfs send | ssh zfs receive`**, y construir una arquitectura **Activo-Pasivo tolerante a fallos** gobernada por un **AWS Application Load Balancer (ALB)**.

---

## 🏗️ Arquitectura de la Solución

```
                                  Internet
                                     |
                                     v  (Puerto 80)
                     +-------------------------------+
                     |  AWS Application Load Balancer|
                     |  Sonda de Salud: GET /health  |
                     +-------------------------------+
                                     |
                    +----------------+----------------+
                    | (100% Tráfico)                  | (0% Standby)
                    | [Salud: 200 OK]                 | [Salud: 503 Service Unavail]
                    v                                 v
   +---------------------------------+  +---------------------------------+
   |      VM 1: NODO ACTIVO          |  |      VM 2: NODO PASIVO          |
   |   (vm-zfs-active-prod)          |  |   (vm-zfs-passive-standby)      |
   |                                 |  |                                 |
   | Nginx sirviendo sitio web       |  | Nginx en espera (/health -> 503)|
   |                                 |  |                                 |
   | Pool: zpool_web                 |  | Pool: zpool_backup              |
   |  |-- Disco 1 (nvme1n1 - 1 GB)   |  |  +-- Disco 1 (nvme1n1 - 1 GB)   |
   |  +-- Disco 2 (nvme2n1 - 1 GB)   |  |                                 |
   |      [Attach en caliente mirror]|  |                                 |
   |                                 |  |                                 |
   | Dataset: zpool_web/site         |  | Dataset: zpool_backup/site      |
   | (readonly = off, comp = lz4)    |  | (readonly = on)                 |
   +---------------------------------+  +---------------------------------+
                    |                                    ^
                    |      zfs snapshot + zfs send       |
                    +------------------------------------+
                          (Túnel SSH incremental)
```

---

## 🧠 Fundamentos Teóricos de ZFS

### 1. ¿Por qué ZFS no usa LVM ni `mkfs`?
En Linux clásico, el almacenamiento se organiza en capas separadas:
```text
Disco Físico -> Partición -> PV -> VG -> LV -> mkfs.ext4 -> mount
```
**ZFS unifica el gestor de volúmenes y el sistema de archivos en una sola entidad.**
No existen particiones fijas ni tamaños rígidos:
* **VDEV (Virtual Device):** Agrupación física de discos (Single, Mirror, RAIDZ1, RAIDZ2).
* **Zpool:** El pool de almacenamiento global que agrega uno o más VDEVs.
* **Dataset:** Un sistema de archivos lógico dentro del pool. Comparte todo el espacio libre del pool dinámicamente y posee sus propias propiedades (compresión, cifrado, cuotas, snapshots).

### 2. Copy-on-Write (CoW) y Snapshots Instantáneos
En sistemas tradicionales (ext4, xfs), modificar un archivo sobreescribe los bloques en su posición original (*in-place*). Si el servidor sufre un corte de energía mientras escribe, se produce inconsistencia de datos.

En **ZFS**, **nunca se sobreescribe un bloque activo**:
1. Los nuevos datos se escriben siempre en bloques libres vírgenes.
2. Una vez completada la escritura y calculado el checksum, los punteros del árbol de metadatos se actualizan atómicamente.
3. Los **Snapshots** en ZFS son instantáneos ($O(1)$) porque simplemente congelan los punteros del árbol de bloques en ese segundo exacto, consumiendo **0 bytes adicionales** hasta que se produzcan nuevas modificaciones.

### 3. Checksums y Auto-Curación (*Self-Healing*)
Cada bloque en ZFS incluye un checksum de 256 bits (SHA-256 o Fletcher4) guardado en el puntero del bloque padre.
* Si un bloque sufre corrupción silenciosa (*bit rot* o error de disco), ZFS detecta que el hash no coincide con el checksum.
* Si el pool está configurado en **mirror (espejo)**, ZFS lee automáticamente el bloque correcto del disco réplica, devuelve el dato bueno a la aplicación sin errores de lectura, y reescribe y repara el bloque dañado en segundo plano.

---

## 🚀 Fase 1: Despliegue de Infraestructura en AWS con Terraform

La arquitectura incluye 2 instancias EC2 `t3.micro` en zonas de disponibilidad separadas (`eu-west-1a` y `eu-west-1b`), 3 discos EBS de 1 GB, el par de claves SSH y un Application Load Balancer público con sondeo en `/health`.

Desde tu terminal de **PowerShell** en Windows:

```powershell
cd linux/administrator/trabajo_integrador_zfs/terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

Terraform reportará las IPs públicas y el DNS del balanceador:
- `alb_url`: URL pública del Load Balancer (`http://alb-lab-zfs-...amazonaws.com`)
- `ssh_active`: `ssh -i id_rsa_lab.pem ubuntu@<IP_ACTIVA>`
- `ssh_passive`: `ssh -i id_rsa_lab.pem ubuntu@<IP_PASIVA>`

Abre dos ventanas de terminal: una conectada al **Nodo Activo** y otra al **Nodo Pasivo**.

---

## 📦 Fase 2: Instalación de ZFS y Detección de Discos

Ejecuta en **ambas máquinas** (`vm_active` y `vm_passive`):

```bash
# 1. Instalar utilidades de ZFS en Linux
sudo apt-get update
sudo apt-get install -y zfsutils-linux nginx

# 2. Inspeccionar dispositivos de almacenamiento
lsblk
```

En la máquina activa verás:
* `nvme0n1`: Disco raíz del sistema (10 GB)
* `nvme1n1`: Disco EBS 1 de 1 GB (para crear el pool inicial)
* `nvme2n1`: Disco EBS 2 de 1 GB (para incorporar el espejo en caliente)

En la máquina pasiva verás:
* `nvme0n1`: Disco raíz del sistema (10 GB)
* `nvme1n1`: Disco EBS 1 de 1 GB (para el pool de réplica)

---

## 🗄️ Fase 3: Creación del Zpool y Dataset en el Nodo Activo

En el **Nodo Activo**, creamos un zpool simple utilizando el primer disco EBS de 1 GB (`/dev/nvme1n1`) y habilitamos compresión LZ4 transparente:

```bash
# 1. Crear el pool de almacenamiento 'zpool_web'
sudo zpool create -f zpool_web /dev/nvme1n1

# 2. Verificar el estado del pool
sudo zpool status zpool_web
```

Salida esperada:
```text
  pool: zpool_web
 state: ONLINE
  scan: none requested
config:

	NAME         STATE     READ WRITE CKSUM
	zpool_web    ONLINE       0     0     0
	  nvme1n1    ONLINE       0     0     0
```

### Crear el Dataset del Sitio Web con Compresión LZ4
```bash
# Crear el dataset dedicado para la aplicación web
sudo zfs create zpool_web/site

# Activar compresión ultrarrápida LZ4 (ahorra I/O y espacio sin impacto de CPU)
sudo zfs set compression=lz4 zpool_web/site

# Configurar el punto de montaje directo hacia /var/www/html
sudo zfs set mountpoint=/var/www/html zpool_web/site

# Verificar las propiedades aplicadas
sudo zfs get compression,mountpoint,readonly zpool_web/site
```

---

## 🪞 Fase 4: Incorporación del Segundo Disco en Caliente (Hot Attach Mirror)

> [!NOTE]
> Demostración en vivo: El zpool se creó con un solo disco. Ahora agregamos el segundo disco (`/dev/nvme2n1`) y lo transformamos en un arreglo **Mirror (RAID 1)** en caliente, sin desmontar `/var/www/html` ni reiniciar.

```bash
# Convertir el vdev simple en un espejo de dos discos
# Sintaxis: zpool attach <pool> <disco_existente> <nuevo_disco>
sudo zpool attach -f zpool_web /dev/nvme1n1 /dev/nvme2n1

# Monitorear la sincronización (resilver) en vivo
sudo zpool status zpool_web
```

Salida esperada:
```text
  pool: zpool_web
 state: ONLINE
status: One or more devices is currently being resilvered.
action: Wait for the resilver to complete.
  scan: resilver in progress ...
config:

	NAME           STATE     READ WRITE CKSUM
	zpool_web      ONLINE       0     0     0
	  mirror-0     ONLINE       0     0     0
	    nvme1n1    ONLINE       0     0     0
	    nvme2n1    ONLINE       0     0     0
```

¡El pool ahora es un espejo tolerante a fallas físicas de disco!

---

## 🌐 Fase 5: Configuración de Nginx y Sondas de Salud (/health)

El balanceador de carga consulta permanentemente `http://<IP>/health`:
* Si devuelve **200**, la instancia recibe tráfico.
* Si devuelve **503**, la instancia es considerada *Standby* y no recibe tráfico.

### 1. En el Nodo Activo:
Creamos la página web y el endpoint `/health` respondiendo **200 OK**:

```bash
# Crear la página del sitio web en el dataset ZFS
sudo cat <<'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head><title>Cluster ZFS Alta Disponibilidad</title></head>
<body style="font-family: Arial; background-color: #e8f5e9; text-align: center; padding: 50px;">
  <h1 style="color: #2e7d32;">🟢 NODO ACTIVO EN PRODUCCIÓN</h1>
  <p>Este sitio web reside sobre un <strong>Dataset ZFS con Compresión LZ4</strong> y arreglo Mirror en caliente.</p>
  <p>Timestamp de creación: <span id="ts"></span></p>
  <script>document.getElementById('ts').innerText = new Date().toISOString();</script>
</body>
</html>
EOF

# Configurar el endpoint /health para devolver 200 OK
sudo cat <<'EOF' > /var/www/html/health
OK - Nodo Activo Saludable
EOF

# Reiniciar Nginx
sudo systemctl restart nginx

# Probar localmente
curl -I http://localhost/health
```

### 2. En el Nodo Pasivo:
Configuramos Nginx para responder **503 Service Unavailable** en `/health` para que el Load Balancer lo mantenga en reserva:

```bash
# Configurar Nginx para responder 503 en la sonda de salud
sudo cat <<'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    location /health {
        return 503 "STANDBY - Nodo Pasivo en Espera\n";
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

sudo systemctl restart nginx

# Probar localmente
curl -I http://localhost/health
```

Abre en tu navegador la URL pública del Load Balancer (`http://<ALB_DNS>`). Verás que responde exclusivamente el **Nodo Activo** con fondo verde.

---

## 🔄 Fase 6: Replicación Remota Incremental con `zfs send | ssh zfs receive`

Ahora configuraremos la tubería de replicación remota desde el Nodo Activo hacia el Nodo Pasivo.

### 1. Preparar el Pool en el Nodo Pasivo
En la terminal del **Nodo Pasivo**:
```bash
# Crear el pool de respaldo con su disco EBS de 1 GB
sudo zpool create -f zpool_backup /dev/nvme1n1
sudo zpool status zpool_backup
```

### 2. Configurar Acceso SSH de Root para Replicación
En el **Nodo Activo**, generamos una clave SSH y la autorizamos en el Nodo Pasivo:

```bash
# En NODO ACTIVO:
sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_zfs
sudo cat /root/.ssh/id_zfs.pub
```

Copia la clave pública impresa y en el **Nodo Pasivo** ejecútala como root:
```bash
# En NODO PASIVO:
sudo mkdir -p /root/.ssh
# Pega la clave pública en authorized_keys:
echo "<CONTENIDO_CLAVE_PUB>" | sudo tee -a /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys

# Permitir temporalmente root login en SSH de la red privada si es necesario
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

### 3. Ejecutar la Primera Replicación Completa (Snapshot Base)
En el **Nodo Activo**:
```bash
IP_PRIVADA_PASIVO="<IP_PRIVADA_NODO_PASIVO>"

# 1. Tomar un snapshot atómico inicial
sudo zfs snapshot zpool_web/site@snap_base

# 2. Enviar el snapshot inicial hacia el nodo pasivo
sudo zfs send zpool_web/site@snap_base | \
  ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_zfs root@$IP_PRIVADA_PASIVO zfs receive -F zpool_backup/site

# 3. En el nodo pasivo, asegurar que el dataset se mantenga en solo-lectura:
ssh -i /root/.ssh/id_zfs root@$IP_PRIVADA_PASIVO zfs set readonly=on zpool_backup/site
```

### 4. Demostrar la Replicación Incremental de Cambios (Deltas)
En el **Nodo Activo**, realizamos una modificación en el sitio:
```bash
# Modificar el archivo agregando nuevo contenido
echo "<p>Actualización Crítica de Datos: Registro de Ventas #99482</p>" | sudo tee -a /var/www/html/index.html

# Tomar snapshot incremental
sudo zfs snapshot zpool_web/site@snap_update1

# Enviar ÚNICAMENTE la diferencia entre snap_base y snap_update1 (pocos kilobytes)
sudo zfs send -i zpool_web/site@snap_base zpool_web/site@snap_update1 | \
  ssh -i /root/.ssh/id_zfs root@$IP_PRIVADA_PASIVO zfs receive -F zpool_backup/site
```

En el **Nodo Pasivo**, verifica que el snapshot y los datos llegaron perfectamente:
```bash
sudo zfs list -t snapshot
```

---

## ⚡ Fase 7: Simulación de Desastre y Conmutación por Error (Failover)

Demostraremos qué sucede cuando el Nodo Activo colapsa y cómo el Nodo Pasivo asume el rol primario con cero divergencia de datos.

### 1. Provocar la Caída del Nodo Activo
En la terminal del **Nodo Activo**, apagamos el servicio web y la sonda de salud:
```bash
# Detener Nginx en el nodo primario
sudo systemctl stop nginx
```

### 2. Comprobar que el Load Balancer Detecta la Falla
En la consola de AWS o ejecutando peticiones hacia el balanceador:
```bash
curl -I http://<ALB_DNS>/health
```
El ALB detecta el fallo del health check en ~15-20 segundos.

### 3. Promover el Nodo Pasivo a Nodo Activo
En el **Nodo Pasivo**, ejecutamos el procedimiento de promoción:

```bash
# 1. Quitar el modo solo-lectura del dataset replicado
sudo zfs set readonly=off zpool_backup/site

# 2. Configurar el punto de montaje hacia el directorio web de producción
sudo zfs set mountpoint=/var/www/html zpool_backup/site

# 3. Cambiar el health check a 200 OK para que el Load Balancer le derive tráfico
sudo cat <<'EOF' > /var/www/html/health
OK - Nodo Promovido a Produccion
EOF

# 4. Ajustar Nginx para servir el sitio
sudo cat <<'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

sudo systemctl restart nginx
```

### 4. Verificación de Recuperación
Refresca la URL del Load Balancer en tu navegador (`http://<ALB_DNS>`):
* El sitio web vuelve a responder de forma inmediata.
* **Todos los datos (incluyendo el registro de ventas #99482) están 100% intactos.**
* El tiempo de recuperación (*RTO*) fue inferior a 30 segundos.

---

## 🛡️ Fase 8: Corrupción de Bloques con `dd`, Detección con Scrub y Auto-Curación

En el nuevo nodo en producción (o en el nodo activo con mirror), demostraremos la capacidad legendaria de **Self-Healing** de ZFS.

### 1. Inyectar Basura Directa en un Disco del Espejo con `dd`
```bash
# Escribir 1 MB de ceros aleatorios sobre el segundo disco del mirror
# saltándonos la tabla inicial para dañar bloques de datos reales:
sudo dd if=/dev/urandom of=/dev/nvme2n1 bs=1M count=2 seek=10 conv=notrunc
```

### 2. Ejecutar un Scrub para Detección de Integridad
ZFS analiza todos los checksums del pool y repara automáticamente los bloques corruptos utilizando la copia sana del otro disco:

```bash
# Iniciar el análisis de integridad
sudo zpool scrub zpool_web

# Comprobar el informe de auto-reparación
sudo zpool status zpool_web
```

Salida esperada de auto-curación:
```text
  pool: zpool_web
 state: ONLINE
status: One or more devices has experienced an unrecoverable error.
action: Determine if the device needs to be replaced.
  scan: scrub repaired 2.14M in 00:00:01 with 0 errors
config:

	NAME           STATE     READ WRITE CKSUM
	zpool_web      ONLINE       0     0     0
	  mirror-0     ONLINE       0     0     0
	    nvme1n1    ONLINE       0     0     0
	    nvme2n1    ONLINE       0     0    48  (repaired)
```

¡ZFS detectó 48 bloques corruptos y los reparó en 1 segundo a partir de `nvme1n1`, sin corrupción de datos ni caídas de servicio!

---

## 🧹 Fase 9: Destrucción de la Infraestructura

Al finalizar la práctica, destruye los recursos en AWS para no generar costos:

```powershell
cd linux/administrator/trabajo_integrador_zfs/terraform
terraform destroy -auto-approve
```
