#!/usr/bin/env bash
set -euo pipefail

for _ in $(seq 1 150); do
    if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',5900),1); s.close()" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

exec websockify --web=/usr/share/novnc 6080 127.0.0.1:5900
