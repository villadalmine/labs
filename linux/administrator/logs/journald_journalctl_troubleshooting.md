---
id: lab-3.20-journald-journalctl-troubleshooting-forense
title: 'Journald y Troubleshooting Forense con journalctl: Configuración, Servicios
  Fallidos (Apache) y Auditoría de Logins (SSH/Logind)'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos, Logs
  y Monitoreo'
section: '3.20'
sections:
- '3.20'
- '3'
category: observability
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- observability
- logs
- journald
- journalctl
- systemd
- troubleshooting
- apache
- sshd
- forensics
- json
- jq
tools:
- journalctl
- systemctl
- systemd-analyze
- ss
- httpd
- sshd
- ssh
- jq
- curl
- grep
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-logs-ubuntu24:test (Ubuntu 24.04.5 LTS + apache2 2.4.58
    + OpenSSH 9.6p1)
  os: Ubuntu 24.04.5 LTS (Container Image)
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_journald_troubleshooting.sh --auto 0 aprobada (exit
    0) en Ubuntu 24.04.5 LTS. Validados apache2 2.4.58 (fallo puerto 18080 + recuperación
    HTTP/1.1 200 OK), sshd (/run/sshd) con logins Accepted/Failed y reporte SOC jq.
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-logs-systemd:test (Fedora 41 + systemd 256.17 + httpd
    2.4.65 + OpenSSH 9.9p1)
  os: Fedora Linux 41 (Container Image)
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_journald_troubleshooting.sh --auto 0 aprobada (exit
    0). Validados drop-in journald.conf.d, fallo real de httpd por puerto 18080 ocupado
    + recuperación, logins SSH exitosos y fuerza bruta + reporte SOC con jq.
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Debian 12
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Requiere systemd activo en WSL2 (/etc/wsl.conf con systemd=true).
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Compatible 100% con instancias EC2 con systemd-journald.
environments:
- Podman Systemd Container (Toolbox Host)
- WSL2
- AWS EC2
operating_systems:
- Fedora Linux 41
- Ubuntu 24.04 LTS
- Debian 12
status: PASSED
rag_summary: 'Laboratorio práctico intermedio centrado en systemd-journald y troubleshooting
  forense con journalctl. Cubre la configuración declarativa en /etc/systemd/journald.conf
  y drop-ins /etc/systemd/journald.conf.d/*.conf (Storage, Compress, SystemMaxUse,
  RuntimeMaxUse), validación con systemd-analyze cat-config y mantenimiento (--disk-usage,
  --list-boots). Reproduce de forma real y segura dos incidentes productivos completos:
  (1) fallo real de arranque de Apache/HTTP por puerto ocupado (Address already in
  use / AH00072 make_sock), diagnóstico con systemctl status y journalctl -xeu, identificación
  del proceso intruso con ss -tulpn y recuperación en caliente; y (2) auditoría forense
  de accesos SSH exitosos y fuerza bruta fallida contra un demonio sshd dedicado en
  systemd, correlación con systemd-logind y exportación estructurada en formato JSON
  (-o json) analizada con jq para generar un reporte SOC automatizado.'
files:
  guide: logs/journald_journalctl_troubleshooting.md
  script: logs/demo_journald_troubleshooting.sh
  terraform: null
prerequisites:
- lab-3.19-logs-fundamentos-varlog-dmesg-severities
next_recommended_labs:
- lab-3.21-rsyslog-filtrado-plantillas-tls-colas
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio 3.20: `systemd-journald` y Troubleshooting Forense con `journalctl`

> **Dificultad:** Intermedio (Nivel 3) | **Tiempo estimado:** 40 minutos | **Ambiente:** Linux o Contenedor con `systemd` activo

En distribuciones Linux modernas, cuando un servicio falla al arrancar o un atacante intenta ingresar por SSH, **`systemd-journald` es la primera fuente de verdad**. A diferencia de los archivos de texto plano, el diario binario indexado permite cruzar en milisegundos servicio (`-u`), arranque (`-b`), identificador de proceso (`_PID`), rango horario (`--since`/`--until`), severidad (`-p`) y formato estructurado (`-o json`).

En este laboratorio pasarás de consultar filtros básicos a **reproducir y resolver dos incidentes reales del día a día de un administrador**: un servidor web Apache bloqueado por conflicto de puertos y una auditoría forense de sesiones SSH exitosas y ataques de fuerza bruta.

---

## 🎯 Objetivos del Laboratorio

1. **Configurar `systemd-journald` de forma segura:** Usar drop-ins en `/etc/systemd/journald.conf.d/*.conf` sin modificar el archivo principal y validar con `systemd-analyze cat-config`.
2. **Dominar filtros de `journalctl`:** Combinar `-n`, `-b`, `-u`, `_PID=`, `--since/--until`, `-p` y `-o json | jq`.
3. **Resolver un incidente de servicio caído (Caso Apache / Puerto Ocupado):** Diagnosticar `Job for ... failed` mediante `systemctl status` y `journalctl -xeu`, encontrar el proceso usurpador con `ss -tulpn`, liberarlo y levantar el servicio.
4. **Realizar auditoría forense de accesos (Caso SSH & `systemd-logind`):** Rastrear eventos `Accepted` y `Failed`/`Invalid` en `sshd` y sesiones `New session`/`Removed session`, produciendo un resumen cuantitativo en JSON.

---

## ⚡ 1. Cheat Sheet de `journalctl`

| Necesidad | Comando | Notas Clave |
| :--- | :--- | :--- |
| **Configuración efectiva** | `systemd-analyze cat-config systemd/journald.conf` | Muestra la fusión real de `journald.conf` + `journald.conf.d/*.conf`. |
| **Uso en disco y arranques** | `journalctl --disk-usage` <br> `journalctl --list-boots` | Verifica cuotas (`SystemMaxUse`) y cuántos boots están guardados. |
| **Últimas N entradas de servicio** | `journalctl -xeu apache2.service -n 30` | `-x` añade explicaciones del catálogo; `-e` salta al final; `-u` filtra unidad. |
| **Por PID exacto** | `journalctl _PID=460` | Campo confiable capturado por el kernel. |
| **Rango temporal dinámico** | `journalctl --since "-15 min" --until "now"` | Acepta `today`, `yesterday` o formato `YYYY-MM-DD HH:MM:SS`. |
| **Por rango de prioridad** | `journalctl -p emerg..warning` | Equivalente a `-p 0..4`. Evitá encadenar varios `-p` sueltos. |
| **Exportar JSON estructurado** | `journalctl -u sshd -n 10 -o json \| jq .` | Ideal para automatización, scripts y backups (`\| tee journal.json`). |

---

## 🧪 2. Desarrollo Paso a Paso

> [!TIP]
> **Preparación en Ubuntu 24.04 LTS / Debian:**
> ```bash
> sudo apt update && sudo apt install -y apache2 openssh-server openssh-client iproute2 curl jq python3
> ```

Podés ejecutar todo el laboratorio interactivamente o en modo automático:

```bash
cd linux/administrator/logs
sudo ./demo_journald_troubleshooting.sh
# Modo automático:
sudo ./demo_journald_troubleshooting.sh --auto 2
```

### Paso 1: Configuración de `journald` con Drop-in Modular
En lugar de editar `/etc/systemd/journald.conf` directamente, creá un archivo de prioridad en `/etc/systemd/journald.conf.d/99-lab-demo.conf`:

```ini
[Journal]
Storage=auto
Compress=yes
SystemMaxUse=500M
RuntimeMaxUse=100M
```

Recargá el servicio y verificá la configuración efectiva:
```bash
sudo systemctl restart systemd-journald
systemd-analyze cat-config systemd/journald.conf | grep -v '^#' | grep -v '^$'
journalctl --disk-usage
```

> [!NOTE]
> Cuando `Storage=auto`, `journald` guarda en `/run/log/journal/<machine-id>/` (volátil en RAM) salvo que exista el directorio `/var/log/journal/`. Con `Storage=persistent`, `systemd-journald` crea `/var/log/journal/` automáticamente y conserva logs tras reinicios.

### Paso 2: Filtros Profesionales de `journalctl`
```bash
# 1. Últimos 10 eventos del sistema
journalctl -n 10 --no-pager

# 2. Solo mensajes del arranque actual
journalctl -b -n 10 --no-pager

# 3. Solo errores y críticos en los últimos 30 minutos
journalctl --since "-30 min" -p emerg..err -n 10 --no-pager

# 4. Salida estructurada JSON para inspección de campos confiables (_PID, _SYSTEMD_UNIT, _BOOT_ID)
journalctl -n 2 -o json-pretty --no-pager
```

*(Recordá: los usuarios no root deben pertenecer al grupo `adm` o `systemd-journal` para ver mensajes de otros usuarios y del sistema; sin esos grupos `journalctl` muestra un aviso `Hint:` y limita la vista).*

### Paso 3: Incidente Real 1 — Servicio Web Falla al Iniciar (`Address already in use`)
Cuando ejecutás `systemctl start apache2` (o `httpd`) y aparece:

```text
Job for lab-web-prod.service failed because the control process exited with error code.
See "systemctl status lab-web-prod.service" and "journalctl -xeu lab-web-prod.service" for details.
```

Tu secuencia determinista de troubleshooting debe ser siempre:
1. **`systemctl status lab-web-prod.service --no-pager`** → Confirma el `ExecStart`, `code=exited, status=1/FAILURE` y las últimas líneas.
2. **`journalctl -xeu lab-web-prod.service -n 25 --no-pager`** → Revela la causa raíz exacta:
   `(98)Address already in use: AH00072: make_sock: could not bind to address 0.0.0.0:18080`.
3. **Identificar al proceso culpable con el kernel:**
   ```bash
   sudo ss -tulpn | grep :18080
   ```
4. **Matar o reconfigurar el proceso intruso**, volver a arrancar `sudo systemctl start lab-web-prod.service` y verificar `curl --noproxy '*' -sI http://127.0.0.1:18080`.

### Paso 4: Incidente Real 2 — Auditoría Forense de Logins SSH y Sesiones
Para investigar intentos de intrusión o confirmar quién accedió al servidor:

```bash
# 1. Buscar autenticaciones SSH exitosas y fallidas
journalctl -u lab-sshd-audit.service --no-pager | grep -E "Accepted|Failed|Invalid"

# 2. Correlacionar apertura y cierre de sesiones locales/consola en systemd-logind
journalctl -u systemd-logind.service -n 15 --no-pager | grep -E "New session|Removed session"
```

### Paso 5: De `grep` a Reporte Forense SOC con JSON + `jq`
En lugar de leer cientos de líneas manualmente, extraé los eventos en JSON y resumilos por IP o tipo de fallo:

```bash
journalctl -u lab-sshd-audit.service -o json --no-pager \
  | jq -r 'select(.MESSAGE | test("Accepted|Failed|Invalid")) | "\(.SYSLOG_TIMESTAMP // .__REALTIME_TIMESTAMP) | \(.MESSAGE)"'
```

---

## 🧹 3. Limpieza del Entorno

Si dejaste el escenario vivo con `--keep`, eliminá las unidades temporales de `systemd`, el drop-in de `journald.conf.d` y los archivos temporales ejecutando:

```bash
sudo ./limpiar_journald_troubleshooting.sh
```
