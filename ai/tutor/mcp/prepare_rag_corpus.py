#!/usr/bin/env python3
"""prepare_rag_corpus.py - Preparador de Corpus RAG Enriquecido para Open WebUI y AnythingLLM.

Exporta y enriquece:
1. Material de estudio práctico (.md) con contexto jerárquico inyectado en cada título (##)
   y frontmatter YAML estandarizado, evitando chunks huérfanos en la base vectorial.
2. Código fuente (.sh, .c, .h, .tf) envuelto en Markdown descriptivo para que el RAG
   pueda responder con precisión sobre llamadas al sistema, comandos y flags.
3. Material teórico oficial de 'study-cybercirujas' (si está clonado) con nombres unívocos.

Uso:
  python prepare_rag_corpus.py [--cybercirujas-dir RUTA] [--output-dir RUTA] [--certs lpic-1,lpi-010-160] [--lang es]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Raíz del repositorio labs (4 niveles arriba desde ai/tutor/mcp/...)
REPO_ROOT = Path(__file__).resolve().parents[3]
LABS_ADMIN_DIR = REPO_ROOT / "linux" / "administrator"
CATALOG_PATH = LABS_ADMIN_DIR / "catalog.json"
SIBLING_DIR = Path(__file__).resolve().parents[4]

FRONTMATTER_REGEX = re.compile(r"^---\s*\r?\n(.*?)\r?\n---\s*\r?\n", re.DOTALL)


def load_catalog_map() -> tuple[dict[str, dict], dict[str, dict]]:
    """Carga catalog.json e indexa laboratorios por guía relativa y por ID/nombre."""
    by_guide = {}
    by_id = {}
    if not CATALOG_PATH.exists():
        return by_guide, by_id

    try:
        with open(CATALOG_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            labs = data.get("labs", [])
            for lab in labs:
                lid = lab.get("id", "")
                by_id[lid] = lab
                guide_rel = lab.get("files", {}).get("guide")
                if guide_rel:
                    by_guide[guide_rel] = lab
                    by_guide[Path(guide_rel).name] = lab
    except Exception as e:
        print(f"⚠️  No se pudo leer catalog.json: {e}", file=sys.stderr)

    return by_guide, by_id


def export_labs_corpus(output_dir: Path, by_guide: dict[str, dict]) -> int:
    """Exporta y enriquece los laboratorios prácticos Markdown."""
    labs_out = output_dir / "labs_practicos"
    labs_out.mkdir(parents=True, exist_ok=True)
    count = 0

    for md_file in sorted(LABS_ADMIN_DIR.rglob("*.md")):
        if md_file.name in ("README.md", "METADATA_SPEC.md"):
            continue

        rel_path = md_file.relative_to(LABS_ADMIN_DIR).as_posix()
        lab = by_guide.get(rel_path) or by_guide.get(md_file.name)

        raw_content = md_file.read_text(encoding="utf-8")
        # Remover frontmatter previo si existe
        match = FRONTMATTER_REGEX.match(raw_content)
        body = raw_content[match.end():] if match else raw_content

        if lab:
            title = lab.get("title", md_file.stem)
            lab_id = lab.get("id", md_file.stem)
            difficulty = lab.get("difficulty_label", "Nivel no especificado")
            category = lab.get("category", "General")
            tools = ", ".join(lab.get("tools", []))
            script_name = lab.get("files", {}).get("script") or "Ninguno"
            summary = lab.get("rag_summary", "")
            prereqs = ", ".join(lab.get("prerequisites", [])) if lab.get("prerequisites") else "Ninguno"
        else:
            title = md_file.stem.replace("_", " ").title()
            lab_id = md_file.stem
            difficulty = "General"
            category = "Linux Administration"
            tools = "bash, linux"
            script_name = "Ninguno"
            summary = f"Guía práctica sobre {title}"
            prereqs = "Ninguno"

        # 1. Cabecera Frontmatter YAML enriquecida
        header_yaml = (
            f"---\n"
            f"lab_id: \"{lab_id}\"\n"
            f"titulo: \"{title}\"\n"
            f"categoria: \"{category}\"\n"
            f"nivel_dificultad: \"{difficulty}\"\n"
            f"herramientas_clave: \"{tools}\"\n"
            f"scripts_asociados: \"{script_name}\"\n"
            f"prerrequisitos: \"{prereqs}\"\n"
            f"resumen_pedagogico: \"{summary}\"\n"
            f"---\n\n"
        )

        # 2. Inyección de contexto jerárquico en cada encabezado ## (Evita chunks huérfanos en RAG)
        context_tag = f"[Lab: {title} | Script: {script_name}]"
        # Reemplazar ## Título por ## [Lab: ...] - Título solo si no lo tiene ya
        enriched_body = re.sub(
            r"^(##\s+)(?!\[Lab:)(.*)$",
            rf"\1{context_tag} - \2",
            body,
            flags=re.MULTILINE,
        )

        final_content = header_yaml + enriched_body.lstrip()
        dest = labs_out / md_file.name
        dest.write_text(final_content, encoding="utf-8")
        count += 1

    print(f"📦 Labs prácticos exportados y enriquecidos: {count} archivos en {labs_out}")
    return count


def export_code_corpus(output_dir: Path, by_guide: dict[str, dict], by_id: dict[str, dict]) -> int:
    """Exporta scripts y código fuente (.sh, .c, .h, .tf) envueltos en Markdown para RAG."""
    code_out = output_dir / "labs_codigo"
    code_out.mkdir(parents=True, exist_ok=True)
    count = 0

    code_extensions = {
        ".sh": "bash",
        ".c": "c",
        ".h": "c",
        ".tf": "hcl",
    }

    # Mapa inverso: script -> lab
    script_to_lab = {}
    for lid, lab in by_id.items():
        script = lab.get("files", {}).get("script")
        if script:
            script_to_lab[Path(script).name] = lab
        tf_dir = lab.get("files", {}).get("terraform")
        if tf_dir:
            script_to_lab[Path(tf_dir).name] = lab

    for file_path in sorted(LABS_ADMIN_DIR.rglob("*")):
        if file_path.suffix not in code_extensions:
            continue
        if not file_path.is_file():
            continue

        rel_path = file_path.relative_to(LABS_ADMIN_DIR).as_posix()
        lang = code_extensions[file_path.suffix]
        lab = script_to_lab.get(file_path.name)

        if lab:
            lab_title = lab.get("title")
            lab_id = lab.get("id")
            category = lab.get("category")
        else:
            lab_title = file_path.parent.name.replace("_", " ").title()
            lab_id = file_path.parent.name
            category = "scripts"

        try:
            content = file_path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue

        md_wrapped = (
            f"---\n"
            f"archivo_codigo: \"{file_path.name}\"\n"
            f"tipo_recurso: \"codigo_fuente_ejecutable\"\n"
            f"lenguaje: \"{lang}\"\n"
            f"laboratorio_asociado: \"{lab_title}\"\n"
            f"lab_id: \"{lab_id}\"\n"
            f"categoria: \"{category}\"\n"
            f"ruta_repositorio: \"linux/administrator/{rel_path}\"\n"
            f"---\n\n"
            f"# Código Fuente: `{file_path.name}`\n\n"
            f"> **Laboratorio Asociado:** {lab_title} (`{lab_id}`)\n"
            f"> **Ubicación en el repositorio:** `linux/administrator/{rel_path}`\n\n"
            f"```{lang}\n"
            f"{content}\n"
            f"```\n"
        )

        clean_ext = file_path.suffix.replace(".", "")
        dest_filename = f"codigo-{file_path.stem}-{clean_ext}.md"
        dest = code_out / dest_filename
        dest.write_text(md_wrapped, encoding="utf-8")
        count += 1

    print(f"💻 Código fuente (.sh, .c, .tf) exportado: {count} archivos en {code_out}")
    return count


def export_cybercirujas_corpus(
    cybercirujas_dir: Path, output_dir: Path, cert_filter: list[str] | None, lang: str = "es"
) -> int:
    """Exporta el material teórico de study-cybercirujas con nombres unívocos."""
    certs_dir = cybercirujas_dir / "certs"
    if not certs_dir.exists():
        print(f"⚠️  No se encontró la carpeta 'certs' en {cybercirujas_dir}")
        return 0

    cyber_out = output_dir / f"cybercirujas_teoria_{lang}"
    cyber_out.mkdir(parents=True, exist_ok=True)
    count = 0

    for cert_path in sorted(certs_dir.iterdir()):
        if not cert_path.is_dir():
            continue
        cert_name = cert_path.name
        if cert_filter and cert_name not in cert_filter:
            continue

        for topic_path in sorted(cert_path.iterdir()):
            if not topic_path.is_dir():
                continue
            topic_name = topic_path.name

            lang_dir = topic_path / lang
            if not lang_dir.exists() and lang != "en":
                lang_dir = topic_path / "en"

            if not lang_dir.exists():
                continue

            for md_file in sorted(lang_dir.glob("*.md")):
                new_filename = f"{cert_name}-{topic_name}-{md_file.name}"
                dest = cyber_out / new_filename
                shutil.copy2(md_file, dest)
                count += 1

    print(f"📚 Temas teóricos de study-cybercirujas exportados: {count} archivos en {cyber_out}")
    return count


def main():
    parser = argparse.ArgumentParser(description="Exporta corpus de estudio enriquecido para RAG")
    parser.add_argument(
        "--cybercirujas-dir",
        type=str,
        default=str(REPO_ROOT.parent / "study-cybercirujas"),
        help="Ruta donde está clonado study-cybercirujas (por defecto: ../study-cybercirujas)",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=str(REPO_ROOT / "ai" / "tutor" / "rag_corpus_export"),
        help="Carpeta de salida para los archivos de conocimiento RAG",
    )
    parser.add_argument(
        "--certs",
        type=str,
        default="lpic-1,lpi-010-160",
        help="Lista de certificaciones a exportar separadas por coma (ej: lpic-1,lpi-010-160,cka)",
    )
    parser.add_argument(
        "--lang",
        type=str,
        default="es",
        help="Idioma preferido para el material teórico (por defecto: es)",
    )

    args = parser.parse_args()
    out_dir = Path(args.output_dir)
    cyber_dir = Path(args.cybercirujas_dir)
    cert_filter = [c.strip() for c in args.certs.split(",") if c.strip()] if args.certs else None

    print("===============================================================================")
    print("🚀 Generador de Corpus RAG Enriquecido: Labs + Código + study-cybercirujas")
    print("===============================================================================")

    by_guide, by_id = load_catalog_map()

    labs_count = export_labs_corpus(out_dir, by_guide)
    code_count = export_code_corpus(out_dir, by_guide, by_id)

    cyber_count = 0
    if cyber_dir.exists():
        cyber_count = export_cybercirujas_corpus(cyber_dir, out_dir, cert_filter, args.lang)
    else:
        print(f"\n💡 [Aviso] No se encontró el repo clonado en: {cyber_dir}")
        print("   Para incluirlo, clónalo con:")
        print(f"   git clone https://github.com/villadalmine/study-cybercirujas.git {cyber_dir}")
        print("   Luego vuelve a ejecutar este script.")

    total = labs_count + code_count + cyber_count
    print("\n-------------------------------------------------------------------------------")
    print(f"✅ Proceso terminado. Total archivos listos: {total}")
    print(f"   - Guías prácticas enriquecidas con contexto: {labs_count}")
    print(f"   - Archivos de código (.sh, .c, .tf) en Markdown: {code_count}")
    print(f"   - Temas teóricos de certificación: {cyber_count}")
    print(f"📂 Carpeta lista para subir a Open WebUI / AnythingLLM:")
    print(f"   {out_dir.resolve()}")
    print("-------------------------------------------------------------------------------")


if __name__ == "__main__":
    main()
