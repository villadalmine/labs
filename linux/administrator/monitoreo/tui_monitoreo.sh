#!/usr/bin/env bash
# Wrapper para scripts/tui_monitoreo.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/scripts/tui_monitoreo.sh" "$@"
