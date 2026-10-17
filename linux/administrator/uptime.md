---
id: lab-1.4-uptime-load-proc
title: 'Diagnóstico de Carga del Sistema: Uptime, Load Average y Estructura Interna
  de /proc'
difficulty_level: 1
difficulty_label: 'Nivel 1: Procesos, Señales, Terminales y Diagnóstico del Kernel'
section: '1.4'
sections:
- '1.4'
- '1'
category: observability
tags:
- uptime
- load-average
- proc
- kernel
- cpu
- diagnostico
- procesos
tools:
- uptime
- cat
- grep
- nproc
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
  test_date: '2026-10-17'
  notes: Inspección de /proc/loadavg, /proc/stat y prueba controlada de estrés con
    bucles de CPU.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Lectura de métricas nativas del kernel en instancias AWS EC2.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Guía de diagnóstico sobre la métrica de Load Average en Linux. Explica
  el significado real de las ventanas de 1, 5 y 15 minutos, su relación con los núcleos
  físicos lógicos (nproc), la diferencia entre procesos en estado R (Running) y D
  (Uninterruptible Sleep/IO Wait) y cómo el kernel calcula los valores leyendo directamente
  desde el pseudofilesystem /proc/loadavg.
files:
  guide: uptime.md
  script: null
  terraform: null
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
prerequisites:
- lab-1.4-tools-stats
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# `uptime`, load average y `/proc`

Esta guía permite leer la salida de `uptime`, encontrar de dónde salen sus valores en `/proc` y observar cómo cambia la carga con una prueba controlada de CPU.

## 1. Leer la salida de `uptime`

Ejecutá:

```bash
uptime
```

Una salida de ejemplo:

```text
14:30:01 up 10 days, 4:13, 2 users, load average: 0.50, 0.25, 0.10
```

- `14:30:01`: hora actual del sistema.
- `up 10 days, 4:13`: tiempo transcurrido desde el último arranque.
- `2 users`: sesiones de usuario conectadas.
- `load average: 0.50, 0.25, 0.10`: promedios de carga de los últimos 1, 5 y 15 minutos, respectivamente.

Las medias no son promedios aritméticos exactos de cada minuto: Linux las suaviza en el tiempo. Por eso responden gradualmente cuando empieza o termina una carga.

## 2. Qué mide load average

En Linux, load average refleja la cantidad promedio de tareas que están ejecutándose o listas para ejecutarse (`R`), más las que esperan de forma ininterrumpible, normalmente por I/O (`D`). No es un porcentaje de CPU y no cuenta simplemente todos los procesos existentes.

Consultá cuántas CPU lógicas tiene disponibles esta sesión:

```bash
nproc
```

Usá ese número para poner la carga en contexto:

- En una máquina con 1 CPU lógica, una carga sostenida cercana a `1` puede significar que esa CPU está ocupada casi todo el tiempo.
- En una máquina con 4 CPU lógicas, una carga cercana a `4` puede corresponder a cuatro tareas ejecutables usando los cuatro núcleos.
- Una carga mayor que la cantidad de CPU puede indicar tareas esperando CPU, aunque también puede aumentar por tareas en estado `D` esperando I/O.
- Una carga menor que la cantidad de CPU no se traduce exactamente en un porcentaje de utilización: importan los estados de las tareas y el intervalo de promedio.

Para observar el porcentaje de CPU y los procesos, usá `top` en paralelo. No deduzcas el porcentaje directamente de load average.

## 3. Leer los valores directamente desde `/proc`

`/proc` es un filesystem virtual que expone información del kernel; estos archivos no son registros de texto guardados en disco.

### `/proc/loadavg`

```bash
cat /proc/loadavg
```

Ejemplo de formato:

```text
0.50 0.25 0.10 2/350 12345
```

Los primeros tres campos son las medias de 1, 5 y 15 minutos. El cuarto indica tareas ejecutables en este instante sobre el total de tareas; el quinto es el PID creado más recientemente. `uptime` presenta las tres medias con etiquetas legibles.

Separar los campos para verlos con nombre:

```bash
awk '{printf "1 min=%s  5 min=%s  15 min=%s  runnable/total=%s  último PID=%s\n", $1, $2, $3, $4, $5}' /proc/loadavg
```

### `/proc/uptime`

```bash
cat /proc/uptime
```

El primer número es el tiempo desde el arranque, en segundos. El segundo es tiempo acumulado de CPU en estado idle, también en segundos. En equipos multinúcleo, el segundo puede ser mayor que el primero porque suma el idle de varias CPU.

Mostrar el primer valor como segundos y minutos:

```bash
awk '{printf "Encendido: %.0f segundos (%.1f minutos)\n", $1, $1/60}' /proc/uptime
```

### `/proc/stat`

```bash
grep '^cpu ' /proc/stat
```

La línea `cpu` contiene contadores acumulados de tiempo de CPU desde el arranque, separados por estado. `top` y otras herramientas comparan muestras de estos contadores para estimar utilización durante un intervalo. No es de aquí de donde se lee directamente el load average; la interfaz correspondiente para esas medias es `/proc/loadavg`.

## 4. Tomar una línea base

Antes de generar carga, guardá una lectura del estado actual:

```bash
date
nproc
uptime
cat /proc/loadavg
cat /proc/uptime
```

Para ver carga y actividad de CPU actualizándose cada dos segundos, abrí otra terminal y ejecutá:

```bash
watch -n 2 'uptime; echo; cat /proc/loadavg'
```

Salí de `watch` con `Ctrl+C`.

## 5. Generar carga de CPU controlada

En Debian o Ubuntu, instalá `stress-ng` si todavía no está disponible:

```bash
sudo apt update
sudo apt install stress-ng
```

En una terminal, iniciá dos workers de CPU durante 90 segundos:

```bash
stress-ng --cpu 2 --timeout 90s --metrics-brief
```

Mientras corre, observá en la otra terminal:

```bash
uptime
cat /proc/loadavg
top
```

En `top`, presioná `q` para salir. Observá que la carga de 1 minuto no salta inmediatamente al nuevo nivel: necesita tiempo para incorporar las muestras. Las medias de 5 y 15 minutos reaccionan aún más despacio.

Con dos workers constantemente ejecutables, el load average tiende a aumentar aproximadamente en dos unidades sobre el valor de fondo. En una máquina con cuatro CPU lógicas eso no implica que el total esté saturado: puede representar dos de cuatro CPU ocupadas. La carga previa y los procesos en espera también cuentan.

El comando termina solo al cabo de 90 segundos. Para detenerlo antes, volvé a su terminal y presioná `Ctrl+C`. Evitá comandos globales de terminación que puedan cerrar shells ajenos a la prueba.

### Cómo comprobar que la prueba está funcionando

Mientras `stress-ng` corre, usá otra terminal para localizar sus procesos y mirar su estado y consumo:

```bash
pgrep -af stress-ng
ps -eo pid,ppid,stat,pcpu,comm,args | grep '[s]tress-ng'
```

Deberías ver los workers de CPU activos. En `ps`, `STAT` suele empezar con `R` cuando están ejecutándose o listos para ejecutar, y `%CPU` debería mostrar consumo. En `top`, buscá los procesos `stress-ng`; cada worker puede acercarse a una CPU lógica ocupada.

Compará las tres vistas durante la prueba:

```bash
uptime
cat /proc/loadavg
top
```

Los tres primeros campos de `/proc/loadavg` deben coincidir con los promedios que muestra `uptime` (1, 5 y 15 minutos). El cuarto campo (`ejecutables/total`) es una fotografía instantánea de tareas, no otro promedio. La carga de 1 minuto puede tardar en reaccionar; el `%CPU` de `top` ayuda a confirmar que la carga está ocurriendo ahora.

Cuando pasen los 90 segundos, verificá que `stress-ng` haya terminado:

```bash
pgrep -af stress-ng || echo 'No quedan procesos de stress-ng'
date
uptime
cat /proc/loadavg
```

La frase `No quedan procesos de stress-ng` confirma el fin de la prueba. El load average no vuelve a la línea base de inmediato: compará las lecturas siguientes y observá cómo descienden gradualmente, primero la media de 1 minuto y más lentamente las de 5 y 15 minutos.

## 6. Comparar una y cuatro tareas de CPU

Primero anotá el número de CPU disponibles:

```bash
nproc
```

Si el sistema tiene cuatro CPU lógicas, podés iniciar cuatro workers durante 90 segundos:

```bash
stress-ng --cpu 4 --timeout 90s --metrics-brief
```

Volvé a observar `uptime`, `/proc/loadavg` y `top`. Si la máquina estaba tranquila, la media de 1 minuto tenderá gradualmente a subir hacia cuatro unidades adicionales; no esperes que llegue exactamente a `4.00`, porque el promedio incluye el estado anterior y la actividad del resto del sistema.

Para adaptar la cantidad de workers a las CPU disponibles:

```bash
stress-ng --cpu "$(nproc)" --timeout 90s --metrics-brief
```

Limitá la prueba a una VM o equipo de laboratorio. `stress-ng` genera carga real y puede hacer más lentas las aplicaciones mientras corre.

## 7. Observar cómo baja la carga

Cuando `stress-ng` termina, las tareas dejan de consumir CPU, pero load average no vuelve a cero inmediatamente. Seguí observando:

```bash
watch -n 5 'uptime; cat /proc/loadavg'
```

Las medias de 1, 5 y 15 minutos disminuyen gradualmente. La de 1 minuto suele reflejar antes que terminó la prueba; la de 15 minutos tarda más porque conserva más efecto de la actividad pasada. Presioná `Ctrl+C` para salir de `watch`.

## Resumen

- `uptime` muestra el tiempo desde el arranque, las sesiones conectadas y tres medias de carga.
- `/proc/loadavg` expone las medias y datos instantáneos de tareas y PID.
- `/proc/uptime` expone el tiempo desde el arranque y el tiempo idle acumulado.
- `/proc/stat` expone contadores de CPU; las herramientas calculan porcentajes comparando muestras.
- Load average no es porcentaje de CPU: comparalo con la cantidad de CPU lógicas y con `top`.
- `stress-ng --timeout` genera una carga limitada en el tiempo.