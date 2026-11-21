---
id: lab-3.19-logs-fundamentos-varlog-dmesg-severities
title: 'Fundamentos de Logs en Linux: /var/log, Severities, Facilities, dmesg, Inodos
  Abiertos y logrotate'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos, Logs
  y Monitoreo'
section: '3.19'
sections:
- '3.19'
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
- syslog
- varlog
- dmesg
- logger
- logrotate
- severities
- facilities
- lsof
- forensics
tools:
- logger
- systemd-cat
- journalctl
- dmesg
- logrotate
- lsof
- last
- lastb
- ls
- df
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-logs-ubuntu24:test (Ubuntu 24.04.5 LTS + logrotate
    3.21.0)
  os: Ubuntu 24.04.5 LTS (Container Image)
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_logs_fundamentos.sh --auto 0 aprobada (exit 0) en
    Ubuntu 24.04.5 LTS. Validados /var/log/syslog, wtmp/last, logger/systemd-cat,
    lsof +L1 y logrotate 3.21.0 con su root root.
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-logs-systemd:test (Fedora 41 + systemd 256.17)
  os: Fedora Linux 41 (Container Image)
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_logs_fundamentos.sh --auto 0 aprobada (exit 0). Validados
    /var/log, last, logger/systemd-cat, journalctl -o verbose, lsof +L1 sobre archivo
    (deleted) y logrotate 3.22.0 (rotación y compresión .gz).
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Debian 12
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Compatible con Debian/Ubuntu y RHEL/Fedora detectando rutas de /var/log dinámicamente.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Compatible con instancias EC2 estándar con acceso completo a dmesg del kernel.
environments:
- Podman Systemd Container (Toolbox Host)
- WSL2
- AWS EC2
operating_systems:
- Fedora Linux 41
- Ubuntu 24.04 LTS
- Debian 12
status: PASSED
rag_summary: Laboratorio práctico de nivel inicial-intermedio sobre los fundamentos
  de registros en Linux. Explora la anatomía real del directorio /var/log (diferenciando
  archivos de texto plano de registros binarios como wtmp, btmp y lastlog), la emisión
  y clasificación de eventos por Severity (0 emerg a 7 debug) y Facility (kern, auth,
  local0-local7) calculando el valor <PRI>, la inspección del Kernel Ring Buffer con
  dmesg (-T, --level=err,warn, grep USB/error y dmesg_restrict), la reproducción y
  diagnóstico forense del clásico problema de disco lleno por archivo borrado retenido
  por un proceso vivo mediante lsof +L1, y la configuración y ejecución real de rotación
  y compresión sin pérdida de eventos mediante logrotate (copytruncate y state file).
files:
  guide: logs/logs_fundamentos_varlog_dmesg.md
  script: logs/demo_logs_fundamentos.sh
  terraform: null
prerequisites:
- lab-3.18-logs-arquitecturas-teoria-maestra
- lab-3.12-enlaces-hard-soft-links
next_recommended_labs:
- lab-3.20-journald-journalctl-troubleshooting-forense
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio 3.19: Fundamentos de Logs en Linux (`/var/log`, Severities, `dmesg` y `logrotate`)

> **Dificultad:** Fácil / Introductorio al Módulo (Nivel 3) | **Tiempo estimado:** 30 minutos | **Ambiente:** Linux nativo, WSL2, Contenedor Systemd o AWS EC2

Antes de configurar servidores centrales o conectar agentes de Inteligencia Artificial, todo administrador Linux debe dominar las piezas atómicas del sistema de registros: dónde se guardan los logs en disco, qué significado matemático tiene cada gravedad y origen, cómo leer el buffer del kernel con `dmesg`, cómo evitar el desastre clásico de llenar `/var` borrando un archivo abierto y cómo automatizar su ciclo de vida con `logrotate`.

---

## 🎯 Objetivos del Laboratorio

1. **Inspeccionar `/var/log` con criterio:** Distinguir archivos de texto plano de archivos binarios de auditoría (`wtmp`, `btmp`, `lastlog`) y reconocer equivalencias Debian/Ubuntu vs RHEL/Fedora.
2. **Clasificar eventos con `Severity` y `Facility`:** Calcular `<PRI> = (Facility × 8) + Severity`, emitir logs reales con `logger` y `systemd-cat`, e inspeccionar los metadatos en el diario.
3. **Diagnosticar el Kernel Ring Buffer (`dmesg`):** Aplicar `-T`, `--level=err,warn`, `-w`, filtros `grep -i` (errores de hardware/USB) y entender la política de seguridad `kernel.dmesg_restrict`.
4. **Resolver un incidente clásico del día a día:** Reproducir un disco "fantasma" tras ejecutar `rm` sobre un log activo, localizar el descriptor abierto con `lsof +L1` / `/proc/<PID>/fd` y liberarlo correctamente.
5. **Configurar rotación profesional con `logrotate`:** Probar un archivo de configuración aislado (`--debug` y ejecución forzada con archivo de estado propio), validando `copytruncate`, compresión y retención.

---

## ⚡ 1. Cheat Sheet Operativa

| Tarea | Comando / Ruta | Qué Obtenemos |
| :--- | :--- | :--- |
| **Explorar `/var/log`** | `ls -lh /var/log/` | Tamaños, permisos y archivos activos/rotados (`.1`, `.gz`). |
| **Leer sesiones exitosas / fallidas** | `last -n 10` / `sudo lastb -n 10` | Decodifica los binarios `/var/log/wtmp` y `/var/log/btmp`. |
| **Emitir evento Syslog** | `logger -p local0.err -t mi_app "Fallo test"` | Envía un mensaje clasificado al socket syslog/journald. |
| **Ver kernel con hora humana** | `sudo dmesg -T \| tail -n 20` | Convierte segundos desde boot a fecha/hora legible. |
| **Filtrar errores críticos del kernel** | `sudo dmesg --level=err,warn` | Aísla alertas y errores de hardware, drivers u OOM. |
| **Hallar logs borrados aún retenidos** | `sudo lsof +L1` | Lista procesos que mantienen abierto un archivo borrado (`(deleted)`). |
| **Probar rotación sin tocar nada** | `sudo logrotate -d /etc/logrotate.d/mi_app` | Simulación (*dry-run*) paso a paso de `logrotate`. |

---

## 🧪 2. Desarrollo Paso a Paso (Manual o con Script Interactivo)

> [!TIP]
> **Preparación en Ubuntu 24.04 LTS / Debian:**
> ```bash
> sudo apt update && sudo apt install -y rsyslog logrotate lsof util-linux python3
> ```

Podés ejecutar todo el laboratorio de forma guiada e interactiva con:

```bash
cd linux/administrator/logs
sudo ./demo_logs_fundamentos.sh
# O en modo automático para pruebas rápidas:
sudo ./demo_logs_fundamentos.sh --auto 2
```

### Paso 1: Radiografía de `/var/log` y Binarios de Sesión
Inspeccioná qué archivos existen realmente en tu distribución:

```bash
ls -lht /var/log | head -n 20
file /var/log/wtmp /var/log/btmp /var/log/lastlog 2>/dev/null || true
last -n 5
```

Observá que `wtmp`, `btmp` y `lastlog` aparecen como `data` (binarios), nunca texto plano. Si intentás hacer `cat /var/log/wtmp`, corromperás tu terminal; siempre se leen con `last`, `lastb` y `lastlog`.

### Paso 2: Severities, Facilities y Cálculo de `<PRI>` en Vivo
Generá eventos con distintas severidades y facilities usando `logger` y `systemd-cat`:

```bash
logger -p local0.info    -t lab-app "Inicio normal del modulo de pagos"
logger -p local0.warning -t lab-app "Latencia de respuesta superando 800ms"
logger -p local0.err     -t lab-app "Error conectando al pool de base de datos"
logger -p auth.notice    -t lab-sec "Cambio de configuracion autorizado"
echo "Fallo critico simulado por stdout" | systemd-cat -t lab-app -p crit
```

Ahora inspeccioná los campos exactos que el sistema guardó (`PRIORITY` y `SYSLOG_FACILITY`):

```bash
journalctl -t lab-app -t lab-sec -n 5 -o verbose --no-pager | grep -E "MESSAGE=|PRIORITY=|SYSLOG_FACILITY=|SYSLOG_IDENTIFIER="
```

*Verificación mental:* `local0` es facility `16` y `err` es severidad `3` $\rightarrow \text{PRI} = (16 \times 8) + 3 = \mathbf{131}$.

### Paso 3: Kernel Ring Buffer con `dmesg`
Comprobá si el kernel restringe la lectura a usuarios sin privilegios y consultá mensajes recientes con marcas de tiempo legibles:

```bash
cat /proc/sys/kernel/dmesg_restrict
sudo dmesg -T | tail -n 15
sudo dmesg --level=err,warn | tail -n 15
```

*(Nota: En contenedores sin capacidad `CAP_SYSLOG`, `dmesg` puede devolver `Operation not permitted`; en ese caso `journalctl -k` cumple el rol de consulta si el journal recibe eventos del kernel, o bien se practica el filtrado sobre un volcado de ejemplo).*

Ejemplo clásico de depuración de hardware USB visto en producción:
```bash
sudo dmesg -T | grep -i "usb" | grep -iE "error|warn|reset|disconnect" | tail -n 10
```

### Paso 4: El Drama Real — "Borré el Log con `rm` y el Disco Sigue Lleno"
Reproducí en un directorio temporal seguro qué ocurre cuando un administrador borra un log activo con `rm`:

```bash
mkdir -p /tmp/lab_demo_logs_fund
python3 -c '
import time
with open("/tmp/lab_demo_logs_fund/app_activa.log", "w", buffering=1) as f:
    for i in range(120):
        f.write(f"linea={i} " + "X"*4096 + "\n")
        time.sleep(0.25)
' &
APP_PID=$!
sleep 2
ls -lh /tmp/lab_demo_logs_fund/app_activa.log
rm -f /tmp/lab_demo_logs_fund/app_activa.log
```

Comprobá que el archivo **desapareció** de `ls`, pero el proceso `$APP_PID` **sigue escribiendo en el inodo abierto**:

```bash
ls -la /tmp/lab_demo_logs_fund/
lsof +L1 /tmp/lab_demo_logs_fund/ 2>/dev/null || ls -l /proc/$APP_PID/fd
```

**Solución correcta en producción (sin matar el servicio ni perder servicio):**
En lugar de `rm`, truncar en caliente (`: > /var/log/app.log`) o liberar el descriptor tras verificar con `lsof`, y delegar el ciclo de vida en `logrotate`.

### Paso 5: Rotación Real con `logrotate`
Creá una regla aislada de `logrotate` con compresión diferida (`delaycompress`) y `copytruncate`:

```bash
cat <<'EOF' > /tmp/lab_demo_logs_fund/logrotate.conf
/tmp/lab_demo_logs_fund/servicio.log {
    su root root
    size 1k
    rotate 3
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

Generá contenido suficiente (>2 KB), simulá con `-d` y ejecutá rotaciones reales usando un archivo de estado aislado (`-s`):

```bash
for i in $(seq 1 40); do echo "2026-11-21T10:00:00Z INFO transaccion_ok id=$i payload=demo_rotacion"; done > /tmp/lab_demo_logs_fund/servicio.log
logrotate -d -s /tmp/lab_demo_logs_fund/state /tmp/lab_demo_logs_fund/logrotate.conf
logrotate -f -s /tmp/lab_demo_logs_fund/state /tmp/lab_demo_logs_fund/logrotate.conf
# Segunda ronda para observar la compresión .gz tras delaycompress:
for i in $(seq 41 80); do echo "2026-11-21T10:01:00Z INFO transaccion_ok id=$i payload=demo_rotacion"; done >> /tmp/lab_demo_logs_fund/servicio.log
logrotate -f -s /tmp/lab_demo_logs_fund/state /tmp/lab_demo_logs_fund/logrotate.conf
ls -lh /tmp/lab_demo_logs_fund/servicio.log*
```

---

## 🧹 3. Limpieza del Entorno

Si corriste los comandos manualmente o usaste `--keep`, limpiá todo con:

```bash
sudo ./limpiar_logs_fundamentos.sh
```
