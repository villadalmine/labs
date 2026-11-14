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
    notes: "Clon limpio desde GitHub: clonar, levantar y verificar tardó 4 s. Probados las tres llamadas con curl, los dos retos (herramientas ocultas y token) y la conexión desde Claude Code. Gemini CLI y VS Code no se probaron."
environments:
  - "Bare-Metal"
  - "WSL2"
operating_systems:
  - "Fedora 44"
  - "Ubuntu 24.04 LTS"
status: "PASSED"
rag_summary: "Práctica corta para clase: el alumno levanta el servidor MCP de los laboratorios del curso con un comando, le habla a mano con curl (initialize, tools/list, tools/call) para ver lo que hace un agente por debajo, le conecta un agente que ya tenga (Claude Code, Gemini CLI o VS Code) y hace dos retos: esconder herramientas y protegerlo con un token."
files:
  guide: "ai/tutor/PRACTICA_15_MIN_MCP.md"
  script: "ai/tutor/hub/hub.py"
  terraform: null
---

# Práctica de 15 minutos: tu primer servidor MCP

En las clases anteriores vimos qué es MCP: la forma estándar en que un agente de IA descubre y usa herramientas. Hoy vas a **levantar uno con tus manos**, hablarle sin ningún agente para ver qué pasa por debajo, y después conectarle un agente de verdad.

**Qué necesitás:** Linux o WSL, con `python3`, `git` y `curl`. No hace falta instalar nada más: el servidor solo usa la biblioteca estándar de Python.

| Minutos | Qué hacés | Qué aprendés |
|---|---|---|
| 0 a 3 | Clonar y levantar el servidor | Un MCP es un proceso que escucha por HTTP |
| 3 a 7 | Hablarle a mano con `curl` | Lo que hace un agente: presentarse, pedir la lista de herramientas, llamar a una |
| 7 a 12 | Conectarle un agente | El agente elige solo qué herramienta usar |
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

**2.2 Pedir la lista de herramientas** (`tools/list`): esto es lo que el agente lee para saber qué puede hacer.

```bash
curl -s $H $URL -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | python3 -m json.tool | grep '"name"'
```

Vas a ver 7 herramientas, por ejemplo `search_curriculum`, `get_lab_details` y `get_progressive_hint`. Cada una trae una descripción y los parámetros que acepta: con eso el modelo decide cuándo usarla.

**2.3 Llamar a una herramienta** (`tools/call`): buscá los labs de RAID.

```bash
curl -s $H $URL -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_curriculum","arguments":{"query":"RAID"}}}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["content"][0]["text"])' | head -30
```

La respuesta viene dentro de `result.content[0].text`; el `python3 -c` solo la saca para que se lea.

Eso es exactamente lo que hace un agente cuando le preguntás "¿qué labs de RAID hay?": elige la herramienta, arma los argumentos y te resume la respuesta.

> **Para pensar:** ¿quién decide qué herramienta usar, el servidor o el modelo? (El modelo. El servidor solo ofrece y ejecuta.)

## 3. Conectarle un agente (minutos 7 a 12)

Usá el que ya tengas de la Clase 2 o la Clase 3. El hub te da la configuración exacta:

```bash
python3 ai/tutor/hub/hub.py config claude-code   # también: vscode, cline, goose
```

- **Claude Code:**
  ```bash
  claude mcp add --transport http labs http://127.0.0.1:8091/mcp
  claude mcp list          # tiene que decir: labs ... ✔ Connected
  ```
- **Gemini CLI** (no probado en clase todavía):
  ```bash
  gemini mcp add --transport http labs http://127.0.0.1:8091/mcp
  ```
- **VS Code con Copilot** (no probado en clase todavía): guardá lo que imprime `hub.py config vscode` en `.vscode/mcp.json`.

Ahora preguntale al agente, sin decirle qué herramienta usar:

- "¿Qué laboratorios del curso hay para practicar RAID? Dame dos ids."
- "Estoy en el lab lab-3.8-raid-mdadm, paso 2. Dame una pista de nivel 1, sin la solución."

Fijate en la pantalla: el agente te muestra qué herramienta llamó y con qué argumentos. Es lo mismo que hiciste a mano en el paso 2.

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
