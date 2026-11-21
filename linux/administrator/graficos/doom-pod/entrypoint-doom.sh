#!/usr/bin/env bash
set -euo pipefail

AUTH_FILE="/tmp/.X11-unix/.Xauthority"

for _ in $(seq 1 150); do
    if [ -S /tmp/.X11-unix/X0 ] && [ -s "${AUTH_FILE}" ] && DISPLAY=:0 XAUTHORITY="${AUTH_FILE}" xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

if [ ! -S /tmp/.X11-unix/X0 ]; then
    echo "[ERROR] No se detectó el socket X11 /tmp/.X11-unix/X0 después de 15s." >&2
    exit 1
fi

IWAD="/usr/share/games/doom/freedoom1.wad"
if [ -r /wads/custom.wad ]; then
    IWAD="/wads/custom.wad"
fi

mkdir -p /tmp/doom-cfg
cp /opt/doom-cfg/default.cfg /tmp/doom-cfg/default.cfg
cp /opt/doom-cfg/chocolate-doom.cfg /tmp/doom-cfg/chocolate-doom.cfg

export DISPLAY=:0
export XAUTHORITY="${AUTH_FILE}"
export SDL_VIDEODRIVER=x11
export SDL_RENDER_DRIVER=software
export SDL_AUDIODRIVER=dummy

echo "[INFO] Lanzando chocolate-doom con IWAD=${IWAD} hacia DISPLAY=${DISPLAY}"
while true; do
    chocolate-doom \
        -iwad "${IWAD}" \
        -config /tmp/doom-cfg/default.cfg \
        -extraconfig /tmp/doom-cfg/chocolate-doom.cfg \
        -window \
        -nograbmouse || true
    sleep 1
done
