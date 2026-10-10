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

En `ps`, `%CPU` es un promedio desde que arrancó cada proceso. Para comparar cómo cambia el consumo durante la prueba, usá `top`:

Para seguirlos en vivo:

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

Normalmente el proceso con nice `5` recibe más tiempo de CPU que el proceso con nice `19`. Cuanto más alto y positivo es el nice, menor es la prioridad relativa. Para dos workers solos en la misma CPU, los pesos de Linux predicen alrededor de `96%` para nice `5` y `4%` para nice `19`; la medición real puede variar por otros procesos y por el intervalo observado.

## 5. Comparar nice `-5` con nice `5`

Primero iniciá ambos workers con nice `5` y fijalos a la misma CPU:

```bash
taskset -c "$CPU_A" nice -n 5 ./cpu_worker &
PID_NICE_MINUS5=$!
taskset -c "$CPU_A" nice -n 5 ./cpu_worker &
PID_NICE_PLUS5=$!
```

Para subir la prioridad del primero a nice `-5`, necesitás privilegios de `root` o `CAP_SYS_NICE`:

```bash
sudo renice -n -5 -p "$PID_NICE_MINUS5"
```

Confirmá los valores y observá el uso en vivo:

```bash
ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$PID_NICE_MINUS5,$PID_NICE_PLUS5"
top -p "$PID_NICE_MINUS5,$PID_NICE_PLUS5"
```

Presioná `q` para salir de `top`. Si solo compiten estos dos workers en esa CPU, el nice `-5` debería usar cerca de `90%` y el nice `5` cerca de `10%`. En este ejemplo `%CPU` de `ps` es un promedio desde que arrancó cada proceso; `top` permite seguir el cambio en vivo.

Detené ambos antes de continuar:

```bash
kill -TERM "$PID_NICE_MINUS5" "$PID_NICE_PLUS5"
wait "$PID_NICE_MINUS5" "$PID_NICE_PLUS5"
```

## 6. Cambiar la prioridad con `renice`

El worker `PID_NICE19` ya está funcionando. Cambiá su valor nice a `5`:

```bash
sudo renice -n 5 -p "$PID_NICE19"
```

Comprobá el nuevo valor y compará el consumo otra vez:

```bash
ps -o pid,psr,ni,%cpu,comm --sort=-%cpu -p "$PID_NICE5,$PID_NICE19"
top -p "$PID_NICE5,$PID_NICE19"
```

Ahora ambos tienen nice `5`, por lo que deberían acercarse a un reparto parejo si siguen compitiendo por la misma CPU. Un usuario normalmente puede subir el valor nice de sus procesos; bajar el valor para aumentar la prioridad suele requerir `root` o `CAP_SYS_NICE`.

Detené los dos procesos antes de continuar:

```bash
kill -TERM "$PID_NICE5" "$PID_NICE19"
wait "$PID_NICE5" "$PID_NICE19"
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