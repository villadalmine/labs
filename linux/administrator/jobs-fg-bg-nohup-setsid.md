# Trabajos, primer plano y procesos separados de la terminal

Esta guía muestra qué hacen `&`, `jobs`, `fg`, `bg`, `nohup` y `setsid`. La idea es distinguir tres cosas diferentes:

1. ¿El proceso recibe `SIGHUP` (*hangup*)?
2. ¿Sigue ejecutándose cuando cierro la shell o la terminal?
3. ¿Puedo volver a conectarme a su terminal interactiva?

`&`, `nohup` y `setsid` responden de manera distinta. Ninguno reemplaza a `tmux` o `screen` si necesitás reconectarte a una sesión interactiva.

## 1. Iniciar un trabajo en segundo plano

`&` inicia el comando en segundo plano, pero no lo separa de la sesión de la shell.

```bash
sleep 120 &
```

La shell muestra un número de trabajo entre corchetes y un PID. Consultá los trabajos de esta shell:

```bash
jobs -l
```

El identificador `%1` es el número de trabajo de la shell. No es el PID. `jobs -l` muestra ambos para que puedas distinguirlos.

## 2. Traer un trabajo al primer plano con `fg`

Traé el trabajo 1 al primer plano:

```bash
fg %1
```

El comando ocupa la terminal mientras se ejecuta. Suspendelo con `Ctrl+Z`. La shell recupera el control y `jobs -l` muestra que el trabajo está detenido.

```bash
jobs -l
```

`Ctrl+Z` envía `SIGTSTP` al grupo de procesos en primer plano. En `ps`, el estado de un proceso detenido suele incluir `T`.

## 3. Reanudarlo en segundo plano con `bg`

Reanudá el trabajo detenido sin traerlo a la terminal:

```bash
bg %1
```

Comprobá su estado y PID:

```bash
jobs -l
```

`bg` continúa el trabajo, normalmente enviando `SIGCONT`. Algunos programas necesitan leer del teclado; si intentan hacerlo desde segundo plano pueden detenerse con `SIGTTIN`. Para usar la terminal interactiva, volvé a traerlos con `fg %1`.

Terminá el trabajo de prueba:

```bash
kill %1
```

## 4. Ver PID, sesión y terminal

Iniciá otro `sleep` en segundo plano y guardá su PID:

```bash
sleep 300 &
PID_JOB=$!
printf 'PID del trabajo: %s\n' "$PID_JOB"
```

Inspeccioná PID, grupo de procesos, sesión, terminal y estado:

```bash
ps -o pid,ppid,pgid,sid,tty,stat,cmd -p "$PID_JOB"
```

En general, el trabajo comparte la sesión (`SID`) y la terminal de control (`TTY`) de la shell. Que tenga `&` no significa que haya creado una sesión independiente.

Detenelo:

```bash
kill "$PID_JOB"
```

## 5. Ejecutar con `nohup`

`nohup` hace que el comando ignore `SIGHUP`. Para dejarlo en segundo plano, también se usa `&`. Redirigí la entrada y la salida para que el proceso no dependa de la terminal:

```bash
nohup sleep 300 > "$HOME/nohup-demo.log" 2>&1 < /dev/null &
PID_NOHUP=$!
printf 'PID de nohup: %s\n' "$PID_NOHUP"
```

Comprobá el proceso y la redirección:

```bash
ps -o pid,ppid,sid,tty,stat,cmd -p "$PID_NOHUP"
cat "$HOME/nohup-demo.log"
```

`nohup` protege contra `SIGHUP`, pero no crea por sí solo una nueva sesión ni ofrece una forma de reconectarse a la entrada/salida. La redirección evita que el comando dependa de la terminal para leer o escribir.

Para limpiar la prueba:

```bash
kill "$PID_NOHUP"
rm -f "$HOME/nohup-demo.log"
```

Al cerrar una terminal, el comportamiento de los trabajos normales depende de la shell y de cómo se cierre la sesión. `nohup` está diseñado para que el programa ignore el hangup, pero no sustituye una comprobación del PID y su estado.

## 6. Iniciar una sesión independiente con `setsid`

`setsid` ejecuta el comando en una sesión nueva, sin la terminal de control original. Usamos `--fork` para que cree el proceso separado de forma explícita. El hijo escribe su PID antes de reemplazar la shell por `sleep`:

```bash
rm -f "$HOME/setsid-demo.pid" "$HOME/setsid-demo.log"
setsid --fork sh -c 'echo $$ > "$HOME/setsid-demo.pid"; exec sleep 300' </dev/null > "$HOME/setsid-demo.log" 2>&1 &
PID_LANZADOR=$!
printf 'PID del lanzador setsid: %s\n' "$PID_LANZADOR"
```

Esperá a que el hijo escriba su PID. En un shell interactivo, es normal que aparezca `[1]+ Done`: ese es el lanzador `setsid`, que terminó después de crear el hijo; no significa que `sleep` haya terminado.

```bash
for intento in {1..20}; do
    [ -s "$HOME/setsid-demo.pid" ] && break
    sleep 0.1
done
PID_SETSID=$(cat "$HOME/setsid-demo.pid")
printf 'PID del worker separado: %s\n' "$PID_SETSID"
ps -p "$PID_SETSID" -o pid,ppid,pgid,sid,tty,stat,cmd
```

El worker debe seguir apareciendo como `sleep 300`; su `SID` y `PGID` normalmente coinciden con su PID y `TTY` aparece como `?`. `exec sleep` conserva el PID que escribió la shell. El `$!` guardado antes es el PID del lanzador y puede ser distinto. Para comprobar que sigue vivo, consultá el PID del worker guardado; `grep` del PID del lanzador no sirve porque ese número no aparece necesariamente en la línea de comandos.

`setsid` separa la sesión de la terminal original, pero no guarda una terminal interactiva a la que puedas volver a conectarte. También conviene redirigir entrada y salida, como en el ejemplo.

Detené y limpiá la prueba:

```bash
kill -TERM "$PID_SETSID"
rm -f "$HOME/setsid-demo.pid" "$HOME/setsid-demo.log"
```

## 7. Resumen: qué resuelve cada comando

| Forma de ejecución | Ignora `SIGHUP` | Nueva sesión sin terminal de control | Reconectable |
| --- | --- | --- | --- |
| `comando &` | No | No | No |
| `nohup comando ... &` | Sí | No | No |
| `setsid comando ... &` | No necesariamente por `setsid` en sí | Sí | No |
| `tmux` o `screen` | Mantiene una sesión administrada aparte | Sí, según configuración | Sí |

`setsid` evita que la sesión nueva tenga la terminal de control original; no equivale a ignorar todas las señales ni protege contra cualquier forma de cierre. `nohup` ignora `SIGHUP`, pero no separa por sí solo la sesión. Para recuperar después una terminal interactiva, usá `tmux` o `screen`.

## Comandos principales

```bash
jobs -l
fg %1
bg %1
nohup comando > salida.log 2>&1 < /dev/null &
setsid comando </dev/null > salida.log 2>&1 &
```