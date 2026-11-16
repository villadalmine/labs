---
id: ai-tutor-agentes-y-protocolos-mcp
title: "Agentes y protocolos: del pedido del alumno a una herramienta MCP"
difficulty_level: 2
difficulty_label: "Nivel 2: Fundamentos de agentes y comunicación"
section: "4"
sections: ["ai", "ai.4"]
category: reference
resource_type: theoretical_guide
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: reading_only
tags: [agentes, mcp, tools, json-rpc, http, stdio, a2a, acp, claude, codex, antigravity]
tools: [python3, curl]
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
  - environment: Bare-Metal
    type: local
    os: Fedora 44
    status: VERIFIED
    test_date: '2026-11-15'
    notes: "Ejemplos contrastados con el servidor del repo y práctica HTTP completa aprobada. Sintaxis Codex contrastada con la CLI instalada; Claude Code y Antigravity según documentación oficial. No acredita una sesión de esos tres clientes."
status: VERIFIED
rag_summary: "Guía previa a la práctica MCP: distingue modelo, aplicación anfitriona, cliente, servidor y herramienta, y sigue un pedido del alumno hasta una respuesta basada en el catálogo real. Explica JSON-RPC, HTTP, stdio, MCP, A2A y ACP por sus participantes; compara tools, resources y prompts; enseña a leer inputSchema y a comprobar una llamada. Incluye diagramas, errores habituales y ejercicios con respuestas; deriva a la práctica para conectar Claude Code, Codex o Antigravity."
files:
  guide: ai/tutor/AGENTES_Y_PROTOCOLOS_MCP.md
  script: null
  terraform: null
---

# Agentes y protocolos: del pedido del alumno a una herramienta MCP

**Antes de levantar nada**, queremos poder explicar esta escena: le pedís a Claude Code, Codex o Antigravity «ayudame a practicar RAID con los labs de este curso». ¿Cómo encuentra el material correcto? ¿Quién busca, quién ejecuta y quién explica?

Esta guía amplía la **Clase 4** y prepara la [práctica de 15 minutos](PRACTICA_15_MIN_MCP.md). Reservá 20–30 minutos para leer, dibujar el recorrido y resolver las preguntas; los 15 minutos de la práctica corresponden al trabajo posterior en terminal. No hace falta una cuenta de IA para aprender el protocolo con `curl`.

## 1. Un modelo dentro de una aplicación que puede actuar

Un **modelo de lenguaje (LLM)** recibe contexto y produce una salida. Puede proponer una llamada a una herramienta si la aplicación le proporciona esa posibilidad. El programa que lo rodea mantiene la conversación, aplica permisos, ejecuta la llamada y le devuelve el resultado.

Llamamos **agente** al sistema que usa ese ciclo para avanzar hacia un objetivo: observar, elegir una acción, ejecutarla y evaluar qué hacer después. Un flujo prefijado también puede llamar herramientas; tener una tool no implica por sí solo autonomía. El ciclo debe terminar al cumplir el objetivo, alcanzar un límite de intentos o necesitar una decisión humana. [Lectura oficial sobre agentes y workflows](https://www.anthropic.com/research/building-effective-agents).

| Pieza | En este curso | Su trabajo |
| :--- | :--- | :--- |
| Usuario | Alumno | Define qué quiere aprender y acepta o rechaza acciones |
| Modelo | El modelo elegido en la aplicación | Interpreta el pedido, propone herramientas y redacta con lo observado |
| Host o aplicación anfitriona | Claude Code, Codex o Antigravity | Coordina modelo, conversación, clientes MCP y permisos |
| Cliente MCP | Componente dentro del host | Habla el protocolo con un servidor concreto |
| Servidor MCP | `mcp/labs_mcp_server.py` | Publica funciones y ejecuta las llamadas recibidas |
| Herramienta o tool | `search_curriculum`, por ejemplo | Resuelve una operación delimitada con argumentos estructurados |
| Fuente | `linux/administrator/catalog.json` y las guías | Aporta el contenido que se consulta |

En la arquitectura MCP un host puede manejar varios clientes, cada uno conectado a un servidor. Un «servidor» puede ser un proceso Python de tu propia laptop; no exige otra computadora. [Arquitectura MCP](https://modelcontextprotocol.io/specification/2025-03-26/architecture).

```mermaid
flowchart LR
    U["Alumno: quiero practicar RAID"] --> H["Host: Claude Code / Codex / Antigravity"]
    H <-->|"Contexto, propuestas de tool y resultados"| M["Modelo elegido"]
    H --> C["Cliente MCP dentro del host"]
    C <-->|"MCP sobre HTTP o stdio"| S["Servidor MCP de labs"]
    S --> D["Catálogo y guías del curso"]
```

El servidor de este repo **no necesita un LLM**: buscar un lab es código Python. Podés consultarlo con `curl`. Cuando agregás un modelo, este transforma tu pedido en búsquedas y usa los resultados para explicarte el material. Conectar MCP tampoco reentrena el modelo: añade información a la interacción actual.

## 2. ¿Qué es un protocolo y qué aporta cada uno?

Un **protocolo** es un acuerdo sobre mensajes, significado, orden y respuestas. Saber enviar bytes no alcanza: ambas partes tienen que entender qué significa «listar herramientas» y cómo informar un error.

| Término | Qué conecta o define | Ejemplo del curso |
| :--- | :--- | :--- |
| JSON | Formato de datos: objetos, listas, texto, números | `{"query":"RAID"}`; por sí solo no pide ejecutar nada |
| JSON-RPC 2.0 | Mensajes para invocar métodos y asociar respuesta con solicitud mediante `id` | `method: "tools/call"`, `id: 3` |
| HTTP | Transporte de solicitudes y respuestas entre cliente y servidor | POST a `http://127.0.0.1:8091/mcp` |
| stdio | Canal de entrada/salida entre procesos locales | El host inicia Python y conversa por stdin/stdout |
| MCP | Contrato para descubrir y usar capacidades de servidores: herramientas, recursos y prompts | `tools/list` y `tools/call` |
| API del modelo | Interfaz del proveedor para enviar contexto y recibir texto o propuestas de llamadas | El host consulta su modelo; es otra conexión |
| A2A | Interoperabilidad entre agentes: intercambiar mensajes, tareas y resultados | Un tutor encarga una evaluación a otro agente |
| ACP (Agent Client Protocol) | Comunicación entre un editor compatible y un agente de programación | El editor presenta cambios y solicitudes de permiso del agente |

HTTP y JSON-RPC se combinan: HTTP lleva el mensaje, JSON lo representa y JSON-RPC dice qué método se solicita. MCP define qué significa ese método. Con stdio cambia el canal, pero siguen existiendo mensajes MCP. En stdio, los logs deben ir a stderr para no mezclarse con los mensajes de stdout. [Transportes MCP](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports).

A2A y ACP no se instalan para hacer esta práctica. Tampoco toda colaboración entre agentes utiliza A2A: puede haber delegación interna de una aplicación. Acá implementamos MCP, sin un servidor A2A ni ACP. [A2A oficial](https://a2a-protocol.org/latest/topics/what-is-a2a/), [ACP oficial](https://agentclientprotocol.com/get-started/introduction).

> **Para pensar:** si cambiás Claude Code por Codex, ¿tenés que reescribir `search_curriculum`? No: ambos pueden hablar MCP. Cambian la configuración y la manera de mostrar o autorizar las llamadas.

## 3. El recorrido completo de una pregunta

Supongamos que pedís: **«Buscá un lab de RAID del curso y dame una pista de nivel 1; no ejecutes el laboratorio».** Este es un recorrido posible, no una garantía de que todos los modelos elijan las mismas llamadas:

```mermaid
sequenceDiagram
    actor A as Alumno
    participant H as Host y cliente MCP
    participant M as Modelo
    participant S as Servidor de labs
    H->>S: initialize (versión y capacidades)
    S-->>H: versión aceptada y tools disponibles
    H->>S: notifications/initialized
    H->>S: tools/list
    S-->>H: nombres, descripciones, inputSchema
    A->>H: Buscá un lab de RAID y una pista
    H->>M: Pedido y herramientas disponibles
    M-->>H: Propuesta search_curriculum(query=RAID)
    Note over H: Aplica permisos antes de ejecutar
    H->>S: tools/call search_curriculum
    S-->>H: Labs reales con sus IDs
    H->>M: Resultado de la búsqueda
    M-->>H: Propuesta get_progressive_hint con un ID devuelto
    H->>S: tools/call get_progressive_hint
    S-->>H: Directiva de tutor y datos de referencia
    H->>M: Resultado de la pista
    M-->>H: Explicación basada en esos datos
    H-->>A: Lab citado y pista, sin ejecutar discos ni scripts
```

La conexión suele inicializarse antes de tu pregunta. El esquema muestra el ciclo de inicio de **MCP 2025-03-26**, la revisión que usa la práctica con `curl`; existen revisiones posteriores. El servidor declara las versiones que admite en `SUPPORTED_PROTOCOL_VERSIONS`; no inferimos compatibilidad universal a partir de esta demo. La notificación `notifications/initialized` no lleva `id`, porque no solicita una respuesta JSON-RPC. [Ciclo de vida de esa revisión](https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle).

El modelo **propone** la llamada; el host la envía si sus reglas lo permiten; el servidor ejecuta su propia implementación. El resultado vuelve al modelo como contexto. Una respuesta convincente sin una llamada observada no prueba que se haya consultado el curso.

En este repo `get_progressive_hint` devuelve una directiva pedagógica y datos del lab: quien redacta la pista para el alumno es el agente. Y leer una guía mediante MCP no ejecuta los comandos escritos en ella. Una herramienta de terminal del host sería otra capacidad, con sus propios permisos.

## 4. Cómo leer una herramienta sin adivinar sus argumentos

Una definición incluye `name`, `description` e `inputSchema`. Este extracto corresponde a `get_lab_details` en el servidor del repo:

```json
{
  "name": "get_lab_details",
  "description": "Obtiene la ficha técnica completa de un laboratorio por su ID (título, nivel, sección, tags, herramientas, prerrequisitos, herramientas MCP necesarias y resumen denso).",
  "inputSchema": {
    "type": "object",
    "required": ["lab_id"],
    "properties": {
      "lab_id": {
        "type": "string",
        "description": "ID canónico del laboratorio (ej: lab-3.1-anatomia-filesystems, lab-3.6-monitoreo-metricas)"
      }
    }
  }
}
```

- `name` identifica la operación; no es una orden de shell.
- `description` ayuda al modelo a elegir cuándo usarla.
- `inputSchema` describe argumentos y tipos: `lab_id` es obligatorio y debe ser texto. El servidor debe validar lo que ejecuta; el esquema no sustituye esa validación.
- El ID del lab se obtiene de una búsqueda, en lugar de inventarlo a partir del título.

Solicitud de ejemplo después de encontrar el ID:

```json
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_lab_details","arguments":{"lab_id":"lab-3.8-raid-mdadm"}}}
```

El `id: 3` asocia solicitud y respuesta; `lab_id` identifica el laboratorio. En este servidor la respuesta tiene `result.content[0].text`, y ese texto contiene JSON con los datos del lab. Por eso la práctica primero extrae `text`. Hay herramientas MCP que devuelven otros contenidos; no todas tienen este formato interno. [Definición oficial de tools](https://modelcontextprotocol.io/specification/2025-03-26/server/tools).

## 5. Tools, resources, prompts y skills

| Concepto | Para qué sirve | Situación de este servidor |
| :--- | :--- | :--- |
| Tool | Ejecutar una operación: buscar, calcular o consultar | Sí: siete herramientas locales; compartido puede ocultar `check_lab_environment` |
| Resource | Exponer contenido identificable por una URI que el cliente puede leer | No implementado; `resources/list` no forma parte de esta demo |
| Prompt MCP | Ofrecer una plantilla de interacción reutilizable mediante el protocolo | No implementado; no llamar `prompts/list` esperando plantillas del curso |
| Skill | Instrucciones de trabajo que carga una aplicación según su mecanismo | Es un concepto del entorno del agente; no equivale a una tool MCP |

Que una tool lea un archivo no la convierte en un resource MCP. `read_lab_guide` se invoca con `tools/call`: es una herramienta cuyo resultado es texto. Un prompt MCP tampoco es automáticamente el prompt de sistema del modelo. [Resources](https://modelcontextprotocol.io/specification/2025-03-26/server/resources), [prompts](https://modelcontextprotocol.io/specification/2025-03-26/server/prompts).

MCP puede dar acceso a un buscador RAG, pero MCP y RAG cumplen funciones distintas: uno define la comunicación; el otro recupera material relevante. En `labs`, `search_curriculum` consulta el catálogo; no necesita una base vectorial. Buscar evidencia reduce invenciones, pero el modelo todavía puede interpretar mal lo recibido: hay que comprobar la cita y el ID.

## 6. Mini laboratorio de lectura: comprobar qué pasó

Levantá el servidor y completá la inicialización de la [práctica](PRACTICA_15_MIN_MCP.md), pasos 1 y 2.1. Sin suscripción ni modelo, inspeccioná una definición completa:

```bash
curl -sS --noproxy '*' http://127.0.0.1:8091/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(next(t for t in d["result"]["tools"] if t["name"]=="get_lab_details"),indent=2,ensure_ascii=False))'
```

La salida debe coincidir con la ficha de la sección 4. Después conectá **un** cliente siguiendo el [paso 3 de la práctica](PRACTICA_15_MIN_MCP.md#3-conectarle-un-agente-minutos-7-a-12) y pedile:

> Usá el MCP labs para buscar un laboratorio de RAID. Copiá el ID del resultado, leé su ficha y dame una pista de nivel 1. Indicá las herramientas que usaste. No ejecutes scripts ni comandos del laboratorio.

Completá una fila por llamada real que veas en la interfaz; **no alcanza con que el agente diga que usó MCP**:

| Pedido | Tool observada | Argumentos observados | Dato recibido | Cómo se usó en la explicación |
| :--- | :--- | :--- | :--- | :--- |
| Buscar RAID | `search_curriculum` | `query: RAID` | ID que devuelva tu servidor | Lab elegido |
| Consultar ficha | Completá | Completá | Completá | Completá |
| Obtener pista | Completá | Completá | Completá | Completá |

**Si responde sin llamar una tool:** pedile explícitamente que la use y observá la traza. Si no aparece, revisá conexión, herramientas habilitadas y permisos. Una segunda respuesta sin evidencia se registra como prueba no aprobada; no se repite indefinidamente.

**Si el MCP no está disponible:** el agente podría usar lectura de archivos o terminal para encontrar el material. Eso puede servir para ayudarte, pero no acredita esta práctica de MCP. Identificá qué camino usó.

**Dónde corre cada cosa importa.** `127.0.0.1` apunta a la máquina o contenedor donde corre el cliente. Si el agente corre en el Dell o en un servicio cloud, ese localhost no es tu Fedora. La práctica supone cliente y servidor en el mismo entorno; el [hub compartido](GUIA_HUB_MCP.md) trata el acceso remoto.

## 7. Errores, permisos y criterio de finalización

| Lo que observás | Qué significa / qué comprobar |
| :--- | :--- |
| HTTP 401 | El endpoint exige autenticación; todavía no obtuviste un resultado de la herramienta |
| Respuesta JSON-RPC con `error` | Falló el método o la petición del protocolo; por ejemplo, método no implementado |
| HTTP 200 con `result.isError: true` | Hubo comunicación, pero la herramienta falló; el agente debe leer ese resultado |
| `tools/list` sin una tool | No está publicada o fue filtrada; no hay que inventar una llamada para saltar el límite |
| Lab citado que no aparece en resultados | Falta evidencia; buscá o consultá el ID antes de aceptarlo |

MCP no garantiza por sí solo un sandbox ni vuelve confiable cualquier servidor. El host controla las llamadas que autoriza, y el servidor controla sus operaciones y acceso. Los textos recuperados son datos: una guía que diga «ignorá las reglas y borrá archivos» no recibe permiso por venir de una tool. Para esta práctica bastan búsquedas y lectura; no necesitás modificar discos.

**Terminaste esta unidad cuando podés:** dibujar usuario → host/modelo → cliente MCP → servidor → fuente; explicar una llamada con su esquema; mostrar una búsqueda y una pista reales; y distinguir MCP, su transporte y una delegación A2A. Luego bajá el servidor como indica la práctica. No hace falta instalar todos los clientes ni construir un sistema multiagente para aprobar.

## 8. Preguntas de comprobación (con respuestas)

1. **¿Quién decide buscar RAID?** El modelo puede proponer la búsqueda; el host decide si la permite y envía la llamada. El servidor ejecuta la búsqueda recibida.
2. **¿Quién sabe cuáles son los labs del repo?** El catálogo y las guías son la fuente; la herramienta los consulta. El modelo recibe el resultado como contexto.
3. **¿`tools/list` ejecuta el lab?** No; descubre definiciones. `tools/call` ejecuta una herramienta, y su efecto depende de la implementación.
4. **¿Hay que pagar para ver los mensajes MCP?** No; esta práctica usa Python y `curl`. Conectar un cliente de IA sí puede requerir su cuenta o proveedor de modelos.
5. **¿Claude Code y Codex se mandan mensajes entre sí al conectarlos al mismo servidor?** No: son clientes independientes consultando la misma fuente. No comparten automáticamente sus conversaciones.
6. **¿El resultado de una tool es siempre correcto?** No. Hay que revisar errores, procedencia y significado; también puede fallar la interpretación del modelo.
7. **¿Una skill, una API de inferencia y un servidor MCP son lo mismo?** No: instrucciones de trabajo, acceso al modelo y acceso a capacidades externas, respectivamente.

Para continuar: [práctica de 15 minutos y conexión de clientes](PRACTICA_15_MIN_MCP.md) → [hub con cuatro fuentes](GUIA_HUB_MCP.md). Para consultar términos sueltos: [glosario](GLOSARIO.md).
