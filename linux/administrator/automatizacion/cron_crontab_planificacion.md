---
id: lab-2.4-cron-crontab-planificacion
title: 'Planificación Clásica con Cron y Crontab: Sintaxis de 5 Campos, Operadores,
  Macros (@), Variables de Entorno y Troubleshooting'
difficulty_level: 2
difficulty_label: 'Nivel 2: Supervisión & Gobernanza Moderna (Systemd & Automatización)'
section: '2.4'
sections:
- '2.4'
- '2'
category: systemd
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
- systemd
- automatizacion
- planificacion
- cron
- crontab
- crond
- cronie
- vixie-cron
- path
- shell
- mailto
- macros
- troubleshooting
tools:
- crontab
- systemctl
- journalctl
- grep
- cat
- chmod
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
- environment: Podman Systemd Container (Toolbox Host)
  type: container
  instance_type: localhost/lab-automatizacion-systemd (Fedora 41 + systemd 256)
  os: Fedora Linux 41 (Container Image)
  kernel: 6.19.6-200.fc43.x86_64
  status: PASSED
  test_date: '2026-11-06'
  notes: Ejecutado de punta a punta con demo_cron_crontab.sh contra crond.service
    activo (cronie 1.7.2), probando /etc/crontab, crontab -l/-e/-r y fallo real de
    PATH con env -i.
- environment: WSL2
  type: local
  instance_type: virtualized
  os: Ubuntu 24.04 LTS / Rocky Linux 10.2
  kernel: 6.18.54.1-microsoft-standard-WSL2
  status: PASSED
  test_date: '2026-11-06'
  notes: Ejecución verificada con demo_cron_crontab.sh probando sintaxis de 5 campos,
    operadores, macros, aislamiento de usuarios y troubleshooting de PATH.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-11-06'
  notes: Compatible 100% con cron (Debian/Ubuntu) y cronie (RHEL/Rocky/Amazon Linux).
environments:
- WSL2
- AWS EC2
- Bare-Metal
operating_systems:
- Ubuntu 24.04 LTS
- Rocky Linux 10.2
- Debian 12
status: PASSED
rag_summary: Laboratorio práctico e interactivo sobre el servicio core cron y la gestión
  de tareas periódicas con crontab en Linux. Cubre en detalle el motor de configuración
  global /etc/crontab (variables SHELL, PATH y MAILTO), la diferencia estructural
  entre crontabs de sistema (con columna de usuario) y crontabs individuales de usuario
  (crontab -l, -e, -r), la anatomía de los 5 campos de tiempo (minuto, hora, día del
  mes, mes, día de la semana), el dominio de operadores de frecuencia (/, -, ,) y
  las macros de tiempo (@yearly, @monthly, @daily, @hourly, @reboot). Incluye reproducción
  y resolución en vivo del fallo clásico de producción donde un script funciona en
  terminal interactiva pero falla en cron por falta de rutas en PATH o permisos.
files:
  guide: automatizacion/cron_crontab_planificacion.md
  script: automatizacion/demo_cron_crontab.sh
  terraform: null
prerequisites:
- lab-2.0-automatizacion-arquitecturas-comparativa
next_recommended_labs:
- lab-2.5-anacron-at-tareas-asincronas
- lab-2.6-systemd-timers-vs-cron-chrony
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Laboratorio: Planificación Clásica con `cron` y `crontab` en Linux

> **Dificultad:** Intermedio (Nivel 2) | **Tiempo estimado:** 35 minutos | **Ambiente:** Cualquier terminal Linux, WSL2 o VM en la nube

`cron` es la utilidad histórica y omnipresente de los sistemas operativos tipo Unix que permite programar la ejecución desatendida de comandos, scripts o programas en momentos exactos o intervalos regulares. Fue diseñado tanto para tareas críticas del sistema operativo (rotación de logs, limpieza de cachés, mantenimiento continuo) como para flujos de trabajo de usuarios individuales.

En este laboratorio vas a dominar el motor de configuración global (`/etc/crontab`), la gestión aislada por usuarios (`crontab -l / -e / -r`), todos los operadores de frecuencia (`*`, `/`, `-`, `,`), las macros `@` (`@yearly`, `@daily`, `@reboot`) y diagnosticarás el error más frecuente de producción: **por qué un script corre perfecto a mano pero falla silenciosamente dentro de `cron`**.

---

## ⚡ 1. Cheat Sheet Rápida de `cron` y `crontab`

| Elemento / Comando | Sintaxis / Ubicación | Propósito Operativo |
| :--- | :--- | :--- |
| **Listar tareas del usuario** | `crontab -l` | Muestra en pantalla las tareas programadas actualmente para el usuario activo. |
| **Editar tareas del usuario** | `crontab -e` | Abre el archivo temporal en el editor predeterminado (`$EDITOR`) y valida la sintaxis al guardar. |
| **Borrar todas las tareas** | `crontab -r` *(¡Peligro!)* | Purga inmediatamente todas las tareas del usuario. Usar **`crontab -i -r`** para pedir confirmación. |
| **Gestionar otro usuario** | `sudo crontab -u <user> -l` | Permite a `root` inspeccionar o editar el crontab de cualquier cuenta del sistema. |
| **Crontab Global** | `/etc/crontab` | Archivo maestro del sistema. **Exige un 6to campo obligatorio indicando el `usuario`**. |
| **Drop-in de Paquetes** | `/etc/cron.d/*` | Archivos modulares de sistema con la misma sintaxis de `/etc/crontab` (incluyen columna `usuario`). |
| **Control de Acceso** | `/etc/cron.allow` y `/etc/cron.deny` | Lista blanca y lista negra que restringen qué usuarios tienen permiso para ejecutar `crontab`. |

---

## 🏗️ 2. Arquitectura del Motor de Configuración Global (`/etc/crontab`)

El demonio `cron` (llamado `cron.service` en Debian/Ubuntu y `crond.service` en RHEL/Rocky Linux) despierta cada minuto, lee sus tablas en memoria y ejecuta los trabajos cuyo patrón temporal coincida con el reloj del sistema.

Si inspeccionamos `/etc/crontab`, observaremos tres directivas de entorno esenciales en su cabecera:

```bash
# cat /etc/crontab
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root

# Example of job definition:
# .---------------- minute (0 - 59)
# |  .------------- hour (0 - 23)
# |  |  .---------- day of month (1 - 31)
# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
# |  |  |  |  |
# *  *  *  *  * user-name  command to be executed
```

### ¿Qué función cumple cada variable de arquitectura?
1. **`SHELL=/bin/bash`**: Indica exactamente qué intérprete de comandos ejecutará las tareas programadas. Si no se declara en un crontab de usuario, `cron` utiliza por defecto `/bin/sh` (que en muchas distros es `dash` y no soporta arrays ni sintaxis extendida de Bash).
2. **`PATH=/sbin:/bin:/usr/sbin:/usr/bin`**: Establece el camino de búsqueda de ejecutables. **Es fundamental para evitar errores de `command not found` en scripts automatizados**, ya que cron no carga el `~/.bashrc` del usuario y suele omitir rutas como `/usr/local/bin` o `~/.local/bin`.
3. **`MAILTO=root`**: Define la casilla de correo local a la que se enviarán las salidas estándar (`stdout`) y de error (`stderr`) de los comandos ejecutados. Si se define como vacío (`MAILTO=""`), se descarta el envío de correos.

> [!IMPORTANT]
> **Diferencia crítica entre `/etc/crontab` y `crontab -e`:**
> - En `/etc/crontab` y `/etc/cron.d/*`, **existe el campo `usuario`** entre el 5to asterisco y el comando:
>   `0 4 * * * root /backup/backup.sh`
> - En los crontabs personales editados con `crontab -e`, **NO va el nombre de usuario** (si ponés `root`, cron intentará ejecutar un comando llamado `root` y fallará):
>   `0 4 * * * /backup/backup.sh`

---

## 📐 3. Anatomía Estructural de una Tarea y Patrones de Ejecución

Cada línea activa de un archivo crontab comienza con **cinco campos de tiempo** separados por espacios o tabulaciones:

```
┌───────────── [1er *] Minuto        : Rango de 0 a 59
│ ┌─────────── [2do *] Hora          : Rango de 0 a 23
│ │ ┌───────── [3er *] Día del mes   : Rango de 1 a 31
│ │ │ ┌─────── [4to *] Mes           : Rango de 1 a 12 (o jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec)
│ │ │ │ ┌───── [5to *] Día de semana : Rango de 0 a 6 (0 o 7 = Domingo, o sun, mon, tue, wed, thu, fri, sat)
│ │ │ │ │
* * * * *  comando_a_ejecutar
```

### 3.1 Patrones de Frecuencias Regulares y Operadores (`/`, `-`)

| Caso de Uso | Expresión Crontab | Explicación Detallada |
| :--- | :--- | :--- |
| **Diariamente a una hora exacta** | `0 4 * * * /backup/backup.sh` | Se ejecuta todos los días exactamente a las **04:00 AM** (minuto 0 de la hora 4). *(Error común: poner `* 4 * * *`, lo cual ejecutaría el script 60 veces, cada minuto desde las 04:00 hasta las 04:59).* |
| **Intervalos divisibles (Operador `/`)** | `*/5 * * * * /home/crond1/backup.sh` | Se ejecuta **cada 5 minutos** (`:00`, `:05`, `:10`, `:15`...). |
| **Intervalos de horas (Operador `/`)** | `0 */5 * * * /home/crond1/backup.sh` | Se ejecuta al minuto cero **cada 5 horas** (`00:00`, `05:00`, `10:00`, `15:00`, `20:00`). *(Nota: `0 */2 * * *` es cada 2 horas).* |
| **Rangos continuos (Operador `-`)** | `0 9-18 * * * /home/crond1/backup.sh` | Se ejecuta al minuto cero de cada hora dentro del rango horario laboral, **desde las 09:00 hasta las 18:00 inclusive**. |

### 3.2 Patrones de Fechas Específicas y Listas Discontinuas (`,`)

| Caso de Uso | Expresión Crontab | Explicación Detallada |
| :--- | :--- | :--- |
| **Día específico del mes** | `0 5 1 * * /home/crond1/backupfull.sh` | Se ejecuta el **día 1 de cada mes a las 05:00 AM**. |
| **Día de la semana (Texto o Número)** | `0 0 * * Fri /home/crond1/backup.sh` <br> `0 0 * * 5 /home/crond1/backup.sh` | Ambas expresiones son equivalentes: ejecutan **todos los viernes a la medianoche (00:00)** (`0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat`). |
| **Listas discontinuas (Operador `,`)** | `0 0 * 5,10 * /home/crond1/backup.sh` | Se ejecuta a medianoche todos los días **solo durante los meses de Mayo (`5`) y Octubre (`10`)**. Como `cron` no posee sintaxis exacta para "cada 5 meses" sin corte anual, los meses deben listarse explícitamente separados por comas. |

### 3.3 Macros y Atajos de Tiempo (`@`)

Las macros sustituyen los cinco campos numéricos por una directiva legible al inicio de la línea:

| Macro | Sintaxis Equivalente | Ejemplo Real del Temario |
| :--- | :---: | :--- |
| **`@yearly`** *(o `@annually`)* | `0 0 1 1 *` | `@yearly /home/educacionit/bin/mantenimiento_anual.sh` |
| **`@monthly`** | `0 0 1 * *` | `@monthly /usr/local/bin/cierre_contable.sh` |
| **`@weekly`** | `0 0 * * 0` | `@weekly /usr/local/bin/limpiar_cache.sh` |
| **`@daily`** *(o `@midnight`)* | `0 0 * * *` | `@daily /usr/local/bin/rotar_logs.sh` |
| **`@hourly`** | `0 * * * *` | `@hourly /usr/local/bin/sincronizar_estado.sh` |
| **`@reboot`** | *(En el arranque)* | `@reboot /usr/local/bin/borra_temporales.sh` *(Ejecuta una sola vez al iniciar el sistema)*. |

---

## 🧪 4. Desarrollo Práctico Paso a Paso

### Paso 1: Verificar e Iniciar el Demonio de Cron
Dependiendo de tu distribución Linux, el servicio se denomina `cron` (Debian/Ubuntu) o `crond` (RHEL/Rocky/Fedora):

```bash
# 1. Detectar e iniciar el servicio automáticamente:
if systemctl list-unit-files | grep -q "^cron\.service"; then
    sudo systemctl enable --now cron.service
    systemctl status cron.service --no-pager
elif systemctl list-unit-files | grep -q "^crond\.service"; then
    sudo systemctl enable --now crond.service
    systemctl status crond.service --no-pager
fi
```

### Paso 2: Crear el Entorno de Scripts de Prueba
Vamos a crear un directorio aislado en `/tmp/lab_cron` con un script de telemetría y respaldo simulado:

```bash
export LAB_CRON="/tmp/lab_cron"
mkdir -p "${LAB_CRON}/bin" "${LAB_CRON}/logs"

cat << 'EOF' > "${LAB_CRON}/bin/tarea_latido.sh"
#!/usr/bin/env bash
FECHA=$(date '+%Y-%m-%d %H:%M:%S')
echo "[${FECHA}] Latido ejecutado por usuario=$(whoami) | SHELL=${SHELL} | PATH=${PATH}" >> /tmp/lab_cron/logs/latido.log
EOF

chmod +x "${LAB_CRON}/bin/tarea_latido.sh"
```

### Paso 3: Gestionar el Crontab del Usuario sin Abrir un Editor Interactivo
Aunque en consola solemos usar `crontab -e`, en scripts de automatización e infraestructura como código podemos inyectar y respaldar crontabs usando tuberías estándar (`crontab -`):

```bash
# 1. Respaldar el crontab actual (si existe) para no perder nada:
crontab -l > "${LAB_CRON}/crontab_backup_original.txt" 2>/dev/null || true

# 2. Instalar una tabla completa con todos los patrones de las diapositivas:
cat << 'EOF' | crontab -
# Variables de entorno personalizadas para el usuario
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=""

# 1. Tarea en vivo cada 1 minuto (para verificar ejecución inmediata en el lab)
* * * * * /tmp/lab_cron/bin/tarea_latido.sh

# 2. Diariamente a las 04:00 AM
0 4 * * * /tmp/lab_cron/bin/tarea_latido.sh --modo=diario

# 3. Intervalo divisible: cada 5 minutos
*/5 * * * * /tmp/lab_cron/bin/tarea_latido.sh --modo=cada5min

# 4. Rango continuo: minuto 0 desde las 09:00 hasta las 18:00
0 9-18 * * * /tmp/lab_cron/bin/tarea_latido.sh --modo=horario-laboral

# 5. Día 1 de cada mes a las 05:00 AM y todos los viernes a medianoche
0 5 1 * * /tmp/lab_cron/bin/tarea_latido.sh --modo=mensual
0 0 * * Fri /tmp/lab_cron/bin/tarea_latido.sh --modo=viernes

# 6. Lista discontinua (Mayo y Octubre) y Macros (@yearly, @reboot)
0 0 * 5,10 * /tmp/lab_cron/bin/tarea_latido.sh --modo=mayo-octubre
@yearly /tmp/lab_cron/bin/tarea_latido.sh --modo=anual
@reboot /tmp/lab_cron/bin/tarea_latido.sh --modo=arranque
EOF
```

### Paso 4: Inspeccionar la Cola y Comprobar la Ejecución Real
```bash
# 1. Listar las tareas activas con crontab -l:
crontab -l

# 2. Esperar hasta el próximo minuto del reloj y verificar el archivo de log:
sleep 62
cat /tmp/lab_cron/logs/latido.log
```

---

## 🔧 5. Troubleshooting Forense: Los 3 Errores Clásicos de Cron en Producción

### Error 1: El Script Funciona Manualmente pero Falla en Cron (`PATH` incompleto)
- **Síntoma:** Tenés una herramienta instalada en `/usr/local/bin/mi_herramienta`. Cuando corrés `/tmp/mi_script.sh` en tu terminal funciona perfecto, pero en `cron` falla con `mi_herramienta: command not found`.
- **Causa:** El `PATH` predeterminado de `cron` es `/usr/bin:/bin`. No incluye `/usr/local/bin`.
- **Solución:** Declarar explícitamente `PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin` al principio del crontab o dentro del propio script Bash, o bien invocar siempre rutas absolutas.

### Error 2: El Carácter `%` sin Escapar (`date +%Y-%m-%d`)
- **Síntoma:** Escribís en tu crontab:
  `0 3 * * * tar -czf /backup/web_$(date +%Y-%m-%d).tar.gz /var/www`
  y el trabajo falla misteriosamente.
- **Causa:** En la especificación de `crontab(5)`, **el símbolo `%` sin escapar es interpretado por `cron` como un salto de línea (`newline`)** y todo lo que sigue al primer `%` se envía como entrada estándar (`stdin`) al comando.
- **Solución:** Escapar siempre los signos de porcentaje con barra invertida (`date +\%Y-\%m-\%d`) o, mejor aún, colocar el comando dentro de un archivo script `.sh` externo.

### Error 3: Silenciar o Redirigir Correctamente `stdout` y `stderr`
- Si un comando genera salida cada minuto y no tenés servidor de correo local, llenará logs o generará alertas de `MTA not installed`.
- Para registrar tanto la salida estándar como los errores en un archivo de auditoría:
  `* * * * * /ruta/script.sh >> /var/log/mi_tarea.log 2>&1`

---

## 🎯 6. Retos de Autoevaluación ("Ponte a Prueba")

<details>
<summary><b>1. ¿Cuál es la diferencia exacta entre escribir <code>0 */5 * * *</code> y <code>* */5 * * *</code> en un crontab?</b></summary>
<br>
<b>Respuesta:</b> <code>0 */5 * * *</code> se ejecuta <b>una sola vez</b> al minuto 0 cada 5 horas (00:00, 05:00, 10:00, 15:00, 20:00). En cambio, <code>* */5 * * *</code> tiene un asterisco en el campo de los minutos, por lo que durante esas horas divisibles por 5 se ejecutará <b>60 veces seguidas (cada minuto durante toda esa hora)</b>.
</details>

<details>
<summary><b>2. ¿Por qué <code>crontab -r</code> es considerado un comando riesgoso para los administradores y cómo se previene?</b></summary>
<br>
<b>Respuesta:</b> Porque elimina instantáneamente todo el archivo crontab del usuario sin pedir confirmación, y en el teclado estándar la tecla <code>r</code> está justo al lado de la tecla <code>e</code> (usada para editar con <code>crontab -e</code>). Se previene acostumbrándose a usar <code>crontab -i -r</code> (que solicita confirmación interactiva) o manteniendo backups versionados de las tablas de cron.
</details>

<details>
<summary><b>3. ¿En qué archivos de cron es obligatorio especificar la columna del nombre de usuario antes del comando?</b></summary>
<br>
<b>Respuesta:</b> Únicamente en el archivo global <code>/etc/crontab</code> y en los archivos ubicados dentro del directorio <code>/etc/cron.d/</code>. Los crontabs de usuario gestionados con <code>crontab -e</code> nunca llevan columna de usuario.
</details>

<details>
<summary><b>4. ¿Cómo programarías un script para que corra únicamente una vez cada vez que el servidor se enciende?</b></summary>
<br>
<b>Respuesta:</b> Utilizando la macro especial <code>@reboot /ruta/absoluta/script.sh</code> al inicio de la línea en el crontab.
</details>

---

## 🛠️ 7. Demostración Interactiva y Limpieza

Podés ejecutar el laboratorio completo de forma interactiva o automática mediante los scripts incluidos en esta carpeta:

```bash
cd linux/administrator/automatizacion

# Ejecutar demostración guiada paso a paso:
sudo ./demo_cron_crontab.sh

# O en modo automático temporizado:
sudo ./demo_cron_crontab.sh --auto 2

# Limpiar todos los archivos y restaurar estado original:
sudo ./limpiar_cron_crontab.sh
```
