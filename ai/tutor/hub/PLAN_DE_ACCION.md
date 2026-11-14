# Plan de acción — Hub Multi-MCP de clase (estado al 2026-11-14)

Para iterar: qué quedó hecho, qué falta y en qué orden. La guía de uso es `ai/tutor/GUIA_HUB_MCP.md`; el despliegue del Dell vive en el repo del homelab (`stacks/mcp-cursos`, runbook `docs/runbooks/mcp-cursos-instalar-y-conectar.md`).

## Hecho

- Hub para cualquier máquina: `ai/tutor/hub/hub.py` (doctor, setup, up, status, verify, config para Open WebUI, VS Code, Cline, Goose y Claude Code, modo alumno con token). 11 tests en CI.
- Este repo expone su propio MCP por HTTP (`ai/tutor/mcp/labs_mcp_server.py --transport http`, puerto 8091) y un puente stdio a HTTP (`mcp_http.py bridge`, con `--exclude-tools`).
- Dell (srv-t7910): los 3 MCP de los cursos como servicios (labs :8570, certificaciones :8571, libros :8572), conectados a Open WebUI (modelo "Tutor de cursos", `casa-tutor`) y al hub agentgateway (`laboratorios`, `certificaciones`, `libros`). Probado de punta a punta con el modelo real: 3 de 3.

## Falta, en orden

1. **Abrir el PR de `update` a `main`** (la rama ya está subida) y dejar que corra el CI.
2. **Probar los clientes que solo se generaron, no se ejecutaron:** las configs de VS Code, Cline, Goose y Claude Code que escribe `hub.py config ...`. Probar cada una contra el hub local y anotar cuál falla.
3. **Probar una conversación real en local** con un modelo (Ollama o API) a través de Open WebUI levantado con `hub.py webui up`; hoy solo se probó el cliente MCP de Open WebUI, no un chat.
4. **Subir los 2 commits locales de `rag-tutor`** (`4bb5d45`, lectura en dos pasos). Hasta entonces los alumnos que clonen de GitHub tienen la versión vieja, y `hub.json` clona esa.
5. **Publicar `oss-docs-mcp`** (no tiene remoto público) o dejar la guía diciendo que es opcional y solo del docente. Hoy está así.
6. **Libros para alumnos:** `rag-tutor` no trae libros. Decidir si el docente publica el índice en el Dell (ya hecho, se usa con `HUB_URL_RAG_TUTOR`) o se arma un corpus chico de ejemplo.
7. **Mejorar el 7B con libros:** con el prompt actual contesta, pero tarda 3 a 5 minutos en CPU. Probar un modelo más grande por LiteLLM o esperar a que la P4 esté fría.
8. **Dell:** el MCP `ext-memoria` del hub se reaplica en cada instalación y reinicia `mcp-hub-memoria`. No es de este trabajo; avisar al dueño del hub.
9. **Dell:** al volver a indexar libros en la laptop, correr `stacks/mcp-cursos/scripts/subir-libros.sh`.

## Cómo retomar

- Estado del Dell: `ssh dalmine@192.168.178.90 'sudo bash /opt/mcp-cursos/verificar.sh'` (13 OK).
- Probar el chat: `bash <AI-LEARNING>/stacks/chat-ia/chat-ia.sh probar tutor ["pregunta"]`.
- Probar el hub local: `python3 ai/tutor/hub/hub.py doctor && python3 ai/tutor/hub/hub.py verify`.
