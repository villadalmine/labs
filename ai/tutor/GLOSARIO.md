---
id: ai-tutor-glosario-tecnico-oficial
title: "Glosario Técnico de Inteligencia Artificial para Administradores de Sistemas"
difficulty_level: 1
difficulty_label: "Nivel 1: Conceptos y Especificaciones Oficiales de IA"
section: "ai.1"
sections:
  - "ai.1"
  - "ai"
  - "glossary"
category: "reference"
resource_type: "cheatsheet"
has_guide: true
has_interactive_script: false
has_terraform: false
execution_mode: "documentation"
tags:
  - "glosario"
  - "inferencia"
  - "training"
  - "gguf"
  - "vram"
  - "mcp"
  - "rag"
  - "hitl"
  - "harness"
  - "skills"
  - "vercel"
  - "matt-pocock"
tools:
  - "ollama"
  - "vllm"
  - "sglang"
  - "llama.cpp"
requirements:
  root_required: false
  cloud_required: false
  min_ram_mb: 512
  min_disks: 0
tested_environments:
  - environment: "Documentation"
    type: "reference"
    status: "VERIFIED"
    test_date: "2026-10-24"
    notes: "Enlaces a documentación y papers oficiales verificados."
environments:
  - "Multiplataforma"
operating_systems:
  - "Agnóstico"
status: "VERIFIED"
rag_summary: "Diccionario técnico y conceptual exhaustivo de Inteligencia Artificial enfocado en servidores Linux y hardware. Define más de 30 términos (Inferencia, Training, GGUF, KV Cache, PagedAttention, MCP, A2A, Harness, HITL, Skills, Routing, Gateways, Moshi) con enlaces a documentación y papers oficiales."
files:
  guide: "ai/tutor/GLOSARIO.md"
  script: null
  terraform: null
---

# 📖 Glosario Técnico de Inteligencia Artificial para Administradores de Sistemas

Este glosario define los conceptos, arquitecturas y siglas fundamentales del ecosistema de IA moderna, con énfasis en su impacto en hardware, servidores Linux y desarrollo de software, acompañado de sus **enlaces a la documentación y especificaciones oficiales**.

---

## 🗂️ Índice Alfabético Rápido

* [A2A (Agent-to-Agent)](#a2a-agent-to-agent)
* [Agente de IA (AI Agent)](#agente-de-ia-ai-agent)
* [AI Gateway (Pasarela de Modelos y Proxies)](#ai-gateway-pasarela-de-modelos-y-proxies)
* [AnythingLLM](#anythingllm)
* [AVX2 / AVX-512 / ARM NEON](#avx2--avx-512--arm-neon)
* [Base de Datos Vectorial (Vector Database)](#base-de-datos-vectorial-vector-database)
* [Capas del Transformer (Transformer Layers)](#capas-del-transformer-transformer-layers)
* [Cuantización (Quantization y GGUF)](#cuantizacion-quantization-y-gguf)
* [Descarga de Capas (Layer Offloading)](#descarga-de-capas-layer-offloading)
* [Embeddings](#embeddings)
* [Entrenamiento (Training y Fine-Tuning)](#entrenamiento-training-y-fine-tuning)
* [Harness (Entorno de Ejecución, Evaluación y Sandbox)](#harness-entorno-de-ejecucion-evaluacion-y-sandbox)
* [Herder (Gestor de Procesos de Agentes)](#herder-gestor-de-procesos-de-agentes)
* [Human-in-the-Loop (HITL)](#human-in-the-loop-hitl)
* [Inferencia (Inference)](#inferencia-inference)
* [KV Cache (Key-Value Cache)](#kv-cache-key-value-cache)
* [LLM Routing (Enrutamiento Dinámico de Modelos)](#llm-routing-enrutamiento-dinamico-de-modelos)
* [MCP (Model Context Protocol)](#mcp-model-context-protocol)
* [Memoria en Agentes (Working vs Long-Term Memory)](#memoria-en-agentes-working-vs-long-term-memory)
* [Método Socrático (Socratic Tutoring en IA)](#metodo-socratico-socratic-tutoring-en-ia)
* [Moshi (Kyutai Labs - Voz Full-Duplex)](#moshi-kyutai-labs---voz-full-duplex)
* [Ollama](#ollama)
* [Open WebUI](#open-webui)
* [PagedAttention](#pagedattention)
* [Parámetros de Muestreo (Temperature, Top-P, Top-K)](#parametros-de-muestreo-temperature-top-p-top-k)
* [RAG (Retrieval-Augmented Generation)](#rag-retrieval-augmented-generation)
* [RAM de Sistema y Ancho de Banda (Memory Bandwidth)](#ram-de-sistema-y-ancho-de-banda-memory-bandwidth)
* [Rate Limits y Cuotas (TPM, RPM, RPD)](#rate-limits-y-cuotas-tpm-rpm-rpd)
* [SGLang](#sglang)
* [Skills (Habilidades Modulares de Agentes)](#skills-habilidades-modulares-de-agentes)
* [System Prompt (Prompt de Sistema)](#system-prompt-prompt-de-sistema)
* [Tokens y Tokenización](#tokens-y-tokenizacion)
* [Ventana de Contexto (Context Window)](#ventana-de-contexto-context-window)
* [vLLM](#vllm)
* [VRAM (Video RAM)](#vram-video-ram)

---

## 📚 Definiciones Técnicas y Documentación Oficial

### A2A (Agent-to-Agent)
Patrón arquitectónico donde múltiples agentes autónomos de IA colaboran dividiéndose responsabilidades: un agente tutor planifica la estrategia pedagógica, delega la ejecución de scripts a un agente ejecutor en terminal, y solicita la verificación a un agente evaluador.
* **Impacto en Sistemas:** Requiere protocolos de comunicación inter-proceso (IPC, HTTP REST o JSON-RPC) y mecanismos de control de acceso para evitar que un agente ejecute comandos destructivos sin supervisión.
* 🔗 **Documentación Oficial:**
  * [Multi-Agent Orchestration en Microsoft AutoGen](https://microsoft.github.io/autogen/)
  * [LangGraph Multi-Agent Architecture](https://langchain-ai.github.io/langgraph/concepts/multi_agent/)

---

### Agente de IA (AI Agent)
Sistema computacional autónomo impulsado por un modelo de lenguaje (el "cerebro" o motor de razonamiento) dotado de **memoria de estado**, **capacidad de planificación** y acceso a **herramientas externas** (APIs, comandos de shell, sistemas de archivos). A diferencia de un chatbot pasivo de pregunta-respuesta, un agente opera en un bucle continuo de **Razonamiento y Acción (*ReAct Loop: Thought -> Action -> Observation*)** hasta alcanzar un objetivo predeterminado.
* **Impacto en Sistemas:** Puede ejecutar diagnósticos en cascada, editar archivos de configuración y autoevaluar errores de compilación sin intervención constante del usuario.
* 🔗 **Documentación Oficial:**
  * [Anthropic Research: Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
  * [Paper Fundacional ReAct: Synergizing Reasoning and Acting in Language Models (Yao et al., ICLR 2023)](https://arxiv.org/abs/2210.03629)

---

### AI Gateway (Pasarela de Modelos y Proxies)
Capa intermedia de infraestructura de red situada entre los clientes o agentes de IA y los proveedores de inferencia (locales o en la nube). Proporciona una interfaz unificada compatible con OpenAI, gestión de cuotas de gasto, conmutación automática por error (*failover* si un proveedor se cae), caché semántica de respuestas para reducir costes y observabilidad centralizada de latencias y tokens.
* **Impacto en Sistemas:** Evita acoplar el código a un único proveedor comercial y permite redirigir peticiones a modelos locales sin alterar la configuración del cliente.
* 🔗 **Documentación Oficial:**
  * [LiteLLM Proxy and AI Gateway Documentation](https://docs.litellm.ai/)
  * [Cloudflare AI Gateway Docs](https://developers.cloudflare.com/ai-gateway/)
  * [Portkey AI Gateway Reference](https://portkey.ai/docs/)

---

### AnythingLLM
Aplicación cliente-servidor de código abierto y todo-en-uno que proporciona interfaz gráfica de chat, gestión de documentos, búsqueda vectorial integrada y compatibilidad con Ollama, LM Studio y APIs cloud.
* **Impacto en Sistemas:** Empaqueta internamente una base de datos vectorial (LanceDB) y procesador de documentos, disponible como binario de escritorio o contenedor Docker.
* 🔗 **Documentación Oficial:**
  * [AnythingLLM Official Documentation](https://docs.anythingllm.com/)
  * [AnythingLLM GitHub Repository](https://github.com/Mintplex-Labs/anything-llm)

---

### AVX2 / AVX-512 / ARM NEON
Conjuntos de instrucciones vectoriales de CPU (*Single Instruction, Multiple Data - SIMD*) que permiten a los procesadores modernos realizar operaciones aritméticas sobre múltiples datos en paralelo en un solo ciclo de reloj.
* **Impacto en Sistemas:** Son el pilar que permite a motores como `llama.cpp` e inferencia en CPU calcular multiplicaciones de matrices de IA sin necesidad de tarjeta gráfica dedicada. En Linux se verifica con `lscpu | grep -i avx`.
* 🔗 **Documentación Oficial:**
  * [Intel Advanced Vector Extensions (AVX) Developer Manual](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-advanced-vector-extensions-512-overview.html)
  * [ARM Architecture Reference Manual - NEON Technology](https://developer.arm.com/Architectures/Neon)

---

### Base de Datos Vectorial (Vector Database)
Sistema de almacenamiento especializado en indexar y consultar representaciones matemáticas vectoriales (*embeddings*) a través de algoritmos de vecinos más cercanos (*Approximate Nearest Neighbors - ANN* como HNSW o IVFFlat).
* **Impacto en Sistemas:** Gestiona índices en memoria RAM y disco para resolver búsquedas de similitud semántica en milisegundos.
* 🔗 **Documentación Oficial:**
  * [ChromaDB Architecture Documentation](https://docs.trychroma.com/)
  * [Milvus Vector Database Docs](https://milvus.io/docs)
  * [Qdrant Vector Engine Documentation](https://qdrant.tech/documentation/)

---

### Capas del Transformer (Transformer Layers)
Bloques constitutivos repetitivos de un modelo de lenguaje basados en la arquitectura Transformer. Cada capa contiene subcapas de **Auto-Atención Multi-Cabezal (*Multi-Head Self-Attention*)** y redes *Feed-Forward*.
* **Impacto en Sistemas:** El número de capas (por ejemplo, 28 capas en `llama3.2:3b` o 32 en `llama-7b`) determina cuánta memoria ocupa el modelo y cómo se pueden subdividir entre GPU y CPU.
* 🔗 **Documentación Oficial:**
  * [Paper Fundacional: Attention Is All You Need (Vaswani et al., 2017)](https://arxiv.org/abs/1706.03762)
  * [The Illustrated Transformer (Jay Alammar)](https://jalammar.github.io/illustrated-transformer/)

---

### Cuantización (Quantization y GGUF)
Técnica matemática que reduce la precisión de los pesos numéricos del modelo (por ejemplo, convirtiendo números flotantes de 16 bits `FP16` a enteros de 4 bits `Q4_K_M` o `INT4`). **GGUF** es el formato binario estándar introducido por Georgi Gerganov (`llama.cpp`) para empaquetar modelos cuantizados junto con sus metadatos y tokenizador en un único archivo portable.
* **Impacto en Sistemas:** Reduce el uso de memoria RAM/VRAM hasta en un **75%** y permite que modelos de 3B o 7B parámetros se ejecuten a gran velocidad en procesadores domésticos.
* 🔗 **Documentación Oficial:**
  * [llama.cpp GGUF Specification](https://github.com/ggerganov/llama.cpp/blob/master/docs/gguf.md)
  * [Hugging Face Quantization Overview](https://huggingface.co/docs/transformers/main/en/quantization/overview)

---

### Descarga de Capas (Layer Offloading)
Mecanismo por el cual el motor de inferencia distribuye las capas secuenciales del Transformer entre los procesadores disponibles (GPU y CPU).
* **Impacto en Sistemas:** Si tu GPU tiene 4 GB de VRAM y el modelo requiere 6 GB, el motor coloca las primeras 18 capas en VRAM (ultra-rápido) y las 10 restantes en la RAM del sistema (modo híbrido).
* 🔗 **Documentación Oficial:**
  * [llama.cpp GPU Offload Architecture](https://github.com/ggerganov/llama.cpp/blob/master/examples/main/README.md)
  * [Ollama Modelfile: Parameter `num_gpu`](https://github.com/ollama/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)

---

### Embeddings
Vectores numéricos continuos de punto flotante (de dimensiones típicas como 384, 768 o 1536) que representan el significado semántico de una palabra, frase o párrafo de texto. Palabras o conceptos con significado similar se ubican cerca en el espacio vectorial multidimensional.
* **Impacto en Sistemas:** Se calculan una sola vez al indexar la documentación del curso y se comparan mediante similitud del coseno (*cosine similarity*).
* 🔗 **Documentación Oficial:**
  * [Nomic Embed Text Technical Report](https://docs.nomic.ai/atlas/models/text-embedding)
  * [Hugging Face Massive Text Embedding Benchmark (MTEB)](https://huggingface.co/spaces/mteb/leaderboard)

---

### Entrenamiento (Training y Fine-Tuning)
Fase intensiva de cómputo donde un modelo ajusta sus millones o miles de millones de pesos internos calculando gradientes de error a través de retropropagación (*backpropagation*).
* **Pre-training:** Aprender lenguaje general a partir de billones de tokens de texto (requiere clústeres de cientos de GPUs durante semanas).
* **Fine-Tuning / SFT (Supervised Fine-Tuning):** Adaptar un modelo base preentrenado a un dominio o formato específico (por ejemplo, administración de sistemas Linux) usando conjuntos de datos curados.
* **Impacto en Sistemas:** Exige almacenar optimizadores (AdamW), gradientes y activaciones, multiplicando por 4x a 8x el requerimiento de memoria respecto a la inferencia.
* 🔗 **Documentación Oficial:**
  * [PyTorch Distributed Training Guide](https://pytorch.org/tutorials/beginner/dist_overview.html)
  * [Hugging Face Fine-Tuning Guide](https://huggingface.co/docs/transformers/training)

---

### Harness (Entorno de Ejecución, Evaluación y Sandbox)
El **arnés o andamiaje** (*test harness / runtime harness*) es la infraestructura de software que rodea y controla al agente. Se encarga de:
1. **Aislar el entorno (Sandboxing):** Ejecutar comandos en contenedores Docker, namespaces de Linux, o *loop devices* aislados para evitar daños accidentales al sistema anfitrión.
2. **Inyección de contexto:** Proveer al agente las herramientas disponibles, variables de entorno y límites de tiempo (*timeouts*).
3. **Evaluación de resultados:** Correr suites de pruebas automatizadas tras la ejecución para verificar si el agente resolvió el problema o introdujo regresiones.
* **Impacto en Sistemas:** En este repositorio, los scripts de prueba `demo_*.sh` y las verificaciones del catálogo actúan como el arnés de evaluación de cada laboratorio.
* 🔗 **Documentación Oficial:**
  * [SWE-bench: Benchmark and Evaluation Harness for Software Engineering Agents (Princeton University)](https://www.swebench.com/)
  * [Docker Security and Sandboxing](https://docs.docker.com/engine/security/)

---

### Herder (Gestor de Procesos de Agentes)
Herramienta de orquestación y administración de procesos diseñada para gestionar flotas de agentes de IA en segundo plano dentro de una terminal Linux. Permite lanzar múltiples agentes concurrentes, monitorear su estado de salud, desviar logs y gestionar su ciclo de vida como si fueran demonios del sistema.
* **Impacto en Sistemas:** Previene que tareas largas (compilaciones, auditorías de seguridad) bloqueen la sesión interactiva del operador.
* 🔗 **Documentación Oficial:**
  * [Herder CLI Process Manager Documentation](https://github.com/)

---

### Human-in-the-Loop (HITL)
Patrón de seguridad y gobernanza en el que un agente de IA no tiene vía libre absoluta para ejecutar acciones irreversibles: se intercalan **puntos de aprobación humana (*Approval Gates*)**. El agente propone un plan o un comando de alto impacto (por ejemplo, `mkfs.ext4 /dev/sdb`, `iptables -F` o `rm -rf`), pero el sistema detiene la ejecución y exige la confirmación explícita del operador humano.
* **Impacto en Sistemas:** Es el estándar de oro en administración de servidores de producción y entornos de DevOps para prevenir pérdidas de datos catastróficas originadas por alucinaciones.
* 🔗 **Documentación Oficial:**
  * [NIST AI Risk Management Framework (AI RMF)](https://www.nist.gov/itl/ai-risk-management-framework)
  * [LangGraph Human-in-the-Loop Architecture](https://langchain-ai.github.io/langgraph/how-tos/human-in-the-loop/)

---

### Inferencia (Inference)
Proceso de **ejecución en vivo** de un modelo de lenguaje previamente entrenado. Recibe una secuencia de tokens de entrada (prompt), propaga los valores a través de las capas con pesos matemáticos congelados (*read-only*) y predice secuencialmente los tokens de salida uno por uno.
* **Impacto en Sistemas:** Requiere significativamente menos memoria que el entrenamiento. No calcula gradientes (`torch.no_grad()`), por lo que puede ejecutarse en CPUs estándar con memoria RAM convencional.
* 🔗 **Documentación Oficial:**
  * [PyTorch Inference Tutorial](https://pytorch.org/tutorials/beginner/inference_intro.html)
  * [Hugging Face LLM Inference Strategies](https://huggingface.co/docs/transformers/main/en/tasks/language_modeling)

---

### KV Cache (Key-Value Cache)
Técnica de optimización de memoria que almacena en RAM/VRAM los tensores de clave (*Keys*) y valor (*Values*) de los tokens previamente procesados durante la generación autoregresiva.
* **Impacto en Sistemas:** Evita que el modelo tenga que recalcular la atención de todo el historial de la conversación en cada palabra nueva generada, acelerando drásticamente la respuesta a costa de un consumo dinámico de memoria RAM.
* 🔗 **Documentación Oficial:**
  * [Hugging Face Key-Value Cache Explanation](https://huggingface.co/docs/transformers/en/llm_tutorial#key-value-cache)
  * [Efficient Memory Management for Large Language Model Serving (PagedAttention)](https://arxiv.org/abs/2309.06180)

---

### LLM Routing (Enrutamiento Dinámico de Modelos)
Arquitectura de optimización donde una capa de decisión ligera (un clasificador o un modelo pequeño) evalúa la complejidad del prompt entrante y lo redirige dinámicamente al modelo más eficiente en relación coste/rendimiento:
* Las preguntas sencillas de sintaxis o saludos se dirigen a modelos ultrarrápidos y económicos (como `llama3.2:3b` o Claude 3.5 Haiku).
* Los problemas arquitectónicos, algoritmos complejos o diagnósticos de fallos multietapa se enrutan a modelos de razonamiento profundo (como DeepSeek R1 o Claude 3.5 Sonnet).
* **Impacto en Sistemas:** Reduce los costes de computación y llamadas a API hasta en un **80%** manteniendo la máxima calidad en los casos difíciles.
* 🔗 **Documentación Oficial:**
  * [RouteLLM: Learning to Route LLMs with Preference Data (UC Berkeley / LMSYS)](https://arxiv.org/abs/2406.18665)
  * [LiteLLM Model Router Reference](https://docs.litellm.ai/docs/routing)

---

### MCP (Model Context Protocol)
Estándar abierto y universal desarrollado por Anthropic para conectar modelos de inteligencia artificial con fuentes de datos externas, herramientas locales y entornos operativos mediante JSON-RPC sobre entrada/salida estándar (`stdio`) o HTTP con Server-Sent Events (SSE).
* **Impacto en Sistemas:** Permite que un modelo consulte el estado de un servidor Linux, inspeccione discos o lea guías locales de forma segura y tipada sin necesidad de plugins propietarios.
* 🔗 **Documentación Oficial:**
  * [Model Context Protocol Specification](https://modelcontextprotocol.io/)
  * [Anthropic MCP Client and Server Documentation](https://docs.anthropic.com/en/docs/agents-and-tools/mcp)

---

### Memoria en Agentes (Working vs Long-Term Memory)
Mecanismo que permite a los agentes recordar información técnica a través del tiempo:
* **Memoria de Trabajo (*Working Memory* / Corto Plazo):** El contexto inmediato retenido en la ventana de tokens activa. Desaparece cuando el proceso o chat se reinicia.
* **Memoria Persistente (*Long-Term Memory* / Largo Plazo):** Capa de almacenamiento persistente (implementada con bases de datos vectoriales, almacenes clave-valor o herramientas como **Engram**) que registra decisiones pasadas, errores corregidos y preferencias de servidor del usuario para utilizarlas en sesiones futuras.
* 🔗 **Documentación Oficial / Referencias:**
  * [LangChain Memory Concepts](https://python.langchain.com/docs/concepts/#memory)
  * [Generative Agents: Interactive Simulacra of Human Behavior (Stanford University)](https://arxiv.org/abs/2304.03442)

---

### Método Socrático (Socratic Tutoring en IA)
Enfoque pedagógico donde el modelo de lenguaje actúa como un facilitador que guía al alumno mediante preguntas reflexivas, pistas graduadas y conceptos de fondo, en lugar de entregar directamente la solución o el comando final para copiar y pegar.
* **Impacto en Sistemas:** En este repositorio se implementa combinando la directiva de sistema [`system_prompt_tutor.md`](system_prompt_tutor.md) con la herramienta MCP `get_progressive_hint`.
* 🔗 **Documentación Oficial / Referencias:**
  * [Stanford NLP Pedagogical Dialogues Research](https://nlp.stanford.edu/)
  * [Prompt Engineering Guidelines for Educational Agents (Anthropic)](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering)

---

### Moshi (Kyutai Labs - Voz Full-Duplex)
Modelo fundacional multimodal de voz a voz en tiempo real de código abierto desarrollado por Kyutai Labs. A diferencia de las cadenas tradicionales de síntesis de voz (que encadenan transcripción ASR + modelo LLM + síntesis TTS con 1-2 segundos de latencia), Moshi procesa audio bidireccional continuo de extremo a extremo con latencias inferiores a **200 milisegundos**.
* **Impacto en Sistemas:** Permite interactuar conversacionalmente por voz natural con un servidor o terminal mientras se ejecutan tareas técnicas complejas.
* 🔗 **Documentación Oficial:**
  * [Kyutai Labs Official Website](https://kyutai.org/)
  * [Moshi Project and Live Demo](https://moshi.chat/)

---

### Ollama
Herramienta de empaquetado y ejecución de modelos de lenguaje en local. Proporciona una interfaz CLI unificada, administración de modelos (*hub* de descarga), gestión de hardware automática (CPU/GPU) y un servidor HTTP con endpoints compatibles con la API de OpenAI en el puerto `11434`.
* **Impacto en Sistemas:** Se ejecuta como servicio de fondo (`systemd` en Linux o proceso de bandeja en Windows/macOS) y encapsula el motor `llama.cpp`.
* 🔗 **Documentación Oficial:**
  * [Ollama Official Documentation & Repository](https://github.com/ollama/ollama)
  * [Ollama API Specification](https://github.com/ollama/ollama/blob/main/docs/api.md)

---

### Open WebUI
Interfaz gráfica de usuario basada en web diseñada para operar de forma 100% autónoma y privada, con soporte para Ollama, APIs compatibles con OpenAI, RAG con documentos, generación de imágenes y gestión multi-usuario.
* **Impacto en Sistemas:** Se distribuye como contenedor Docker o paquete de Python (`pip install open-webui`), comunicándose por HTTP con el backend de inferencia.
* 🔗 **Documentación Oficial:**
  * [Open WebUI Official Documentation](https://docs.openwebui.com/)
  * [Open WebUI GitHub Repository](https://github.com/open-webui/open-webui)

---

### PagedAttention
Algoritmo de gestión de memoria virtual inspirado en la paginación del kernel de los sistemas operativos (paginación por bloques en lugar de asignaciones contiguas), diseñado para el almacenamiento del **KV Cache** de modelos de lenguaje.
* **Impacto en Sistemas:** Elimina casi por completo la fragmentación de memoria en servidores de inferencia multi-usuario, permitiendo multiplicar el rendimiento hasta por 4x respecto a implementaciones tradicionales.
* 🔗 **Documentación Oficial:**
  * [vLLM Project: PagedAttention Original Paper](https://arxiv.org/abs/2309.06180)
  * [vLLM Documentation](https://docs.vllm.ai/)

---

### Parámetros de Muestreo (Temperature, Top-P, Top-K)
Hiperparámetros que controlan la aleatoriedad y diversidad matemática al seleccionar el siguiente token a partir de las probabilidades de salida (*logits*):
* **Temperature:** Controla la escala de entropía. Valores bajos (ej. `0.2`) producen respuestas deterministas y lógicas (ideal para código y comandos); valores altos (ej. `0.8`) aumentan la creatividad.
* **Top-P (Nucleus Sampling):** Descarta tokens cuya probabilidad acumulada supere un porcentaje determinado (ej. `0.9`).
* **Top-K:** Limita la selección exclusivamente a los $K$ tokens más probables.
* 🔗 **Documentación Oficial:**
  * [Hugging Face Text Generation Strategies](https://huggingface.co/docs/transformers/main/en/generation_strategies)
  * [Ollama Modelfile Parameters Reference](https://github.com/ollama/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values)

---

### RAG (Retrieval-Augmented Generation)
Arquitectura que combina un modelo de lenguaje con un sistema de recuperación de información externo. Antes de responder al usuario, el sistema busca fragmentos relevantes en una base de datos documental (mediante embeddings o búsqueda léxica) y los inyecta en el prompt del modelo como contexto confiable.
* **Impacto en Sistemas:** Previene alucinaciones y permite que el modelo responda con precisión sobre archivos privados o códigos locales sin necesidad de reentrenarlo.
* 🔗 **Documentación Oficial:**
  * [Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks (Lewis et al., Meta AI)](https://arxiv.org/abs/2005.11401)
  * [AWS Architecture Overview: What is RAG?](https://aws.amazon.com/what-is/retrieval-augmented-generation/)

---

### RAM de Sistema y Ancho de Banda (Memory Bandwidth)
La memoria principal de trabajo de la computadora (estándares DDR4 o DDR5). En inteligencia artificial, la velocidad de generación de tokens durante la inferencia en CPU está directamente limitada por el **ancho de banda de transferencia de memoria** (típicamente entre 30 y 80 GB/s) más que por la frecuencia de reloj del procesador.
* 🔗 **Documentación Oficial:**
  * [JEDEC DDR5 SDRAM Standard Specification](https://www.jedec.org/standards-documents/docs/jesd79-5)
  * [Intel Memory Architecture Guidelines](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)

---

### Rate Limits y Cuotas (TPM, RPM, RPD)
Mecanismos de control de tráfico impuestos por proveedores de APIs comerciales de IA para proteger su infraestructura contra abusos y gestionar la saturación:
* **RPM (Requests Per Minute):** Máximo de solicitudes HTTP por minuto.
* **TPM (Tokens Per Minute):** Máximo de tokens procesados por minuto (suma de prompt y respuesta).
* **RPD (Requests Per Day):** Límite total de peticiones diarias.
* 🔗 **Documentación Oficial:**
  * [OpenAI Rate Limits Documentation](https://platform.openai.com/docs/guides/rate-limits)
  * [Anthropic Rate Limits and Tier Structure](https://docs.anthropic.com/en/api/rate-limits)

---

### SGLang
Framework y motor de ejecución estructurado de última generación diseñado para acelerar la interacción y llamadas encadenadas a modelos de lenguaje (*Structured Generation Language*).
* **Impacto en Sistemas:** Optimiza el manejo de KV Cache mediante el intérprete RadixAttention y agiliza la decodificación de esquemas JSON estructurados.
* 🔗 **Documentación Oficial:**
  * [SGLang Official Documentation](https://sgl-project.github.io/)
  * [SGLang GitHub Repository](https://github.com/sgl-project/sglang)

---

### Skills (Habilidades Modulares de Agentes)
Paquetes modulares y autocontenidos que combinan instrucciones de comportamiento (*prompting* especializado), esquemas de validación y herramientas de código para dotar a un agente de una capacidad de dominio específica (por ejemplo: análisis de volcados de kernel, optimización de consultas SQL o configuración de reglas de firewall). El agente carga y descarga habilidades según la tarea en curso para no saturar su ventana de contexto.
* 🔗 **Documentación Oficial y Referencias del Sector:**
  * [Anthropic: Building Effective Agents and Skills](https://www.anthropic.com/research/building-effective-agents)
  * [Vercel AI SDK: Tools & Tool Calling Specification](https://sdk.vercel.ai/docs/ai-sdk-core/tools-and-tool-calling)
  * [Matt Pocock (Total TypeScript) - AI Skills and Rules](https://github.com/mattpocock)
  * [Semantic Kernel Plugin & Skill Documentation (Microsoft)](https://learn.microsoft.com/en-us/semantic-kernel/concepts/plugins/)

---

### System Prompt (Prompt de Sistema)
Instrucción directiva primordial que se envía al modelo al inicio de una conversación para establecer su personalidad, límites de comportamiento, metodología de respuesta y herramientas permitidas. Posee mayor jerarquía que los mensajes subsiguientes del usuario.
* **Impacto en Sistemas:** En este proyecto, el archivo [`system_prompt_tutor.md`](system_prompt_tutor.md) instruye al modelo para actuar como tutor socrático de servidores Linux.
* 🔗 **Documentación Oficial:**
  * [OpenAI Guide to System Messages](https://platform.openai.com/docs/guides/text-generation)
  * [Anthropic Prompt Engineering - System Prompts](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/system-prompts)

---

### Tokens y Tokenización
Un **token** es la unidad básica atómica de texto que procesa una red neuronal. No equivale necesariamente a una palabra completa: en promedio, 1 token corresponde aproximadamente a 4 caracteres en inglés o 2-3 caracteres en español o código fuente.
* **Tokenizador:** Algoritmo determinista (como Byte-Pair Encoding - BPE o SentencePiece) que convierte cadenas de texto sin procesar en secuencias de identificadores numéricos enteros.
* 🔗 **Documentación Oficial:**
  * [OpenAI Tokenizer Interactive Tool](https://platform.openai.com/tokenizer)
  * [Hugging Face Tokenizers Documentation](https://huggingface.co/docs/tokenizers/)
  * [Tiktoken Byte Pair Encoding Library](https://github.com/openai/tiktoken)

---

### Ventana de Contexto (Context Window)
Cantidad máxima de tokens totales (sumando el prompt del sistema, el historial de la conversación, los documentos adjuntos y la respuesta generada) que el modelo puede retener y atender simultáneamente en su memoria de trabajo.
* **Impacto en Sistemas:** Modelos modernos manejan desde 8.192 tokens (8k) hasta 1 o 2 millones de tokens. A mayor ventana de contexto, mayor es el consumo de memoria para el **KV Cache**.
* 🔗 **Documentación Oficial:**
  * [Anthropic Claude Context Window Documentation](https://docs.anthropic.com/en/docs/build-with-claude/context-window)
  * [Google Gemini Long Context Developer Guide](https://ai.google.dev/gemini-api/docs/long-context)

---

### vLLM
Servidor y biblioteca de inferencia de código abierto y alta velocidad para modelos de lenguaje, optimizado para entornos de producción, alto rendimiento (*throughput*) y servicio concurrente multi-usuario.
* **Impacto en Sistemas:** Implementa *PagedAttention*, decodificación continua por lotes (*continuous batching*) y paralelismo de tensores para clústeres de servidores.
* 🔗 **Documentación Oficial:**
  * [vLLM Official Documentation](https://docs.vllm.ai/)
  * [vLLM GitHub Repository](https://github.com/vllm-project/vllm)

---

### VRAM (Video RAM)
Memoria de acceso aleatorio de ultra-alta velocidad integrada físicamente en las tarjetas gráficas (GPU). Diseñada para ofrecer anchos de banda masivos (entre 300 GB/s y más de 1.000 GB/s en memorias GDDR6 o HBM3), fundamentales para procesar operaciones matriciales en paralelo sin cuellos de botella de bus.
* 🔗 **Documentación Oficial:**
  * [NVIDIA CUDA Memory Hierarchy Documentation](https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#memory-hierarchy)
