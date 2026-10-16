# Borg

## Instalar y primeros pasos en Borg

Escrito en C y Python, es increíblemente rápido y eficiente para copias locales, discos externos o servidores remotos a través de SSH.


BorgBackup para crear un repositorio cifrado y deduplicado:

```bash
sudo apt install borgbackup
```

- Inicializar
Le decimos a Borg que cree un repositorio en un disco externo y lo cifre (repokey significa que la llave se guarda en el repositorio, pero protegida por tu contraseña).

```bash
borg init --encryption=repokey /mnt/disco_externo/mi_backup
```

- Copia Seguridad
Vamos a hacer un backup de /var/www y /etc. El sufijo ::{now} le pondrá la fecha y hora actual como nombre a la copia.

```
borg create --stats --progress \
    /mnt/disco_externo/mi_backup::"servidor-{now}" \
    /var/www /etc
    
```

- Mas Tareas

La magia de la deduplicación (Segunda copia):Vuelve a ejecutar exactamente el mismo comando de creación 5 minutos después. Verás que tarda un segundo y ocupa 0 bytes adicionales, porque Borg analiza los fragmentos, reconoce que ya los tiene todos en la bóveda y simplemente crea un nuevo índice apuntando a los datos existentes.

Borg permite montar tu repositorio de backups como si fuera un disco duro externo para que puedas navegar por las carpetas con ls y copiar solo el archivo que borraste por error:

```
mkdir /tmp/restauracion
borg mount /mnt/disco_externo/mi_backup /tmp/restauracion

# Cuando termines de sacar tus archivos:
borg umount /tmp/restauracion
```

## Resumen completo

El flujo básico de una copia manual con Borg es:

1. Instalar BorgBackup.
2. Inicializar una sola vez un repositorio cifrado.
3. Crear un archivo de backup con las rutas que quieras proteger.
4. Montar el repositorio para explorar o recuperar archivos.
5. Desmontarlo al terminar.

Comandos principales:

```bash
sudo apt install borgbackup
borg init --encryption=repokey /mnt/disco_externo/mi_backup
borg create --stats --progress \
    /mnt/disco_externo/mi_backup::"servidor-{now}" \
    /var/www /etc
mkdir -p /tmp/restauracion
borg mount /mnt/disco_externo/mi_backup /tmp/restauracion
borg umount /tmp/restauracion
```

La contraseña protege la clave del repositorio: guardala de forma segura. Borg deduplica los datos, por lo que las ejecuciones siguientes pueden reutilizar bloques ya almacenados. Para restaurar, montá el repositorio y copiá los archivos necesarios desde `/tmp/restauracion` antes de desmontarlo.

## Opción: Demostración interactiva paso a paso para dar clase (`demo_borg.sh`)

Si vas a dar una clase sobre BorgBackup y deduplicación, podés utilizar el script interactivo [`demo_borg.sh`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/demo_borg.sh).

El script genera datos simulados de un servidor web (`/var/www` y `/etc/nginx`), inicializa el repositorio cifrado, crea el primer snapshot, realiza un segundo snapshot tras modificar una sola línea para **demostrar la deduplicación en vivo** (0 segundos, solo bytes adicionales para 10 MB de datos), simula un borrado accidental y **monta el repositorio como carpeta con FUSE** (`borg mount`) para recuperar el archivo borrado, finalizando con la política de retención (`borg prune`).

### Ejecución:

```bash
./demo_borg.sh          # Modo interactivo (pausa con [ENTER])
./demo_borg.sh --auto 5 # Modo automático (espera 5s por paso)
```
