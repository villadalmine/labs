---
id: ai-tutor-practica-15-min-mcp
title: "Práctica de 15 minutos: tu primer servidor MCP (levantarlo, hablarle a mano y conectarle un agente)"
difficulty_level: 2
difficulty_label: "Nivel 2: Primer contacto práctico con MCP"
section: "ai.8"
sections:
  - "ai.8"
  - "ai"
  - "tutor"
category: "reference"
resource_type: "tutorial"
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: "local"
tags:
  - "mcp"
  - "streamable-http"
  - "json-rpc"
  - "agentes"
  - "practica"
tools:
  - "python"
  - "git"
  - "curl"
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 1024
  min_disks: 0
tested_environments:
  - environment: "Bare-Metal"
    type: "local"
    instance_type: "physical"
    os: "Fedora 44"
    status: "PASSED"
    test_date: "2026-11-14"
    notes: "Clon limpio desde GitHub: clonar, levantar y verificar tardó 4 s. demo_practica_15_min_mcp.sh --auto 0: TODO OK. Gemini CLI y VS Code no se probaron."
  - environment: "Container"
    type: "local"
    instance_type: "podman"
    os: "Ubuntu 24.04 LTS"
    status: "PASSED"
    test_date: "2026-11-14"
    notes: "Imagen ubuntu:24.04 limpia, solo apt install python3 git curl; usuario sin root clona la rama desde GitHub y corre demo_practica_15_min_mcp.sh --auto 0: TODO OK en 9 s (40 s con la instalación). Python 3.12.3."
environments:
  - "Bare-Metal"
  - "Container"
  - "WSL2"
operating_systems:
  - "Fedora 44"
  - "Ubuntu 24.04 LTS"
status: "PASSED"
rag_summary: "Práctica corta para clase: el alumno levanta el servidor MCP de los laboratorios del curso, observa initialize, notifications/initialized, tools/list y tools/call con curl, y lee el esquema de una herramienta. Explica cómo un host conecta al modelo con el catálogo real y ofrece conexión de Claude Code, Codex, Antigravity, Gemini CLI y VS Code con su cobertura de pruebas explícita. Incluye retos de exclusión y autenticación y una ficha para demostrar una llamada real."
files:
  guide: "ai/tutor/PRACTICA_15_MIN_MCP.md"
  script: "ai/tutor/demo_practica_15_min_mcp.sh"
  terraform: null
---

# Práctica de 15 minutos: tu primer servidor MCP

Hoy vas a **levantar un servidor MCP con tus manos**, hablarle sin ningún agente para ver qué pasa por debajo, y después conectarle un agente de verdad. MCP (Model Context Protocol) define cómo una aplicación descubre y usa capacidades externas: en nuestro caso, buscar labs, leer guías y pedir pistas del curso.

**Antes de empezar:** si todavía no distinguís modelo, agente, herramienta y protocolo, hacé la unidad [Agentes y protocolos: del pedido del alumno a una herramienta MCP](AGENTES_Y_PROTOCOLOS_MCP.md). Explica con diagramas quién habla con quién, qué aportan JSON-RPC, HTTP, stdio, MCP y A2A, y cómo el agente usa la respuesta para ayudarte. Son 20–30 minutos previos; esta práctica conserva sus 15 minutos con el entorno y un cliente ya preparados.

**La situación real:** le pedís a Claude Code, Codex o Antigravity «ayudame con RAID». La aplicación consulta su modelo; el modelo puede proponer `search_curriculum`; el cliente MCP de la aplicación envía la llamada al servidor Python; el servidor lee el catálogo y devuelve labs reales; la aplicación entrega el resultado al modelo y este te explica cuál practicar. Configurar el servidor habilita ese recorrido, pero hay que observar una llamada para comprobarlo.

El servidor de este lab no tiene un modelo dentro ni ejecuta los comandos de RAID de las guías. Consultarlo con `curl` no necesita una suscripción. Para la parte con un agente usás su cuenta o proveedor habitual; el costo del modelo, si lo hay, es independiente de MCP.

**Qué necesitás:** Linux o WSL, con `python3`, `git` y `curl`. No hace falta instalar nada más: el servidor solo usa la biblioteca estándar de Python.

| Minutos | Qué hacés | Qué aprendés |
|---|---|---|
| 0 a 3 | Clonar y levantar el servidor | Este servidor MCP es un proceso local; acá lo usamos por HTTP |
| 3 a 7 | Hablarle a mano con `curl` | Lo que hace un agente: presentarse, pedir la lista de herramientas, llamar a una |
| 7 a 12 | Conectarle un agente | El modelo propone una herramienta y el host controla y envía la llamada |
| 12 a 15 | Dos retos | Control: qué herramientas ve el agente y quién puede entrar |

## 1. Levantar el servidor (minutos 0 a 3)

```bash
git clone https://github.com/villadalmine/labs.git
cd labs
python3 ai/tutor/hub/hub.py up labs
python3 ai/tutor/hub/hub.py verify labs
```

Tiene que decir algo así:

```
  labs       OK   linux-labs-tutor | 7 herramientas | search_curriculum -> 5778 caracteres
```

Tu servidor MCP está escuchando en `http://127.0.0.1:8091/mcp`, solo en tu máquina.

## 2. Hablarle a mano (minutos 3 a 7)

Un agente no hace magia: le manda mensajes JSON al servidor. Hacelo vos con `curl`. Primero guardá las cabeceras en una variable para no repetirlas:

```bash
H='-H Content-Type:application/json -H Accept:application/json,text/event-stream'
URL=http://127.0.0.1:8091/mcp
```

**2.1 Presentarse** (`initialize`): el cliente dice quién es y el servidor responde con su nombre y qué sabe hacer.

```bash
curl -s $H $URL -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"yo","version":"1"}}}' | python3 -m json.tool
```

La práctica usa la revisión `2025-03-26`, admitida por este servidor; no afirma que sea la última revisión de MCP. Después de la respuesta, el cliente confirma que terminó la inicialización:

```bash
curl -s -o /dev/null -w '%{http_code}\n' $H $URL -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
```

Este servidor HTTP devuelve `202` sin contenido JSON. La notificación no tiene `id` y no espera una respuesta JSON-RPC. El cliente real hace este intercambio por vos. [Ciclo de vida oficial de esta revisión](https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle).

**2.2 Pedir la lista de herramientas** (`tools/list`): esto es lo que el agente lee para saber qué puede hacer.

```bash
curl -s $H $URL -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | python3 -m json.tool | grep '"name"'
```

Vas a ver 7 herramientas, por ejemplo `search_curriculum`, `get_lab_details` y `get_progressive_hint`. Cada una trae una descripción y los parámetros que acepta: con eso el modelo decide cuándo usarla.

Para ver una definición completa en lugar de solo nombres:

```bash
curl -s $H $URL -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(next(t for t in d["result"]["tools"] if t["name"]=="get_lab_details"),indent=2,ensure_ascii=False))'
```

Identificá `name`, `description` e `inputSchema`. En esta herramienta, `required: ["lab_id"]` exige un ID de laboratorio; en `search_curriculum`, `query` es el texto que querés buscar. Esta ficha le permite al modelo armar los argumentos, pero el host y el servidor siguen teniendo que aplicar permisos y validar la ejecución.

**2.3 Llamar a una herramienta** (`tools/call`): buscá los labs de RAID.

```bash
curl -s $H $URL -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_curriculum","arguments":{"query":"RAID"}}}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["content"][0]["text"])' | head -30
```

La respuesta viene dentro de `result.content[0].text`; el `python3 -c` solo la saca para que se lea.

Ese es el intercambio MCP que puede usar un agente cuando le preguntás "¿qué labs de RAID hay?": el modelo propone la herramienta y sus argumentos, el host envía la llamada y luego usa el resultado para elaborar la respuesta. El modelo no abre el puerto ni ejecuta Python por sí mismo.

> **Para pensar:** ¿quién propone la herramienta, quién controla si se puede llamar y quién hace la búsqueda? (El modelo, el host y el servidor, respectivamente.)

## 3. Conectarle un agente (minutos 7 a 12)

Elegí **uno** que ya tengas de la Clase 2 o la Clase 3. Cliente y servidor deben estar en el mismo entorno para usar `127.0.0.1`: un agente remoto o dentro de otro contenedor tiene otro localhost. El hub genera configuración para estos clientes:

```bash
python3 ai/tutor/hub/hub.py config claude-code   # también: vscode, cline, goose
```

- **Claude Code:**
  ```bash
  claude mcp add --transport http labs http://127.0.0.1:8091/mcp
  claude mcp list          # tiene que decir: labs ... ✔ Connected
  ```
- **Codex CLI:** la sintaxis se comprobó con `codex mcp add --help` de la CLI instalada; falta probar la llamada desde una sesión Codex.
  ```bash
  codex mcp add labs --url http://127.0.0.1:8091/mcp
  codex mcp list
  codex                   # iniciar una sesión desde el repo
  ```
  La CLI registra la conexión en su configuración; no instala un modelo en el servidor. No reemplaces tu configuración existente para agregar el lab. Comprobá que el nombre `labs` no esté ocupado por otro servidor.
- **Antigravity IDE:** instrucciones contrastadas con la [documentación oficial](https://antigravity.google/docs/mcp), sin sesión gráfica probada en este lab. En el panel del agente: `…` → `MCP Servers` → `Manage MCP Servers` → `View raw config`. Integrá esta entrada en el mapa `mcpServers` existente, conservando las demás:
  ```json
  {
    "mcpServers": {
      "labs": {
        "serverUrl": "http://127.0.0.1:8091/mcp"
      }
    }
  }
  ```
  Recargá la conexión en el gestor MCP y comprobá que aparecen herramientas. Gemini CLI y Antigravity son clientes distintos; el comando `gemini mcp add` de abajo no configura automáticamente Antigravity.
- **Gemini CLI** (no probado en clase todavía):
  ```bash
  gemini mcp add --transport http labs http://127.0.0.1:8091/mcp
  ```
- **VS Code con Copilot** (no probado en clase todavía): `python3 ai/tutor/hub/hub.py config vscode --write` suma los MCP a `.vscode/mcp.json` (conserva lo que ya tenía y deja copia `.bak`).

El comando o la configuración solo registran la conexión. Abrí el chat o sesión del cliente y preguntale:

> Usá el MCP labs para buscar un laboratorio del curso sobre RAID. Leé la ficha del resultado y dame una pista de nivel 1, sin ejecutar el laboratorio. Citá el ID que recibiste.

Primero comprobamos explícitamente la integración. Después probá sin decirle qué herramienta usar:

- "¿Qué laboratorios del curso hay para practicar RAID? Dame dos ids."
- "Estoy en el lab lab-3.8-raid-mdadm, paso 2. Dame una pista de nivel 1, sin la solución."

Buscá el detalle de herramientas o registro de actividad de tu cliente. Anotá nombre de la tool, argumentos, ID recibido y cómo aparece en la respuesta. El nombre visible puede llevar un prefijo del servidor. Lo que acredita MCP es esa llamada real; que el agente afirme «consulté el curso» no alcanza. Si solo leyó archivos con la terminal, usó otro camino.

**Qué gana el alumno:** la búsqueda trae labs de este curso, la ficha da requisitos reales y `get_progressive_hint` devuelve instrucciones y datos para que el agente te dé una pista gradual. Seguís decidiendo qué practicar; la tool no formatea discos ni ejecuta el script del lab por pedir una pista.

**Cobertura:** Claude Code ya hizo una llamada real con este servidor (ver [plan](hub/PLAN_DE_ACCION.md)); la conexión de Codex, Antigravity, Gemini CLI y VS Code queda como prueba manual del alumno. No hace falta probarlos todos para terminar esta unidad.

## 4. Dos retos (minutos 12 a 15)

Bajá el servidor del hub para liberar el puerto: `python3 ai/tutor/hub/hub.py down labs`.

**Reto 1: esconder herramientas.** Levantá el servidor ocultando las pistas y la guía completa:

```bash
python3 ai/tutor/mcp/labs_mcp_server.py --transport http --port 8095 --exclude-tools get_progressive_hint,read_lab_guide
```

En otra terminal, pedí la lista de nuevo (con `URL=http://127.0.0.1:8095/mcp`): ¿cuántas herramientas hay ahora? Intentá llamar igual a `get_progressive_hint`: ¿qué responde? (Tiene que haber 5, y la llamada tiene que fallar con "herramienta deshabilitada".)

> **Para pensar:** ¿por qué conviene que el servidor oculte una herramienta, en vez de pedirle al modelo que no la use?

**Reto 2: ponerle llave.** Cortá el servidor con `Ctrl+C` y levantalo con un token:

```bash
MCP_HTTP_TOKEN=clase123 python3 ai/tutor/mcp/labs_mcp_server.py --transport http --port 8095
```

Repetí el `tools/list`: ¿qué código HTTP devuelve? Ahora agregá la llave a las cabeceras y probá otra vez:

```bash
curl -s -o /dev/null -w "%{http_code}\n" $H -H "Authorization: Bearer clase123" http://127.0.0.1:8095/mcp -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
```

(Sin token, 401; con token, 200.)

## Probar todo de una vez (docente)

El script [`demo_practica_15_min_mcp.sh`](demo_practica_15_min_mcp.sh) hace los mismos pasos que esta guía y comprueba cada resultado. Sirve para mostrarla en clase o para revisar que una máquina está lista antes de empezar:

```bash
./ai/tutor/demo_practica_15_min_mcp.sh            # interactivo: pausa con [ENTER] entre pasos
./ai/tutor/demo_practica_15_min_mcp.sh --auto 0   # sin pausas: termina con "TODO OK" o con los pasos que fallaron
./ai/tutor/demo_practica_15_min_mcp.sh --clean    # baja los servidores si quedó alguno
```

Sale con código 0 si todo funcionó y 1 si algo falló.

## Al terminar

```bash
python3 ai/tutor/hub/hub.py down     # baja lo que haya levantado el hub
```

Y cortá con `Ctrl+C` el servidor de los retos si sigue abierto.

**Si querés seguir:** la [Clase 8](GUIA_HUB_MCP.md) suma tres MCP más (certificaciones, libros y documentación oficial) detrás del mismo agente, y los conecta a Open WebUI.

## Si algo falla

- **`puerto en uso`:** otro programa usa el 8091 o el 8095. Bajá lo anterior (`hub.py down`) o usá otro puerto con `--port`.
- **`python3: command not found`:** en WSL, `sudo apt install python3`.
- **`curl` devuelve `Host no permitido`:** usá `127.0.0.1` en la URL, no la IP de tu máquina. Por seguridad, el servidor solo acepta conexiones locales.
- **El agente no ve las herramientas:** fijate que el servidor siga corriendo (`hub.py status`) y que la URL termine en `/mcp`.
