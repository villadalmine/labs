#!/usr/bin/env bash
# Utilitario de conveniencia para consultar el catálogo de laboratorios desde bash/WSL
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="python3"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    PYTHON_BIN="python"
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "Error: Python 3 no está instalado en el sistema." >&2
    exit 1
fi

exec "$PYTHON_BIN" "$SCRIPT_DIR/query_catalog.py" "$@"
