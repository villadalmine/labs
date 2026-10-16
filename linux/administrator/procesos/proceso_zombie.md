# Proceso zombie en Linux

Un proceso zombie terminó su ejecución, pero todavía conserva una entrada en la tabla de procesos porque su padre no leyó su estado de salida con `wait()` o `waitpid()`. En esta práctica vas a observarlo, terminarás a su padre original y comprobarás que el zombie puede ser adoptado por un *subreaper* que tampoco lo recoge.

## 1. Crear el programa

Guardá este código en un archivo llamado `zombie_maker.c`:

```c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <unistd.h>

static void esperar(void)
{
    for (;;) {
        pause();
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);

    // Este proceso adoptará al zombie si matamos a su padre original.
    if (prctl(PR_SET_CHILD_SUBREAPER, 1) == -1) {
        perror("prctl(PR_SET_CHILD_SUBREAPER)");
        return EXIT_FAILURE;
    }

    pid_t padre = fork();
    if (padre == -1) {
        perror("fork del padre");
        return EXIT_FAILURE;
    }

    if (padre == 0) {
        pid_t hijo = fork();
        if (hijo == -1) {
            perror("fork del hijo");
            _exit(EXIT_FAILURE);
        }

        if (hijo == 0) {
            printf("[Hijo PID: %d] Dormire 60 segundos.\n", getpid());
            sleep(60);
            printf("[Hijo PID: %d] Termine. Ahora soy zombie porque mi padre no hace wait().\n",
                   getpid());
            _exit(EXIT_SUCCESS);
        }

        printf("[Padre PID: %d] Hijo PID: %d. No llamare a wait().\n", getpid(), hijo);
        printf("Mata este padre despues de que el hijo sea zombie.\n");
        esperar();
    }

    printf("[Subreaper PID: %d] Padre original PID: %d.\n", getpid(), padre);
    printf("Este proceso tampoco llamara a wait(); mantendra al zombie adoptado.\n");
    esperar();
}
```

Hay tres procesos: el subreaper, el padre original y el hijo. El hijo espera 60 segundos y termina con `_exit(0)`. Como el padre original no llama a `wait()`, el hijo queda como zombie. El subreaper se registra con `PR_SET_CHILD_SUBREAPER`, por lo que, si el padre original muere, el hijo zombie se reasigna a este proceso en lugar de ser recogido inmediatamente por `init`/`systemd`.

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

Anotá los PID del subreaper, del padre original y del hijo que aparecen en pantalla. Abrí otra terminal para las comprobaciones.

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

## 5. Terminar al padre y observar el zombie adoptado

Después de que pasen 60 segundos y el hijo aparezca como zombie, terminá únicamente al padre original con `SIGKILL`:

```bash
kill -9 <PID_PADRE>
```

Volvé a consultar el PID del hijo:

```bash
ps -o pid,ppid,stat,cmd -p <PID_HIJO>
```

Esta vez el PID debe seguir apareciendo con `STAT=Z`, pero su `PPID` será el PID del subreaper:

```text
PID     PPID              STAT    CMD
...     <PID_SUBREAPER>  Z       [zombie_maker] <defunct>
```

El hijo no quedó literalmente sin padre: fue adoptado por el subreaper. Como este programa tampoco llama a `wait()`, conserva la entrada zombie incluso después de morir el padre original.

**El zombie no está ejecutando código y `kill -9` no lo elimina.** Para que desaparezca, terminá también al subreaper:

```bash
kill -9 <PID_SUBREAPER>
```

Al morir el subreaper, el zombie se reasigna a `init`/`systemd`, que normalmente lo recoge enseguida.

## 6. Limpiar

El proceso debería terminar al enviar `SIGTERM` al padre. Comprobá que no queden instancias del ejemplo:

```bash
pgrep -af zombie_maker
```

Si el subreaper todavía aparece, terminá únicamente el PID de esta práctica:

```bash
kill -9 <PID_SUBREAPER>
```

Usá `kill -9 <PID>` para terminar un PID concreto. `pkill -9 32857` busca un proceso cuyo nombre sea `32857`; no interpreta `32857` como PID. Para esta práctica, terminá primero al padre original y después al subreaper.

Cuando ya no necesites el ejecutable ni el código fuente, podés borrarlos:

```bash
rm -f zombie_maker zombie_maker.c
```

## Ideas clave

- Un zombie ya terminó; no consume CPU como un proceso activo.
- `STAT=Z` indica que el proceso terminó y espera que su padre recoja su estado.
- `kill -9` no elimina un zombie: las señales no hacen que un proceso ya terminado ejecute código.
- Un zombie siempre conserva un padre o proceso adoptivo; no puede quedar literalmente sin padre.
- Sin un subreaper que también ignore `wait()`, `init`/`systemd` normalmente recoge el zombie inmediatamente después de la muerte del padre original.
- En un programa real, el padre debe gestionar a sus hijos con `wait()` o `waitpid()`.