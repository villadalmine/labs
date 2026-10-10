# Prioridad y consumo de CPU con `nice` y `renice`

Esta guía permite observar cómo se reparte la CPU entre procesos con distintos valores nice, cambiar la prioridad de un proceso en ejecución y comprobar en qué CPU lógica se ejecuta.

## Conceptos

- `nice` ajusta la prioridad al iniciar un programa. En Linux, el valor habitual va de `-20` (mayor prioridad) a `19` (menor prioridad); el valor normal es `0`.
- `renice` cambia el valor nice de un proceso que ya está ejecutándose. El valor que se indica es el nuevo valor, no un incremento.
- Nice no reserva CPU ni garantiza un porcentaje. El efecto se ve cuando procesos ocupados compiten por la misma CPU lógica.
- `taskset` restringe las CPU lógicas en las que se permite ejecutar un proceso. No cambia su prioridad.

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

Normalmente el proceso con nice `5` recibe más tiempo de CPU que el proceso con nice `19`. Cuanto más alto y positivo es el nice, menor es la prioridad relativa. El porcentaje depende de la carga y no tiene una proporción fija.

## 5. Cambiar la prioridad con `renice`

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

## 6. Observar el uso de una CPU lógica u otra

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
- `%CPU`: tiempo de CPU utilizado durante el intervalo de medición.
- `PSR`: CPU lógica en la que se ejecutó por última vez; no indica toda la afinidad.
- `taskset -pc PID`: CPUs lógicas permitidas para el proceso.

`nice` modifica la prioridad; `taskset` restringe la afinidad. Se pueden usar juntos, pero cumplen funciones distintas.