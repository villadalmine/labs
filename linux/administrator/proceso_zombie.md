# Proceso zombie en Linux

Un proceso zombie terminó su ejecución, pero todavía conserva una entrada en la tabla de procesos porque su padre no leyó su estado de salida con `wait()` o `waitpid()`. En esta práctica vas a observarlo y después terminarás al padre para ver qué ocurre con el hijo.

## 1. Crear el programa

Guardá este código en un archivo llamado `zombie_maker.c`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

int main() {
    // fork() clona el proceso actual. Devuelve 0 al hijo y el PID del hijo al padre.
    pid_t pid = fork();

    if (pid < 0) {
        perror("Fallo al crear el proceso hijo");
        exit(1);
    }

    if (pid == 0) {
        // === BLOQUE DEL PROCESO HIJO ===
        printf("[Hijo PID: %d] Nací. Voy a simular trabajo durante 60 segundos...\n", getpid());
        sleep(60);

        // Cuando este exit(0) se ejecute, el hijo morirá.
        // Como el padre no lo está esperando, se convertirá en Zombi.
        printf("[Hijo PID: %d] Mi tiempo terminó. Me convierto en Zombi AHORA.\n", getpid());
        exit(0);
    } else {
        // === BLOQUE DEL PROCESO PADRE ===
        printf("[Padre PID: %d] Creé un hijo con PID: %d\n", getpid(), pid);
        printf("[Padre PID: %d] Soy un mal padre. No usaré wait(). Me quedaré en un bucle.\n", getpid());
        printf("-> Abre otra terminal y verifica el estado en 1 minuto.\n\n");

        // El padre se queda vivo bloqueando el proceso.
        // Si el padre muere, el zombi es adoptado por init/systemd y limpiado.
        while (1) {
            sleep(5); // Duerme para no saturar la CPU mientras ignora al hijo
        }
    }

    return 0;
}
```

`fork()` crea el hijo. El hijo espera 60 segundos y luego termina con `exit(0)`. Como el padre no llama a `wait()`, el hijo queda como zombie mientras el padre siga vivo.

## 2. Compilar y ejecutar

Instalá el compilador si hace falta:

```bash
sudo apt update
sudo apt install build-essential
```

Compilá el programa:

```bash
gcc zombie_maker.c -o zombie_maker
```

Ejecutá el programa en segundo plano:

```bash
./zombie_maker &
```

Anotá los PID del padre y del hijo que aparecen en pantalla. Abrí otra terminal para las comprobaciones.

## 3. Ver el hijo antes de que termine

Durante los primeros 60 segundos, reemplazá `<PID_HIJO>` por el PID informado por el programa:

```bash
ps -o pid,ppid,stat,cmd -p <PID_HIJO>
```

El estado todavía no contiene `Z`, porque el hijo sigue ejecutándose o durmiendo.

## 4. Ver el estado zombie

Pasado 1 minuto, repetí el comando:

```bash
ps -o pid,ppid,stat,cmd -p <PID_HIJO>
```

La columna `STAT` debe mostrar `Z` (a veces acompañado por otros caracteres). El `PPID` todavía corresponde al padre del programa. El hijo ya terminó: no está ejecutando instrucciones, pero su entrada sigue en la tabla de procesos porque el padre no recogió su estado.

También podés ver los procesos en forma de árbol:

```bash
ps -o pid,ppid,stat,cmd --forest -p <PID_PADRE>,<PID_HIJO>
```

## 5. Terminar al padre y observar qué pasa

Desde la segunda terminal, terminá el padre con `SIGKILL`, como en el ejemplo original. Reemplazá `<PID_PADRE>` por el PID que imprimió el programa:

```bash
kill -9 <PID_PADRE>
```

Volvé a consultar el PID del hijo:

```bash
ps -o pid,ppid,stat,cmd -p <PID_HIJO>
```

Normalmente ya no aparecerá ninguna fila para ese PID: al morir el padre, el zombie es adoptado por `systemd`/`init` (o por un proceso subreaper) y recogido. Puede existir un intervalo muy breve durante la adopción, por lo que repetir la consulta no garantiza que alcances a verlo con el nuevo PPID.

**El zombie no queda ejecutándose ni se elimina enviándole otra señal.** Ya había terminado; lo que faltaba era que un proceso recogiera su estado. Al desaparecer el padre original, el proceso adoptivo se ocupa de ello.

## 6. Limpiar

El proceso debería terminar al enviar `SIGTERM` al padre. Comprobá que no queden instancias del ejemplo:

```bash
pgrep -af zombie_maker
```

Si el padre todavía aparece, terminá únicamente el PID de esta práctica:

```bash
kill -9 <PID_PADRE>
```

Cuando ya no necesites el ejecutable ni el código fuente, podés borrarlos:

```bash
rm -f zombie_maker zombie_maker.c
```

## Ideas clave

- Un zombie ya terminó; no consume CPU como un proceso activo.
- `STAT=Z` indica que el proceso terminó y espera que su padre recoja su estado.
- `kill -9` no elimina un zombie: las señales no hacen que un proceso ya terminado ejecute código.
- Si el padre muere antes de recogerlo, el zombie se reasigna a un proceso adoptivo, que normalmente lo recoge rápidamente.
- En un programa real, el padre debe gestionar a sus hijos con `wait()` o `waitpid()`.