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
| 2 | Configs de los clientes | Hecho (salvo VS Code y Cline) | **Claude Code**: con token conecta, sin token da un error limpio, y una conversación real llamó a `search_curriculum`. **Goose**: la config generada, en el Goose del Dell, llamó a `search_curriculum` y contestó en 37 s. **VS Code y Cline**: son apps gráficas no instaladas acá; el JSON generado es válido y sigue su formato documentado. Falta probarlos a mano en la máquina de un alumno |
| 3 | Conversación real con un modelo | Hecho | Dell: Open WebUI + modelo + los 4 MCP (3 de 3 fuentes). Local: `hub.py webui up` con el LiteLLM del Dell (`OPENAI_API_BASE_URL`) y `labs`: el modelo llamó a `search_curriculum` y contestó en 12 s. Claude Code con `labs` y con `rag-tutor` local también |
| 4 | Subir los commits de `rag-tutor` | Hecho | `4bb5d45` está en GitHub y es el que corre en el Dell |
| 5 | `oss-docs-mcp` público | No se puede | El repo no tiene remoto y tiene 14 archivos sin commitear de otra sesión. Queda como servidor del docente (`HUB_URL_OSS_DOCS`); la guía ya lo dice |
| 6 | Libros para alumnos | Hecho | `hub.py corpus` indexa los labs de este repo como libro `labs-practicos` (88 s; 13 tests) |
| 7 | 7B con libros muy lento | Resuelto | Con la P4 fría (51 °C) la pregunta de libros tarda 37 s; con la P4 caliente cae a CPU y tarda 3 a 5 minutos |
| 8 | `ext-memoria` se reaplica | No es un defecto | Los archivos de `stacks/memoria` los edita otra sesión y el instalador reinicia el servicio cuando cambian sus datos. Hoy el Dell y el repo son idénticos |
| 9 | Reindexar libros | Documentado | `stacks/mcp-cursos/scripts/subir-libros.sh` |

`hub.py webui up` ahora avisa si el puerto está ocupado (antes el contenedor quedaba reiniciándose; en esta laptop el 3000 lo usa un `kubectl port-forward`).

Se arregló además un fallo real que apareció al probar Claude Code sin token: el servidor HTTP dejaba sin leer el cuerpo de un POST rechazado y la conexión quedaba corrupta (`Bad request syntax`). Ahora las respuestas 4xx cierran la conexión (con test). El Dell corre ya ese commit.

## Falta

1. **Probar VS Code y Cline** a mano en una máquina que los tenga (por ejemplo la de un alumno) y anotar acá si conectan.
2. **Decisión de Rino:** darle remoto a `oss-docs-mcp` si quiere que los alumnos lo usen (hoy tiene cambios sin commitear de otra sesión).
3. **Decisión de Rino:** un modelo más grande para el tutor si quiere respuestas rápidas aunque la P4 esté caliente. Revisado el 2026-11-14, sin gastar hay tres caminos:
   - el 27B en CPU de `llama-server :8080`: es intocable y lo comparte el Workspace Docente, así que no se usa sin su OK;
   - un 14B Q3 en la P4 de 8 GB: hay que bajar el modelo y cambiar `stacks/goose-servicio`. Es la opción recomendada;
   - GPU alquilada o nube: cuestan plata.

   Queda en el pendiente `tutor-modelo-mas-grande` del homelab.

## Cómo retomar

- Estado del Dell: `ssh dalmine@192.168.178.90 'sudo bash /opt/mcp-cursos/verificar.sh'` (13 OK).
- Probar el chat: `bash <AI-LEARNING>/stacks/chat-ia/chat-ia.sh probar tutor ["pregunta"]`.
- Probar el hub local: `python3 ai/tutor/hub/hub.py doctor && python3 ai/tutor/hub/hub.py verify`.
