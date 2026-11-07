#!/usr/bin/env bash
# Wrapper conveniente para ejecutar el centinela de alertas desde la raíz de monitoreo
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${DIR}/scripts/alerta_centinela.sh" "$@"
