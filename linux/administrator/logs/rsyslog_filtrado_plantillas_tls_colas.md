---
id: lab-3.21-rsyslog-filtrado-plantillas-tls-colas
title: 'Rsyslog Avanzado: RainerScript, Filtrado, Plantillas JSON, Transporte Seguro
  TLS (x509) y Disk-Assisted Queues'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos, Logs
  y Monitoreo'
section: '3.21'
sections:
- '3.21'
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
- rsyslog
- rainerscript
- tls
- x509
- pki
- imfile
- omfwd
- queues
- json
tools:
- rsyslogd
- logger
- openssl
- jq
- grep
- tail
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-logs-ubuntu24:test (Ubuntu 24.04.5 LTS + rsyslog 8.2312.0-3ubuntu9.4
    + rsyslog-gnutls)
  os: Ubuntu 24.04.5 LTS (Container Image)
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_rsyslog_pipelines.sh --auto 0 aprobada (exit 0) en
    Ubuntu 24.04.5 LTS usando rutas compatibles con AppArmor (/var/spool/rsyslog/
    y /var/log/). Validados gtls TLSv1.3 x509/name y recuperación 5/5 vía Disk-Assisted
    Queue.
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-logs-systemd:test (Fedora 41 + rsyslog 8.2312.0 + rsyslog-gnutls)
  os: Fedora Linux 41 (Container Image)
  kernel: 7.2.11-200.fc44.x86_64
  status: PASSED
  test_date: '2026-11-21'
  notes: Ejecución E2E con demo_rsyslog_pipelines.sh --auto 0 aprobada (exit 0). Validados
    rsyslogd -N1, descarte debug, plantillas MiFormato y JSON, mTLS TLSv1.3 x509/name
    (gtls) y recuperación 5/5 de eventos tras caída del colector mediante Disk-Assisted
    Queue.
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Debian 12
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Requiere paquetes rsyslog y rsyslog-gnutls (o rsyslog-openssl).
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-21'
  notes: Arquitectura validada para colector central TLS en puerto 6514 con colas
    en disco en nodos emisores.
environments:
- Podman Systemd Container (Toolbox Host)
- WSL2
- AWS EC2
operating_systems:
- Fedora Linux 41
- Ubuntu 24.04 LTS
- Debian 12
status: PASSED
rag_summary: Laboratorio práctico avanzado sobre rsyslogd en arquitectura cliente-servidor.
  Traduce la configuración clásica de /etc/rsyslog.conf (imudp, plantillas personalizadas,
  descarte de debug, filtrado por $programname y seguridad SSL/TLS) a RainerScript
  moderno. Construye e inicia dos instancias reales aisladas de rsyslogd (servidor
  receptor y cliente emisor) respaldadas por una PKI efímera de OpenSSL con certificados
  X.509 SAN y autenticación mutua x509/name sobre TLS. Configura módulos imudp, imtcp,
  imfile y omfwd, plantillas de texto (MiFormato) y JSON estructurado, y ejecuta una
  prueba de resiliencia productiva (Disk-Assisted Queues) deteniendo el servidor colector
  mientras la aplicación escribe eventos críticos para demostrar almacenamiento temporal
  en spool y drenaje con cero pérdida al reconectar.
files:
  guide: logs/rsyslog_filtrado_plantillas_tls_colas.md
  script: logs/demo_rsyslog_pipelines.sh
  terraform: null
prerequisites:
- lab-3.20-journald-journalctl-troubleshooting-forense
- lab-3.3-fundamentos-criptografia-llaves
next_recommended_labs:
- lab-3.22-logging-centralizado-estructurado-ai-sre
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio 3.21: `rsyslog` Avanzado — Filtrado, Plantillas, Cifrado TLS (`x509`) y Colas en Disco

> **Dificultad:** Avanzado (Nivel 3) | **Tiempo estimado:** 45 minutos | **Ambiente:** Linux / Contenedor / WSL2 con `rsyslog` y `rsyslog-gnutls`

Cuando pasás de un servidor aislado a una red distribuida, `journald` local ya no basta: necesitás **enrutar, transformar, cifrar y garantizar la entrega** de logs hacia colectores centrales o plataformas como Elasticsearch, Loki o Kafka. Ese es el dominio de **`rsyslog`**.

En este laboratorio levantaremos **dos demonios `rsyslogd` reales y aislados** (un servidor receptor y un cliente emisor) comunicándose en vivo: primero por UDP con filtrado y plantillas, luego por **TCP cifrado con TLS mutuo (`x509/name`)**, y finalmente rompiendo el servidor a propósito para comprobar cómo las **Disk-Assisted Queues** evitan perder un solo evento.

---

## 🎯 Objetivos del Laboratorio

1. **Validar sintaxis antes de reiniciar:** Dominar `rsyslogd -N1 -f <archivo.conf>` para evitar tirar el logging de producción por un error tipográfico.
2. **Aplicar RainerScript moderno:** Reemplazar reglas legacy (`$ModLoad`, `~`, `@`) por bloques modulares `module()`, `input()`, `template()`, `if/then { stop }` y `action()`.
3. **Filtrar ruido y formatear en JSON:** Descartar `*.debug`, generar un formato clásico (`MiFormato`) y producir JSON válido simultáneamente.
4. **Cifrar el transporte con mTLS (`gtls` / `ossl`):** Generar una CA y certificados X.509 con SAN mediante `openssl` y autenticar nodos con `x509/name`.
5. **Garantizar 0% de pérdida ante caídas (*Disk-Assisted Queues*):** Simular la caída del servidor central mientras `imfile` sigue leyendo logs de una app y confirmar la entrega diferida al recuperar el colector.

---

## ⚡ 1. Mapa de Directivas Legacy vs RainerScript

| Concepto | Sintaxis Legacy (Histórica) | RainerScript Moderno (v8+) |
| :--- | :--- | :--- |
| **Cargar módulo UDP** | `$ModLoad imudp` <br> `$UDPServerRun 514` | `module(load="imudp")` <br> `input(type="imudp" port="514")` |
| **Plantilla de salida** | `$template MiFormato,"%TIMESTAMP%..."` | `template(name="MiFormato" type="string" string="%TIMESTAMP%...")` |
| **Descartar `debug`** | `*.debug ~` | `if ($syslogseverity-text == "debug") then { stop }` |
| **Enrutar app + reenviar** | `if $programname == 'app' then @host:514` | `if ($programname == "app") then { action(type="omfwd" ...) }` |
| **TLS + Cola en Disco** | Directivas globales `$ActionSendStreamDriver*` mezcladas | Parámetros encapsulados dentro de cada `action(type="omfwd" queue.type="LinkedList" ...)` |

---

## 🧪 2. Desarrollo Paso a Paso

> [!TIP]
> **Preparación en Ubuntu 24.04 LTS / Debian:**
> ```bash
> sudo apt update && sudo apt install -y rsyslog rsyslog-gnutls openssl jq
> ```
> *Nota AppArmor (Ubuntu):* El script utiliza `/var/spool/rsyslog/lab_demo_rsyslog` (configuración, certificados y spool) y `/var/log/lab_demo_rsyslog` (archivos de salida), rutas permitidas de forma nativa por `/etc/apparmor.d/usr.sbin.rsyslogd` sin necesidad de desactivar AppArmor.

Ejecutá la demostración interactiva completa o en modo automático:

```bash
cd linux/administrator/logs
sudo ./demo_rsyslog_pipelines.sh
# Modo automático:
sudo ./demo_rsyslog_pipelines.sh --auto 2
```

### Paso 1: PKI Efímera con OpenSSL (CA + Servidor + Cliente con SAN)
En TLS moderno, los certificados requieren la extensión `subjectAltName` (`DNS:localhost,IP:127.0.0.1`) para pasar la verificación `x509/name` de `rsyslog`:

```bash
mkdir -p /tmp/lab_demo_rsyslog/certs
# 1. CA propia
openssl req -x509 -newkey rsa:2048 -days 7 -nodes \
  -keyout /tmp/lab_demo_rsyslog/certs/ca.key \
  -out /tmp/lab_demo_rsyslog/certs/ca.crt \
  -subj "/CN=LabRsyslogCA"

# 2. Certificado de servidor/cliente con SAN=DNS:localhost,IP:127.0.0.1
openssl req -newkey rsa:2048 -nodes \
  -keyout /tmp/lab_demo_rsyslog/certs/server.key \
  -out /tmp/lab_demo_rsyslog/certs/server.csr \
  -subj "/CN=localhost"
openssl x509 -req -in /tmp/lab_demo_rsyslog/certs/server.csr \
  -CA /tmp/lab_demo_rsyslog/certs/ca.crt -CAkey /tmp/lab_demo_rsyslog/certs/ca.key -CAcreateserial \
  -out /tmp/lab_demo_rsyslog/certs/server.crt -days 7 \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth,clientAuth")
```

### Paso 2: Servidor Receptor `rsyslog` (UDP :15514 + TLS :16514 + Plantillas + Filtros)
```rsyslog
global(
    workDirectory="/tmp/lab_demo_rsyslog/spool_srv"
    DefaultNetstreamDriver="gtls"
    DefaultNetstreamDriverCAFile="/tmp/lab_demo_rsyslog/certs/ca.crt"
    DefaultNetstreamDriverCertFile="/tmp/lab_demo_rsyslog/certs/server.crt"
    DefaultNetstreamDriverKeyFile="/tmp/lab_demo_rsyslog/certs/server.key"
)

module(load="imudp")
input(type="imudp" port="15514")

module(load="imtcp" StreamDriver.Name="gtls" StreamDriver.Mode="1"
       StreamDriver.AuthMode="x509/name" PermittedPeer=["localhost","127.0.0.1"])
input(type="imtcp" port="16514")

template(name="MiFormato" type="string"
         string="%TIMESTAMP:::date-rfc3339% %HOSTNAME% %syslogtag%%msg%\n")

template(name="FormatoJSON" type="list") {
    constant(value="{")
    constant(value="\"timestamp\":\"")   property(name="timereported" dateFormat="rfc3339")
    constant(value="\",\"host\":\"")     property(name="hostname" format="json")
    constant(value="\",\"app\":\"")      property(name="programname" format="json")
    constant(value="\",\"severity\":\"") property(name="syslogseverity-text" format="json")
    constant(value="\",\"msg\":\"")      property(name="msg" format="json")
    constant(value="\"}\n")
}

if ($syslogseverity-text == "debug") then { stop }

if ($programname == "mi_aplicacion") then {
    action(type="omfile" file="/tmp/lab_demo_rsyslog/logs/mi_aplicacion.log" template="MiFormato")
    action(type="omfile" file="/tmp/lab_demo_rsyslog/logs/mi_aplicacion.json" template="FormatoJSON")
    stop
}

action(type="omfile" file="/tmp/lab_demo_rsyslog/logs/mislogs.log" template="MiFormato")
```

Validá siempre la sintaxis antes de arrancar:
```bash
rsyslogd -N1 -f /tmp/lab_demo_rsyslog/rsyslog_server.conf
```

### Paso 3: Prueba de Filtrado y JSON Estructurado
Enviá mensajes de prueba con `logger --udp -n 127.0.0.1 -P 15514`:
```bash
logger --udp -n 127.0.0.1 -P 15514 -p local0.debug -t mi_aplicacion "Traza DEBUG descartada"
logger --udp -n 127.0.0.1 -P 15514 -p local0.err   -t mi_aplicacion "Error critico de pago tx=8841"
```
Verificá que `mi_aplicacion.log` **no contiene** la línea `debug`, y que `mi_aplicacion.json` se valida limpiamente con `jq . /tmp/lab_demo_rsyslog/logs/mi_aplicacion.json`.

### Paso 4: Cliente `rsyslog` con `imfile` + Transporte TLS + Disk-Assisted Queue
En el cliente, `imfile` lee `/tmp/lab_demo_rsyslog/app_origen.log` y `omfwd` reenvía cifrado a `127.0.0.1:16514` con cola persistente en disco:

```rsyslog
action(
    type="omfwd"
    target="127.0.0.1"
    port="16514"
    protocol="tcp"
    StreamDriver="gtls"
    StreamDriverMode="1"
    StreamDriverAuthMode="x509/name"
    StreamDriverPermittedPeers="localhost"
    queue.type="LinkedList"
    queue.filename="fwd_tls_queue"
    queue.maxdiskspace="50m"
    queue.saveonshutdown="on"
    action.resumeRetryCount="-1"
    action.resumeInterval="1"
)
```

Durante la prueba del script:
1. Se detiene el servidor `rsyslog` receptor (`kill`).
2. La aplicación escribe 5 eventos mientras el servidor está **caído**.
3. El cliente retiene los mensajes en memoria/disco (`spool_cli`).
4. Al reiniciar el servidor, los 5 eventos retenidos aparecen íntegros en el servidor central (**0% de pérdida**).

---

## 🧹 3. Limpieza del Entorno

```bash
sudo ./limpiar_rsyslog_pipelines.sh
```
