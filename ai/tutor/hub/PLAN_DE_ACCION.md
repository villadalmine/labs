# Plan de acción — Hub Multi-MCP de clase (estado al 2026-11-14)

Para iterar: qué quedó hecho, qué falta y en qué orden. La guía de uso es `ai/tutor/GUIA_HUB_MCP.md`; el despliegue del Dell vive en el repo del homelab (`stacks/mcp-cursos`, runbook `docs/runbooks/mcp-cursos-instalar-y-conectar.md`).

## Hecho

- Hub para cualquier máquina: `ai/tutor/hub/hub.py` (doctor, setup, up, status, verify, config para Open WebUI, VS Code, Cline, Goose y Claude Code, modo alumno con token). 11 tests en CI.
- Este repo expone su propio MCP por HTTP (`ai/tutor/mcp/labs_mcp_server.py --transport http`, puerto 8091) y un puente stdio a HTTP (`mcp_http.py bridge`, con `--exclude-tools`).
- Dell (srv-t7910): los 3 MCP de los cursos como servicios (labs :8570, certificaciones :8571, libros :8572), conectados a Open WebUI (modelo "Tutor de cursos", `casa-tutor`) y al hub agentgateway (`laboratorios`, `certificaciones`, `libros`). Probado de punta a punta con el modelo real: 3 de 3.

## Revisado el 2026-11-14 (punto por punto)

| # | Punto | Estado | Evidencia |
|---|---|---|---|
| 1 | PR de `update` a `main` | Hecho | PR #15 mergeado (`9179fd0`) con el CI en verde |
| 2 | Configs de los clientes | Hecho (salvo VS Code) | **Claude Code**: con token conecta, sin token da un error limpio, y una conversación real llamó a `search_curriculum`. **Goose**: la config generada, en el Goose del Dell, llamó a `search_curriculum` y contestó en 37 s. **VS Code y Cline**: son apps gráficas no instaladas acá; el JSON generado es válido y sigue su formato documentado. Falta probarlos a mano en la máquina de un alumno |
| 3 | Conversación real con un modelo | Hecho | Dell: Open WebUI + modelo + los 4 MCP (3 de 3 fuentes). Local: `hub.py webui up` con el LiteLLM del Dell (`OPENAI_API_BASE_URL`) y `labs`: el modelo llamó a `search_curriculum` y contestó en 12 s. Claude Code con `labs` y con `rag-tutor` local también |
| 4 | Subir los commits de `rag-tutor` | Hecho | `4bb5d45` está en GitHub y es el que corre en el Dell |
| 5 | `oss-docs-mcp` público | Hecho (2026-11-14) | Con el OK de Rino: [villadalmine/oss-docs-mcp](https://github.com/villadalmine/oss-docs-mcp), con el historial revisado sin secretos. `hub.py setup oss-docs` desde cero clona, instala e indexa 12 proyectos (1,2 GB) y `verify` da OK. Se arregló de paso un fallo real: GitHub rechazaba por HTTP/2 la bajada de kubeflow, llm-d, sglang y vllm (ahora git usa HTTP/1.1) |
| 6 | Libros para alumnos | Hecho | `hub.py corpus` indexa los labs de este repo como libro `labs-practicos` (88 s; 13 tests) |
| 7 | 7B con libros muy lento | Resuelto | Con la P4 fría (51 °C) la pregunta de libros tarda 37 s; con la P4 caliente cae a CPU y tarda 3 a 5 minutos |
| 8 | `ext-memoria` se reaplica | No es un defecto | Los archivos de `stacks/memoria` los edita otra sesión y el instalador reinicia el servicio cuando cambian sus datos. Hoy el Dell y el repo son idénticos |
| 9 | Reindexar libros | Documentado | `stacks/mcp-cursos/scripts/subir-libros.sh` |

`hub.py webui up` ahora avisa si el puerto está ocupado (antes el contenedor quedaba reiniciándose; en esta laptop el 3000 lo usa un `kubectl port-forward`).

Se arregló además un fallo real que apareció al probar Claude Code sin token: el servidor HTTP dejaba sin leer el cuerpo de un POST rechazado y la conexión quedaba corrupta (`Bad request syntax`). Ahora las respuestas 4xx cierran la conexión (con test). El Dell corre ya ese commit.

## Falta

1. **Probar VS Code** a mano en una máquina que lo tenga (por ejemplo la de un alumno) y anotar acá si conecta. **Cline ya está probado** (2026-11-14): la CLI oficial 3.0.74, que usa el mismo núcleo y la misma config que la extensión, llamó a `labs` y `oss-docs` con la salida de `hub.py config cline`.
2. **Modelo más grande para el tutor: probado, sin cambio.** Con el OK de Rino (2026-11-14):
   - Un 14B no entra en la P4 de 7,5 GB con el contexto que necesita el tutor.
   - Se comparó el 7B actual con Qwen3-8B con 5 preguntas reales del tutor:

     | | qwen2.5-7b (actual) | Qwen3-8B |
     | :--- | :--- | :--- |
     | Correctas | 5/5 | 4/5 |
     | Tiempo total | 348 s | 516 s |
     | Problemas | inventó un `lab_id` en la pregunta de dos fuentes | no consultó los labs en esa pregunta |
     | A favor | más rápido | leyó la doc antes de responder |

   - No es claramente mejor, así que la P4 sigue con el 7B. El detalle está en el pendiente `tutor-modelo-mas-grande` del homelab.

## Cómo retomar

- Estado del Dell: `ssh dalmine@192.168.178.90 'sudo bash /opt/mcp-cursos/verificar.sh'` (13 OK).
- Probar el chat: `bash <AI-LEARNING>/stacks/chat-ia/chat-ia.sh probar tutor ["pregunta"]`.
- Probar el hub local: `python3 ai/tutor/hub/hub.py doctor && python3 ai/tutor/hub/hub.py verify`.
