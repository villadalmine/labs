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
import subprocess
import platform
import shutil
from pathlib import Path

# Configurar UTF-8 en stdin/stdout
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
        sys.stdin.reconfigure(encoding="utf-8")
    except Exception:
        pass

REPO_ROOT = Path(__file__).resolve().parents[3]
ADMIN_DIR = REPO_ROOT / "linux" / "administrator"
TUTOR_DIR = REPO_ROOT / "ai" / "tutor"
CATALOG_PATH = ADMIN_DIR / "catalog.json"

sys.path.insert(0, str(TUTOR_DIR))
sys.path.insert(0, str(ADMIN_DIR))


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
    },
    {
        "name": "get_progressive_hint",
        "description": "Proporciona una pista graduada (Nivel 1: Concepto teórico socrático; Nivel 2: Comandos/flags a investigar; Nivel 3: Sintaxis de referencia del script) extrayendo dinámicamente la información del laboratorio sin revelar la solución directa.",
        "inputSchema": {
            "type": "object",
            "required": ["lab_id", "hint_level"],
            "properties": {
                "lab_id": {
                    "type": "string",
                    "description": "ID del laboratorio en curso (ej: lab-1.2-proceso-zombie, lab-3.3-cifrado-luks)"
                },
                "hint_level": {
                    "type": "integer",
                    "description": "Nivel de pista: 1 (solo concepto teórico sin comandos), 2 (comandos/flags a buscar), 3 (ejemplo de referencia análogo)",
                    "minimum": 1,
                    "maximum": 3,
                    "default": 1
                },
                "step": {
                    "type": "integer",
                    "description": "Número de paso o sección donde está trabado el alumno (opcional)"
                }
            }
        }
    },
    {
        "name": "check_lab_environment",
        "description": "Ejecuta una radiografía rápida y no destructiva de solo lectura del entorno Linux (kernel, loop devices, discos, inodos, unidades systemd con fallas, procesos zombies y memoria) para que el tutor evalúe el estado del alumno.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "lab_id": {
                    "type": "string",
                    "description": "ID del laboratorio para cruzar requisitos técnicos (opcional)"
                }
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

    elif name == "get_progressive_hint":
        lab_id = arguments.get("lab_id")
        hint_level = int(arguments.get("hint_level", 1))
        step = arguments.get("step")

        lab = next((l for l in labs if l.get("id") == lab_id), None)
        if not lab:
            return {"error": f"Laboratorio '{lab_id}' no encontrado en el catálogo."}

        guide_rel = lab.get("files", {}).get("guide")
        guide_text = ""
        if guide_rel:
            gp = ADMIN_DIR / guide_rel
            if gp.exists():
                guide_text = gp.read_text(encoding="utf-8")

        script_rel = lab.get("files", {}).get("script")
        script_text = ""
        if script_rel:
            sp = ADMIN_DIR / script_rel
            if sp.exists():
                script_text = sp.read_text(encoding="utf-8")

        if hint_level == 1:
            directive = (
                "DIRECTIVA SOCRÁTICA NIVEL 1 (Concepto Teórico): Explica el principio del sistema operativo, "
                "mecanismo del kernel o arquitectura involucrada para orientar al alumno. PROHIBIDO dar comandos "
                "exactos, nombres de flags ni soluciones terminadas."
            )
            reference = {
                "rag_summary": lab.get("rag_summary"),
                "tags": lab.get("tags"),
                "category": lab.get("category"),
                "prerequisites": lab.get("prerequisites"),
            }
        elif hint_level == 2:
            directive = (
                "DIRECTIVA SOCRÁTICA NIVEL 2 (Comandos y Búsqueda): Indica qué comandos, binarios o archivos "
                "del sistema (/proc, /sys, man) y flags generales debe investigar el alumno. No le des los "
                "argumentos específicos del ejercicio."
            )
            reference = {
                "tools": lab.get("tools"),
                "guide_excerpt": guide_text[:2000] if guide_text else "Sin guía.",
            }
        else:
            directive = (
                "DIRECTIVA SOCRÁTICA NIVEL 3 (Sintaxis de Referencia): Muestra un ejemplo de sintaxis formal "
                "o análogo basado en el script de prueba, recordando al alumno que es un modelo y no la respuesta directa."
            )
            reference = {
                "script_name": script_rel,
                "script_snippet": script_text[:2000] if script_text else "Sin script asociado.",
            }

        return {
            "lab_id": lab_id,
            "title": lab.get("title"),
            "hint_level": hint_level,
            "step": step,
            "tutor_directive": directive,
            "reference_data": reference,
        }

    elif name == "check_lab_environment":
        lab_id = arguments.get("lab_id")
        lab = next((l for l in labs if l.get("id") == lab_id), None) if lab_id else None

        def run_diag(cmd: list[str]) -> str:
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
                out = (r.stdout or r.stderr or "").strip()
                return out if out else "(sin salida)"
            except Exception as e:
                return f"No disponible ({e})"

        diag = {
            "platform": platform.platform(),
            "kernel": run_diag(["uname", "-srm"]),
            "block_devices": run_diag(["lsblk", "-f"]),
            "loop_devices": run_diag(["losetup", "-a"]),
            "disk_usage": run_diag(["df", "-hT", "/", "/tmp"]),
            "inodes": run_diag(["df", "-i", "/", "/tmp"]),
            "failed_services": run_diag(["systemctl", "--failed", "--no-legend", "--no-pager"]),
            "zombie_processes": run_diag(["sh", "-c", "ps -eo pid,ppid,stat,comm | awk '$3 ~ /Z/'"]),
            "memory": run_diag(["free", "-h"]),
        }

        response = {
            "system_snapshot": diag,
        }

        if lab:
            reqs = lab.get("requirements", {})
            root_needed = reqs.get("root_required", False)
            is_root = (os.geteuid() == 0) if hasattr(os, "geteuid") else False
            missing_tools = [t for t in lab.get("tools", []) if not shutil.which(t)]

            response["lab_compliance"] = {
                "lab_id": lab.get("id"),
                "title": lab.get("title"),
                "root_required": root_needed,
                "is_current_user_root": is_root,
                "root_status": "OK" if (not root_needed or is_root) else "FAIL (requiere sudo / root)",
                "missing_tools": missing_tools,
                "tools_status": "OK" if not missing_tools else f"Faltan instalar: {', '.join(missing_tools)}",
            }

        return response

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
