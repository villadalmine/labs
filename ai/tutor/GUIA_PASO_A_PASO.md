# Guía Maestra: Entorno de Aprendizaje con IA Local, Protocolos Modernos (MCP, A2A, jdev, RAG), Open WebUI, Goose CLI y VS Code

Esta guía paso a paso te enseña a armar un **entorno integral de estudio y tutoría asistido por Inteligencia Artificial** para dominar la administración de servidores Linux.

Aprenderás a conectar interfaces visuales (**Open WebUI**), agentes autónomos de terminal (**Goose CLI**) y tu editor de código (**VS Code**) tanto con **modelos 100% locales en tu CPU/GPU (Ollama)** como con **APIs en la nube (OpenRouter)**, utilizando los protocolos modernos de la industria:
* **MCP (Model Context Protocol):** Estándar abierto para que los modelos invoquen herramientas del catálogo de laboratorios y de la terminal.
* **RAG (Retrieval-Augmented Generation):** Recuperación semántica de conceptos sobre el plan de estudios.
* **A2A (Agent-to-Agent) & jdev:** Patrones de interacción donde un agente tutor delega tareas a un agente evaluador o ejecutor de comandos.
* **Voz Local (Voice-to-Voice en CPU):** Módulo opcional para hablarle al tutor por micrófono y escuchar sus explicaciones en tiempo real sin GPU.

---

## 🏗️ Arquitectura General del Ecosistema

```mermaid
flowchart TD
    subgraph Interfaces["Interfaces del Estudiante"]
        Web["1. Interfaz Web (Open WebUI)\nChat visual, RAG y Knowledge Base"]
        Terminal["2. Terminal / Shell (Goose CLI)\nAgente autónomo con ejecución de comandos"]
        IDE["3. Editor (VS Code + Continue / Cline)\nPair-programming, autocompletado y tutor inline"]
    end

    subgraph Protocols["Protocolos de Comunicación"]
        MCP["MCP (Model Context Protocol)\nServidor stdio: labs_mcp_server.py"]
        RAG["RAG Vectorial (ChromaDB)\nIndexación de catalog.json y guías *.md"]
        A2A["A2A / jdev Workflow\nDelegación Tutor -> Evaluador"]
    end

    subgraph Backends["Proveedores de Inteligencia Artificial (Tú Eliges)"]
        OllamaLocal["Opción A: Ollama Local (100% Offline)\nCPU o GPU (llama3.2:3b / qwen2.5)"]
        OpenRouterCloud["Opción B: OpenRouter API\nModelos Top (DeepSeek R1, Claude 3.5 Sonnet)"]
    end

    subgraph LinuxHost["Tu Máquina / Servidor Linux"]
        Catalog["24 Laboratorios con Metadatos\nNiveles 0 al 4"]
        DemoScripts["Scripts de Prueba\n(demo_filesystems, demo_monitoreo, etc.)"]
    end

    Interfaces <--> Protocols
    Protocols <--> Backends
    Protocols <--> LinuxHost
```

---

## ⚙️ Paso 1: Configurar el Proveedor de Modelos (Ollama Local vs OpenRouter)

Puedes elegir entre correr los modelos 100% en tu máquina o conectarte a la API unificada de OpenRouter:

### Opción A: 100% Local con Ollama (CPU o GPU, Sin Costo, Privado)
1. Instala Ollama:
   * **Windows:** Descarga e instala desde [ollama.com](https://ollama.com).
   * **Linux / WSL2:** `curl -fsSL https://ollama.com/install.sh | sh`
2. Descarga los modelos optimizados:
   ```bash
   # Modelo de lenguaje para el tutor (2.0 GB - corre a 35 tokens/seg en CPU)
   ollama pull llama3.2:3b

   # Modelo de embeddings para RAG (274 MB)
   ollama pull nomic-embed-text

   # (Opcional) Si quieres autocompletado de código rápido en VS Code:
   ollama pull qwen2.5-coder:1.5b
   ```

### Opción B: Conexión Cloud con OpenRouter (Modelos de Razonamiento como DeepSeek R1 o Claude 3.5)
Si prefieres usar modelos más grandes sin consumir CPU ni RAM local:
1. Crea una cuenta en [openrouter.ai](https://openrouter.ai).
2. Genera una API Key en **Keys** -> **Create Key**.
3. Guarda tu variable de entorno:
   ```bash
   # En Linux / WSL:
   export OPENROUTER_API_KEY="sk-or-v1-tu-clave..."
   
   # En Windows PowerShell:
   $env:OPENROUTER_API_KEY="sk-or-v1-tu-clave..."
   ```
> [!NOTE]
> OpenRouter ofrece acceso a modelos como `deepseek/deepseek-r1`, `meta-llama/llama-3.3-70b-instruct` o `anthropic/claude-3.5-sonnet` pagando fracciones de centavo por consulta o usando modelos con cuota gratuita.

---

## 🌐 Paso 2: Interfaz Visual y RAG con Open WebUI

Open WebUI te ofrece una experiencia similar a ChatGPT en tu navegador, integrada con RAG local y herramientas personalizadas.

### 1. Iniciar Open WebUI con Docker
```bash
docker run -d -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -v open-webui:/app/backend/data \
  --name open-webui --restart always \
  ghcr.io/open-webui/open-webui:main
```

### 2. Conectar Open WebUI a tu Backend
* **Si usas Ollama Local:** Ya viene configurado por defecto apuntando a `http://host.docker.internal:11434`.
* **Si usas OpenRouter:** En **Admin Settings** -> **Connections** -> **OpenAI API**:
  * URL: `https://openrouter.ai/api/v1`
  * Key: Tu `OPENROUTER_API_KEY`.
  * Presiona el botón de recargar modelos y aparecerán todos los modelos de OpenRouter.

### 3. Cargar la Base de Conocimiento (RAG)
1. Ve a **Workspace** -> **Knowledge** -> **+**.
2. Crea una colección llamada `Laboratorios Linux`.
3. Arrastra el archivo [`linux/administrator/catalog.json`](file:///C:/Users/rino/Documents/GitHub/labs/linux/administrator/catalog.json) y las carpetas de guías Markdown.
4. El motor creará los embeddings con `nomic-embed-text` en segundos.

### 4. Instalar las Herramientas del Tutor en Open WebUI
1. Ve a **Workspace** -> **Tools** -> **+ (Add Tool)**.
2. Abre el archivo [`ai/tutor/mcp/openwebui_tools.py`](file:///C:/Users/rino/Documents/GitHub/labs/ai/tutor/mcp/openwebui_tools.py), copia todo su contenido y pégalo en el editor de Open WebUI.
3. Guarda la herramienta. Ahora el modelo en Open WebUI puede invocar `get_student_roadmap` y `search_curriculum` de forma nativa.

---

## 💻 Paso 3: Agente Autónomo de Terminal con Goose CLI (Block)

[Goose](https://github.com/block/goose) es un agente autónomo de código abierto creado por Block para la terminal. Es ideal para estudiantes de Linux porque **puede ejecutar comandos bash reales, diagnosticar errores en vivo, reparar servicios caídos y consultar el servidor MCP de este repositorio**.

### 1. Instalar Goose CLI
* **En Linux / WSL2:**
  ```bash
  curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | bash
  ```
* **En Windows:** Descarga el binario o instálalo vía `pipx install goose-ai` o `cargo install goose-cli`.

### 2. Configurar Goose con el Servidor MCP de Laboratorios
Copia la plantilla [`ai/tutor/mcp/goose_config.yaml`](file:///C:/Users/rino/Documents/GitHub/labs/ai/tutor/mcp/goose_config.yaml) a tu carpeta de configuración de Goose:

```bash
mkdir -p ~/.config/goose
cp ai/tutor/mcp/goose_config.yaml ~/.config/goose/config.yaml
```

Contenido clave de la configuración:
```yaml
# ~/.config/goose/config.yaml
provider: ollama        # o 'openrouter'
model: llama3.2:3b      # o 'deepseek/deepseek-r1'

extensions:
  linux_labs_tutor:
    name: linux_labs_tutor
    cmd: python
    args:
      - "ai/tutor/mcp/labs_mcp_server.py"
    type: stdio
    enabled: true
  developer:
    enabled: true       # Permite a Goose ejecutar comandos shell seguros
```

### 3. Iniciar una Sesión de Tutoría en Terminal con Goose
Ejecuta en la raíz del repositorio:

```bash
goose session
```

**Ejemplo de interacción real en la terminal:**
> **Tú:** *"Hola Goose, soy alumno, estoy en WSL2 con Ubuntu 24.04 y quiero empezar a practicar almacenamiento. ¿Qué laboratorio me recomiendas?"*

> **Goose:**
> 1. Invoca automáticamente la herramienta MCP `get_student_roadmap(environment='WSL2')`.
> 2. Te responde que el siguiente laboratorio es `lab-3.1-anatomia-filesystems`.
> 3. Lee la guía con `read_lab_guide(lab_id='lab-3.1-anatomia-filesystems')`.
> 4. Te ofrece ejecutar `demo_filesystems.sh` paso a paso o simular un rescate de superbloque con `e2fsck -b 32768`.

---

## 📝 Paso 4: Integración en VS Code (Continue.dev y Cline)

Para que puedas leer las guías, inspeccionar los scripts de demostración o editar código de Terraform teniendo al tutor al lado en el editor:

### Opción 1: Continue.dev (Extensión de VS Code)
1. Instala la extensión **Continue** (`continue.continue`) desde el Marketplace de VS Code.
2. Copia el archivo [`ai/tutor/mcp/continue_config.json`](file:///C:/Users/rino/Documents/GitHub/labs/ai/tutor/mcp/continue_config.json) a `~/.continue/config.json`.
3. Ya tendrás:
   * **Chat con el Tutor:** Presiona `Ctrl + L` para preguntarle dudas sobre cualquier archivo que tengas abierto.
   * **Comando `@tutor`:** Selecciona un fragmento de script Bash o Makefile y escribe `/tutor` para que te explique qué hace cada línea del kernel.
   * **Autocompletado Tab:** Sugerencias automáticas en scripts `.sh` corriendo en tu CPU con `qwen2.5-coder:1.5b`.

### Opción 2: Cline / Roo Code (Agente Autónomo en VS Code)
1. Instala la extensión **Cline** (`saoudrizwan.claude-dev`).
2. Abre la pestaña de MCP en Cline y añade el servidor configurado en [`ai/tutor/mcp/cline_mcp_settings.json`](file:///C:/Users/rino/Documents/GitHub/labs/ai/tutor/mcp/cline_mcp_settings.json).
3. Cline reconocerá inmediatamente las 5 herramientas del catálogo (`get_student_roadmap`, `get_lab_details`, etc.).

---

## 🤝 Paso 5: Protocolos Modernos (MCP, A2A y jdev)

### 1. Model Context Protocol (MCP)
En este repositorio creamos [`ai/tutor/mcp/labs_mcp_server.py`](file:///C:/Users/rino/Documents/GitHub/labs/ai/tutor/mcp/labs_mcp_server.py).
Cualquier cliente compatible con MCP (Claude Desktop, Goose, Cursor, Cline, Continue) puede conectarse ejecutando:
`python ai/tutor/mcp/labs_mcp_server.py`.
El servidor expone herramientas estandarizadas:
* `get_student_roadmap`: Resuelve el grafo curricular evitando bloqueos.
* `get_lab_details`: Retorna metadatos, tags y herramientas requeridas.
* `search_curriculum`: Búsqueda instantánea en el catálogo.
* `verify_student_readiness`: Comprueba si el estudiante tiene permisos antes de fallar.
* `read_lab_guide`: Inyecta la guía Markdown bajo demanda sin saturar la ventana de contexto.

### 2. Flujo de Trabajo estilo jdev / A2A (Agent-to-Agent)
El protocolo A2A permite que múltiples agentes especializados colaboren:
* **Agente 1: El Tutor Pedagógico (Orquestador):** Evalúa al estudiante, lee el plan de estudios, presenta los conceptos teóricos y diseña los ejercicios prácticos.
* **Agente 2: El Ejecutor de Terminal (Worker / Shell Agent):** Ejecuta de forma controlada comandos como `lsblk`, `tune2fs -l /dev/loop20` o `docker compose up` en la máquina del alumno.
* **Agente 3: El Evaluador Forense (Grader):** Analiza la salida de los comandos (o el código de retorno) y valida si el estudiante resolvió el problema (por ejemplo, si recuperó el superbloque o liberó inodos).

---

## 🎙️ Paso 6 (Bonus): Tutor con Voz Local (Voice-to-Voice en CPU / GPU)

Si deseas poder **hablarle al tutor por micrófono** mientras estás en la terminal y que el tutor **te responda con voz humana natural**:

### ¿Cómo funciona en Open WebUI sin GPU?
Open WebUI incluye soporte nativo para **Speech-to-Text (STT)** y **Text-to-Speech (TTS)**:

1. **Opción 1: Web Speech API (Gratis, 0 Consumo de CPU, Instantáneo):**
   * En Open WebUI, ve a **Settings** -> **Audio**.
   * En **Speech-to-Text Engine**, selecciona `Web API` (usa el reconocimiento de voz nativo de tu navegador Chrome / Edge).
   * En **Text-to-Speech Engine**, selecciona `Web API`.
   * ¡Listo! Aparecerá un ícono de micrófono junto a la caja de chat. Habla en español y el navegador transcribirá tu voz, y el tutor te responderá hablándote.

2. **Opción 2: Modelos Locales Avanzados (Kokoro-82M & Whisper):**
   * **Whisper (STT Local):** Puedes levantar Whisper en CPU para transcribir audio offline con alta precisión.
   * **Kokoro-82M (TTS Local de Última Generación):** Es un modelo ultra-liviano de solo 82 millones de parámetros que corre en CPU en tiempo real produciendo una voz con calidad de estudio.
   * En Open WebUI, puedes activar Kokoro en **Audio Settings** seleccionando el backend de OpenAI TTS compatible con un contenedor local de Kokoro FastAPI.

---

## 🌐 Paso 7: Super-Cerebro: Integración con study.cybercirujas (MCP y RAG Oficial)

Para enriquecer al tutor con la **teoría conceptual de 28 certificaciones internacionales** (LPIC-1, Linux Essentials, LPIC-3, CKA, CKAD, MCPA, etc.) preservando la soberanía y privacidad en tu propia máquina:

1. **Clona localmente [study.cybercirujas](https://github.com/villadalmine/study-cybercirujas):**
   ```bash
   cd ..
   git clone https://github.com/villadalmine/study-cybercirujas.git
   cd study-cybercirujas && make setup && make mcp-setup
   ```
2. **Servidor MCP Dual:** Conecta ambos servidores (`linux_labs_tutor` + `study_cybercirujas`) en Goose CLI o Cline. Tu agente podrá consultar la teoría de examen y prescribir los laboratorios prácticos en loop devices.
3. **RAG Unificado:** Ejecuta `python ai/tutor/mcp/prepare_rag_corpus.py` para exportar tanto los 24 labs prácticos como la teoría oficial en una carpeta lista para arrastrar a **Knowledge** en Open WebUI.

> 📖 Consulta la guía completa y detallada en: [**`INTEGRACION_STUDY_CYBERCIRUJAS.md`**](INTEGRACION_STUDY_CYBERCIRUJAS.md).

---

## 📋 Resumen de Archivos en `ai/tutor/`

| Archivo | Propósito |
| :--- | :--- |
| [`README.md`](README.md) | Portal principal de bienvenida y arquitectura general para el estudiante. |
| [`GUIA_PASO_A_PASO.md`](GUIA_PASO_A_PASO.md) | Este tutorial completo de instalación, backends (Ollama/OpenRouter) y clientes. |
| [`INTEGRACION_STUDY_CYBERCIRUJAS.md`](INTEGRACION_STUDY_CYBERCIRUJAS.md) | **Guía de integración con study.cybercirujas** (MCP dual, RAG con `prepare_rag_corpus.py` y API REST). |
| [`system_prompt_tutor.md`](system_prompt_tutor.md) | Instrucciones maestras del Tutor para Open WebUI, Goose, Cline o Continue. |
| [`mcp/labs_mcp_server.py`](mcp/labs_mcp_server.py) | Servidor MCP nativo stdio con 5 herramientas curriculares de labs prácticos. |
| [`mcp/prepare_rag_corpus.py`](mcp/prepare_rag_corpus.py) | Script utilitario para preparar y exportar el corpus unificado para Open WebUI. |
| [`mcp/goose_config.yaml`](mcp/goose_config.yaml) | Configuración para Goose CLI con MCP dual (labs + study-cybercirujas). |
| [`mcp/continue_config.json`](mcp/continue_config.json) | Configuración para Continue.dev en VS Code (Ollama + OpenRouter). |
| [`mcp/cline_mcp_settings.json`](mcp/cline_mcp_settings.json) | Configuración para Cline / Roo Code en VS Code con MCP dual. |
| [`mcp/openwebui_tools.py`](mcp/openwebui_tools.py) | Herramienta en Python para importar en Open WebUI. |

