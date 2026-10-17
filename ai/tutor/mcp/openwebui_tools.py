"""
title: Linux Labs Tutor Tools
author: Antigravity AI
description: Herramientas para que Open WebUI consulte el catálogo de laboratorios Linux, recomiende la ruta de aprendizaje y valide la preparación del estudiante.
version: 1.0.0
"""

import json
from pathlib import Path


class Tools:
    def __init__(self):
        # Localizar la ruta de catalog.json en el repositorio
        self.catalog_path = None
        possible_paths = [
            Path("/app/backend/data/catalog.json"),
            Path("linux/administrator/catalog.json"),
            Path("../linux/administrator/catalog.json"),
            Path(__file__).resolve().parent.parent.parent / "linux" / "administrator" / "catalog.json"
        ]
        for p in possible_paths:
            try:
                if p.exists():
                    self.catalog_path = p
                    break
            except Exception:
                continue

    def _load_labs(self):
        if self.catalog_path and self.catalog_path.exists():
            with open(self.catalog_path, "r", encoding="utf-8") as f:
                return json.load(f).get("labs", [])
        return []

    def get_student_roadmap(self, environment: str = "WSL2", os_name: str = "Ubuntu 24.04 LTS", completed_labs: str = "") -> str:
        """
        Recomienda el siguiente laboratorio ideal para el estudiante analizando su entorno y trayectoria.
        :param environment: Entorno del alumno (WSL2, AWS EC2, Bare-Metal o Docker).
        :param os_name: Distribución Linux del alumno (ej: Ubuntu 24.04 LTS).
        :param completed_labs: Lista de IDs de laboratorios ya completados separados por coma.
        :return: JSON con el laboratorio recomendado y la justificación pedagógica.
        """
        labs = self._load_labs()
        completed = [c.strip() for c in completed_labs.split(",") if c.strip()]
        
        compatible = []
        for l in labs:
            envs = [e.lower() for e in l.get("environments", [])]
            if environment.lower() not in envs or l.get("id") in completed:
                continue
            compatible.append(l)

        def sort_key(item):
            lvl = item.get("difficulty_level", 99)
            sec = item.get("section", "99")
            try:
                sec_float = float(sec)
            except ValueError:
                sec_float = 99.0
            return (lvl, sec_float)

        compatible.sort(key=sort_key)

        for candidate in compatible:
            prereqs = candidate.get("prerequisites", [])
            missing = [p for p in prereqs if p not in completed]
            if not missing:
                return json.dumps({
                    "decision": "RECOMMENDED",
                    "lab_id": candidate.get("id"),
                    "title": candidate.get("title"),
                    "level": candidate.get("difficulty_level"),
                    "section": candidate.get("section"),
                    "resource_type": candidate.get("resource_type"),
                    "execution_mode": candidate.get("execution_mode"),
                    "guide": candidate.get("files", {}).get("guide"),
                    "script": candidate.get("files", {}).get("script"),
                    "summary": candidate.get("rag_summary"),
                    "reason": f"Siguiente paso natural en el Nivel {candidate.get('difficulty_level')}. 100% compatible con {environment}."
                }, indent=2, ensure_ascii=False)

        if compatible:
            first = compatible[0]
            return json.dumps({
                "decision": "PREREQUISITE_REQUIRED",
                "lab_id": first.get("id"),
                "missing": [p for p in first.get("prerequisites", []) if p not in completed]
            }, indent=2, ensure_ascii=False)

        return json.dumps({"decision": "ALL_COMPLETED", "message": "Todos los laboratorios completados."}, ensure_ascii=False)

    def search_curriculum(self, query: str = "", tag: str = "", category: str = "", tool: str = "") -> str:
        """
        Busca laboratorios en el catálogo por tema, herramienta, categoría o palabra clave.
        :param query: Texto libre a buscar en título o resumen.
        :param tag: Etiqueta (ej: storage, lvm, prometheus, btrfs).
        :param category: Categoría (processes, storage, systemd, etc).
        :param tool: Comando (ej: tune2fs, nice, borg, lvextend).
        :return: Lista de laboratorios coincidentes.
        """
        labs = self._load_labs()
        results = []
        for l in labs:
            if category and l.get("category", "").lower() != category.lower():
                continue
            if tag and not any(tag.lower() in t.lower() for t in l.get("tags", [])):
                continue
            if tool and not any(tool.lower() in t.lower() for t in l.get("tools", [])):
                continue
            if query:
                blob = f"{l.get('id')} {l.get('title')} {l.get('rag_summary')} {' '.join(l.get('tags', []))}".lower()
                if query.lower() not in blob:
                    continue
            results.append({
                "id": l.get("id"),
                "title": l.get("title"),
                "level": l.get("difficulty_level"),
                "section": l.get("section"),
                "category": l.get("category"),
                "resource_type": l.get("resource_type"),
                "summary": l.get("rag_summary"),
                "guide": l.get("files", {}).get("guide")
            })
        return json.dumps({"total": len(results), "labs": results}, indent=2, ensure_ascii=False)
