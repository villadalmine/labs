---
id: lab-1.4-tools-stats
title: Herramientas de Estadísticas y Diagnóstico en Vivo (vmstat, iostat, sar, dstat)
difficulty_level: 1
difficulty_label: 'Nivel 1: Procesos, Señales, Terminales y Diagnóstico del Kernel'
section: '1.4'
sections:
- '1.4'
- '1'
category: observability
tags:
- diagnostico
- metricas
- estadisticas
- vmstat
- iostat
- sar
- dstat
- sysstat
- rendimiento
tools:
- vmstat
- iostat
- sar
- dstat
- top
- free
- mpstat
requirements:
  root_required: true
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
  notes: Paquetes sysstat y dstat instalados y verificados con muestreo continuo.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Herramientas estándar de observabilidad del paquete sysstat.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Guía práctica de observabilidad forense y diagnóstico en tiempo real
  de servidores Linux. Enseña a interpretar métricas de CPU, memoria, I/O wait (wa),
  swap (si/so) y latencia de disco (await) utilizando vmstat, iostat, mpstat, dstat
  y sar del paquete sysstat.
files:
  guide: tools-stats.md
  script: null
  terraform: null
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: manual_commands
prerequisites:
- lab-1.3-planificacion-cpu-nice
---

# Herramientas para consultar estadísticas del sistema Linux

Esta guía reúne comandos para observar CPU, memoria, almacenamiento, procesos y red. Algunas herramientas muestran una fotografía del momento; otras actualizan las métricas a intervalos.

## Instalar herramientas

En Debian y Ubuntu, `sysstat` incluye `iostat`, `mpstat`, `pidstat` y `sar`. `top`, `free`, `vmstat`, `uptime`, `ss` e `ip` suelen estar disponibles en una instalación estándar.

```bash
sudo apt update
sudo apt install sysstat htop
```

`dstat` puede instalarse como paquete independiente o estar disponible mediante una implementación compatible de Performance Co-Pilot (PCP), según la distribución y su versión. Revisá el nombre del paquete en los repositorios de tu sistema.

## Vista combinada con dstat

Para ver CPU, discos, red, paginación y actividad del sistema en una línea de tiempo, con una muestra por segundo:

```bash
dstat -cdngy 1
```

Las secciones que habilitan las opciones son:

- `-c`: uso de CPU. Las columnas pueden variar; suelen separar tiempo de usuario, sistema, inactividad y espera de I/O. En máquinas virtuales puede aparecer tiempo de CPU cedido al hipervisor (*steal*).
- `-d`: tasas agregadas de lectura y escritura de discos.
- `-n`: tasas agregadas de recepción y envío de red.
- `-g`: actividad de paginación hacia dentro y hacia fuera. No equivale por sí sola a una medición directa del uso de swap; contrastala con `vmstat` o `free`.
- `-y`: actividad del sistema, como interrupciones y cambios de contexto por segundo.

Presioná `Ctrl+C` para detenerlo. Un valor alto aislado no confirma un problema: compará las métricas con la carga esperada y observá su evolución.

## Memoria y actividad general

### Memoria disponible

```bash
free -h
```

Muestra memoria total, usada, disponible y swap. Para evaluar si falta RAM, prestá atención a `available` y a la evolución de swap, no solo a la columna `free`.

### CPU, memoria, procesos y espera de I/O

```bash
vmstat 1 5
```

Muestra cinco informes con un segundo de intervalo. La primera fila suele representar promedios desde el arranque; usá las filas siguientes para observar la actividad durante la prueba. Entre las columnas útiles están `r` (procesos listos para usar CPU), `si` y `so` (swap de entrada y salida), `bi` y `bo` (I/O de bloques), `in` (interrupciones), `cs` (cambios de contexto) y `us`, `sy`, `id`, `wa` (tiempo de CPU).

La columna `wa` representa tiempo de CPU en espera de I/O; no mide espera de red. Un valor alto merece investigar el almacenamiento, pero debe interpretarse junto con otras métricas.

### Carga promedio

```bash
uptime
```

Muestra cuánto tiempo lleva activo el sistema y la carga promedio de 1, 5 y 15 minutos. La carga incluye procesos ejecutables y procesos en espera ininterrumpible; interpretala teniendo en cuenta la cantidad de CPU y otras métricas.

## CPU

### Vista interactiva

```bash
top
```

Muestra procesos y uso de recursos en tiempo real. Si está instalado `htop`, ofrece una vista interactiva alternativa:

```bash
htop
```

### Uso por CPU lógica

```bash
mpstat -P ALL 1
```

Actualiza cada segundo y muestra estadísticas por CPU lógica. Para detenerlo, presioná `Ctrl+C`.

### Uso por proceso

```bash
pidstat -u 1
```

También se pueden observar memoria y actividad de disco por proceso:

```bash
pidstat -r -d 1
```

## Almacenamiento

### Tasas y latencia por dispositivo

```bash
iostat -xz 1
```

Actualiza las estadísticas extendidas de cada dispositivo. Revisá las tasas de lectura/escritura, la cola y la latencia (`await`) junto con la carga de trabajo. La primera muestra puede incluir promedios desde el arranque; evaluá las siguientes para ver el intervalo actual.

### Espacio de filesystems y directorios

```bash
df -h
du -sh /ruta/al/directorio
```

`df` muestra el espacio de los filesystems montados; `du` estima cuánto ocupan archivos y directorios.

## Red

### Tráfico por interfaz

```bash
sar -n DEV 1
```

Muestra estadísticas de tráfico por dispositivo de red en intervalos. Presioná `Ctrl+C` para detenerlo.

### Contadores de una interfaz

```bash
ip -s link
```

Muestra contadores de bytes, paquetes y errores por interfaz. Son contadores acumulados; compará dos lecturas si necesitás calcular una tasa.

### Resumen de sockets

```bash
ss -s
```

Resume los sockets y sus estados. Es una fotografía del momento, no una serie temporal de tráfico.

## Registrar muestras con sar

`sar` puede mostrar mediciones por intervalo en la terminal:

```bash
sar -u 1 5
sar -r 1 5
sar -d 1 5
```

Estos ejemplos recopilan cinco muestras de CPU, memoria y dispositivos de almacenamiento, respectivamente. Según la configuración de `sysstat`, el sistema también puede guardar datos periódicos para consultarlos más tarde; la recolección histórica puede requerir habilitar el servicio o timer de la distribución.

## Qué herramienta elegir

- Para una vista rápida de CPU, memoria, discos y red juntos: `dstat -cdngy 1`.
- Para memoria disponible y swap: `free -h` y `vmstat 1`.
- Para localizar procesos que consumen CPU o memoria: `top`, `htop` o `pidstat`.
- Para revisar actividad y latencia de discos: `iostat -xz 1`.
- Para examinar tráfico por interfaz: `sar -n DEV 1` o `ip -s link`.
- Para conservar muestras de métricas: `sar` y la configuración de recolección de `sysstat`.