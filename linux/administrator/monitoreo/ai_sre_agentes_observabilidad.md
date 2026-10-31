---
id: lab-3.6.3-ai-sre-agentes-observabilidad
title: 'AI SRE y Agentes Autónomos: Diagnóstico Inteligente, Protocolo MCP y Remediación en Linux'
difficulty_level: 3
difficulty_label: 'Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo'
section: '3.6'
sections:
  - '3.6'
  - '3'
category: observability
resource_type: interactive_lab
has_guide: true
has_interactive_script: true
has_terraform: false
execution_mode: cli_interactive
tags:
  - observability
  - monitoring
  - ai-sre
  - agentes
  - mcp
  - react
  - self-healing
  - remediacion
  - guardrails
  - prometheus
  - node-exporter
  - python
  - cli
tools:
  - python3
  - curl
  - systemctl
  - journalctl
  - df
  - node_exporter
  - bash
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
  - environment: WSL2
    type: local
    instance_type: virtualized
    os: Ubuntu 24.04 LTS / Rocky Linux 10.2
    kernel: 6.18.54.1-microsoft-standard-WSL2
    status: PASSED
    test_date: '2026-10-31'
    notes: Laboratorio interactivo probado con script demo_ai_sre.sh y motor CLI en Python.
  - environment: AWS EC2
    type: cloud
    instance_type: t3.micro
    os: Ubuntu 24.04 LTS
    status: VERIFIED
    test_date: '2026-10-31'
    notes: Compatible con instancias Linux cloud y colectores Prometheus.
environments:
  - WSL2
  - AWS EC2
  - Bare Metal
operating_systems:
  - Ubuntu 24.04 LTS
  - Rocky Linux 10.2
  - Debian 12
status: PASSED
rag_summary: 'Laboratorio práctico y marco conceptual de ingeniería de confiabilidad de sitios asistida por inteligencia artificial (AI SRE). Explica cómo conectar la telemetría moderna de Prometheus y Node Exporter con agentes autónomos basados en el patrón cognitivo ReAct (Thought, Action, Observation) y el estándar Model Context Protocol (MCP). Detalla los guardrails de contención indispensables para producción (blast radius, lista blanca de remediaciones, validación humana previa o Human-in-the-Loop) para evitar comandos destructivos no deseados. Incluye la implementación y ejecución paso a paso de un agente CLI en Python funcional (ai_sre_agent.py) capaz de detectar caídas de servicio, investigar el estado con herramientas del sistema operativo, proponer un plan acotado, aplicar autorremediación segura (self-healing) y certificar el restablecimiento del SLO mediante re-evaluación de métricas.'
files:
  guide: monitoreo/ai_sre_agentes_observabilidad.md
  script: monitoreo/demo_ai_sre.sh
  terraform: null
prerequisites:
  - lab-3.6-monitoreo-metricas
  - lab-3.6.0-monitoreo-arquitecturas-comparativa
next_recommended_labs:
  - lab-3.16-taller-integrador-web-lvm-monitoreo
mcp_tools:
  - linux-labs-tutor
  - bash
  - filesystem
---

# AI SRE y Agentes Autónomos: Diagnóstico Inteligente, Protocolo MCP y Remediación en Linux

> *"Monitorear te dice cuándo y dónde algo se rompió. Un agente SRE con telemetría estructurada investiga la causa raíz, formula la mitigación y restaura el servicio en segundos antes de que el cliente lo perciba."*

En infraestructuras de misión crítica, el tiempo medio de resolución (**MTTR - Mean Time to Resolution**) es la métrica de oro. Gran parte de ese tiempo se pierde en tareas repetitivas: revisar qué nodo alertó, buscar en `journalctl`, consultar el uso de inodos con `df -i`, comprobar si el proceso fue terminado por el OOM Killer y aplicar un *runbook* operativo estándar.

El advenimiento del **AI SRE** transforma este paradigma mediante **Agentes Autónomos y Asistidos** capaces de razonar sobre la telemetría del sistema, invocar herramientas del sistema operativo mediante protocolos estandarizados como **MCP (Model Context Protocol)** y ejecutar remediaciones seguras acotadas por **Guardrails de Contención**.

---

## 🧭 1. El Marco Cognitivo ReAct en Administración de Sistemas

Para que un modelo de inteligencia artificial actúe de forma determinista y sin alucinaciones sobre un servidor Linux, se utiliza el patrón **ReAct (Reasoning + Acting)**:

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │                           EL CICLO REACT DE AI SRE                     │
  │                                                                        │
  │  [THOUGHT]     ──► "¿Por qué Node Exporter reporta up == 0?"          │
  │  [ACTION]      ──► Invocar tool: check_service_status("node_exporter") │
  │  [OBSERVATION] ──► "El puerto :9100 rechaza conexiones activas"        │
  │  [THOUGHT]     ──► "El proceso no está activo. Verifico causa de caída"│
  │  [ACTION]      ──► Invocar tool: query_journalctl("node_exporter")     │
  │  [OBSERVATION] ──► "Signal SIGKILL recibida (Out of Memory)"          │
  │  [PLAN]        ──► 1. Limpiar caches huérfanas 2. Reiniciar servicio  │
  │  [GUARDRAIL]   ──► Acción 'restart_service' en lista blanca: APROBADA  │
  │  [REMEDIATION] ──► systemctl restart node_exporter                     │
  │  [VEREDICT]    ──► up == 1 confirmado. Incidente cerrado en 4.2s.     │
  └────────────────────────────────────────────────────────────────────────┘
```

---

## 🔌 2. Protocolo MCP (Model Context Protocol): La Conexión Segura con Linux

Tradicionalmente, darle acceso a un LLM a la terminal implicaba otorgarle una sesión SSH ciega con permisos excesivos, con el riesgo latente de un comando destructivo como `rm -rf` o un borrado accidental de bases de datos.

El **Model Context Protocol (MCP)** resuelve este dilema separando al agente en dos entidades:
1. **Cliente MCP (El Cerebro / LLM)**: Razona y decide *qué información necesita* o *qué acción propone*.
2. **Servidor MCP (El Conector Seguro en Linux)**: Proceso local que expone un catálogo estricto de herramientas tipadas (JSON Schema). Solo ejecuta comandos previamente aprobados y valida parámetros de entrada.

```
   ┌──────────────┐         JSON-RPC 2.0 (MCP)         ┌──────────────────────┐
   │  AGENTE IA   │ ◄────────────────────────────────► │     SERVIDOR MCP     │
   │ (Cerebro LLM)│   Tools:                           │ (Linux Tool Executor)│
   └──────────────┘   - query_metrics(metric_name)     └──────────┬───────────┘
                      - inspect_system(command)                   │
                      - execute_remediation(action)               │
                                                                  ▼
                                                      ┌──────────────────────┐
                                                      │  SISTEMA OPERATIVO   │
                                                      │  - procfs / sysfs    │
                                                      │  - Node Exporter     │
                                                      │  - systemctl / logs  │
                                                      └──────────────────────┘
```

---

## 🛡️ 3. Guardrails de Contención y Blast Radius

En producción, un agente **NUNCA debe poseer privilegios de ejecución destructiva irrestricta**. Se implementan cuatro capas de contención:

1. **Lista Blanca de Remediaciones (*Allowlist*)**: El agente solo puede ejecutar acciones tipadas:
   * `restart_service`: Reiniciar unidades de systemd conocidas.
   * `rotate_logs`: Forzar compactación con `journalctl --vacuum-time=1d` o rotación de `logrotate`.
   * `cleanup_tmp`: Eliminar archivos temporales con más de 60 minutos de inactividad (`find /tmp -mmin +60`).
   * `repair_lvm_mirror`: Reconstruir un volumen espejo con `lvconvert --repair`.
2. **Patrones Prohibidos (*Denylist*)**: Bloqueo estricto e irrevocable ante cadenas peligrosas:
   * `rm -rf /`, `mkfs.*`, `dd if=/dev/zero`, `shutdown`, `reboot`, manipulaciones directas sobre `/dev/sd*`.
3. **Modo Dry-Run / Planificación Previa**: El agente debe emitir el plan completo con el impacto proyectado antes de tocar el sistema.
4. **Human-in-the-Loop (Aprobación Interactiva)**: Para acciones que excedan el umbral de bajo riesgo, el agente pausa su ejecución y solicita confirmación interactiva al operador de guardia por terminal.

---

## 🧪 4. Práctica de Laboratorio: Diagnóstico y Autorremediación en Vivo

En este laboratorio ejecutaremos el agente CLI [`ai_sre_agent.py`](scripts/ai_sre_agent.py) incluido en el repositorio para diagnosticar e intervenir un incidente simulado en caliente.

### Paso 1: Ejecutar la Demostración Automatizada
El repositorio provee el script interactivo [`demo_ai_sre.sh`](demo_ai_sre.sh), que simula la infraestructura web corporativa, detiene el servicio forzosamente y lanza el agente de IA:

```bash
# Otorgar permisos de ejecución si es necesario
chmod +x linux/administrator/monitoreo/demo_ai_sre.sh
chmod +x linux/administrator/monitoreo/limpiar_ai_sre.sh

# Ejecutar la demostración de extremo a extremo
./linux/administrator/monitoreo/demo_ai_sre.sh
```

---

### Paso 2: Uso Manual del Agente AI SRE por Terminal (CLI)

Podés interactuar directamente con el motor cognitivo del agente utilizando sus distintas modalidades:

#### A. Modo Triage Forense (Solo Inspección Pasiva)
Realiza la lectura de telemetría desde Node Exporter (`http://127.0.0.1:9100/metrics`) e inspecciona el estado de los procesos y filesystems sin alterar nada:

```bash
python3 linux/administrator/monitoreo/scripts/ai_sre_agent.py --triage
```

*Salida de Terminal:*
```text
╔══════════════════════════════════════════════════════════════════════════════╗
║                   🤖 AI SRE AGENT: Autonomous Linux Remediation Engine       ║
║            Model Context Protocol (MCP) & ReAct Pattern for Infrastructure   ║
╚══════════════════════════════════════════════════════════════════════════════╝

--- [FASE 1: TELEMETRÍA Y SIGNOS VITALES DEL SISTEMA] ---

[THOUGHT / RAZONAMIENTO] El agente consulta los colectores de métricas para detectar desviaciones de SLOs.
[ACTION / HERRAMIENTA] Invocando query_node_exporter con argumentos: http://127.0.0.1:9100/metrics
[OBSERVATION / RESULTADO]
  │ Métricas recibidas exitosamente (142 series temporales scrapeadas).

[THOUGHT / RAZONAMIENTO] Comprobando disponibilidad del servicio web (Nginx / Python HTTP).
[ACTION / HERRAMIENTA] Invocando check_service_status con argumentos: nginx
[THOUGHT / RAZONAMIENTO] El servidor web corporativo no responde ni figura en la tabla de procesos.
```

---

#### B. Modo Planificación de Mitigación (`--plan`)
El agente analiza los hallazgos (*findings*), pasa cada acción por los **Guardrails de Seguridad** y genera la secuencia óptima de pasos:

```bash
python3 linux/administrator/monitoreo/scripts/ai_sre_agent.py --plan
```

*Salida de Terminal:*
```text
--- [FASE 2: FORMULACIÓN DEL PLAN DE ACCIÓN (REMEDIATION PLAN)] ---

[THOUGHT / RAZONAMIENTO] Plan generado con 1 pasos de remediación aprobados por guardrails.
  Paso 1: [restart_service] sobre nginx
    Comando: systemctl restart nginx || nohup python3 -m http.server 8080 >/dev/null 2>&1 &
    Impacto: Restablece el servicio web sin alterar archivos de configuración.
```

---

#### C. Modo Remediación Asistida (*Human-in-the-Loop*)
El agente solicita autorización explícita antes de ejecutar el comando:

```bash
python3 linux/administrator/monitoreo/scripts/ai_sre_agent.py --remediate
```

*Interacción:*
```text
▶ Ejecutando Paso 1: restart_service en nginx
  ¿Desea autorizar la ejecución de 'systemctl restart nginx ...'? (s/N): s
[ACTION / HERRAMIENTA] Invocando execute_bounded_shell ...
[OBSERVATION / RESULTADO]
  │ [Ejecución completada con código de salida 0]
  ✓ Verificando restauración de métrica...

--- [FASE 4: VERIFICACIÓN POST-MORTEM] ---
[THOUGHT / RAZONAMIENTO] Re-evaluando métricas de telemetría para certificar el cierre del incidente.
✅ [VEREDICT / ESTADO FINAL: RESOLVED] El incidente ha sido mitigado satisfactoriamente. Telemetría normalizada.
```

---

#### D. Modo Centinela Autónomo Continuo (`--watch`)
Monitorea de forma continua en segundo plano cada `N` segundos, actuando como un operador de guardia incansable:

```bash
python3 linux/administrator/monitoreo/scripts/ai_sre_agent.py --watch --interval 10
```

---

## 🧹 5. Saneamiento del Laboratorio

Para detener los procesos de prueba y purgar archivos temporales:

```bash
./linux/administrator/monitoreo/limpiar_ai_sre.sh
```

---

## 🎯 Resumen de Aprendizaje
* **La telemetría es el sistema sensorial del LLM**: Sin métricas y logs estructurados, los modelos alucinan; con telemetría en tiempo real, razonan de forma causal.
* **El patrón ReAct**: Permite alternar razonamiento (*Thought*) con llamadas controladas a herramientas del sistema (*Action* y *Observation*).
* **Protocolo MCP**: Estandariza la conexión entre la IA y las herramientas de Linux bajo un modelo cliente-servidor seguro por JSON-RPC.
* **Guardrails inquebrantables**: La autorremediación productiva exige listas blancas, contención de radio de explosión (*blast radius*) y confirmación humana en acciones críticas.
