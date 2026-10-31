---
id: lab-1.3-planificacion-cpu-nice
title: Planificación de CPU, Prioridades Nice/Renice, CFS y Afinidad de Núcleos con
  Taskset
difficulty_level: 1
difficulty_label: 'Nivel 1: Procesos, Señales, Terminales y Diagnóstico del Kernel'
section: '1.3'
sections:
- '1.3'
- '1'
category: processes
tags:
- procesos
- cpu
- nice
- renice
- cfs
- scheduler
- taskset
- afinidad
- prioridades
tools:
- nice
- renice
- taskset
- top
- htop
- pidstat
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
  notes: Ejecución exitosa de demo_nice.sh compilando cpu_worker.c, fijando núcleos
    con taskset y comprobando reparto porcentual de CFS.
- environment: AWS EC2
  type: cloud
  instance_type: t3.micro
  os: Ubuntu 24.04 LTS
  status: VERIFIED
  test_date: '2026-10-17'
  notes: Validado en instancias EC2 multi-core y single-core.
environments:
- WSL2
- AWS EC2
operating_systems:
- Ubuntu 24.04 LTS
status: PASSED
rag_summary: Laboratorio sobre el planificador de CPU Completely Fair Scheduler (CFS)
  en el kernel Linux. Demuestra matemáticamente cómo los valores nice (-20 a 19) se
  transforman en pesos de CPU cuando los procesos compiten en el mismo núcleo, cómo
  modificar prioridades en caliente con renice y cómo aislar la ejecución a CPUs específicas
  con taskset.
files:
  guide: nice/nice.md
  script: nice/demo_nice.sh
  terraform: null
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
prerequisites:
- lab-1.1-jobs-multiplexores
mcp_tools:
- linux-labs-tutor
- bash
- filesystem
---

# Prioridad y consumo de CPU con `nice` y `renice`

Esta guía permite observar cómo se reparte la CPU entre procesos con distintos valores nice, cambiar la prioridad de un proceso en ejecución y comprobar en qué CPU lógica se ejecuta.

## Conceptos

- `nice` ajusta la prioridad al iniciar un programa. En Linux, el valor habitual va de `-20` (mayor prioridad) a `19` (menor prioridad); el valor normal es `0`.
- `renice` cambia el valor nice de un proceso que ya está ejecutándose. El valor que se indica es el nuevo valor, no un incremento.
- Nice no reserva CPU ni garantiza un porcentaje. El efecto se ve cuando procesos ocupados compiten por la misma CPU lógica.
- `taskset` restringe las CPU lógicas en las que se permite ejecutar un proceso. No cambia su prioridad.

## Cómo se reparte la CPU

Linux no convierte los valores nice en porcentajes lineales. Usa pesos: cuanto menor el nice, mayor el peso y mayor la parte de CPU cuando las tareas compiten en la misma CPU lógica. Como aproximación, la parte de una tarea es:

```text
peso de la tarea / suma de los pesos de las tareas que compiten x 100
```

Ejemplos aproximados si los dos procesos están continuamente ocupados y fijados al mismo núcleo:

| Nice de los procesos | Peso aproximado | Reparto de ese núcleo |
| --- | ---: | ---: |
| `0` y `0` | `1024` y `1024` | `50%` y `50%` |
| `0` y `19` | `1024` y `15` | `98.6%` y `1.4%` |
| `-5` y `5` | `3121` y `335` | `90.3%` y `9.7%` |

El rango válido termina en `19`: no existe un nice `20`. Estos porcentajes son una referencia matemática para dos tareas que compiten solas; otros procesos ejecutables en ese núcleo también participan y cambian el reparto observado.

### ¿Qué cambia si la máquina tiene cuatro CPU lógicas?

Cada CPU lógica puede aportar hasta aproximadamente `100%` de capacidad en herramientas como `top`. Con cuatro CPU, la máquina puede ejecutar hasta cuatro tareas de un solo hilo a la vez si hay trabajo suficiente. Nice solo cambia el reparto cuando varias tareas compiten por la misma CPU; no obliga a que el uso total de la máquina sume `100%`.

- Dos workers sin restricción pueden ejecutarse en núcleos distintos y acercarse a `100%` cada uno, aunque sus valores nice sean diferentes.
- Si ambos se fijan con `taskset` a la misma CPU, compiten entre sí y se ve el reparto por pesos de la tabla.
- Cuatro workers con nice `0`, todos fijados a una misma CPU, recibirían aproximadamente `25%` de ese núcleo cada uno si no hay más competencia.
- Dos workers nice `0` y dos nice `19`, todos fijados a la misma CPU, darían aproximadamente `49.3%` a cada worker nice `0` y `0.7%` a cada worker nice `19`.

Para demostrar el efecto de nice, fijá los procesos a la misma CPU. Para demostrar uso de varios núcleos, fijalos a CPUs distintas o dejalos sin restricción y observá `PSR`.

## 1. Revisar las CPU disponibles

> **Requisitos para la práctica:**
> - Compilador `gcc` (`sudo apt install build-essential` en Debian/Ubuntu).
> - Permisos de `sudo` para las pruebas con `renice` que aumentan prioridad o usan nice negativo.
> - Al menos 2 CPUs lógicas para la Sección 7 (si tu máquina o VM solo tiene 1 CPU, esa sección no se podrá ejecutar).

```bash
nproc
taskset -pc $$
```

Usá identificadores de CPU que estén permitidos para la terminal. Los ejemplos siguientes usan `0` y `1`; reemplazalos si no aparecen en la salida.

```bash
CPU_A=0
CPU_B=1
```

Mantené estos valores y los procesos en la misma terminal. Comprobá también el nice heredado por la terminal:

```bash
ps -o pid,ni,comm -p $$
```

Los valores nice absolutos de los ejemplos asumen que la terminal tiene `NI=0`. GNU `nice -n` ajusta el valor heredado.

## 2. Crear el proceso de prueba

Guardá este programa como `cpu_worker.c`. Consume CPU incrementando un contador, muestra el contador al recibir `SIGUSR1` y termina ordenadamente al recibir `SIGTERM` o `SIGINT`.

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>

// Banderas modificadas por los manejadores de señales.
volatile sig_atomic_t keep_running = 1;
volatile sig_atomic_t print_status = 0;

// SIGTERM y SIGINT solicitan que el proceso termine.
void handle_sigterm(int signum) {
    (void)signum;
    keep_running = 0;
}

// SIGUSR1 solicita mostrar el estado en el bucle principal.
void handle_sigusr1(int signum) {
    (void)signum;
    print_status = 1;
}

int main(void) {
    unsigned long long counter = 0;
    struct sigaction action_term = {0};
    action_term.sa_handler = handle_sigterm;
    sigemptyset(&action_term.sa_mask);
    sigaction(SIGTERM, &action_term, NULL);
    sigaction(SIGINT, &action_term, NULL);

    struct sigaction action_usr1 = {0};
    action_usr1.sa_handler = handle_sigusr1;
    sigemptyset(&action_usr1.sa_mask);
    sigaction(SIGUSR1, &action_usr1, NULL);

    printf("Proceso iniciado PID: %d\n", getpid());
    fflush(stdout);

    while (keep_running) {
        counter++;

        if (print_status) {
            printf("[PID %d] SIGUSR1 recibido. Contador: %llu\n", getpid(), counter);
            print_status = 0;
        }
    }

    printf("\n[PID %d] Señal de terminación recibida. Contador final: %llu\n",
           getpid(), counter);
    return EXIT_SUCCESS;
}
```

Compilá el programa:

```bash
gcc -Wall -Wextra cpu_worker.c -o cpu_worker
```

## 3. Ver un reparto cercano a 50/50

Iniciá dos workers con el mismo nice, restringidos a la misma CPU lógica:

```bash
taskset -c "$CPU_A" nice -n 10 ./cpu_worker &
PID_NICE_A=$!
taskset -c "$CPU_A" nice -n 10 ./cpu_worker &
PID_NICE_B=$!
printf 'Worker A: PID=%s\nWorker B: PID=%s\n' "$PID_NICE_A" "$PID_NICE_B"
```

Observá el valor nice, la CPU lógica más reciente y el porcentaje de CPU. La salida queda ordenada por consumo:

```bash
ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$PID_NICE_A,$PID_NICE_B"
```

En `ps`, `%CPU` es un promedio desde que arrancó cada proceso. Para seguir el consumo instantáneo en vivo durante la prueba, usá `top`:

```bash
top -p "$PID_NICE_A,$PID_NICE_B"
```

Presioná `q` para salir de `top`. Como los dos workers tienen el mismo nice y compiten por el mismo núcleo, deberían repartirse el tiempo de esa CPU de forma aproximadamente pareja: cerca de `50%` cada uno si no hay otra carga importante. No es un porcentaje garantizado; puede variar.

Pediles que informen sus contadores. Esto no cambia su prioridad ni los detiene:

```bash
kill -USR1 "$PID_NICE_A" "$PID_NICE_B"
```

Detené este par antes de comenzar la siguiente prueba:

```bash
kill -TERM "$PID_NICE_A" "$PID_NICE_B"
wait "$PID_NICE_A" "$PID_NICE_B"
```

## 4. Comparar nice positivo bajo y alto

Ahora iniciá un worker con nice `5` y otro con nice `19`, ambos en la misma CPU:

```bash
taskset -c "$CPU_A" nice -n 5 ./cpu_worker &
PID_NICE5=$!
taskset -c "$CPU_A" nice -n 19 ./cpu_worker &
PID_NICE19=$!
printf 'Worker nice 5: PID=%s\nWorker nice 19: PID=%s\n' "$PID_NICE5" "$PID_NICE19"
```

Compará los valores y ordená por consumo de CPU:

```bash
ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$PID_NICE5,$PID_NICE19"
```

También podés ver ambos procesos en vivo:

```bash
top -p "$PID_NICE5,$PID_NICE19"
```

Presioná `q` para salir de `top`. Normalmente el proceso con nice `5` recibe mucho más tiempo de CPU que el proceso con nice `19`. Para dos workers solos en la misma CPU, los pesos de Linux predicen alrededor de `96%` para nice `5` y `4%` para nice `19` (la medición real puede variar por otros procesos del sistema y por la ventana de muestreo).

Consultá los contadores para ver la diferencia de velocidad a la que avanza cada uno:

```bash
kill -USR1 "$PID_NICE5" "$PID_NICE19"
```

Notarás que el contador del worker con nice `5` avanza aproximadamente 20 a 24 veces más rápido que el de nice `19`.

> **Importante**: No detengas estos procesos todavía; en la siguiente sección los modificaremos en caliente.

## 5. Cambiar la prioridad en caliente con `renice`

El worker `PID_NICE19` ya está funcionando con nice `19`. Subí su prioridad cambiando su valor nice a `5` para igualarlo con `PID_NICE5`:

```bash
sudo renice -n 5 -p "$PID_NICE19"
```

Comprobá el nuevo valor y observá cómo se equilibra el consumo en vivo:

```bash
ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$PID_NICE5,$PID_NICE19"
top -p "$PID_NICE5,$PID_NICE19"
```

Presioná `q` para salir de `top`. Ahora ambos tienen nice `5`, por lo que deberían acercarse a un reparto parejo (~50/50) al competir por la misma CPU.

> **Regla de permisos**: Un usuario común normalmente puede subir el valor nice de sus procesos (disminuir su prioridad); pero bajar el valor nice para aumentar la prioridad requiere privilegios de `root` o `CAP_SYS_NICE`.

Detené los dos procesos antes de continuar:

```bash
kill -TERM "$PID_NICE5" "$PID_NICE19"
wait "$PID_NICE5" "$PID_NICE19"
```

Al terminar, ambos informarán su contador final acumulado.

## 6. Comparar nice negativo (`-5`) con nice positivo (`5`)

Los valores negativos representan prioridades más altas que la normal (de `-1` a `-20`). Asignar nice negativo requiere privilegios de `root` o `CAP_SYS_NICE`.

Iniciá ambos workers con nice `5` en la misma CPU:

```bash
taskset -c "$CPU_A" nice -n 5 ./cpu_worker &
PID_NICE_MINUS5=$!
taskset -c "$CPU_A" nice -n 5 ./cpu_worker &
PID_NICE_PLUS5=$!
printf 'Worker A: PID=%s\nWorker B: PID=%s\n' "$PID_NICE_MINUS5" "$PID_NICE_PLUS5"
```

Subí la prioridad del primero a nice `-5` usando `sudo`:

```bash
sudo renice -n -5 -p "$PID_NICE_MINUS5"
```

Confirmá los valores y observá el uso en vivo:

```bash
ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$PID_NICE_MINUS5,$PID_NICE_PLUS5"
top -p "$PID_NICE_MINUS5,$PID_NICE_PLUS5"
```

Presioná `q` para salir de `top`. Si solo compiten estos dos workers en esa CPU, el nice `-5` (peso 3121) debería usar cerca del `90.3%` y el nice `5` (peso 335) cerca del `9.7%`.

Comprobá el avance de los contadores:

```bash
kill -USR1 "$PID_NICE_MINUS5" "$PID_NICE_PLUS5"
```

Detené ambos antes de continuar:

```bash
kill -TERM "$PID_NICE_MINUS5" "$PID_NICE_PLUS5"
wait "$PID_NICE_MINUS5" "$PID_NICE_PLUS5"
```

## 7. Observar el uso de una CPU lógica u otra

Con dos CPU lógicas disponibles, iniciá un proceso fijado a cada una:

```bash
taskset -c "$CPU_A" nice -n 10 ./cpu_worker &
PID_CPU_A=$!
taskset -c "$CPU_B" nice -n 10 ./cpu_worker &
PID_CPU_B=$!
```

Revisá la afinidad de cada uno y la CPU en la que corrió más recientemente:

```bash
taskset -pc "$PID_CPU_A"
taskset -pc "$PID_CPU_B"
ps -o pid,psr,ni,%cpu,comm -p "$PID_CPU_A,$PID_CPU_B"
```

Como cada worker puede ocupar un núcleo distinto, no compiten por la misma CPU. Cada uno podría acercarse al `100%` de una CPU lógica; no se dividirían un único `100%` en dos mitades.

Para permitir que un worker se ejecute en cualquiera de las dos CPU:

```bash
taskset -c "$CPU_A,$CPU_B" nice -n 10 ./cpu_worker &
PID_MIGRANTE=$!
taskset -pc "$PID_MIGRANTE"
```

La afinidad muestra dónde puede ejecutarse. La columna `PSR` de `ps` muestra la última CPU lógica que usó; puede cambiar entre muestras, pero no necesariamente alterna en cada consulta. Un proceso de un solo hilo puede migrar entre CPU permitidas, pero no ejecutarse en ambas al mismo tiempo.

Terminá los workers de esta prueba:

```bash
kill -TERM "$PID_CPU_A" "$PID_CPU_B" "$PID_MIGRANTE"
wait "$PID_CPU_A" "$PID_CPU_B" "$PID_MIGRANTE"
```

## Interpretar la salida

- `NI`: valor nice del proceso.
- `%CPU` en `ps`: promedio de uso desde el inicio del proceso.
- `%CPU` en `top`: uso calculado para los intervalos de actualización.
- `PSR`: CPU lógica en la que se ejecutó por última vez; no indica toda la afinidad.
- `taskset -pc PID`: CPUs lógicas permitidas para el proceso.

`nice` modifica la prioridad; `taskset` restringe la afinidad. Se pueden usar juntos, pero cumplen funciones distintas.

## Opción: Demostración interactiva paso a paso para dar clase (`demo_nice.sh`)

Si preferís dar la clase o presentación en vivo sin tener que copiar y pegar cada comando manualmente mientras explicás, podés utilizar el script interactivo [`demo_nice.sh`](demo_nice.sh).

El script compila automáticamente `cpu_worker.c`, prepara las variables de CPU, ejecuta cada escenario, muestra tablas de monitoreo en tiempo real con colores y se detiene en cada etapa para darte tiempo de explicar antes de continuar.

### Modo interactivo (control manual con [ENTER]):

```bash
chmod +x demo_nice.sh
./demo_nice.sh
```

En cada etapa el script muestra el comando a ejecutar, su fundamento teórico y espera a que presiones `[ENTER]` para dispararlo, consultar los contadores de avance (`SIGUSR1`) o aplicar `renice`.

### Modo automático con temporizador:

Si preferís que avance de forma autónoma con pausas fijas (por ejemplo, 5 segundos por paso):

```bash
./demo_nice.sh --auto 5
```

> **Nota de seguridad**: El script cuenta con un manejador de señales (`trap`). Si lo cancelás en cualquier momento con `Ctrl+C`, detendrá automáticamente todos los workers en segundo plano para no dejar ningún núcleo saturado.

---

## Apéndice: Origen teórico de los pesos en el planificador CFS

Para responder dudas o profundizar en clase sobre **de dónde salen los números de los pesos** (ej. `1024`, `335`, `15`) y los porcentajes calculados:

### 1. La tabla `sched_prio_to_weight` del Kernel de Linux

En el código fuente del kernel de Linux ([`kernel/sched/core.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/kernel/sched/core.c)), existe una tabla fija de 40 valores correspondiente a los niveles de nice desde `-20` hasta `+19`:

```c
const int sched_prio_to_weight[40] = {
 /* -20 */     88761,     71755,     56483,     46273,     36291,
 /* -15 */     29154,     23254,     18705,     14949,     11916,
 /* -10 */      9548,      7620,      6100,      4904,      3906,
 /*  -5 */      3121,      2501,      1991,      1586,      1277,
 /*   0 */      1024,       820,       655,       526,       423,
 /*   5 */       335,       272,       215,       172,       137,
 /*  10 */       110,        87,        70,        56,        45,
 /*  15 */        36,        29,        23,        18,        15,
};
```

* **Nice 0** tiene el peso base de referencia **`1024`** (una potencia de dos, computacionalmente eficiente para operaciones de bits en el CPU).
* **Nice 5** tiene peso **`335`**.
* **Nice 19** tiene peso **`15`**.

### 2. La regla del ~10% (Escala geométrica)

El autor de CFS (Ingo Molnar) diseñó la tabla de forma exponencial/geométrica en lugar de lineal para cumplir la siguiente propiedad de diseño:

> *Cada diferencia de 1 nivel de nice debe representar aproximadamente un 10% de diferencia en el tiempo de CPU relativo entre dos tareas que compiten.*

Matemáticamente, cada paso equivale a multiplicar o dividir por un factor constante de aproximadamente **`1.25`**:
- $1024 / 1.25 \approx 820$ (nice 1)
- $820 / 1.25 \approx 655$ (nice 2)
- $1024 \times 1.25 \approx 1277$ (nice -1)

Esto asegura que la diferencia relativa entre `nice 0` y `nice 1` sea proporcionalmente la misma que entre `nice 10` y `nice 11`.

### 3. Cálculo de los porcentajes teóricos

Cuando dos tareas compiten al 100% en la misma CPU lógica:

$$\text{\% de CPU} = \frac{\text{Peso de la tarea}}{\sum \text{Pesos de tareas en competencia}} \times 100$$

Para **Nice 5** vs **Nice 19**:
- Suma de pesos: $335 + 15 = 350$
- Tarea con Nice 5: $\frac{335}{350} \times 100 \approx \mathbf{95.7\%}$
- Tarea con Nice 19: $\frac{15}{350} \times 100 \approx \mathbf{4.3\%}$

### 4. Implementación interna con `vruntime`

Para no recalcular porcentajes constantemente, el kernel lleva un reloj virtual (**`vruntime`**) para cada tarea:

$$\Delta vruntime = \text{tiempo\_real\_ejecutado} \times \left( \frac{1024}{\text{peso}} \right)$$

* Una tarea con **nice 19** (peso 15) divide por 15 y multiplica por 1024, haciendo que su `vruntime` aumente muy rápido (~68 veces más rápido). El planificador la desaloja enseguida porque "virtualmente consumió mucho tiempo".
* Una tarea con **nice 5** (o nice negativo) acumula `vruntime` mucho más lento, por lo que el planificador le permite permanecer en el procesador mucho más tiempo real.