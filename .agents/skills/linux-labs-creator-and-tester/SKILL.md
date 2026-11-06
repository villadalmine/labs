---
name: linux-labs-creator-and-tester
description: >-
  Crea, documenta, prueba de extremo a extremo y mantiene laboratorios prácticos,
  guías teóricas (.md), scripts interactivos de clase (demo_*.sh) e infraestructuras
  efímeras en la nube o contenedores (AWS EC2 / Terraform / Docker / procesos aislados).
  Úsese siempre que el usuario pida crear un nuevo laboratorio, agregar un tema o guía
  al repositorio de labs, actualizar tablas comparativas, validar metadatos determinísticos
  (catalog.json / metadata.schema.json) o ejecutar pruebas E2E asegurando la destrucción
  total de las VMs, instancias AWS y contenedores creados al finalizar.
---

# Linux Labs Creator, Tester & Ephemeral Infra Lifecycle Skill

Este skill codifica la metodología estándar, las lecciones aprendidas de infraestructura real y las reglas innegociables para **diseñar, construir, probar de punta a punta y limpiar laboratorios** dentro del repositorio `labs` (`linux/administrator/`).

---

## 1. Reglas de Oro Innegociables (Always Enforce)

1. **Destrucción Obligatoria de Infraestructura Efímera (Zero Leftovers):**
   - **TODA** máquina virtual (AWS EC2, VPC, EBS, EIP, ALB), contenedor Docker o demonio local (`sshd`, `http.server`, loop devices `/dev/loopX`, montajes FUSE/LVM/LUKS) levantado para probar un laboratorio **DEBE SER DESTRUIDO** antes de dar por cerrada la tarea o apenas el usuario confirme que terminó de ver la demostración en vivo.
   - En scripts Bash (`demo_*.sh`), es obligatorio incluir `trap cleanup EXIT INT TERM` limpiando procesos por PID, desmontando volúmenes y borrando directorios `/tmp/demo_*`.
   - En laboratorios Cloud (Terraform), siempre verificar con `terraform destroy -auto-approve` seguido de una auditoría real en la API de AWS (`aws ec2 describe-instances` + `aws ec2 describe-volumes` + `aws ec2 describe-addresses`) comprobando **`0` recursos activos** para evitar cargos en la cuenta.

2. **Metadatos Determinísticos 100% Validados (`metadata.schema.json` + `catalog.json`):**
   - Todo archivo `.md` de laboratorio debe iniciar con un bloque **YAML Frontmatter** que cumpla estrictamente con [`linux/administrator/metadata.schema.json`](../../../linux/administrator/metadata.schema.json).
   - **Cuidado con el campo `section`:** El esquema exige el patrón `^[0-9]+(\.[0-9]+)?$` (ejemplo: `'3.3'`, `'3.17'`, `'2.4'`). **Nunca** pongas letras en el atributo YAML `section` (como `'3.3c'`); las letras como `3.3a`, `3.3b`, `3.3c` se usan únicamente como etiquetas visuales en las tablas de [`linux/administrator/README.md`](../../../linux/administrator/README.md).
   - **Cuidado con `difficulty_level`:** Debe ser un entero (`0`, `1`, `2`, `3` o `4`), nunca un string como `"intermediate"`.
   - Siempre sincronizar y validar después de cualquier cambio ejecutando:
     ```bash
     python3 linux/administrator/manage_catalog.py populate
     python3 linux/administrator/manage_catalog.py validate
     ```

3. **Scripts Interactivos de Clase (`demo_*.sh`) Dual-Mode:**
   - Todos los scripts deben poder correrse tanto en vivo durante la clase (con pausas `[ENTER]` y preguntas socráticas `pie_clase`) como en modo desatendido de prueba rápida (`./demo_xxx.sh --auto 0` o `./demo_xxx.sh --auto 2`).
   - **Atención a `--auto 0`:** Al implementar el parser de argumentos en Bash, usar una bandera booleana `AUTO_MODE=true` cuando `$1 == "--auto"`, de modo que `./demo_xxx.sh --auto 0` nunca quede bloqueado en `read -r` esperando entrada de teclado.

---

## 2. Plantilla Determinística de Metadatos (YAML Frontmatter)

Cada nuevo laboratorio o guía en `linux/administrator/<modulo>/<nombre>.md` debe registrar exactamente qué herramientas, sistemas operativos y entornos reales o virtualizados se utilizaron para construirlo y probarlo:

```yaml
---
id: lab-3.3-ejemplo-identificador-unico
title: 'Título Descriptivo del Laboratorio y Tecnologías Cubiertas'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.3'
sections:
- '3.3'
- '3'
category: security # Enum: fundamentals | processes | systemd | storage | security | observability | cloud-iac | reference
resource_type: interactive_lab # Enum: interactive_lab | theoretical_guide | cheatsheet | cloud_project
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive # Enum: cli_interactive | manual_commands | terraform_apply | reading_only
tags:
- security
- tag-tecnologia-1
- tag-tecnologia-2
tools:
- comando1
- comando2
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-11-06'
  notes: Descripción exacta de los escenarios probados con el script interactivo.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-06'
  notes: Validación en instancias cloud o contenedores equivalentes.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
- Debian 12
status: PASSED
rag_summary: 'Resumen técnico de alta densidad semántica (80-150 palabras) detallando la arquitectura, comandos, casos de uso, modos de falla y remediación para indexación en el motor RAG y el servidor MCP del tutor.'
files:
  guide: cifrado/nombre_guia.md
  script: cifrado/demo_nombre.sh
  terraform: null
prerequisites:
- lab-3.3.0-cifrado-arquitecturas-comparativa
next_recommended_labs:
- lab-3.3-cifrado-luks
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---
```

---

## 3. Aprendizajes de Infraestructura (Lecciones Aprendidas en Pruebas Reales)

Al construir y probar laboratorios en distintos entornos (Host local, Sandbox restringido, WSL2, Contenedores Docker y AWS EC2 con Terraform), aplicá siempre estas soluciones probadas:

### A. Laboratorios de Demonios Locales y SSH (`sshd`, Puertos Altos y Túneles)
- **Aislamiento Total sin `root`:** Podés levantar un servidor `/usr/sbin/sshd` (o `/usr/bin/sshd`) real sin privilegios de superusuario pasándole `-f /tmp/demo_ssh_XXX/server/sshd_config` en un puerto alto (`Port 22222`), con sus propias Host Keys (`ssh-keygen -t ed25519 -f .../ssh_host_ed25519_key`), `UsePAM no` y `StrictModes no` (porque `/tmp` pertenece a `root` y no al usuario actual).
- **Evitar conflictos con configuraciones del Host (`/etc/ssh/ssh_config.d/`):** Al invocar el cliente `ssh` dentro de un script de prueba, pasá siempre `-F /dev/null` e `-o IdentitiesOnly=yes` para evitar que archivos del sistema con permisos especiales (como `20-systemd-ssh-proxy.conf`) o agentes externos interfieran con la demostración.
- **Proxies HTTP en el entorno:** Al probar túneles locales (`ssh -L`) o microservicios en `127.0.0.1` con `curl`, incluí siempre `--noproxy '*'` (`curl --noproxy '*' -s http://127.0.0.1:PORT/...`) para evitar que un proxy del entorno intercepte las llamadas a loopback.

### B. Laboratorios de Almacenamiento, LVM, RAID, LUKS y Filesystems
- **Modo Dual (Loopback en Local / EBS en AWS):** Los scripts de discos (`demo_luks.sh`, `demo_raid_*.sh`, `demo_lab_storage.sh`) deben crear imágenes dispersas (`truncate -s 256M`) asociadas con `losetup -fP` cuando corren localmente, y aceptar dispositivos reales (`/dev/nvme1n1`, `/dev/xvdf`) cuando corren en una VM EC2.
- **Orden estricto de desmontaje en `cleanup()`:**
  1. `umount -lf <mountpoint>`
  2. `cryptsetup close <mapper_name>` (si hay LUKS)
  3. `vgchange -an <vg_name>` (si hay LVM)
  4. `mdadm --stop /dev/mdX` (si hay RAID mdadm)
  5. `losetup -d /dev/loopX` y `rm -rf /tmp/demo_*`

### C. Laboratorios Multi-Nodo en AWS EC2 con Terraform (Observabilidad, HA, RAID, ZFS)
- **Orden de Arranque e Internet (`NAT` / `Elastic IP`):** Si una instancia EC2 se crea con `associate_public_ip_address = false` y se le adjunta un `aws_eip_association` separado, su script `user_data` (`cloud-init`) puede arrancar **antes** de que la Elastic IP esté adjunta, haciendo que `apt-get update` falle por falta de salida a Internet.
  - **Solución:** Definir `associate_public_ip_address = true` en el recurso `aws_instance` o incluir un bucle de espera de red al inicio del `user_data` (`until ping -c1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done`).
- **Dispositivos NVMe en instancias Nitro (`t3.micro`):** Los volúmenes EBS adjuntos como `/dev/sdf` y `/dev/sdg` aparecen en el kernel como `/dev/nvme1n1`, `/dev/nvme2n1`, etc. En scripts automatizados, detectá dinámicamente los discos secundarios libres excluyendo el disco raíz (`lsblk -dpno NAME | grep -v "$(findmnt -n -o SOURCE / | sed 's/p\?[0-9]\+$//')"`).
- **Verificación de `cloud-init` antes de correr el Caos:** Después de `terraform apply`, esperá siempre a que los nodos terminen su aprovisionamiento (`ssh ... "cloud-init status --wait"`) y verificá que todos los endpoints HTTP/Prometheus respondan `200 OK` antes de inyectar fallas (`dd`, `mdadm --fail`, `cryptsetup close`).

---

## 4. Flujo de Trabajo Paso a Paso para Crear y Probar un Nuevo Lab

Cada vez que el usuario pida agregar un laboratorio, guía o demostración:

### Paso 1: Diseño e Integración en las Tablas Comparativas
1. Creá la guía paso a paso en `linux/administrator/<modulo>/<nombre_lab>.md` con el bloque YAML Frontmatter completo.
2. Si el tema pertenece a una familia con guía comparativa (por ejemplo:
   - Cifrado: [`cifrado/cifrado_arquitecturas_comparativa.md`](../../../linux/administrator/cifrado/cifrado_arquitecturas_comparativa.md) y [`cifrado/fundamentos_criptografia_llaves_certificados.md`](../../../linux/administrator/cifrado/fundamentos_criptografia_llaves_certificados.md)
   - Automatización: [`automatizacion/automatizacion_arquitecturas_comparativa.md`](../../../linux/administrator/automatizacion/automatizacion_arquitecturas_comparativa.md)
   - Backups: [`backup/backup_arquitecturas_comparativa.md`](../../../linux/administrator/backup/backup_arquitecturas_comparativa.md)
   - Monitoreo: [`monitoreo/monitoreo_arquitecturas_comparativa.md`](../../../linux/administrator/monitoreo/monitoreo_arquitecturas_comparativa.md)
   - RAID: [`raid/raid_teoria.md`](../../../linux/administrator/raid/raid_teoria.md)),
   **actualizá la tabla comparativa maestra** para que la nueva tecnología figure comparada lado a lado con todas las demás.

### Paso 2: Creación y Prueba del Script Interactivo (`demo_*.sh`)
1. Escribí el script en `linux/administrator/<modulo>/demo_<nombre>.sh` y dale permisos de ejecución (`chmod +x`).
2. Probá el script de extremo a extremo en modo automático:
   ```bash
   ./linux/administrator/<modulo>/demo_<nombre>.sh --auto 0
   ```
3. Confirmá que el código de salida sea `0`, que todos los pasos muestren salidas reales y que el bloque `cleanup` elimine todos los procesos y archivos temporales.

### Paso 3: Prueba y Destrucción de Infraestructura Cloud / Contenedores (Si aplica)
1. Si el laboratorio involucra Terraform (AWS) o Docker:
   - Desplegá la infraestructura (`terraform init && terraform apply -auto-approve` o `docker compose up -d`).
   - Ejecutá la prueba de extremo a extremo (estado saludable ➔ inyección de fallo / caos ➔ disparo de alertas ➔ autorreparación en caliente ➔ estado `resolved`).
   - **DESTRUÍ TODA LA INFRAESTRUCTURA** inmediatamente después de validar (o tras mostrarla al usuario si pidió verla en vivo):
     ```bash
     terraform destroy -auto-approve
     ```
   - Verificá que no queden instancias, volúmenes ni contenedores huérfanos (`docker ps -a`, `aws ec2 describe-instances`).

### Paso 4: Sincronización de Metadatos, Índices y Glosario
1. Agregá los prerequisitos correspondientes en [`linux/administrator/manage_catalog.py`](../../../linux/administrator/manage_catalog.py) si aplica.
2. Ejecutá el motor del catálogo:
   ```bash
   python3 linux/administrator/manage_catalog.py populate
   python3 linux/administrator/manage_catalog.py validate
   ```
3. Actualizá el árbol de carrera y la tabla de la sección correspondiente en [`linux/administrator/README.md`](../../../linux/administrator/README.md), el contador e índice en [`README.md`](../../../README.md) raíz, y las definiciones técnicas nuevas en [`linux/administrator/GLOSARIO.md`](../../../linux/administrator/GLOSARIO.md).
