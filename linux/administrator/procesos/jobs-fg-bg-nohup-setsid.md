---
id: "lab-1.1-jobs-multiplexores"
title: "Control de Trabajos, Señales Unix y Multiplexores de Terminal (tmux, screen, zellij)"
difficulty_level: 1
difficulty_label: "Nivel 1: Procesos, Señales, Terminales y Diagnóstico del Kernel"
section: "1.1"
sections:
  - "1.1"
  - "1"
category: "processes"
tags:
  - "procesos"
  - "jobs"
  - "fg"
  - "bg"
  - "nohup"
  - "setsid"
  - "sighup"
  - "tmux"
  - "screen"
  - "zellij"
  - "guacamole"
  - "tty"
tools:
  - "jobs"
  - "fg"
  - "bg"
  - "nohup"
  - "setsid"
  - "ps"
  - "kill"
  - "tmux"
  - "screen"
  - "zellij"
requirements:
  root_required: false
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
    notes: "Comportamiento de SIGHUP, nohup, setsid y comandos de multiplexores verificados en consola."
  - environment: "AWS EC2"
    type: "cloud"
    instance_type: "t3.micro"
    os: "Ubuntu 24.04 LTS"
    status: "VERIFIED"
    test_date: "2026-10-17"
    notes: "Multiplexores y reconexión remota verificados vía SSH y Guacamole."
environments:
  - "WSL2"
  - "AWS EC2"
operating_systems:
  - "Ubuntu 24.04 LTS"
status: "PASSED"
rag_summary: "Guía completa de control de trabajos y persistencia de procesos en Linux. Cubre diferencias entre segundo plano (&), inmunidad a SIGHUP (nohup), creación de nuevas sesiones sin terminal controladora (setsid), y el uso de multiplexores de terminal (tmux, GNU screen, zellij) con atajos para redimensionar paneles y zoom en terminales remotas como Apache Guacamole."
files:
  guide: "procesos/jobs-fg-bg-nohup-setsid.md"
  script: null
  terraform: null
---

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

## 7. Retomar una terminal con `tmux`, `screen` o `zellij`

`tmux`, `screen` y `zellij` mantienen una sesión de terminal dentro del servidor. La conexión SSH es solamente la vista que se conecta a esa sesión. Si la red falla, cerrás la laptop o perdés la terminal, la sesión sigue ejecutando sus procesos en el servidor.

### Con `tmux`

Creá una sesión con un nombre:

```bash
tmux new -s trabajo
```

Ejecutá comandos normalmente. Para desconectarte sin detenerlos, presioná `Ctrl+B` y después `D`. La combinación `Ctrl+B` es el prefijo de `tmux`; `D` significa *detach*.

Cuando vuelvas a conectarte al servidor:

```bash
tmux ls
tmux attach -t trabajo
```

También podés crear o retomar la sesión directamente:

```bash
tmux new -As trabajo
```

### Con `screen`

```bash
screen -S trabajo
```

Desconectate con `Ctrl+A` y después `D`. Para volver:

```bash
screen -ls
screen -r trabajo
```

### Con `zellij`

```bash
zellij attach --create trabajo
```

Usá `Ctrl+O` y después `D` para desconectarte. Para listar y retomar sesiones:

```bash
zellij list-sessions
zellij attach trabajo
```

Si cerrás deliberadamente una sesión con `exit`, o reiniciás el servidor, los procesos de esa sesión terminan. Estas herramientas protegen contra la pérdida de la conexión, no contra un apagado o reinicio del servidor. Para procesos que deben sobrevivir a reinicios, usá un servicio de `systemd` o un supervisor.

### Manejo de Paneles, Zoom y Tamaño de Fuentes (Especial para Apache Guacamole y Terminales Web)

Cuando administras servidores mediante consolas web o escritorios remotos como **Apache Guacamole**, PuTTY o consolas Cloud (AWS EC2 Instance Connect, Cloud Shell), cambiar el tamaño de letra o ver bien los paneles divididos suele ser un desafío.

#### 1. ¿Cómo cambiar el tamaño de la fuente (*Font Size*) en Guacamole / Terminal Web?
> [!NOTE]
> Los multiplexores (`tmux`, `screen`, `zellij`) **no controlan los píxeles de la fuente tipográfica**, sino la cantidad de filas y columnas de la cuadrícula de texto (manejando la señal `SIGWINCH` del kernel).
> * **En Apache Guacamole:** Presiona `Ctrl + Alt + Shift` para abrir el panel lateral de Guacamole -> ajusta el zoom o resolución en la sección *Display*, o bien usa el zoom nativo de tu navegador web (`Ctrl + +` / `Ctrl + -`).
> * **En terminales locales/SSH clásicas:** Ajusta el tamaño de fuente en las preferencias de tu emulador (Windows Terminal, iTerm2, Alacritty, GNOME Terminal) con `Ctrl + +` o `Ctrl + Rueda del ratón`.

---

#### 2. Nota importante sobre "Agrandar" Paneles (Espacio Visual y Zoom)

Si lo que buscas no es el tamaño de la fuente, sino **agrandar el espacio visual de un panel dentro del multiplexor** (hacerlo pantalla completa temporalmente para leer logs o ajustar sus divisiones):

##### 🔲 En `tmux`:
* **Zoom a pantalla completa (Maximizar/Restaurar):**
  Presiona `Ctrl + b` seguido de `z`.
  *(El panel actual se expande ocupando toda la ventana. Vuelve a presionar `Ctrl + b` y luego `z` para restaurar la división original sin perder nada).*
* **Redimensionar divisiones con el teclado:**
  Presiona `Ctrl + b` y luego mantén presionado `Ctrl` mientras pulsas las **flechas de dirección** (`Arriba`, `Abajo`, `Izquierda`, `Derecha`) para empujar los bordes del panel.
* **Redimensionar con el ratón (Ideal para novatos):**
  Ejecuta dentro de tmux:
  ```bash
  tmux set -g mouse on
  ```
  Ahora puedes hacer clic y arrastrar los bordes divisorios con el cursor del ratón.

##### 🔲 En `Zellij`:
* **Modo Redimensionar (*Resize Mode*):**
  Presiona `Alt + n` para entrar al modo de redimensionar paneles.
  * Usa las teclas `h`, `j`, `k`, `l` o las **flechas del teclado** para encoger o agrandar el panel hacia cualquier dirección.
  * Presiona `+` o `-` para agrandar o achicar el panel activo.
  * Presiona `Esc` o `Enter` para salir del modo redimensionar.
* **Atajos directos de redimensión:**
  Presiona `Alt + h/j/k/l` directamente para mover las divisiones.
* **Maximizar / Fullscreen (Toggle Fullscreen):**
  Presiona `Alt + f` para alternar el panel activo a pantalla completa.

##### 🔲 En `GNU Screen`:
* **Hacer pantalla completa (Ocultar las demás regiones):**
  Presiona `Ctrl + a` seguido de `Q` (deja únicamente la región actual en toda la pantalla).
* **Dividir pantalla:**
  * Horizontal: `Ctrl + a` seguido de `S` (mayúscula).
  * Vertical: `Ctrl + a` seguido de `|` (barra vertical).
* **Ajustar el tamaño de las divisiones:**
  Presiona `Ctrl + a` seguido de `:` y escribe:
  * `resize +5` (agranda la región actual en 5 líneas).
  * `resize -5` (achica la región actual en 5 líneas).
  * `resize =` (iguala el tamaño de todas las regiones).


## 8. Resumen: qué resuelve cada comando

| Forma de ejecución | Ignora `SIGHUP` | Nueva sesión sin terminal de control | Reconectable |
| --- | --- | --- | --- |
| `comando &` | No | No | No |
| `nohup comando ... &` | Sí | No | No |
| `setsid comando ... &` | No necesariamente por `setsid` en sí | Sí | No |
| `tmux`, `screen` o `zellij` | Mantiene una sesión administrada aparte | Sí, según configuración | Sí |

`setsid` evita que la sesión nueva tenga la terminal de control original; no equivale a ignorar todas las señales ni protege contra cualquier forma de cierre. `nohup` ignora `SIGHUP`, pero no separa por sí solo la sesión. Para recuperar después una terminal interactiva, usá `tmux`, `screen` o `zellij`.

## Comandos principales

```bash
jobs -l
fg %1
bg %1
nohup comando > salida.log 2>&1 < /dev/null &
setsid comando </dev/null > salida.log 2>&1 &
tmux new -As trabajo
screen -r trabajo
zellij attach --create trabajo
```