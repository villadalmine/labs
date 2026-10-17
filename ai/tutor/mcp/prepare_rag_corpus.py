#!/usr/bin/env python3
"""prepare_rag_corpus.py - Preparador de Corpus RAG para Open WebUI y AnythingLLM.

Exporta y unifica el material de estudio práctico de 'labs' y el material
teórico oficial de 'study-cybercirujas' (si está clonado) en una carpeta
limpia y lista para subir a la sección 'Knowledge' (Base de Conocimiento)
de Open WebUI o AnythingLLM.

Uso:
  python prepare_rag_corpus.py [--cybercirujas-dir RUTA] [--output-dir RUTA] [--certs lpic-1,lpi-010-160] [--lang es]
"""

from __future__ import annotations

import argparse
import os
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
SIBLING_DIR = Path(__file__).resolve().parents[4]


def export_labs_corpus(output_dir: Path) -> int:
    """Exporta los laboratorios prácticos de labs/linux/administrator (todos los módulos)."""
    labs_out = output_dir / "labs_practicos"
    labs_out.mkdir(parents=True, exist_ok=True)
    count = 0

    for md_file in LABS_ADMIN_DIR.rglob("*.md"):
        if md_file.name in ("README.md", "METADATA_SPEC.md"):
            continue
        dest = labs_out / md_file.name
        shutil.copy2(md_file, dest)
        count += 1

    print(f"📦 Labs prácticos exportados: {count} archivos en {labs_out}")
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

    # Iterar sobre las certificaciones
    for cert_path in certs_dir.iterdir():
        if not cert_path.is_dir():
            continue
        cert_name = cert_path.name
        if cert_filter and cert_name not in cert_filter:
            continue

        # Temas dentro de la certificación
        for topic_path in cert_path.iterdir():
            if not topic_path.is_dir():
                continue
            topic_name = topic_path.name

            # Buscar en el idioma solicitado (con fallback a 'en' si no existe)
            lang_dir = topic_path / lang
            if not lang_dir.exists() and lang != "en":
                lang_dir = topic_path / "en"

            if not lang_dir.exists():
                continue

            for md_file in lang_dir.glob("*.md"):
                # Nombre único para que el RAG identifique la fuente exacta
                # Ej: cka-2.1-content.md, lpic-1-104.1-exercises.md
                new_filename = f"{cert_name}-{topic_name}-{md_file.name}"
                dest = cyber_out / new_filename
                shutil.copy2(md_file, dest)
                count += 1

    print(f"📚 Temas teóricos de study-cybercirujas exportados: {count} archivos en {cyber_out}")
    return count


def main():
    parser = argparse.ArgumentParser(description="Exporta corpus de estudio para RAG")
    parser.add_argument(
        "--cybercirujas-dir",
        type=str,
        default=str(REPO_ROOT.parent / "study-cybercirujas"),
        help="Ruta donde está clonado el repositorio study-cybercirujas (por defecto: ../study-cybercirujas)",
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

    print("=======================================================")
    print("🚀 Generador de Corpus RAG: Labs + study-cybercirujas")
    print("=======================================================")

    labs_count = export_labs_corpus(out_dir)

    cyber_count = 0
    if cyber_dir.exists():
        cyber_count = export_cybercirujas_corpus(cyber_dir, out_dir, cert_filter, args.lang)
    else:
        print(f"\n💡 [Aviso] No se encontró el repo clonado en: {cyber_dir}")
        print("   Para incluirlo, clónalo con:")
        print(f"   git clone https://github.com/villadalmine/study-cybercirujas.git {cyber_dir}")
        print("   Luego vuelve a ejecutar este script.")

    print("\n-------------------------------------------------------")
    print(f"✅ Proceso terminado. Total archivos listos: {labs_count + cyber_count}")
    print(f"📂 Carpeta lista para subir a Open WebUI / AnythingLLM:")
    print(f"   {out_dir.resolve()}")
    print("-------------------------------------------------------")


if __name__ == "__main__":
    main()
