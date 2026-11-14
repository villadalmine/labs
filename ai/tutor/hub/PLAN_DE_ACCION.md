# Plan de acción — Hub Multi-MCP de clase (estado al 2026-11-14)

Este es el punto de entrada para retomar el trabajo: qué quedó hecho, qué se decidió, qué falta y quién lo hace.

## Dónde está cada cosa

| Qué | Dónde |
| :--- | :--- |
| Guía de uso del hub (docente y alumnos) | [`ai/tutor/GUIA_HUB_MCP.md`](../GUIA_HUB_MCP.md) |
| Práctica de 15 minutos para alumnos | [`ai/tutor/PRACTICA_15_MIN_MCP.md`](../PRACTICA_15_MIN_MCP.md) y su script de prueba `ai/tutor/demo_practica_15_min_mcp.sh` |
| Hub para cualquier máquina | `ai/tutor/hub/hub.py` (manifiesto `hub.json`, tests `test_hub.py`) |
| MCP de este repo | `ai/tutor/mcp/labs_mcp_server.py` (`--transport http`, puerto 8091) y el puente `ai/tutor/mcp/mcp_http.py` |
| Despliegue en el Dell | repo del homelab `AI-LEARNING`: `stacks/mcp-cursos`, `stacks/chat-ia`, `stacks/oss-docs`, `stacks/mcp-hub` |
| Runbooks del Dell | `docs/runbooks/mcp-cursos-instalar-y-conectar.md` y `docs/runbooks/chat-ia-comparar-modelo-tutor.md` (homelab) |
| Pendientes con dueño | `docs/pendientes/pendientes.yml` del homelab (ids abajo, en "Falta") |
| Notas privadas para dar clase | `NOTAS_CLASE.local.md` en la raíz de este repo (ignorado por git) |

## Estado

| Pieza | Estado | Probado |
| :--- | :--- | :--- |
| `hub.py` (doctor, setup, up, verify, corpus, config, webui) | Funciona | 13 tests en CI; setup desde cero de `oss-docs` el 2026-11-14 |
| MCP de `labs` por HTTP | Funciona | Práctica de 15 min en Fedora y en Ubuntu 24.04 limpio (TODO OK) |
| `study-cybercirujas` | Funciona | En el Dell (certificaciones :8571) |
| `rag-tutor` | Funciona | `4bb5d45` en GitHub y en el Dell (libros :8572) |
| `oss-docs-mcp` | **Público** desde el 2026-11-14 | [villadalmine/oss-docs-mcp](https://github.com/villadalmine/oss-docs-mcp), CI verde; el Dell corre `f30df02` (falta desplegar el arreglo, ver "Falta") |
| Open WebUI del Dell, modelo "Tutor de cursos" (`casa-tutor`) | Funciona | 3 de 3 fuentes con el modelo real |
| Clientes | Claude Code, Goose, Open WebUI y **Cline** probados; VS Code no | Ver tabla de clientes |

### Clientes

| Cliente | Resultado | Cómo se probó |
| :--- | :--- | :--- |
| Open WebUI | OK | Dell (`casa-tutor`, 4 MCP) y local con `hub.py webui up` |
| Claude Code | OK | Con token conecta y llamó a `search_curriculum`; sin token da un error limpio |
| Goose | OK | La config generada, en el Goose del Dell, llamó a `search_curriculum` (37 s) |
| Cline | OK (2026-11-14) | CLI oficial 3.0.74, que usa el mismo núcleo y la misma config que la extensión. Con la salida de `hub.py config cline` llamó a `labs__search_curriculum` y a `oss-docs__search_docs` + `read_chunks` |
| VS Code | **Sin probar** | No hay VS Code en la máquina de prueba y su chat con MCP pide sesión de GitHub Copilot |

## Arreglos que salieron de probar

- **Conexión corrupta tras un 401** (`mcp_http.py`): un POST rechazado dejaba el cuerpo sin leer y la conexión quedaba rota (`Bad request syntax`). Las respuestas 4xx ahora cierran la conexión, con test. El Dell ya corre ese commit.
- **Puerto ocupado** (`hub.py webui up`): avisa en vez de dejar el contenedor reiniciándose.
- **oss-docs con HTTP/2** (`oss-docs-mcp` `4ed4d4b`): GitHub rechazaba con HTTP 400 la bajada de kubeflow, llm-d, sglang y vllm en un clon desde cero. Ahora git usa HTTP/1.1, con test.
- **Tokens vacíos en el Dell** (homelab, `chat-ia.sh` 1.0.2): desde la laptop Linux, `secretos` buscaba los tokens en la ruta de la PC Windows y dejaba los archivos del Dell en 0 bytes. Ahora usa `~/.super6c/mcp-hub` si esa ruta no existe, y no sube un token vacío.

## Decisiones tomadas

| Fecha | Decisión | Por qué |
| :--- | :--- | :--- |
| 2026-11-14 | `oss-docs-mcp` se publica en GitHub | OK de Rino; así los alumnos lo instalan con `hub.py setup oss-docs` |
| 2026-11-14 | La P4 **sigue con qwen2.5 7B** para el tutor | Un 14B no entra en la P4 (7,5 GB) con el contexto del tutor. Qwen3-8B no fue claramente mejor (tabla abajo) |
| 2026-11-14 | El token del hub de `goose-rino` se rotó | Se había impreso en una conversación. El viejo da 401 |

Comparación del modelo del tutor (5 preguntas reales, mismo prompt y mismos MCP; runbook `chat-ia-comparar-modelo-tutor`):

| | qwen2.5-7b (actual) | Qwen3-8B Q4_K_M |
| :--- | :--- | :--- |
| Correctas | 5/5 | 4/5 |
| Tiempo total | 348 s | 516 s |
| Problema | inventó un `lab_id` en la pregunta que cruza temario y lab | en esa pregunta no consultó los labs |
| A favor | más rápido | leyó la doc antes de responder |

## Falta

| # | Qué | Quién | Pendiente del homelab |
| :--- | :--- | :--- | :--- |
| 1 | Probar VS Code: `python3 ai/tutor/hub/hub.py config vscode > .vscode/mcp.json` en una máquina con VS Code y Copilot, y anotar acá si conecta | Rino o un alumno, a mano | — |
| 2 | Que las pruebas no usen la cuenta ni la clave de una persona: `chat-ia.sh probar` entra como ealbano; hace falta una cuenta y una clave de prueba | Rino decide; después el agente chat-ia | `chat-ia-probar-sin-persona` |
| 3 | Desplegar `oss-docs-mcp` `4ed4d4b` en el Dell (fuera del domingo 04:50 UTC, que es el sync) | Agente chat-ia | `oss-docs-desplegar-http11` |
| 4 | Si se quiere seguir con el modelo: Qwen3-8B con razonamiento, o un prompt que obligue a buscar en los labs cuando la pregunta mezcla temario y lab | Rino decide | `tutor-modelo-mas-grande` |
| 5 | Abrir una sesión SSH al Dell tarda 1 a 3 minutos cuando hay carga | Agente servidor-t7910 | `dell-ssh-lento-en-picos` |
| 6 | Probar la práctica de 15 minutos con alumnos reales | Rino en clase | — |

## Reglas para quien retome

- **No probar como una persona.** Las claves de `~/.super6c/chat-bots/clientes/*.key` y los `.pass` son identidades de Rino, ealbano o soldan, y quedan en los logs con su nombre. Para pruebas: una clave o cuenta de prueba propia, con alta aprobada por Rino.
- **Para probar el tutor sin LiteLLM:** el runbook `chat-ia-comparar-modelo-tutor` usa un `llama-server` temporal en la P4, sin identidad.
- **Desde la laptop Linux:** los scripts del homelab pensados para la PC Windows pueden apuntar a `/c/Users/rino/...`. Mirar la ruta antes de subir secretos.
- **`/tmp` es un tmpfs chico:** el índice de oss-docs (1,2 GB) no entra. Usar un directorio en disco.
- **Placas del Dell:** CUDA numera la P4 como 0 y `nvidia-smi` como 1. Para elegir placa en CUDA usar `CUDA_DEVICE_ORDER=PCI_BUS_ID`.

## Cómo retomar

```bash
# Hub local (desde la raíz de este repo; los repos hermanos en la carpeta padre o en HUB_REPOS_DIR)
python3 ai/tutor/hub/hub.py doctor
python3 ai/tutor/hub/hub.py verify
python3 ai/tutor/hub/test_hub.py

# Práctica de los alumnos de punta a punta
./ai/tutor/demo_practica_15_min_mcp.sh --auto 0

# Dell
ssh dalmine 'sudo bash /opt/mcp-cursos/verificar.sh'                        # 13 OK
bash /var/home/dalmine/Nextcloud/Cursos/AI-LEARNING/stacks/chat-ia/chat-ia.sh verificar
```
