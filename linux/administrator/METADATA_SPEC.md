# Especificación de Metadatos y Catálogo Estructurado para RAG / IA

Esta especificación define el estándar de metadatos del repositorio para laboratorios, guías y scripts de administración de servidores Linux.

El objetivo central es permitir que cualquier motor de **Retrieval-Augmented Generation (RAG)**, base de datos vectorial (como Chroma, Pinecone, Qdrant, Weaviate o pgvector) o asistente autónomo de Inteligencia Artificial pueda:

1. **Filtrar determinísticamente** laboratorios por ambiente de prueba (`WSL2`, `AWS EC2`, `Bare-Metal`, `Docker`).
2. **Validar si el laboratorio funcionó** (`PASSED`, `VERIFIED`, `FAILED`, `PENDING`).
3. **Conocer la distribución y versión de Linux** sobre la que se certificó (`Ubuntu 24.04 LTS`, `Debian 12`, etc.).
4. **Segmentar por tags temáticos, herramientas y nivel de complejidad** (`storage`, `lvm`, `raid1`, `prometheus`, `systemd`, `level: 3`).
5. **Recuperar texto denso** mediante el campo semántico `rag_summary` para maximizar la similitud en embeddings.

---

## 🏛️ Arquitectura del Sistema de Metadatos

El sistema implementa una **estrategia dual** complementaria:

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                 GUÍAS MARKDOWN (*.md)                   │
                  │   Encabezado YAML Frontmatter al inicio de cada archivo │
                  └────────────────────────────┬────────────────────────────┘
                                               │
                           Sincronización con  │  python query_catalog.py --sync
                                               ▼
                  ┌─────────────────────────────────────────────────────────┐
                  │          REGISTRO CENTRAL: catalog.json                 │
                  │   Índice consolidado y normalizado de todo el repo      │
                  └──────┬──────────────────────────────────────────┬───────┘
                         │                                          │
                         ▼                                          ▼
           ┌───────────────────────────┐              ┌───────────────────────────┐
           │     CONSULTAS CLI / DEV   │              │   INGESTA RAG / VECTOR DB │
           │  python query_catalog.py  │              │ LangChain / LlamaIndex    │
           │  ./query_catalog.sh       │              │ Metadata Filter & Chunks  │
           └───────────────────────────┘              └───────────────────────────┘
```

1. **Nivel Documento (YAML Frontmatter):** Cada archivo `.md` incluye al inicio un bloque delimitado por `---` con los metadatos estructurados. Los cargadores de RAG (e.g. `UnstructuredMarkdownLoader`, `FrontmatterLoader`) los extraen directamente como atributos del documento.
2. **Nivel Repositorio (`catalog.json`):** Un archivo JSON consolidado que reúne todos los laboratorios en un único índice. Permite a una IA o a un script realizar consultas estructuradas en milisegundos sin recorrer el árbol de archivos.
3. **Esquema Formal (`metadata.schema.json`):** Valida la integridad de tipos, formatos y enumeraciones mediante JSON Schema (Draft 2020-12).

---

## 📋 Estructura y Campos del Frontmatter

A continuación se detalla la plantilla estándar a incluir en cada guía:

```yaml
---
id: "lab-3.1-anatomia-filesystems"
title: "Anatomía de Sistemas de Archivos (ext4, XFS, Btrfs, tmpfs) y Diagnóstico Forense"
difficulty_level: 3
difficulty_label: "Nivel 3: Almacenamiento, Filesystems, Cifrado, Respaldos y Monitoreo"
section: "3.1"
sections:
  - "3.1"
  - "3"
category: "storage"
tags:
  - "storage"
  - "filesystems"
  - "ext4"
  - "xfs"
  - "btrfs"
  - "tmpfs"
  - "tune2fs"
  - "dumpe2fs"
  - "xfs_info"
  - "inodes"
  - "forensics"
tools:
  - "tune2fs"
  - "dumpe2fs"
  - "xfs_info"
  - "xfs_growfs"
  - "btrfs"
  - "e2fsck"
  - "df"
requirements:
  root_required: true
  cloud_required: false
  min_ram_mb: 1024
  min_disks: 0
tested_environments:
  - environment: "WSL2"
    type: "local"
    instance_type: "virtualized"
    os: "Ubuntu 24.04 LTS"
    kernel: "6.18.54.1-microsoft-standard-WSL2"
    status: "PASSED"
    test_date: "2026-10-17"
    notes: "Ejecución automatizada mediante demo_filesystems.sh sobre loop devices. Inodos y superbloques validados."
  - environment: "AWS EC2"
    type: "cloud"
    instance_type: "t3.micro"
    os: "Ubuntu 24.04 LTS"
    status: "VERIFIED"
    test_date: "2026-10-17"
    notes: "Compatible en instancias EBS t3.micro."
environments:
  - "WSL2"
  - "AWS EC2"
operating_systems:
  - "Ubuntu 24.04 LTS"
status: "PASSED"
rag_summary: "Laboratorio sobre la estructura interna de sistemas de archivos en Linux. Cubre diferencias arquitecturales entre ext4, XFS y Btrfs, inspección y ajuste de superbloques con tune2fs y dumpe2fs, resolución forense del agotamiento de inodos y rescate de particiones dañadas mediante superbloques de respaldo."
files:
  guide: "filesystems/anatomia_filesystems.md"
  script: "filesystems/demo_filesystems.sh"
  terraform: null
---
```

---

## 🏷️ Diccionario de Términos y Valores Permitidos

### 1. `tested_environments[].environment`
- `WSL2`: Windows Subsystem for Linux v2 (con kernel Linux oficial de Microsoft).
- `AWS EC2`: Instancias virtuales elásticas en Amazon Web Services (e.g. `t3.micro`, `t2.micro`).
- `Bare-Metal`: Servidor físico real sobre hardware dedicado.
- `Docker`: Contenedor Linux aislado.
- `QEMU/KVM`: Máquina virtual sobre hipervisor KVM.

### 2. `tested_environments[].status` y `status` general
- `PASSED`: El laboratorio y su script interactivo fueron ejecutados de punta a punta y completaron todas las pruebas con código de salida `0` sin errores.
- `VERIFIED`: La arquitectura, comandos y configuraciones fueron verificadas en dicha plataforma o son completamente compatibles por diseño agnóstico.
- `FAILED`: La ejecución falló o requiere dependencias de kernel inexistentes en ese ambiente.
- `PENDING`: Laboratorio diseñado pero pendiente de prueba en esa plataforma específica.

### 3. `category`
- `fundamentals`: Compilación C, Makefiles, llamadas al sistema POSIX.
- `processes`: Control de trabajos, señales Unix, prioridades nice, CFS y zombies.
- `systemd`: Unidades de servicio, timers de reemplazo de cron, sockets y cgroups v2.
- `storage`: Dispositivos de bloque, loop devices, LVM2, filesystems (ext4/XFS/Btrfs/ZFS).
- `security`: Cifrado en reposo LUKS dm-crypt y FUSE gocryptfs.
- `observability`: Monitoreo de métricas, Node Exporter, collectors de texto y diagnóstico en vivo.
- `cloud-iac`: Proyectos integradores en AWS con Terraform y multi-tiering.
- `reference`: Guías de consulta rápida y chuletas operativas.

---

## 🤖 Integración con RAG e Inteligencia Artificial

### 1. Filtrado de Metadatos en Bases de Datos Vectoriales

Cuando se indexan los documentos en una base vectorial (Chroma, Qdrant, Pinecone), los campos `environments`, `operating_systems`, `tags`, `difficulty_level` y `status` se almacenan en el payload de cada chunk.

#### Ejemplo de Consulta Semántica Asistida:
> *"Dame un laboratorio de nivel 3 sobre monitoreo de mirrors RAID que haya sido probado y aprobado en WSL2 con Ubuntu 24.04."*

El recuperador RAG aplica el siguiente filtro determinístico antes de calcular la distancia del coseno:

```python
# Ejemplo de filtro en Chroma / LangChain
results = vector_store.similarity_search(
    query="monitoreo de mirrors RAID y metricas continuas",
    filter={
        "$and": [
            {"difficulty_level": {"$eq": 3}},
            {"status": {"$eq": "PASSED"}},
            {"environments": {"$in": ["WSL2"]}},
            {"operating_systems": {"$in": ["Ubuntu 24.04 LTS"]}},
            {"tags": {"$in": ["monitoring", "storage"]}}
        ]
    },
    k=3
)
```

### 2. Uso del campo `rag_summary`
El campo `rag_summary` contiene un resumen de alta densidad semántica (sin código ni ruido de formato). Durante la etapa de indexación, este campo puede ser vectorizado como un embedding complementario del documento completo (*Parent Document Retrieval* / *Hierarchical Indexing*), garantizando que la búsqueda encuentre el laboratorio exacto incluso con preguntas abstractas del usuario.

---

## 🛠️ Herramientas CLI: Consulta, ABM y Motor Pedagógico

El repositorio dispone de tres utilitarios complementarios:

### 1. `query_catalog.py`: Consultas y RAG Context
```bash
# Listar todos los laboratorios con su estado y ambiente
python query_catalog.py --list

# Filtrar por tag temático (ej: storage, lvm, monitoring, btrfs)
python query_catalog.py --tag storage

# Filtrar por ambiente y estado de prueba
python query_catalog.py --env WSL2 --status PASSED

# Filtrar por sistema operativo
python query_catalog.py --os "Ubuntu 24.04 LTS"

# Exportar contexto estructurado para el system prompt de un LLM / RAG
python query_catalog.py --rag-context
```

### 2. `manage_catalog.py`: Motor ABM (Alta, Baja, Modificación) y Validación
Permite extender o modificar el esquema iterando automáticamente sobre todos los archivos `.md`:
```bash
# Autodetectar scripts/terraform y rellenar tipos de recurso y modos de ejecución
python manage_catalog.py populate

# ALTA DE CAMPO: Agregar un nuevo atributo con valor por defecto a todos los laboratorios
python manage_catalog.py add-field --field "target_role" --default "devops-engineer"

# BAJA DE CAMPO: Eliminar un atributo obsoleto en todo el repositorio
python manage_catalog.py remove-field --field "target_role"

# MODIFICACIÓN: Actualizar un atributo de un laboratorio puntual
python manage_catalog.py set --id lab-3.6-monitoreo-metricas --field "difficulty_level" --value 3

# SCAFFOLD: Generar la plantilla de un nuevo laboratorio con frontmatter validado
python manage_catalog.py new-lab --id lab-1.5-strace --title "Diagnóstico de Syscalls con strace" --category processes --section 1.5

# VALIDACIÓN: Validar cumplimiento del esquema formal
python manage_catalog.py validate

# SINCRONIZACIÓN: Reconstruir catalog.json
python manage_catalog.py sync
```

### 3. `tutor_engine.py`: Motor de Decisiones para Protocolos de Agentes (jdev / MCP)
Diseñado para que agentes autónomos tomen decisiones algorítmicas sin alucinar:
```bash
# Recomendar siguiente laboratorio según ambiente y trayectoria
python tutor_engine.py recommend --env WSL2 --os "Ubuntu 24.04 LTS" --completed lab-0.1-compilar

# Verificar si el alumno cumple los requisitos de ejecución
python tutor_engine.py verify --id lab-3.2-lvm2-online-resize --env WSL2 --root
```
