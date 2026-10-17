---
id: "lab-2.3-systemd-cgroups-v2"
title: "Gobernanza de Recursos con Cgroups v2 y Systemd (Límites Duros de CPUQuota y MemoryMax)"
difficulty_level: 2
difficulty_label: "Nivel 2: Supervisión & Gobernanza Moderna (Systemd)"
section: "2.3"
sections:
  - "2.3"
  - "2"
category: "systemd"
tags:
  - "systemd"
  - "cgroups"
  - "cgroups-v2"
  - "cpuquota"
  - "memorymax"
  - "recursos"
  - "gobernanza"
  - "kernel"
tools:
  - "systemd-run"
  - "systemctl"
  - "stat"
  - "cat"
  - "top"
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
  - environment: "WSL2"
    type: "local"
    instance_type: "virtualized"
    os: "Ubuntu 24.04 LTS"
    kernel: "6.18.54.1-microsoft-standard-WSL2"
    status: "PASSED"
    test_date: "2026-10-17"
    notes: "Verificación de cgroup2fs en /sys/fs/cgroup y limitación transitoria con systemd-run --property=CPUQuota=50%."
  - environment: "AWS EC2"
    type: "cloud"
    instance_type: "t3.micro"
    os: "Ubuntu 24.04 LTS"
    status: "VERIFIED"
    test_date: "2026-10-17"
    notes: "Cgroups v2 nativo en Ubuntu 24.04 LTS en AWS."
environments:
  - "WSL2"
  - "AWS EC2"
operating_systems:
  - "Ubuntu 24.04 LTS"
status: "PASSED"
rag_summary: "Laboratorio sobre control y gobernanza dura de recursos mediante el árbol unificado de cgroups v2 y systemd. Enseña a verificar controladores habilitados en /sys/fs/cgroup, lanzar servicios transitorios con límites de CPU (CPUQuota=50%) usando systemd-run, modificar límites dinámicamente y comprobar la contención física del procesador sin degradar el resto del servidor."
files:
  guide: "systemd/systemd-cgroups.md"
  script: null
  terraform: null
---

# Límites de CPU y cgroups con systemd

Esta guía muestra cómo iniciar un servicio de prueba con un límite de CPU, modificar el límite en ejecución y localizar sus procesos y archivos de control en cgroups v2.

La práctica usa una unidad transitoria llamada `lab-cpu.service`: no modifica `cron` ni escribe una unidad permanente en `/etc/systemd/system/`.

## 1. Comprobar cgroups v2

Verificá que `/sys/fs/cgroup` sea el punto de montaje unificado de cgroups v2 y que el controlador de CPU esté disponible:

```bash
stat -fc %T /sys/fs/cgroup
cat /sys/fs/cgroup/cgroup.controllers
```

La primera salida esperada es `cgroup2fs`; en la segunda debería aparecer `cpu`. Si no aparece, esta práctica puede requerir una configuración distinta del sistema.

> `/proc/sys` contiene parámetros del kernel (*sysctl*). La pertenencia de un proceso a un cgroup se consulta en `/proc/<PID>/cgroup`; los controles de cgroups v2 se encuentran bajo `/sys/fs/cgroup`.

## 2. Iniciar un servicio de prueba limitado

Este comando crea un servicio temporal que mantiene ocupada la CPU, con una cuota máxima del 50% de una CPU lógica:

```bash
sudo systemd-run --unit=lab-cpu.service --property=CPUQuota=50% /bin/bash -c 'while :; do :; done'
```

`systemd-run` inicia la unidad en segundo plano. `CPUQuota=50%` limita el servicio a aproximadamente medio núcleo, aunque la máquina tenga varias CPU lógicas.

Obtené el PID principal de la unidad y comprobá el uso:

```bash
PID=$(systemctl show --property=MainPID --value lab-cpu.service)
printf 'PID del servicio: %s\n' "$PID"
ps -o pid,psr,%cpu,comm -p "$PID"
top -p "$PID"
```

Presioná `q` para salir de `top`. La cifra puede fluctuar; con la cuota al 50%, el uso debería limitarse aproximadamente a la mitad de una CPU lógica.

## 3. Cambiar el límite en ejecución

Reducí temporalmente la cuota a 25%:

```bash
sudo systemctl set-property --runtime lab-cpu.service CPUQuota=25%
```

Comprobá el valor que systemd aplica a la unidad:

```bash
systemctl show lab-cpu.service -p MainPID -p ControlGroup -p CPUQuotaPerSecUSec
```

Volvé a observar el proceso:

```bash
top -p "$PID"
```

Con `--runtime`, el cambio no queda como configuración persistente. `CPUQuota` es un máximo; no es el reparto relativo de CPU entre servicios.

## 4. Ver el árbol de procesos con systemd

Mostrar el cgroup de la unidad:

```bash
systemd-cgls --unit=lab-cpu.service
```

También se puede consultar el estado de la unidad y sus procesos:

```bash
systemctl status lab-cpu.service
```

`systemd-cgls` presenta la jerarquía de cgroups; `systemctl status` vincula esa jerarquía con la unidad de systemd.

## 5. Encontrar el cgroup desde `/proc` y leer sus controles

Cada proceso indica en `/proc/<PID>/cgroup` a qué cgroup pertenece:

```bash
cat "/proc/$PID/cgroup"
```

En cgroups v2, la línea suele tener el formato `0::/system.slice/lab-cpu.service`. Podés extraer esa ruta y leer los archivos del controlador:

```bash
CGROUP_PATH=$(awk -F: '$1 == "0" { print $3 }' "/proc/$PID/cgroup")
printf 'Ruta del cgroup: %s\n' "$CGROUP_PATH"
cat "/sys/fs/cgroup${CGROUP_PATH}/cpu.max"
cat "/sys/fs/cgroup${CGROUP_PATH}/cpu.weight"
cat "/sys/fs/cgroup${CGROUP_PATH}/cpu.stat"
```

- `cpu.max` muestra la cuota y el período en microsegundos. El primer número limita cuánto tiempo de CPU se permite durante el período; `max` indica que no hay cuota configurada.
- `cpu.weight` es el peso relativo frente a cgroups hermanos que compiten por CPU. No fija un porcentaje máximo.
- `cpu.stat` incluye uso acumulado y estadísticas de períodos y throttling. `throttled_usec` puede aumentar cuando la cuota limita al servicio.

El valor de `cpu.max` puede variar según el período configurado por systemd. Por eso conviene compararlo con `CPUQuotaPerSecUSec` y no esperar siempre una cadena exacta.

## 6. Detener y limpiar la prueba

Detené la unidad transitoria:

```bash
sudo systemctl stop lab-cpu.service
```

Verificá que ya no esté activa:

```bash
systemctl status lab-cpu.service
```

La unidad y sus procesos se crearon para esta prueba. No hace falta borrar archivos de `/etc/systemd/system/`.

## Diferencia entre cuota y peso

- `CPUQuota` limita el tiempo máximo de CPU que puede usar una unidad; por ejemplo, `50%` equivale aproximadamente a medio núcleo.
- `CPUWeight` influye en el reparto relativo entre unidades hermanas cuando compiten por CPU. Un peso de `50` no significa que la unidad tenga un límite de 50%.
- `/proc/<PID>/cgroup` muestra la pertenencia del proceso; `/sys/fs/cgroup/...` expone los controles y estadísticas de cgroups v2.