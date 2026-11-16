---
id: labs-hub-mcp-traspaso-20261116
title: "Traspaso del Hub MCP: estado, evidencia y próximos pasos"
tipo: reporte
version: 1.2.0
fecha_ultimo_cambio: '2026-11-16'
categoria: continuidad
dueno_agente: chat-ia
tags: [traspaso, hitos, mcp, goose, clases]
---

# Traspaso — MCP Hub y práctica de clase (actualizado 2026-11-16)

**Estado: 4/7 hitos cerrados. La ampliación didáctica D01–D03 está terminada (3/3).** H04 está cerrado por identidad técnica y llamadas Goose reales. El verificador completo conserva un fallo de Open WebUI sin tools. No declarar la entrega total hasta cerrar H05–H07 y registrar la fecha. Plan y aceptación: [PLAN_DE_ACCION.md](PLAN_DE_ACCION.md).

## Para retomar en la próxima sesión

1. Abrir `/var/home/dalmine/Nextcloud/Repos/labs`, rama `main`; leer primero este archivo y luego `ai/tutor/hub/PLAN_DE_ACCION.md`.
2. Ejecutar `git status --short` y conservar los cambios locales. No hacer commit ni push como parte del traspaso. El PDF `linux/materials/Arquitecturas_de_Respaldo_en_Linux.pdf` aparece sin seguimiento, es anterior a este trabajo y debe quedar fuera.
3. No repetir H01–H04 ni el alta de cuentas/credenciales. H04 está cerrado y su evidencia está abajo.
4. Continuar solo cuando llegue el evento requerido para cada pendiente:
   - **H05:** sesión interactiva real de VS Code con Copilot disponible.
   - **H06:** pico natural comparable al incidente, para tomar tiempos/PSI/journal juntos.
   - **H07:** clase con un alumno disponible.
5. Cuando H05–H07 cumplan su aceptación, actualizar las filas de `PLAN_DE_ACCION.md`, escribir fecha de cierre total y actualizar este handover. No añadir hitos nuevos a esta entrega.

No dejar sondeos o repeticiones en loop. Si no aparece el evento, conservar el hito como pendiente con el siguiente disparador escrito aquí.

## Qué leer y dónde trabajar

- Repo de clases: `/var/home/dalmine/Nextcloud/Repos/labs`, rama main, sin commit ni push de estos cambios.
- Homelab: `/var/home/dalmine/Nextcloud/Cursos/AI-LEARNING`, sin Git. Leer su AGENTS.md y handover global antes de operar; esta sesión es la dueña de chat-ia, otras sesiones trabajan otros stacks.
- Skills operativas: chat-ia, servidor-t7910, infra-como-codigo. Runbook: homelab `docs/runbooks/chat-ia-pruebas-identidad.md`.
- El usuario autorizó continuar lo pendiente y pidió hitos finitos y traspaso. La sesión actual está con acceso completo y aprobaciones never; otra sesión puede tener otro perfil. Última revisión de H06 el 2026-11-16; la evidencia no reproduce el pico.

## Hitos cerrados

| Hito | Evidencia |
| :--- | :--- |
| H01: hub local | 13 tests OK; demo original y ampliada TODO OK; sin procesos de prueba locales restantes |
| H02: cuatro fuentes Dell | Cursos: 13 OK, labs 6 tools / study 4 / libros 5. oss-docs: 12 proyectos, sin error |
| H03: clientes ya admitidos | Claude Code, Goose, Open WebUI y Cline CLI con llamadas reales registradas anteriormente; no acredita sus interfaces gráficas |
| H04: pruebas sin personas | Unix chat-prueba y credenciales propias aplicadas; Goose aislado OK en 56,8 s y dentro del verificador completo OK en 13,6 s. Ambos con par exitoso casa__conocimiento_buscar y respuesta final posterior |
| D01–D03: didáctica | Guía nueva AGENTES_Y_PROTOCOLOS_MCP.md, práctica/demo ampliadas, índices y glosario; esquema, ejemplos y enlaces verificados |

H04 requería que Goose se ejecutara con identidad propia y herramientas reales, sin saltarlo ni usar cuentas personales. Eso está acreditado. **No equivale a que todo el verificador sea verde**: la calidad/uso de tools de Open WebUI sigue registrada en el pendiente existente `tutor-modelo-mas-grande`. No reabrir el alta técnica por ese fallo independiente.

## Estado vivo de H04

- Open WebUI usa la cuenta técnica `prueba`; Goose usa Unix `chat-prueba`, UID 983, shell nologin, password bloqueado. No se agregaron acceso SSH ni sudo.
- Cliente LLM `goose-prueba`: solo alias locales, 10 rpm / 100 pedidos por día. Token MCP propio de rol operador. Journal previo confirmó identidad goose-prueba y usd=0.0.
- Rutas de credenciales: `/home/chat-prueba/.chat-ia/litellm.key` y `hub.token`, permisos 600. Nunca imprimir valores ni usar claves humanas.
- Ansible e instaladores ya aplicados: chat-ia segunda aplicación changed=0; chat-bots y hub sin cambios; verificación del hub y de chat-ia TODO OK.
- No repetir altas ni instaladores de credenciales. La última continuación solo publicó código del verificador por el flujo de chat-ia.

## Arreglo del verificador y pruebas

El stdout anterior tenía un banner de 126 caracteres y luego JSON. Además su respuesta final era «The model returned an empty response», sin tools. El nuevo `dell/goose_evidencia.py` extrae una única sesión JSON completa con mensajes/metadata y rechaza ambigüedad o truncado.

La aceptación exige request/response por el mismo ID, resultado exitoso, sin isError, y texto final posterior a la herramienta. No cuentan eventos falsos dentro de texto ni menciones de tools sin ejecución. Ocho regresiones offline OK. Replay de la grabación anterior: JSON leído, evaluación sigue rechazada, cero pares y empty_model_response=true.

`chat-ia.sh probar goose` ejecuta solo Goose. El prompt de prueba usa el nombre completo de la herramienta de la extensión habilitada; no cambió el prompt ni el modelo de producción. Persiste stdout, stderr y rc/tiempo en archivos root 600. Sigue limitado a seis turnos, dos repeticiones iguales y 240 segundos.

### Último verificador completo: **FALLAS: 1**, rc=1

- Open WebUI respondió en 24,3 s con tools=[] e inventó una cita a casa-operador_conocimiento_ver(id=nas-gen8-ilo). **El control lo rechazó**; no se quitó esa condición.
- Sus controles de modelos/permisos pasaron: sin casa-rino, HTTP 400 al intentar usarlo, operador sin herramientas admin.
- Goose pasó con identidad chat-prueba, par casa__conocimiento_buscar y respuesta final no vacía en 13,6 s.
- El pendiente de identidad `chat-ia-probar-sin-persona` está hecho. El fallo de Open WebUI quedó agregado al pendiente existente del modelo; no se inició otro ciclo de experimentos.

## Fuentes modificadas del homelab

- `stacks/chat-ia/config/chat-ia.yml`: pruebas/crear_unix y cuenta técnica.
- `stacks/chat-ia/ansible/playbooks/chat-ia.yml`: alta declarativa etiquetada cuentas-unix.
- `stacks/chat-ia/chat-ia.sh`: cuentas-unix y probar goose.
- `stacks/chat-ia/dell/probar.py` 1.3.0: identidad, replay, subprueba y evidencia estricta.
- Nuevos `stacks/chat-ia/dell/goose_evidencia.py` y `test_goose_evidencia.py`.
- `stacks/chat-bots/config/clientes-llm.yml` y `stacks/mcp-hub/config/hub.yml`: perfil local y rol operador propios.
- README/meta de los tres stacks; notas H04 dentro de `notas:` y artefactos de chat-ia actualizados; runbook con SVG; SERVICIOS y pendientes actualizados.
- Análisis: `docs/reportes/2026-11-15-mirar-atras-chat-ia-evidencia-goose.md`.

No se tocaron modelos/prompts de producción, red, VMs ni cuentas humanas. No usar/despertar Radeon, domyn-*, ws* ni el lab docente. No gastar en GPUs o modelos de nube.

## Evidencias persistentes

Directorio Fedora: `/home/dalmine/.local/state/chat-ia-h04-20261115/`. Conserva fuentes originales como copia normal, sin nuevos respaldos cifrados. Logs en `resultados/` (600):

- h04-chatbots.log, h04-mcp-hub.log, h04-idempotencia-gateways.log: instalación e idempotencia anteriores.
- h04-prueba-e2e.log: fallo anterior de parser, conservado.
- h04-goose-aislado.log: Goose 56,8 s, TODO OK.
- h04-e2e-final.log: verificador completo, Goose 13,6 s OK / Open WebUI FALLA.
- h04-parser-aplicar.log: publicación y verificación del arreglo.
- h06-ssh-nuevas.json: tres conexiones sin ControlMaster, 0,269 / 0,239 / 0,243 s, load 7,96/8,12/5,66; presión IO full avg10 0,18. No reproduce el pico original.

Evidencias remotas root 600 en `/var/lib/chat-ia/pruebas/`:

- goose-qufw30wq.json: anterior, sin tools, debe seguir rechazado.
- goose-nbm2e17p.json (+ .stderr/.meta): aislado aprobado.
- goose-54qh7x5p.json (+ .stderr/.meta): Goose aprobado en verificador completo.

No reejecutar auxiliares históricos de /tmp/labs-h04-stage ni finalizar.py: quedaron obsoletos. Las fuentes actuales y este traspaso prevalecen. No hay una prueba de inferencia pendiente tras las corridas anteriores.

## Próximo trabajo, sin reiniciar lo cerrado

| Hito | Próxima acción y dependencia |
| :--- | :--- |
| H05 | En una máquina con VS Code y Copilot, generar `python3 ai/tutor/hub/hub.py config vscode`; integrar la salida en `.vscode/mcp.json` conservando la configuración existente. En la sesión interactiva, confirmar que aparece el MCP, llamar `search_curriculum` y guardar versión/fecha/resultado. No hay code/codium ni sesión Copilot en este entorno; generar JSON solo no cierra el hito. |
| H06 | **Pendiente.** El journal del 14/11 sitúa un retraso en apertura/registro de sesión: clave aceptada 11:18:07, `pam_unix` abre 11:18:53, logind registra 11:19:46; el stack contiene `pam_systemd.so`. La pista apunta a pam_systemd/logind, pero no explica qué lo demoró. No había PSI histórico ni alertas de kernel/OOM. El 16/11, con carga menor, tres SSH nuevas abrieron en 0,204/0,232/0,254 s. Antecedente: load 36 y PSI I/O full avg10=10; no reproducido. En un pico natural comparable, medir fase de autenticación/apertura con `ssh -vvv -o ControlMaster=no -o ControlPath=none`, tomar PSI de `/proc/pressure/{cpu,io,memory}` y journal de sshd/logind/systemd en la misma ventana. Sin pesos, reinicios ni VMs hasta tener causa. Evidencia: `/home/dalmine/.local/state/chat-ia-h04-20261115/resultados/h06-ssh-20261116.json`. |
| H07 | En una clase real, un alumno sigue `../PRACTICA_15_MIN_MCP.md` con un cliente compatible, observa una llamada real y completa los dos retos. Registrar fecha, cliente/versión, duración, resultado de cada reto y bloqueos. La demo automatizada no sustituye a esta sesión. |

No se programaron reintentos ni chequeos perpetuos. El experimento de modelos sigue siendo opcional posterior; si el problema impide completar la práctica real, registrarlo en H07. Conservar el fallo completo de Open WebUI como limitación conocida.

## Repo y archivos de esta entrega

Repo `/var/home/dalmine/Nextcloud/Repos/labs`, rama `main`. Todo sigue como cambios locales sin commit ni push.

Archivos modificados por el trabajo del Hub MCP:

- `README.md`
- `ai/tutor/GLOSARIO.md`
- `ai/tutor/PRACTICA_15_MIN_MCP.md`
- `ai/tutor/README.md`
- `ai/tutor/demo_practica_15_min_mcp.sh`
- `ai/tutor/hub/PLAN_DE_ACCION.md`
- Nuevo `ai/tutor/AGENTES_Y_PROTOCOLOS_MCP.md`
- Nuevo `ai/tutor/hub/TRASPASO.md` (este documento)

`linux/materials/Arquitecturas_de_Respaldo_en_Linux.pdf` está sin seguimiento y no forma parte de esta entrega; no agregarlo. Confirmar el estado exacto con `git status --short` antes de preparar cualquier commit.

La evidencia H04/H06 fuera del repo está en `/home/dalmine/.local/state/chat-ia-h04-20261115/`. La captura más reciente de H06 es `resultados/h06-ssh-20261116.json`, permisos 600. Los logs remotos de Goose están en `/var/lib/chat-ia/pruebas/` en el Dell, permisos root 600.

Texto para transferir a otro chat: «Leé `/var/home/dalmine/Nextcloud/Repos/labs/ai/tutor/hub/TRASPASO.md` y después `PLAN_DE_ACCION.md`. Conservá los cambios locales de `main`; no agregues el PDF sin seguimiento, no hagas commit/push. Estado 4/7: H04 Goose está cerrado; quedan H05 sesión VS Code/Copilot, H06 reproducir y explicar retraso SSH pam_systemd/logind bajo carga comparable, H07 clase real con alumno. No repitas hitos cerrados ni dejes reintentos en loop».
