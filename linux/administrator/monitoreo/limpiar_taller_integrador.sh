#!/usr/bin/env bash
# Wrapper para limpiar_taller_integrador_web_lvm_monitoreo.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/limpiar_taller_integrador_web_lvm_monitoreo.sh" "$@"
