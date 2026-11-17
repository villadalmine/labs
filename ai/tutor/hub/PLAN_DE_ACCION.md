# Plan de acción — Hub Multi-MCP de clase (actualizado 2026-11-16)

Este es el punto de entrada para retomar el trabajo: qué quedó hecho, qué se decidió, qué falta y quién lo hace.

**Handover actualizado 2026-11-16:** leer [TRASPASO.md](TRASPASO.md) antes de retomar. Goose técnico validado en dos corridas; el verificador completo conserva un fallo de Open WebUI sin tools, registrado en el pendiente existente del modelo.

## Hitos y cierre de esta entrega

Pedido de Rino, 2026-11-15: retomar lo pendiente, marcar dónde va cada cosa y saber cuándo terminó todo, sin una lista interminable. El alcance de esta entrega son los siete hitos siguientes. **Estado: 5/7 cerrados (H06 el 2026-11-17); entrega completa todavía pendiente.** Las pruebas de ayer se distinguen de las repetidas hoy; no se certifica de nuevo el Dell por haber pasado una prueba local.

| Hito | Entregable / ubicación | Estado y evidencia | Responsable / siguiente paso | Se cierra cuando… |
| :--- | :--- | :--- | :--- | :--- |
| H01 | Hub HTTP local: `hub.py`, `test_hub.py`, `../mcp/mcp_http.py` | **Cerrado.** El 2026-11-15: 13/13 tests OK (HTTP nativo, puente, concurrencia, autenticación y exclusión). Práctica completa y versión didáctica ampliada: TODO OK en Fedora el 15; Ubuntu limpio probado el 14. Sin procesos de prueba restantes | Agente de labs; conservar evidencia abajo | La batería pasa y existe una ejecución completa de la práctica con limpieza; ambas condiciones están acreditadas |
| H02 | Cuatro fuentes en el Dell: homelab `stacks/mcp-cursos`, `stacks/oss-docs`, `stacks/mcp-hub` | **Cerrado, revalidado el 15.** Verificador de cursos: 13 OK, salida 0; labs 6 tools, study 4, libros 5. `list_projects` de oss-docs respondió sin error con 12 proyectos | Agente de labs / homelab; verificadores en «Cómo retomar» | Los cuatro MCP responden y el despliegue de oss-docs se verifica; ver estado y arreglos de esta página |
| H03 | Clientes ya admitidos y guías: `../GUIA_HUB_MCP.md`, `../PRACTICA_15_MIN_MCP.md` | **Cerrado con evidencia del 14.** Claude Code, Goose, Open WebUI y Cline CLI llamaron herramientas reales | Agente de labs; mantener explícita la cobertura de cada cliente | Cada cliente admitido tiene una llamada real registrada; Cline CLI no acredita su interfaz gráfica |
| H04 | Goose con identidad propia: homelab chat-ia/chat-bots/mcp-hub | **Cerrado 2026-11-15.** Cuenta y credenciales propias, idempotencia verificada; Goose aislado 56,8 s y completo 13,6 s, par exitoso casa__conocimiento_buscar y final no vacío. El completo rc=1 por Open WebUI sin tools, conservado en el pendiente del modelo | No repetir altas; evidencia en TRASPASO.md | Objetivo específico: Goose con identidad técnica y llamada real sin pasos saltados; cumplido |
| H05 | VS Code + Copilot: `hub.py config vscode --write` | **Pendiente de sesión interactiva.** Desde 2026-11-17 `--write` integra la config en `.vscode/mcp.json` sin pisar lo existente (2 tests). Generar JSON no demuestra una conexión | Rino o alumno con VS Code y Copilot | En una sesión real aparece el MCP y `search_curriculum` devuelve un laboratorio; registrar fecha, versión y resultado |
| H06 | SSH al Dell durante picos: homelab, ID `dell-ssh-lento-en-picos` | **Cerrado 2026-11-17.** Causa: ráfagas de `systemctl daemon-reload` (85-125/h, ~1 s cada una, 854 desde el 13/11) que agentes disparan por SSH desde instaladores; durante la recarga PID1 no atiende a logind y la sesión espera. PSI de VictoriaMetrics bajo en las ventanas lentas: no era CPU/IO. Reproducido: SSH 0,25 s → 11 s con 10 recargas. Arreglo: envoltorio `/usr/local/sbin/systemctl` (homelab `stacks/dell-base` 1.2.0, runbook `dell-recarga-systemd.md`) que omite la recarga si nada cambió; verificado: 10 recargas → 0 reales, SSH 0,18-0,27 s con load 10-13 | servidor-t7910; si una unit editada no toma, mirar `journalctl -t recarga-systemd` | Cumplido: causa documentada y sesiones nuevas rápidas bajo la misma ráfaga |
| H07 | Uso en clase: `../PRACTICA_15_MIN_MCP.md`, registro en [REGISTRO_CLASE.md](REGISTRO_CLASE.md) | **Pendiente de clase real.** La ejecución automatizada no sustituye a los alumnos | Rino en la próxima clase | Un alumno termina la práctica, conecta un cliente y completa los dos retos; registrar duración, resultado y cualquier fallo que impida terminar |

**Criterio de cierre técnico:** H01–H06 cerrados. **Criterio de cierre total:** H01–H07 cerrados, fecha de cierre escrita aquí y ningún fallo que impida completar la práctica. El cierre técnico (H01–H06) queda pendiente solo de H05; hay 5/7 hitos cerrados. H05 requiere una sesión real de VS Code/Copilot y H07 una clase con alumno; ambos dependen de participación humana. H04 de identidad técnica está cerrado; el fallo de Open WebUI sin tools sigue como limitación conocida. No hay fecha de fin acreditada mientras H05 y H07 sigan abiertos.

Para evitar volver a empezar: al cerrar un hito se registra fecha, prueba y resultado en su fila. Solo se reabre ante una regresión demostrada. Las ideas nuevas se anotan como una entrega posterior y no aumentan estos siete hitos. Si una comprobación falla, se conserva el error y el próximo paso; no se repite sin un cambio o evidencia nueva. El problema del modelo queda registrado como limitación y experimento opcional, no como una comparación sin fin; si impide terminar la práctica real, se registra como fallo de H07.

### Historial de verificaciones — anterior al cierre H04

- Última verificación completada: `python3 ai/tutor/hub/test_hub.py`: **13 tests, OK**. El primer intento dentro del sandbox falló al crear sockets (`PermissionError: [Errno 1] Operation not permitted`); la misma batería fuera del sandbox pasó. No fue una regresión del hub.
- La primera repetición de `demo_practica_15_min_mcp.sh --auto 0` se interrumpió antes de ejecutar al reiniciarse la sesión. Se retomó y terminó en **TODO OK**; después la versión ampliada también terminó en **TODO OK**, incluidos `notifications/initialized` (202), esquema real y retos (401 sin token, 200 con token). Sin procesos de prueba restantes.
- Dell: `sudo -n bash /opt/mcp-cursos/verificar.sh`: **13 OK, salida 0**. `list_projects` de oss-docs: 12 proyectos, `isError: false`. H02 revalidado; no se repitieron pruebas de generación con modelos.
- H06: conexión SSH sin ControlMaster completada con carga media de 10,83/10,72/8,17. `ssh.service` y `systemd-logind.service` sin pesos CPU/IO explícitos; 27 sesiones. En el journal de las últimas 24 h se conservan tres timeouts de abandono de scopes del 14 (10:52, 11:06 y 11:17). Eso confirma el antecedente, no una causa ni una corrección. No se cambiaron servicios ni VMs; el incidente sigue abierto.
- Próxima acción: H05 con sesión de VS Code/Copilot disponible, H06 durante un pico de IO comparable o H07 en clase. H04 no se reabre por el fallo independiente del modelo de Open WebUI.
- Continuación H04: fuente guardada en el homelab, backup normal en `~/.local/state/chat-ia-h04-20261115`. Preflight de 118 archivos desplegados de chat-bots y mcp-hub: cero diferencias ajenas. `cuentas-unix --check`: solo el alta de prueba; aplicación: `ok=1 changed=1 failed=0`. Instalador chat-bots: clave propia entregada, modelos exclusivamente locales, 10 rpm y 100 pedidos/día. Runbook: homelab `docs/runbooks/chat-ia-pruebas-identidad.md`. No cerrar H04 hasta prueba E2E y segunda corrida sin cambios.
- H06, continuación: Dell con load 4,77/4,84/4,93 y GPUs en reposo (M4000 39 °C, P4 37 °C); sin errores de logind en las últimas dos horas. No reproduce el pico original. No se aplican cambios de pesos CPU/IO sin evidencia de causa.
- H06, ampliación de solo lectura 2026-11-16: logs del 14/11 muestran clave aceptada 11:18:07, `pam_unix(sshd:session): session opened` 11:18:53 y nuevos eventos de logind 11:19:46; el stack PAM tiene `pam_systemd.so` opcional. Esto acota la demora al tramo pam_systemd/logind de apertura/registro, pero no explica por qué se retrasó. Sin OOM/blocked-task/I/O-error en kernel ni PSI/sysstat histórico para esa ventana. Evidencia actual e histórica resumida en `/home/dalmine/.local/state/chat-ia-h04-20261115/resultados/h06-ssh-20261116.json`. Sigue abierto hasta que la demora y su mecanismo se reproduzcan o correlacionen con datos suficientes bajo presión comparable.
- Cierre de esta pasada: hub TODO OK; chat-ia TODO OK y segunda aplicación changed=0; chat-bots y mcp-hub sin cambios. E2E FALLAS: 1 por JSONDecodeError de Goose. Evidencias persistidas en `~/.local/state/chat-ia-h04-20261115/resultados/`; stdout remoto `/var/lib/chat-ia/pruebas/goose-qufw30wq.json` (root 600). No hay procesos de esta prueba activos. Detalle completo en [TRASPASO.md](TRASPASO.md).

## Ampliación didáctica solicitada el 2026-11-15 — cerrada

Entrega separada de H01–H07 para conservar su alcance. Rino pidió contexto sobre agentes, protocolos, herramientas y cómo los usan Claude, Codex y Antigravity.

| Hito | Entregable | Estado / aceptación |
| :--- | :--- | :--- |
| D01 | [`AGENTES_Y_PROTOCOLOS_MCP.md`](../AGENTES_Y_PROTOCOLOS_MCP.md): unidad previa de 20–30 min, diagramas y ejercicios con respuestas | **Cerrado 2026-11-15.** Distingue modelo/host/cliente/servidor/tool, JSON-RPC/HTTP/stdio/MCP/A2A/ACP, esquema de argumentos y ciclo de llamada con el catálogo real |
| D02 | Práctica de 15 min y demo ampliadas | **Cerrado 2026-11-15.** Explica para qué ayuda el MCP, enseña el esquema y la notificación de inicio, agrega instrucciones Codex/Antigravity con cobertura de pruebas explícita y exige observar una llamada real |
| D03 | Índices, glosario y comprobaciones | **Cerrado 2026-11-15.** Enlaces desde README raíz y tutor, aclaraciones MCP/A2A y RAG. 52 labs con validación estricta, guía nueva validada contra el esquema, ejemplos JSON contrastados con el servidor y enlaces locales comprobados. Demo ampliada: TODO OK |

**Ampliación terminada el 2026-11-15: 3/3.** Los inicios de sesión de Codex y Antigravity no se ejecutaron; sus instrucciones se contrastaron con `codex mcp add --help` y documentación oficial de Antigravity. Se ofrece elegir un cliente, no una nueva obligación de probar todos. La prueba con alumnos sigue siendo H07. No se agregaron guías de IA al catálogo Linux: el índice de esta unidad es `ai/tutor/README.md`, como en la práctica previa.

## Dónde está cada cosa

| Qué | Dónde |
| :--- | :--- |
| Guía de uso del hub (docente y alumnos) | [`ai/tutor/GUIA_HUB_MCP.md`](../GUIA_HUB_MCP.md) |
| Práctica de 15 minutos para alumnos | [`ai/tutor/PRACTICA_15_MIN_MCP.md`](../PRACTICA_15_MIN_MCP.md) y su script de prueba `ai/tutor/demo_practica_15_min_mcp.sh` |
| Hub para cualquier máquina | `ai/tutor/hub/hub.py` (manifiesto `hub.json`, tests `test_hub.py`) |
| MCP de este repo | `ai/tutor/mcp/labs_mcp_server.py` (`--transport http`, puerto 8091) y el puente `ai/tutor/mcp/mcp_http.py` |
| Despliegue en el Dell | repo del homelab `AI-LEARNING`: `stacks/mcp-cursos`, `stacks/chat-ia`, `stacks/oss-docs`, `stacks/mcp-hub` |
| Runbooks del Dell | `docs/runbooks/mcp-cursos-instalar-y-conectar.md` y `docs/runbooks/chat-ia-comparar-modelo-tutor.md` (homelab) |
| Pendientes con dueño | `docs/pendientes/pendientes.yml` del homelab (ids abajo, en "Pendientes por ubicación") |
| Notas privadas para dar clase | `NOTAS_CLASE.local.md` en la raíz de este repo (ignorado por git) |

## Estado

| Pieza | Estado | Probado |
| :--- | :--- | :--- |
| `hub.py` (doctor, setup, up, verify, corpus, config, webui) | Funciona | 13 tests en CI; setup desde cero de `oss-docs` el 2026-11-14 |
| MCP de `labs` por HTTP | Funciona | Práctica de 15 min en Fedora y en Ubuntu 24.04 limpio (TODO OK) |
| `study-cybercirujas` | Funciona | En el Dell (certificaciones :8571) |
| `rag-tutor` | Funciona | `4bb5d45` en GitHub y en el Dell (libros :8572) |
| `oss-docs-mcp` | **Público** desde el 2026-11-14 | [villadalmine/oss-docs-mcp](https://github.com/villadalmine/oss-docs-mcp), CI verde. El Dell corre `e807f38` (con el arreglo HTTP/1.1) y ahora indexa 12 proyectos |
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
| Codex CLI | **Sintaxis comprobada; llamada sin probar** (2026-11-15) | `codex mcp add --help` local confirma `--url`; instrucciones en la práctica |
| Antigravity IDE | **Configuración documentada; sesión sin probar** (2026-11-15) | Documentación oficial consultada: `mcpServers` / `serverUrl`; instrucciones en la práctica |

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
| 2026-11-14 | El prompt del tutor **no se cambia** | Un prompt que obliga a buscar primero en los labs no mejoró la pregunta que cruza temario y lab (4/5 igual, y más lento) |
| 2026-11-14 | Las pruebas del chat usan la cuenta **`prueba`** | Ningún agente prueba con la cuenta de una persona. `chat-ia.sh probar` ya no entra como Rino ni como ealbano |

Comparación del modelo del tutor (5 preguntas reales, mismo prompt y mismos MCP; runbook `chat-ia-comparar-modelo-tutor`):

| | qwen2.5-7b (actual) | Qwen3-8B Q4_K_M |
| :--- | :--- | :--- |
| Correctas | 5/5 | 4/5 |
| Tiempo total | 348 s | 516 s |
| Problema | inventó un `lab_id` en la pregunta que cruza temario y lab | en esa pregunta no consultó los labs |
| A favor | más rápido | leyó la doc antes de responder |

Esas dos corridas fueron en la M4000. En la P4 real el 7B tarda 98 s en total, unas 3,5 veces menos.

Otra señal de que el 7B no alcanza: con la cuenta de prueba, el modelo de docs (`casa-oss-docs`) contestó **3 de 3 veces sin llamar a `search_docs`** e inventó una URL (el 2026-11-11 había fallado 1 de 3). `casa-tutor` sí usa sus herramientas (3 de 3).

## Pendientes por ubicación (referencia a los hitos)

| # | Qué | Quién | Pendiente del homelab |
| :--- | :--- | :--- | :--- |
| H05 | Probar VS Code: correr `python3 ai/tutor/hub/hub.py config vscode --write` (integra en `.vscode/mcp.json` y conserva lo existente); usar una máquina con VS Code y Copilot | Rino o un alumno, a mano | — |
| H04 (cerrado) | Identidad técnica Goose y llamada real verificadas; el fallo Open WebUI sin tools se conserva en el pendiente del modelo | Operador chat-ia; sin nuevas altas | chat-ia-probar-sin-persona: hecho |
| Posterior, opcional | Qwen3-8B con razonamiento, si se decide experimentar; corte térmico a 80 °C. No bloquea los siete hitos ni se ejecuta automáticamente al retomar | Rino decide | `tutor-modelo-mas-grande` |
| H06 | Abrir una sesión SSH al Dell tarda 1 a 3 minutos cuando hay carga | Operador servidor-t7910 | `dell-ssh-lento-en-picos` |
| H07 | Probar la práctica de 15 minutos con alumnos reales | Rino en clase | — |

## Reglas para quien retome

- **No probar como una persona.** Las claves de `~/.super6c/chat-bots/clientes/*.key` y los `.pass` son identidades de Rino, ealbano o soldan, y quedan en los logs con su nombre. Para pruebas: una clave o cuenta de prueba propia, con alta aprobada por Rino.
- **Para probar el chat:** `chat-ia.sh probar` entra con la cuenta de Open WebUI `prueba`. Para comparar modelos sin LiteLLM, el runbook `chat-ia-comparar-modelo-tutor` usa un `llama-server` temporal en la P4, sin identidad.
- **La P4 se calienta:** en una prueba larga llegó a 89 °C. Todo lo que la use tiene que cortar a 80 °C, como `llm@p4` y el comparador (1.1.1).
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


### Cierre H04 — 2026-11-15 noche

Parser y evidencia estricta: 8 tests OK; replay anterior rechazado correctamente. Goose técnico aislado TODO OK (56,8 s) y Goose dentro del verificador completo OK (13,6 s). El completo terminó FALLAS:1 porque Open WebUI respondió sin tools e inventó una cita; se conserva el control y la evidencia y se anota en tutor-modelo-mas-grande. No se afirma verificador completo verde. Pendiente de identidad cerrado. Último estado vigente: [TRASPASO.md](TRASPASO.md).
