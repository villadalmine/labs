#!/usr/bin/env python3
"""
query_catalog.py - Utilitario de consulta y sincronización de metadatos de laboratorios Linux.

Permite:
- Sincronizar y generar 'catalog.json' leyendo los frontmatters YAML de los archivos Markdown.
- Filtrar laboratorios por entorno de prueba (WSL2, AWS EC2), sistema operativo, estado (PASSED/VERIFIED),
  nivel de complejidad, etiquetas (tags) y comandos/herramientas.
- Exportar contexto optimizado para sistemas RAG (Retrieval-Augmented Generation) y prompts de LLMs.
"""

import os
import sys
import json
import argparse
import re
from pathlib import Path

# Asegurar soporte de acentos y caracteres UTF-8 en cualquier consola (Windows / Linux)
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

try:
    import yaml
except ImportError:
    print("Advertencia: 'yaml' no está instalado. Instalalo con 'pip install pyyaml' para soportar sincronización completa.", file=sys.stderr)
    yaml = None

BASE_DIR = Path(__file__).resolve().parent
CATALOG_PATH = BASE_DIR / "catalog.json"
SCHEMA_PATH = BASE_DIR / "metadata.schema.json"

FRONTMATTER_REGEX = re.compile(r"^---\s*\r?\n(.*?)\r?\n---\s*\r?\n", re.DOTALL)


def extract_frontmatter(md_path: Path):
    """Extrae el frontmatter YAML y el contenido restante de un archivo Markdown."""
    try:
        content = md_path.read_text(encoding="utf-8")
    except Exception as e:
        print(f"Error leyendo {md_path}: {e}", file=sys.stderr)
        return None, ""

    match = FRONTMATTER_REGEX.match(content)
    if not match:
        return None, content

    yaml_text = match.group(1)
    body = content[match.end():]
    if yaml is None:
        return None, body

    try:
        data = yaml.safe_load(yaml_text)
        return data, body
    except Exception as e:
        print(f"Error parseando YAML en {md_path}: {e}", file=sys.stderr)
        return None, body


def scan_and_build_catalog():
    """Recorre todos los archivos .md bajo BASE_DIR, extrae su frontmatter y genera catalog.json."""
    if yaml is None:
        print("Error: Se requiere PyYAML para sincronizar el catálogo desde archivos Markdown.", file=sys.stderr)
        return False

    labs = []
    for md_file in sorted(BASE_DIR.rglob("*.md")):
        # Evitar el catálogo mismo o READMEs de soporte
        if md_file.name in ("README.md", "METADATA_SPEC.md", "GLOSARIO.md"):
            continue

        meta, _ = extract_frontmatter(md_file)
        if meta and isinstance(meta, dict) and "id" in meta:
            # Normalizar rutas relativas
            rel_path = str(md_file.relative_to(BASE_DIR)).replace("\\", "/")
            if "files" not in meta:
                meta["files"] = {}
            if "guide" not in meta["files"] or not meta["files"]["guide"]:
                meta["files"]["guide"] = rel_path

            # Asegurar consistencia de arrays planos
            if "tested_environments" in meta and isinstance(meta["tested_environments"], list):
                if "environments" not in meta or not meta["environments"]:
                    meta["environments"] = list(dict.fromkeys(
                        e.get("environment") for e in meta["tested_environments"] if e.get("environment")
                    ))
                if "operating_systems" not in meta or not meta["operating_systems"]:
                    meta["operating_systems"] = list(dict.fromkeys(
                        e.get("os") for e in meta["tested_environments"] if e.get("os")
                    ))
                if "status" not in meta or not meta["status"]:
                    # Si alguno falló -> FAILED, si todos PASSED -> PASSED, si alguno VERIFIED -> VERIFIED
                    statuses = [e.get("status") for e in meta["tested_environments"] if e.get("status")]
                    if "FAILED" in statuses:
                        meta["status"] = "FAILED"
                    elif "PASSED" in statuses:
                        meta["status"] = "PASSED"
                    elif "VERIFIED" in statuses:
                        meta["status"] = "VERIFIED"
                    else:
                        meta["status"] = "PENDING"

            labs.append(meta)

    # Ordenar por nivel de dificultad y sección
    def sort_key(item):
        lvl = item.get("difficulty_level", 99)
        sec = item.get("section", "99")
        try:
            sec_float = float(sec)
        except ValueError:
            sec_float = 99.0
        return (lvl, sec_float)

    labs.sort(key=sort_key)

    catalog_data = {
        "$schema": "./metadata.schema.json",
        "version": "1.0.0",
        "total_labs": len(labs),
        "updated_at": "2026-10-17T12:00:00Z",
        "labs": labs
    }

    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog_data, f, indent=2, ensure_ascii=False)

    print(f" Catálogo actualizado exitosamente con {len(labs)} laboratorios en: {CATALOG_PATH}")
    return True


def load_catalog():
    """Carga catalog.json del disco."""
    if not CATALOG_PATH.exists():
        print(f"Catálogo no encontrado en {CATALOG_PATH}. Intentando construirlo...", file=sys.stderr)
        scan_and_build_catalog()

    if not CATALOG_PATH.exists():
        print(f"Error: No se pudo generar {CATALOG_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def filter_labs(labs, args):
    """Aplica filtros combinados sobre la lista de laboratorios."""
    results = []
    for lab in labs:
        # Filtro de nivel
        if args.level is not None and lab.get("difficulty_level") != args.level:
            continue

        # Filtro de categoría
        if args.category and lab.get("category", "").lower() != args.category.lower():
            continue

        # Filtro de estado
        if args.status:
            target_status = args.status.upper()
            lab_status = lab.get("status", "").upper()
            env_statuses = [e.get("status", "").upper() for e in lab.get("tested_environments", [])]
            if lab_status != target_status and target_status not in env_statuses:
                continue

        # Filtro de entorno (WSL2, AWS EC2, Bare-Metal, etc.)
        if args.env:
            target_env = args.env.lower()
            envs = [e.lower() for e in lab.get("environments", [])]
            env_objs = [e.get("environment", "").lower() for e in lab.get("tested_environments", [])]
            if not any(target_env in x for x in envs + env_objs):
                continue

        # Filtro de sistema operativo
        if args.os:
            target_os = args.os.lower()
            os_list = [o.lower() for o in lab.get("operating_systems", [])]
            env_os = [e.get("os", "").lower() for e in lab.get("tested_environments", [])]
            if not any(target_os in x for x in os_list + env_os):
                continue

        # Filtro de etiquetas (tags)
        if args.tag:
            target_tag = args.tag.lower()
            tags = [t.lower() for t in lab.get("tags", [])]
            if not any(target_tag in t for t in tags):
                continue

        # Filtro de herramientas (tools)
        if args.tool:
            target_tool = args.tool.lower()
            tools = [t.lower() for t in lab.get("tools", [])]
            if not any(target_tool in t for t in tools):
                continue

        # Filtro directo por ID
        if args.id and lab.get("id", "").lower() != args.id.lower():
            continue

        # Búsqueda de texto libre en ID, título, resumen y tags
        if args.search:
            kw = args.search.lower()
            lab_id = lab.get("id", "").lower()
            title = lab.get("title", "").lower()
            summary = lab.get("rag_summary", "").lower()
            tags = " ".join(lab.get("tags", [])).lower()
            if kw not in lab_id and kw not in title and kw not in summary and kw not in tags:
                continue

        results.append(lab)
    return results


def print_table(labs):
    """Imprime un resumen tabular formateado para la terminal."""
    if not labs:
        print("No se encontraron laboratorios que coincidan con los filtros especificados.")
        return

    print(f"\n{'ID':<30} | {'Sec':<4} | {'Nvl':<3} | {'Estado':<8} | {'Entornos':<14} | {'Título'}")
    print("-" * 115)
    for l in labs:
        id_str = l.get("id", "")[:29]
        sec = l.get("section", "-")
        lvl = str(l.get("difficulty_level", "-"))
        status = l.get("status", "PENDING")
        envs = ", ".join(l.get("environments", []))[:13]
        title = l.get("title", "")
        print(f"{id_str:<30} | {sec:<4} | {lvl:<3} | {status:<8} | {envs:<14} | {title}")
    print(f"\nTotal: {len(labs)} laboratorio(s) encontrado(s).\n")


def export_rag_context(labs):
    """Genera un fragmento de texto enriquecido óptimo para inyectar en el contexto de un LLM."""
    print("### CATÁLOGO DE LABORATORIOS LINUX VERIFICADOS (CONTEXTO PARA RAG)\n")
    for l in labs:
        print(f"#### [{l.get('id')}] {l.get('title')}")
        print(f"- **Nivel y Sección:** Nivel {l.get('difficulty_level')} (Sección {l.get('section')}) | Categoría: {l.get('category')}")
        print(f"- **Estado General:** {l.get('status')} | **Entornos:** {', '.join(l.get('environments', []))}")
        print(f"- **Sistemas Operativos:** {', '.join(l.get('operating_systems', []))}")
        print(f"- **Herramientas Clave:** {', '.join(l.get('tools', []))}")
        print(f"- **Tags:** {', '.join(l.get('tags', []))}")
        print(f"- **Ruta Guía:** {l.get('files', {}).get('guide')}")
        if l.get('files', {}).get('script'):
            print(f"- **Script Demo:** {l.get('files', {}).get('script')}")
        print(f"- **Resumen Técnico:** {l.get('rag_summary')}")
        print("- **Detalle de Ambientes Probados:**")
        for env in l.get("tested_environments", []):
            print(f"  * {env.get('environment')} ({env.get('os')}): {env.get('status')} - {env.get('notes')}")
        print()


def main():
    parser = argparse.ArgumentParser(
        description="Buscador y sincronizador de laboratorios Linux para humanos y agentes de IA."
    )
    parser.add_argument("--sync", action="store_true", help="Escanea los archivos .md y regenera catalog.json")
    parser.add_argument("--list", action="store_true", help="Lista todos los laboratorios registrados")
    parser.add_argument("--id", type=str, help="Filtra por ID exacto de laboratorio (ej: lab-3.6-monitoreo-metricas)")
    parser.add_argument("--tag", type=str, help="Filtra por etiqueta (ej: storage, lvm, prometheus)")
    parser.add_argument("--tool", type=str, help="Filtra por herramienta (ej: tune2fs, nice, borg)")
    parser.add_argument("--env", type=str, help="Filtra por entorno (ej: WSL2, AWS EC2, Bare-Metal)")
    parser.add_argument("--os", type=str, help="Filtra por sistema operativo (ej: Ubuntu 24.04, Debian 12)")
    parser.add_argument("--status", type=str, choices=["PASSED", "VERIFIED", "FAILED", "PENDING"], help="Filtra por resultado de prueba")
    parser.add_argument("--level", type=int, choices=[0, 1, 2, 3, 4], help="Filtra por nivel de dificultad")
    parser.add_argument("--category", type=str, help="Filtra por categoría tecnológica")
    parser.add_argument("--search", type=str, help="Búsqueda de texto libre")
    parser.add_argument("--json", action="store_true", help="Salida en formato JSON crudo")
    parser.add_argument("--rag-context", action="store_true", help="Exporta texto denso formateado para prompts RAG")

    args = parser.parse_args()

    if args.sync:
        success = scan_and_build_catalog()
        if not success:
            sys.exit(1)
        if not (args.list or args.id or args.search or args.tag or args.env or args.os or args.status or args.level or args.json or args.rag_context):
            return

    catalog = load_catalog()
    labs = catalog.get("labs", [])

    filtered = filter_labs(labs, args)

    if args.json:
        print(json.dumps(filtered, indent=2, ensure_ascii=False))
    elif args.rag_context:
        export_rag_context(filtered)
    else:
        print_table(filtered)


if __name__ == "__main__":
    main()
