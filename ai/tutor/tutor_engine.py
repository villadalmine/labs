#!/usr/bin/env python3
"""
tutor_engine.py - Motor de Decisiones Pedagógicas para Tutores de IA y Protocolos de Agentes (jdev / MCP).

Proporciona funciones determinísticas para que agentes autónomos y LLMs puedan:
1. Analizar el perfil del estudiante (entorno, OS, nivel, labs completados).
2. Recomendar la ruta de aprendizaje óptima (Roadmap / DAG pedagógico).
3. Verificar si el estudiante cumple los prerequisitos (root, hardware, nubes).
4. Servir como backend para MCP (Model Context Protocol) o llamadas a herramientas (Tool-Calling).
"""

import sys
import json
from pathlib import Path

# Soporte UTF-8
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
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


def recommend_next_lab(student_env: str = "WSL2", student_os: str = "Ubuntu 24.04 LTS", current_level: int = 0, completed_labs: list = None):
    """
    Toma decisiones pedagógicas sobre cuál es el próximo laboratorio ideal para el alumno
    según su ambiente físico, distribución y trayectoria.
    """
    completed_labs = completed_labs or []
    labs = load_catalog()

    # Filtrar por compatibilidad de entorno y OS
    compatible_labs = []
    for l in labs:
        # Verificar ambiente
        envs = [e.lower() for e in l.get("environments", [])]
        env_objs = [e.get("environment", "").lower() for e in l.get("tested_environments", [])]
        if student_env.lower() not in (envs + env_objs):
            continue

        # Verificar nivel mínimo y que no esté ya completado
        if l.get("id") in completed_labs:
            continue

        compatible_labs.append(l)

    # Ordenar por nivel ascendente y sección
    def sort_key(item):
        lvl = item.get("difficulty_level", 99)
        sec = item.get("section", "99")
        try:
            sec_float = float(sec)
        except ValueError:
            sec_float = 99.0
        return (lvl, sec_float)

    compatible_labs.sort(key=sort_key)

    # Buscar el primer laboratorio cuyos prerequisitos estén satisfechos
    for candidate in compatible_labs:
        prereqs = candidate.get("prerequisites", [])
        missing_prereqs = [p for p in prereqs if p not in completed_labs]
        
        # Si no tiene prerequisitos pendientes, es el elegido
        if not missing_prereqs:
            return {
                "decision": "RECOMMENDED",
                "lab": candidate,
                "reason": f"Siguiente paso natural en el Nivel {candidate.get('difficulty_level')} (Sección {candidate.get('section')}). Compatible 100% con tu entorno {student_env}.",
                "prerequisites_status": "ALL_MET"
            }

    # Si todos los candidatos restantes tienen prerequisitos pendientes
    if compatible_labs:
        first = compatible_labs[0]
        return {
            "decision": "PREREQUISITE_REQUIRED",
            "lab": first,
            "missing_prerequisites": [p for p in first.get("prerequisites", []) if p not in completed_labs],
            "reason": f"El laboratorio [{first.get('id')}] requiere completar primero sus prerequisitos."
        }

    return {
        "decision": "ALL_COMPLETED",
        "message": f"¡Felicitaciones! Has completado todos los laboratorios compatibles con {student_env}."
    }


def verify_lab_readiness(lab_id: str, student_env: str = "WSL2", has_root: bool = False, has_aws: bool = False):
    """
    Verifica si el alumno puede ejecutar el laboratorio sin toparse con bloqueos de permisos o nube.
    """
    labs = load_catalog()
    lab = next((l for l in labs if l.get("id") == lab_id), None)
    if not lab:
        return {"ready": False, "error": f"Laboratorio '{lab_id}' no encontrado en el catálogo."}

    reqs = lab.get("requirements", {})
    issues = []

    if reqs.get("root_required") and not has_root:
        issues.append("Requiere permisos de superusuario (sudo / root).")

    if reqs.get("cloud_required") and not has_aws:
        issues.append("Requiere cuenta de AWS con credenciales de Terraform configuradas.")

    # Verificar si el entorno fue probado
    envs = [e.lower() for e in lab.get("environments", [])]
    if student_env.lower() not in envs:
        issues.append(f"Este laboratorio no ha sido validado en {student_env}. Plataformas recomendadas: {', '.join(lab.get('environments', []))}.")

    return {
        "ready": len(issues) == 0,
        "lab_id": lab_id,
        "title": lab.get("title"),
        "resource_type": lab.get("resource_type"),
        "execution_mode": lab.get("execution_mode"),
        "issues": issues,
        "guide_path": lab.get("files", {}).get("guide"),
        "script_path": lab.get("files", {}).get("script")
    }


def main():
    if len(sys.argv) < 2:
        print("Uso: python tutor_engine.py [recommend|verify|lab] [args...]")
        print("Ejemplos:")
        print("  python tutor_engine.py recommend --env WSL2 --os 'Ubuntu 24.04 LTS' --completed lab-0.1-compilar")
        print("  python tutor_engine.py verify --id lab-3.2-lvm2-online-resize --env WSL2 --root")
        print("  python tutor_engine.py lab --id lab-3.6-monitoreo-metricas")
        sys.exit(0)

    cmd = sys.argv[1]
    if cmd == "recommend":
        env = "WSL2"
        os_name = "Ubuntu 24.04 LTS"
        completed = []
        for i, a in enumerate(sys.argv):
            if a == "--env" and i + 1 < len(sys.argv):
                env = sys.argv[i + 1]
            if a == "--os" and i + 1 < len(sys.argv):
                os_name = sys.argv[i + 1]
            if a == "--completed" and i + 1 < len(sys.argv):
                completed = sys.argv[i + 1].split(",")

        res = recommend_next_lab(student_env=env, student_os=os_name, completed_labs=completed)
        print(json.dumps(res, indent=2, ensure_ascii=False))

    elif cmd == "verify":
        lab_id = ""
        env = "WSL2"
        has_root = "--root" in sys.argv
        has_aws = "--aws" in sys.argv
        for i, a in enumerate(sys.argv):
            if a == "--id" and i + 1 < len(sys.argv):
                lab_id = sys.argv[i + 1]
            if a == "--env" and i + 1 < len(sys.argv):
                env = sys.argv[i + 1]

        res = verify_lab_readiness(lab_id, student_env=env, has_root=has_root, has_aws=has_aws)
        print(json.dumps(res, indent=2, ensure_ascii=False))

    elif cmd == "lab":
        lab_id = sys.argv[2] if len(sys.argv) > 2 else ""
        labs = load_catalog()
        found = next((l for l in labs if l.get("id") == lab_id), None)
        if found:
            print(json.dumps(found, indent=2, ensure_ascii=False))
        else:
            print(f"Error: Laboratorio {lab_id} no encontrado.", file=sys.stderr)


if __name__ == "__main__":
    main()
