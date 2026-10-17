#!/usr/bin/env python3
"""
manage_catalog.py - Motor de Gestión, Mantenimiento y ABM (Alta, Baja, Modificación)
para Metadatos de Laboratorios Linux.

Permite:
- [Alta/Extensión de Campo]: Añadir dinámicamente nuevos atributos a todos los archivos .md.
- [Baja de Campo]: Eliminar atributos obsoletos de todos los archivos .md.
- [Modificación de Metadatos]: Modificar valores puntuales o en lote para uno o varios labs.
- [Scaffold de Nuevo Lab]: Generar una nueva plantilla .md con frontmatter completo y validado.
- [Auto-Detección y Poblado]: Detectar automáticamente scripts .sh y carpetas terraform para
  asustar resource_type, has_interactive_script, has_terraform y execution_mode.
- [Validación de Esquema]: Validar todos los documentos contra metadata.schema.json.
- [Sincronización]: Reconstruir catalog.json.
"""

import os
import sys
import json
import argparse
import re
from pathlib import Path

# Soporte de codificación UTF-8 en consola
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

try:
    import yaml
except ImportError:
    print("Error: PyYAML no está instalado. Ejecute 'pip install pyyaml'.", file=sys.stderr)
    sys.exit(1)

BASE_DIR = Path(__file__).resolve().parent
CATALOG_PATH = BASE_DIR / "catalog.json"
SCHEMA_PATH = BASE_DIR / "metadata.schema.json"

FRONTMATTER_REGEX = re.compile(r"^---\s*\r?\n(.*?)\r?\n---\s*\r?\n", re.DOTALL)


def get_all_lab_files():
    """Retorna la lista ordenada de archivos Markdown de laboratorio."""
    files = []
    for md in sorted(BASE_DIR.rglob("*.md")):
        if md.name in ("README.md", "METADATA_SPEC.md"):
            continue
        files.append(md)
    return files


def read_frontmatter(md_path: Path):
    """Lee y parsea el frontmatter YAML y el cuerpo de un archivo Markdown."""
    content = md_path.read_text(encoding="utf-8")
    match = FRONTMATTER_REGEX.match(content)
    if not match:
        return None, content
    yaml_text = match.group(1)
    body = content[match.end():]
    data = yaml.safe_load(yaml_text)
    return data, body


def write_frontmatter(md_path: Path, data: dict, body: str):
    """Escribe de forma limpia y formateada el frontmatter YAML preservando el cuerpo Markdown."""
    # Volcar YAML con formato legible y preservación de UTF-8
    yaml_output = yaml.dump(
        data,
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
        indent=2
    )
    new_content = f"---\n{yaml_output}---\n\n{body.lstrip()}"
    md_path.write_text(new_content, encoding="utf-8")


def auto_populate_resource_types():
    """Detecta recursos (scripts, terraform) y autocompleta atributos en todos los laboratorios."""
    files = get_all_lab_files()
    updated_count = 0

    # Mapa de prerequisitos pedagógicos sugeridos
    prereqs = {
        "lab-1.1-jobs-multiplexores": ["lab-0.1-compilar"],
        "lab-1.2-proceso-zombie": ["lab-1.1-jobs-multiplexores"],
        "lab-1.3-planificacion-cpu-nice": ["lab-1.1-jobs-multiplexores"],
        "lab-1.4-tools-stats": ["lab-1.3-planificacion-cpu-nice"],
        "lab-1.4-uptime-load-proc": ["lab-1.4-tools-stats"],
        "lab-2.1-systemd-memlogger": ["lab-1.1-jobs-multiplexores"],
        "lab-2.2-systemd-socket-activation": ["lab-2.1-systemd-memlogger"],
        "lab-2.3-systemd-cgroups-v2": ["lab-1.3-planificacion-cpu-nice", "lab-2.1-systemd-memlogger"],
        "lab-3.1-anatomia-filesystems": ["ref-guia-discos-procesos"],
        "lab-3.2-lvm2-online-resize": ["lab-3.1-anatomia-filesystems"],
        "lab-3.3-cifrado-luks": ["lab-3.2-lvm2-online-resize"],
        "lab-3.4-cifrado-fuse-gocryptfs": ["lab-3.3-cifrado-luks"],
        "lab-3.5-borg-backup": ["lab-3.2-lvm2-online-resize"],
        "lab-3.5-borg-systemd-timers": ["lab-3.5-borg-backup", "lab-2.1-systemd-memlogger"],
        "lab-3.6-monitoreo-metricas": ["lab-1.4-tools-stats", "lab-3.2-lvm2-online-resize"],
        "integrador-4.1-servidor-web-raid-luks-borg": ["lab-3.2-lvm2-online-resize", "lab-3.3-cifrado-luks", "lab-3.5-borg-systemd-timers"],
        "integrador-4.2-docker-lvm-hotmirror-mysql-s3": ["lab-3.2-lvm2-online-resize", "integrador-4.1-servidor-web-raid-luks-borg"],
        "integrador-4.3-btrfs-subvolumes-reflinks-raid1": ["lab-3.1-anatomia-filesystems", "integrador-4.1-servidor-web-raid-luks-borg"],
        "integrador-4.4-zfs-ha-activo-pasivo-alb": ["lab-3.1-anatomia-filesystems", "integrador-4.3-btrfs-subvolumes-reflinks-raid1"]
    }

    for md_path in files:
        data, body = read_frontmatter(md_path)
        if not data or "id" not in data:
            continue

        lab_id = data["id"]
        file_info = data.get("files", {})
        script_rel = file_info.get("script")
        tf_rel = file_info.get("terraform")

        has_script = bool(script_rel and (BASE_DIR / script_rel).exists())
        has_tf = bool(tf_rel and (BASE_DIR / tf_rel).exists())
        has_guide = True

        category = data.get("category", "")

        # Determinar resource_type
        if has_tf or data.get("difficulty_level") == 4:
            resource_type = "cloud_project"
            execution_mode = "terraform_apply" if has_tf else "cli_interactive"
        elif has_script:
            resource_type = "interactive_lab"
            execution_mode = "cli_interactive"
        elif category == "reference":
            resource_type = "cheatsheet"
            execution_mode = "reading_only"
        else:
            resource_type = "theoretical_guide"
            execution_mode = "manual_commands"

        # Asignar propiedades
        data["resource_type"] = resource_type
        data["has_guide"] = has_guide
        data["has_interactive_script"] = has_script
        data["has_terraform"] = has_tf
        data["execution_mode"] = execution_mode

        # Determinar herramientas MCP compatibles para que los agentes las reconozcan
        mcp_tools = ["linux-labs-tutor"]
        tags_lower = [t.lower() for t in data.get("tags", [])]
        if category in ["storage", "security", "systemd", "processes", "fundamentals", "observability"]:
            mcp_tools.extend(["bash", "filesystem"])
        if "docker" in tags_lower:
            mcp_tools.append("docker")
        if "terraform" in tags_lower or category == "cloud-iac":
            mcp_tools.extend(["terraform", "aws"])
        data["mcp_tools"] = list(dict.fromkeys(mcp_tools))

        if lab_id in prereqs and ("prerequisites" not in data or not data["prerequisites"]):
            data["prerequisites"] = prereqs[lab_id]

        write_frontmatter(md_path, data, body)
        updated_count += 1

    print(f"✅ Propiedades de tipo de recurso y ejecución autocompletadas en {updated_count} archivos.")
    sync_catalog()


def add_field_to_all(field_name: str, default_value):
    """Añade un nuevo campo con su valor por defecto a todos los laboratorios."""
    files = get_all_lab_files()
    count = 0
    for md_path in files:
        data, body = read_frontmatter(md_path)
        if not data:
            continue
        if field_name not in data:
            data[field_name] = default_value
            write_frontmatter(md_path, data, body)
            count += 1
    print(f"✅ Campo '{field_name}' añadido exitosamente a {count} laboratorios.")
    sync_catalog()


def remove_field_from_all(field_name: str):
    """Elimina un campo de todos los laboratorios."""
    files = get_all_lab_files()
    count = 0
    for md_path in files:
        data, body = read_frontmatter(md_path)
        if not data:
            continue
        if field_name in data:
            del data[field_name]
            write_frontmatter(md_path, data, body)
            count += 1
    print(f"🗑️ Campo '{field_name}' eliminado de {count} laboratorios.")
    sync_catalog()


def set_field_value(lab_id: str, field_name: str, value):
    """Actualiza o crea un valor para un laboratorio específico."""
    files = get_all_lab_files()
    found = False
    for md_path in files:
        data, body = read_frontmatter(md_path)
        if not data or data.get("id") != lab_id:
            continue
        data[field_name] = value
        write_frontmatter(md_path, data, body)
        print(f"✅ Laboratorio [{lab_id}]: '{field_name}' actualizado a: {value}")
        found = True
        break
    if not found:
        print(f"❌ Error: No se encontró el laboratorio con ID '{lab_id}'.", file=sys.stderr)
        return False
    sync_catalog()
    return True


def scaffold_new_lab(args):
    """Crea un nuevo laboratorio Markdown con la plantilla de metadatos completa."""
    dest_dir = BASE_DIR / args.category
    dest_dir.mkdir(parents=True, exist_ok=True)
    file_path = dest_dir / f"{args.id}.md"

    if file_path.exists():
        print(f"❌ Error: El archivo {file_path} ya existe.", file=sys.stderr)
        return False

    tags = [t.strip() for t in args.tags.split(",")] if args.tags else [args.category]
    tools = [t.strip() for t in args.tools.split(",")] if args.tools else ["bash"]

    template_data = {
        "id": args.id,
        "title": args.title,
        "difficulty_level": args.level,
        "difficulty_label": f"Nivel {args.level}: {args.category.capitalize()}",
        "section": args.section,
        "sections": [args.section, str(args.level)],
        "category": args.category,
        "resource_type": args.resource_type,
        "has_guide": True,
        "has_interactive_script": bool(args.script),
        "has_terraform": False,
        "execution_mode": "cli_interactive" if args.script else "manual_commands",
        "tags": tags,
        "tools": tools,
        "prerequisites": [],
        "requirements": {
            "root_required": args.root,
            "cloud_required": False,
            "min_ram_mb": 512,
            "min_disks": 0
        },
        "tested_environments": [
            {
                "environment": "WSL2",
                "type": "local",
                "instance_type": "virtualized",
                "os": "Ubuntu 24.04 LTS",
                "status": "PENDING",
                "notes": "Pendiente de ejecución inicial."
            }
        ],
        "environments": ["WSL2"],
        "operating_systems": ["Ubuntu 24.04 LTS"],
        "status": "PENDING",
        "rag_summary": args.summary or f"Laboratorio sobre {args.title}.",
        "files": {
            "guide": str(file_path.relative_to(BASE_DIR)).replace("\\", "/"),
            "script": args.script or None,
            "terraform": None
        }
    }

    body = f"""# {args.title}

Este laboratorio enseña los conceptos y comandos de {args.title}.

## 1. Requisitos Previos

- Entorno Linux o WSL2 con Ubuntu 24.04 LTS.

## 2. Desarrollo Paso a Paso

(Escribe aquí las instrucciones del laboratorio)

"""

    write_frontmatter(file_path, template_data, body)
    print(f"🎉 Nuevo laboratorio creado exitosamente en: {file_path}")
    sync_catalog()
    return True


def validate_catalog():
    """Valida los frontmatters contra el esquema formal."""
    try:
        import jsonschema
    except ImportError:
        print("⚠️ Nota: 'jsonschema' no está instalado. Instalalo con 'pip install jsonschema' para validación estricta.")
        print("Realizando validación básica de campos requeridos...")
        files = get_all_lab_files()
        reqs = ["id", "title", "difficulty_level", "section", "category", "tags", "tools", "tested_environments", "rag_summary", "files"]
        errors = 0
        for md in files:
            data, _ = read_frontmatter(md)
            if not data:
                print(f"❌ {md.name}: Sin frontmatter YAML válido.")
                errors += 1
                continue
            missing = [r for r in reqs if r not in data]
            if missing:
                print(f"❌ {md.name} [{data.get('id')}]: Faltan campos requeridos: {missing}")
                errors += 1
        if errors == 0:
            print(f"✅ Todos los {len(files)} laboratorios pasaron la validación básica.")
        return errors == 0

    schema_data = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    files = get_all_lab_files()
    errors = 0
    for md in files:
        data, _ = read_frontmatter(md)
        if not data:
            print(f"❌ {md.name}: Sin frontmatter YAML.")
            errors += 1
            continue
        try:
            jsonschema.validate(instance=data, schema=schema_data)
        except jsonschema.ValidationError as e:
            print(f"❌ {md.name} [{data.get('id')}]: Error de validación: {e.message}")
            errors += 1

    if errors == 0:
        print(f"✅ ¡Validación estricta completada! {len(files)} laboratorios cumplen al 100% con {SCHEMA_PATH.name}")
    return errors == 0


def sync_catalog():
    """Sincroniza y regenera catalog.json a partir de los archivos Markdown."""
    from query_catalog import scan_and_build_catalog
    return scan_and_build_catalog()


def main():
    parser = argparse.ArgumentParser(
        description="Gestor ABM (Alta, Baja, Modificación) y mantenimiento de Metadatos de Laboratorios Linux."
    )
    subparsers = parser.add_subparsers(dest="command", help="Comando a ejecutar")

    # Comando: auto-populate
    subparsers.add_parser("populate", help="Autodetecta scripts, terraform y puebla resource_type, execution_mode y prerequisitos")

    # Comando: add-field
    parser_add = subparsers.add_parser("add-field", help="Añade un nuevo campo a todos los laboratorios")
    parser_add.add_argument("--field", required=True, help="Nombre del campo a añadir")
    parser_add.add_argument("--default", required=True, help="Valor por defecto (JSON o string)")

    # Comando: remove-field
    parser_rm = subparsers.add_parser("remove-field", help="Elimina un campo de todos los laboratorios")
    parser_rm.add_argument("--field", required=True, help="Nombre del campo a remover")

    # Comando: set
    parser_set = subparsers.add_parser("set", help="Modifica un campo para un laboratorio específico")
    parser_set.add_argument("--id", required=True, help="ID del laboratorio a modificar")
    parser_set.add_argument("--field", required=True, help="Nombre del campo")
    parser_set.add_argument("--value", required=True, help="Nuevo valor (JSON o string)")

    # Comando: new-lab
    parser_new = subparsers.add_parser("new-lab", help="Genera la estructura de un nuevo laboratorio con frontmatter")
    parser_new.add_argument("--id", required=True, help="ID único en kebab-case")
    parser_new.add_argument("--title", required=True, help="Título del laboratorio")
    parser_new.add_argument("--level", type=int, choices=[0, 1, 2, 3, 4], default=1, help="Nivel de dificultad (0-4)")
    parser_new.add_argument("--section", required=True, help="Sección curricular (ej: 1.5, 3.7)")
    parser_new.add_argument("--category", required=True, choices=["fundamentals", "processes", "systemd", "storage", "security", "observability", "cloud-iac", "reference"])
    parser_new.add_argument("--resource-type", default="interactive_lab", choices=["interactive_lab", "theoretical_guide", "cheatsheet", "cloud_project"])
    parser_new.add_argument("--script", help="Ruta relativa al script .sh si aplica")
    parser_new.add_argument("--tags", help="Tags separados por coma")
    parser_new.add_argument("--tools", help="Herramientas separadas por coma")
    parser_new.add_argument("--root", action="store_true", help="Si requiere privilegios root")
    parser_new.add_argument("--summary", help="Resumen denso para RAG")

    # Comando: validate
    subparsers.add_parser("validate", help="Valida todos los laboratorios contra metadata.schema.json")

    # Comando: sync
    subparsers.add_parser("sync", help="Regenera catalog.json desde los archivos Markdown")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    if args.command == "populate":
        auto_populate_resource_types()
    elif args.command == "add-field":
        try:
            val = json.loads(args.default)
        except Exception:
            val = args.default
        add_field_to_all(args.field, val)
    elif args.command == "remove-field":
        remove_field_from_all(args.field)
    elif args.command == "set":
        try:
            val = json.loads(args.value)
        except Exception:
            val = args.value
        set_field_value(args.id, args.field, val)
    elif args.command == "new-lab":
        scaffold_new_lab(args)
    elif args.command == "validate":
        validate_catalog()
    elif args.command == "sync":
        sync_catalog()


if __name__ == "__main__":
    main()
