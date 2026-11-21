#!/usr/bin/env bash
set -euo pipefail

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 /tmp/.X11-unix/.Xauthority

COOKIE=$(od -tx1 -An -N16 /dev/urandom | tr -d ' \n')
AUTH_FILE="/tmp/.X11-unix/.Xauthority"
touch "${AUTH_FILE}"
xauth -f "${AUTH_FILE}" add :0 . "${COOKIE}"
chmod 644 "${AUTH_FILE}"

Xvfb :0 -screen 0 820x640x24 -nolisten tcp -auth "${AUTH_FILE}" >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!

for _ in $(seq 1 50); do
    if [ -S /tmp/.X11-unix/X0 ] && DISPLAY=:0 XAUTHORITY="${AUTH_FILE}" xdpyinfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

export DISPLAY=:0
export XAUTHORITY="${AUTH_FILE}"

# Window manager mínimo (~5 MB RAM) para manejo limpio de foco de teclado
openbox >/tmp/openbox.log 2>&1 &
sleep 0.3

cleanup() {
    kill "${XVFB_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# x11vnc escucha EXCLUSIVAMENTE en loopback (127.0.0.1:5900 dentro del Pod)
exec x11vnc \
    -display :0 \
    -auth "${AUTH_FILE}" \
    -localhost \
    -rfbport 5900 \
    -forever \
    -shared \
    -nopw \
    -noxdamage \
    -wait 20 \
    -defer 20
