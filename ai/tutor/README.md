# Entorno de Aprendizaje con IA: Tutor de Administración Linux

Bienvenido al ecosistema de **Tutoría Inteligente y Asistida por IA** para el plan de carrera de Administración de Servidores Linux.

Este directorio contiene la arquitectura, herramientas, configuraciones y guías para que cualquier estudiante pueda:
1. Estudiar con una interfaz web local tipo ChatGPT (**Open WebUI**) integrada con **RAG** sobre todo el repositorio.
2. Contar con un agente autónomo en su terminal (**Goose CLI**) que ejecuta comandos, diagnostica fallas y resuelve dudas en tiempo real.
3. Integrar al tutor dentro de su editor (**VS Code**) mediante **Continue.dev** y **Cline**.
4. Conectar protocolos modernos de la industria (**MCP - Model Context Protocol**, **A2A - Agent-to-Agent** y flujos estilo **jdev**).
5. Elegir libremente entre **modelos 100% locales en CPU/GPU (Ollama)** o **modelos cloud avanzados (OpenRouter)**.
6. (Opcional) Hablarle al tutor por voz y escucharlo explicar conceptos con voz humana sin necesidad de tarjeta gráfica dedicada.

---

## 🗺️ Mapa de Contenidos

| Recurso | Descripción |
| :--- | :--- |
| 📖 [`GUIA_PASO_A_PASO.md`](GUIA_PASO_A_PASO.md) | **Tutorial maestro paso a paso** para configurar Ollama, OpenRouter, Open WebUI, Goose CLI, VS Code y Voice-to-Voice. |
| 🤖 [`system_prompt_tutor.md`](system_prompt_tutor.md) | Prompt de sistema universal listo para configurar el rol y la metodología pedagógica del Tutor. |
| 🔌 [`mcp/labs_mcp_server.py`](mcp/labs_mcp_server.py) | **Servidor MCP nativo** (JSON-RPC stdio) que expone herramientas para consultar el catálogo de laboratorios, verificar requisitos y leer guías. |
| 🛠️ [`mcp/goose_config.yaml`](mcp/goose_config.yaml) | Archivo de configuración para el agente de terminal **Goose CLI**. |
| 💻 [`mcp/continue_config.json`](mcp/continue_config.json) | Configuración para **Continue.dev** en VS Code. |
| 🧩 [`mcp/cline_mcp_settings.json`](mcp/cline_mcp_settings.json) | Configuración de servidor MCP para **Cline / Roo Code** en VS Code. |
| 🐍 [`mcp/openwebui_tools.py`](mcp/openwebui_tools.py) | Herramienta Python nativa para importar directamente en **Open WebUI**. |

---

## 🚀 Inicio Rápido en 3 Pasos

### 1. Iniciar el Backend Local (Ollama en CPU)
```bash
ollama pull llama3.2:3b
ollama pull nomic-embed-text
```

### 2. Iniciar la Interfaz Web (Open WebUI)
```bash
docker run -d -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -v open-webui:/app/backend/data \
  --name open-webui --restart always \
  ghcr.io/open-webui/open-webui:main
```
Abre en tu navegador: `http://localhost:3000`.

### 3. Probar el Servidor MCP desde Terminal
```bash
python ai/tutor/mcp/labs_mcp_server.py
```

Para una guía detallada con capturas, integración en VS Code y comandos paso a paso, consulta [`GUIA_PASO_A_PASO.md`](GUIA_PASO_A_PASO.md).
