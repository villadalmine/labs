#!/usr/bin/env python3
"""
labs_mcp_server.py - Servidor MCP (Model Context Protocol) nativo para el Tutor de Laboratorios Linux.

Implementa la especificación JSON-RPC 2.0 de MCP sobre stdio (entrada/salida estándar).
Permite que cualquier cliente o agente autónomo (Goose CLI, Cline, Claude Desktop,
Continue.dev, jdev, Open WebUI) consulte el catálogo de laboratorios, obtenga recomendaciones
pedagógicas, lea guías y verifique la preparación del alumno mediante llamadas a herramientas.
"""

import sys
import os
import json
from pathlib import Path

# Configurar UTF-8 en stdin/stdout
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
        sys.stdin.reconfigure(encoding="utf-8")
    except Exception:
        pass

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ADMIN_DIR = REPO_ROOT / "linux" / "administrator"
CATALOG_PATH = ADMIN_DIR / "catalog.json"


def load_catalog():
    if not CATALOG_PATH.exists():
        sys.path.insert(0, str(ADMIN_DIR))
        from manage_catalog import sync_catalog
        sync_catalog()
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        return json.load(f).get("labs", [])


TOOLS = [
    {
        "name": "get_student_roadmap",
        "description": "Calcula y recomienda el siguiente laboratorio ideal para el estudiante analizando su entorno (WSL2, AWS EC2, Bare-Metal), sistema operativo y lista de laboratorios ya cursados.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "environment": {
                    "type": "string",
                    "description": "Entorno del alumno: WSL2, AWS EC2, Bare-Metal o Docker",
                    "default": "WSL2"
                },
                "os": {
                    "type": "string",
                    "description": "Distribución Linux del alumno (ej: Ubuntu 24.04 LTS)",
                    "default": "Ubuntu 24.04 LTS"
                },
                "completed_labs": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Lista de IDs de laboratorios ya completados por el alumno",
                    "default": []
                }
            }
        }
    },
    {
        "name": "get_lab_details",
        "description": "Obtiene la ficha técnica completa de un laboratorio por su ID (título, nivel, sección, tags, herramientas, prerrequisitos, herramientas MCP necesarias y resumen denso).",
        "inputSchema": {
            "type": "object",
            "required": ["lab_id"],
            "properties": {
                "lab_id": {
                    "type": "string",
                    "description": "ID canónico del laboratorio (ej: lab-3.1-anatomia-filesystems, lab-3.6-monitoreo-metricas)"
                }
            }
        }
    },
    {
        "name": "search_curriculum",
        "description": "Busca laboratorios en el plan de estudios filtrando por etiqueta temática, categoría, herramienta CLI o palabra clave en el resumen.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Texto libre a buscar en título o resumen"},
                "tag": {"type": "string", "description": "Etiqueta temática (ej: storage, lvm, prometheus, btrfs)"},
                "category": {"type": "string", "description": "Categoría (fundamentals, processes, systemd, storage, security, observability, cloud-iac)"},
                "tool": {"type": "string", "description": "Comando evaluado (ej: tune2fs, nice, borg, lvextend)"},
                "environment": {"type": "string", "description": "Filtrar por compatibilidad de entorno (WSL2, AWS EC2)"},
                "has_script": {"type": "boolean", "description": "Filtrar solo laboratorios con scripts interactivos de prueba"}
            }
        }
    },
    {
        "name": "verify_student_readiness",
        "description": "Verifica si el alumno cuenta con los requisitos necesarios (permisos root, cuenta cloud) para ejecutar un laboratorio sin bloqueos.",
        "inputSchema": {
            "type": "object",
            "required": ["lab_id"],
            "properties": {
                "lab_id": {"type": "string", "description": "ID del laboratorio"},
                "environment": {"type": "string", "description": "Entorno del alumno", "default": "WSL2"},
                "has_root": {"type": "boolean", "description": "Si el alumno cuenta con permisos sudo / root", "default": False},
                "has_aws": {"type": "boolean", "description": "Si el alumno tiene configurado AWS CLI y Terraform", "default": False}
            }
        }
    },
    {
        "name": "read_lab_guide",
        "description": "Lee el contenido Markdown completo de la guía teórica y procedimental de un laboratorio para explicar conceptos o guiar paso a paso.",
        "inputSchema": {
            "type": "object",
            "required": ["lab_id"],
            "properties": {
                "lab_id": {"type": "string", "description": "ID del laboratorio a consultar"}
            }
        }
    }
]


def execute_tool(name: str, arguments: dict):
    labs = load_catalog()

    if name == "get_student_roadmap":
        sys.path.insert(0, str(ADMIN_DIR))
        from tutor_engine import recommend_next_lab
        env = arguments.get("environment", "WSL2")
        os_name = arguments.get("os", "Ubuntu 24.04 LTS")
        completed = arguments.get("completed_labs", [])
        return recommend_next_lab(student_env=env, student_os=os_name, completed_labs=completed)

    elif name == "get_lab_details":
        lab_id = arguments.get("lab_id")
        lab = next((l for l in labs if l.get("id") == lab_id), None)
        if not lab:
            return {"error": f"Laboratorio '{lab_id}' no encontrado en el catálogo."}
        return lab

    elif name == "search_curriculum":
        results = []
        q = arguments.get("query", "").lower()
        tag = arguments.get("tag", "").lower()
        cat = arguments.get("category", "").lower()
        tool = arguments.get("tool", "").lower()
        env = arguments.get("environment", "").lower()
        has_script = arguments.get("has_script")

        for l in labs:
            if cat and l.get("category", "").lower() != cat:
                continue
            if tag and not any(tag in t.lower() for t in l.get("tags", [])):
                continue
            if tool and not any(tool in t.lower() for t in l.get("tools", [])):
                continue
            if env:
                envs = [x.lower() for x in l.get("environments", [])]
                if env not in envs:
                    continue
            if has_script is not None and l.get("has_interactive_script") != has_script:
                continue
            if q:
                blob = f"{l.get('id')} {l.get('title')} {l.get('rag_summary')} {' '.join(l.get('tags', []))}".lower()
                if q not in blob:
                    continue
            results.append({
                "id": l.get("id"),
                "title": l.get("title"),
                "level": l.get("difficulty_level"),
                "section": l.get("section"),
                "category": l.get("category"),
                "resource_type": l.get("resource_type"),
                "environments": l.get("environments"),
                "mcp_tools": l.get("mcp_tools")
            })
        return {"total_found": len(results), "labs": results}

    elif name == "verify_student_readiness":
        sys.path.insert(0, str(ADMIN_DIR))
        from tutor_engine import verify_lab_readiness
        lab_id = arguments.get("lab_id")
        env = arguments.get("environment", "WSL2")
        has_root = arguments.get("has_root", False)
        has_aws = arguments.get("has_aws", False)
        return verify_lab_readiness(lab_id, student_env=env, has_root=has_root, has_aws=has_aws)

    elif name == "read_lab_guide":
        lab_id = arguments.get("lab_id")
        lab = next((l for l in labs if l.get("id") == lab_id), None)
        if not lab:
            return {"error": f"Laboratorio '{lab_id}' no encontrado."}
        guide_rel = lab.get("files", {}).get("guide")
        if not guide_rel:
            return {"error": f"El laboratorio '{lab_id}' no define archivo de guía."}
        guide_path = ADMIN_DIR / guide_rel
        if not guide_path.exists():
            return {"error": f"Archivo de guía no encontrado en {guide_path}."}
        return {
            "lab_id": lab_id,
            "title": lab.get("title"),
            "guide_path": str(guide_rel),
            "content": guide_path.read_text(encoding="utf-8")
        }

    return {"error": f"Herramienta desconocida: {name}"}


def send_response(response_dict):
    """Envía un mensaje JSON-RPC formateado sobre stdout."""
    line = json.dumps(response_dict, ensure_ascii=False)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def main():
    """Bucle principal de escucha JSON-RPC 2.0 sobre stdin."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError as e:
            continue

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {})

        if method == "initialize":
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {}
                    },
                    "serverInfo": {
                        "name": "linux-labs-tutor",
                        "version": "1.0.0"
                    }
                }
            })

        elif method == "notifications/initialized":
            # Notificación de inicialización del cliente, no requiere respuesta
            pass

        elif method == "ping":
            send_response({"jsonrpc": "2.0", "id": req_id, "result": {}})

        elif method == "tools/list":
            send_response({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "tools": TOOLS
                }
            })

        elif method == "tools/call":
            tool_name = params.get("name")
            tool_args = params.get("arguments", {})
            try:
                res = execute_tool(tool_name, tool_args)
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": json.dumps(res, indent=2, ensure_ascii=False)
                            }
                        ]
                    }
                })
            except Exception as e:
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "isError": True,
                    "result": {
                        "content": [
                            {
                                "type": "text",
                                "text": f"Error ejecutando herramienta {tool_name}: {str(e)}"
                            }
                        ]
                    }
                })

        else:
            if req_id is not None:
                send_response({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {
                        "code": -32601,
                        "message": f"Método no implementado: {method}"
                    }
                })


if __name__ == "__main__":
    main()
