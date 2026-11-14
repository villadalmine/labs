#!/usr/bin/env python3
"""
mcp_http.py - Transporte MCP "Streamable HTTP" mínimo, solo con la biblioteca estándar.

Sirve para dos cosas:

1. Publicar por HTTP un servidor MCP escrito a mano (lo usa labs_mcp_server.py con
   `--transport http`), para que Open WebUI, VS Code o cualquier cliente remoto lo
   consuman en `http://host:puerto/mcp`.

2. Hacer de PUENTE stdio -> HTTP para servidores MCP que solo hablan stdio
   (study-cybercirujas, rag-tutor), sin tocar su código:

       python mcp_http.py bridge --port 8092 --cwd ../study-cybercirujas \
           -- .venv/bin/python -m teach.mcp_server

Alcance (deliberadamente chico, para que se pueda leer en clase):
- Solo herramientas (tools). Cada POST recibe un mensaje JSON-RPC y devuelve la
  respuesta como `application/json`. No hay stream SSE iniciado por el servidor
  (GET responde 405, que la especificación permite).
- Sin sesiones: el servidor no guarda estado por cliente.
- El puente mantiene UN solo proceso hijo compartido entre todos los clientes
  (importante con servidores pesados como rag-tutor, que tardan en cargar).

Seguridad:
- Escuchando en loopback se valida la cabecera Host (defensa contra DNS rebinding).
- `--token` (o la variable MCP_HTTP_TOKEN) exige `Authorization: Bearer <token>`.
  Usalo siempre que escuches en 0.0.0.0 (modo clase).
"""

import argparse
import hmac
import itertools
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Versiones del protocolo MCP que este transporte acepta negociar (más nueva primero).
SUPPORTED_PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
# Versión que el puente le pide al proceso hijo: la primera que definió Streamable HTTP,
# así cualquier cliente HTTP la acepta.
BRIDGE_PROTOCOL_VERSION = "2025-03-26"

MAX_BODY_BYTES = 4 * 1024 * 1024
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}


def negotiate_version(requested):
    """Devuelve la versión pedida por el cliente si la conocemos; si no, la más nueva."""
    if requested in SUPPORTED_PROTOCOL_VERSIONS:
        return requested
    return SUPPORTED_PROTOCOL_VERSIONS[0]


def rpc_error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def log(msg):
    sys.stderr.write(f"[mcp-http] {msg}\n")
    sys.stderr.flush()


# ------------------------------------------------------------------------------
# Servidor HTTP
# ------------------------------------------------------------------------------

def serve(handle_message, host="127.0.0.1", port=8091, path="/mcp", name="mcp",
          token=None, is_ready=None):
    """
    Publica `handle_message(dict) -> dict | None` como endpoint MCP Streamable HTTP.

    handle_message recibe un mensaje JSON-RPC ya parseado y devuelve la respuesta
    (para requests) o None (para notificaciones). Bloquea hasta Ctrl+C / SIGTERM.
    """
    token = token or None
    path = "/" + path.strip("/")
    loopback_only = host in LOOPBACK_HOSTS

    class Handler(BaseHTTPRequestHandler):
        server_version = "labs-mcp-http/1.0"
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # silenciar el access log por request
            pass

        def _send(self, status, body=None, headers=None):
            payload = b""
            if body is not None:
                payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            if body is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            if status >= 400:
                # El cuerpo del POST puede quedar sin leer (401, 403, 404): se cierra la conexión
                # para que esos bytes no se interpreten como una petición nueva ("Bad request syntax").
                self.send_header("Connection", "close")
                self.close_connection = True
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            if payload:
                self.wfile.write(payload)

        def _host_ok(self):
            if not loopback_only:
                return True  # quien escucha en la LAN ya eligió exponerse; usar --token
            hostname = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]").lower()
            return hostname in LOOPBACK_HOSTS

        def _auth_ok(self):
            if token is None:
                return True
            given = self.headers.get("Authorization") or ""
            return hmac.compare_digest(given.encode(), f"Bearer {token}".encode())

        def _is_endpoint(self):
            return self.path.split("?", 1)[0].rstrip("/") == path

        def do_GET(self):
            if self.path.split("?", 1)[0] == "/healthz":
                ready = True if is_ready is None else bool(is_ready())
                self._send(200 if ready else 503,
                           {"status": "ok" if ready else "starting", "server": name})
            elif self._is_endpoint():
                # No ofrecemos stream SSE iniciado por el servidor.
                self._send(405, rpc_error(None, -32000, "Solo POST"), {"Allow": "POST"})
            else:
                self._send(404, {"error": "not found", "endpoint": path})

        def do_DELETE(self):
            self._send(405, rpc_error(None, -32000, "Sin sesiones"), {"Allow": "POST"})

        def do_POST(self):
            if not self._is_endpoint():
                self._send(404, {"error": "not found", "endpoint": path})
                return
            if not self._host_ok():
                self._send(403, rpc_error(None, -32000, "Host no permitido"))
                return
            if not self._auth_ok():
                self._send(401, rpc_error(None, -32000, "Falta o es inválido el token Bearer"),
                           {"WWW-Authenticate": "Bearer"})
                return
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = -1
            if length < 0 or length > MAX_BODY_BYTES:
                self._send(413, rpc_error(None, -32600, "Cuerpo demasiado grande o inválido"))
                return
            try:
                message = json.loads(self.rfile.read(length).decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                self._send(400, rpc_error(None, -32700, "JSON inválido"))
                return

            batch = message if isinstance(message, list) else [message]
            responses = []
            for item in batch:
                if not isinstance(item, dict):
                    responses.append(rpc_error(None, -32600, "Mensaje JSON-RPC inválido"))
                    continue
                try:
                    resp = handle_message(item)
                except Exception as e:  # nunca tirar abajo el servidor por una herramienta
                    resp = rpc_error(item.get("id"), -32603, f"Error interno: {e}")
                # Solo los requests (method + id) llevan respuesta.
                if resp is not None and "method" in item and item.get("id") is not None:
                    responses.append(resp)

            if not responses:
                self._send(202)
            elif isinstance(message, list):
                self._send(200, responses)
            else:
                self._send(200, responses[0])

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    httpd = Server((host, port), Handler)
    auth = "con token Bearer" if token else "SIN autenticación"
    log(f"{name}: escuchando en http://{host}:{port}{path} ({auth})")
    if not loopback_only and not token:
        log("AVISO: expuesto a la red sin token. Usá --token o MCP_HTTP_TOKEN.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


# ------------------------------------------------------------------------------
# Puente stdio -> HTTP
# ------------------------------------------------------------------------------

class StdioBridge:
    """
    Mantiene un servidor MCP stdio como proceso hijo y multiplexa sobre él los
    requests de muchos clientes HTTP.

    - El `initialize` con el hijo se hace una sola vez; a cada cliente HTTP se le
      contesta con ese resultado guardado.
    - Los ids de los clientes se reescriben a ids propios del puente para que dos
      clientes no choquen entre sí.
    - Si el hijo muere, se lo vuelve a levantar en el próximo request.
    """

    def __init__(self, cmd, cwd=None, env=None, timeout=120.0, start_timeout=300.0, excluded_tools=()):
        self.excluded_tools = frozenset(excluded_tools)
        self.cmd = cmd
        self.cwd = cwd
        self.env = env
        self.timeout = timeout
        self.start_timeout = start_timeout
        self._ids = itertools.count(1)
        self._pending = {}           # id del puente -> [Event, respuesta]
        self._write_lock = threading.Lock()
        self._start_lock = threading.Lock()
        self._proc = None
        self._init_result = None

    # -- ciclo de vida del hijo --------------------------------------------------

    def is_ready(self):
        return self._init_result is not None and self._proc is not None and self._proc.poll() is None

    def start_in_background(self):
        threading.Thread(target=self._ensure_started_quiet, daemon=True).start()

    def _ensure_started_quiet(self):
        try:
            self._ensure_started()
        except Exception as e:
            log(f"no se pudo iniciar el servidor stdio: {e}")

    def _ensure_started(self):
        with self._start_lock:
            if self.is_ready():
                return
            self._init_result = None
            if self._proc is not None and self._proc.poll() is None:
                self._proc.kill()
            log(f"iniciando servidor stdio: {' '.join(self.cmd)} (cwd={self.cwd or os.getcwd()})")
            self._proc = subprocess.Popen(
                self.cmd, cwd=self.cwd, env=self.env,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=None,
                text=True, encoding="utf-8", bufsize=1,
            )
            threading.Thread(target=self._reader, args=(self._proc,), daemon=True).start()
            resp = self._call(self._proc, "initialize", {
                "protocolVersion": BRIDGE_PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "labs-mcp-http-bridge", "version": "1.0"},
            }, self.start_timeout)
            if "error" in resp:
                raise RuntimeError(f"initialize falló: {resp['error']}")
            self._write(self._proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})
            self._init_result = resp["result"]
            info = self._init_result.get("serverInfo", {})
            log(f"servidor stdio listo: {info.get('name')} {info.get('version', '')}".rstrip())

    def close(self):
        if self._proc is not None and self._proc.poll() is None:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.kill()

    # -- E/S con el hijo ---------------------------------------------------------

    def _write(self, proc, message):
        with self._write_lock:
            proc.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
            proc.stdin.flush()

    def _reader(self, proc):
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                continue  # un servidor stdio bien portado no escribe otra cosa en stdout
            if not isinstance(msg, dict):
                continue
            if "method" in msg:
                # Pedido del servidor al cliente (sampling, roots...): no lo soportamos.
                if msg.get("id") is not None:
                    try:
                        self._write(proc, rpc_error(msg["id"], -32601, "No soportado por el puente"))
                    except OSError:
                        pass
                continue
            slot = self._pending.get(msg.get("id"))
            if slot is not None:
                slot[1] = msg
                slot[0].set()
        # stdout cerrado: el hijo terminó. Despertar a quien esté esperando.
        for slot in list(self._pending.values()):
            slot[0].set()

    def _call(self, proc, method, params, timeout):
        bridge_id = next(self._ids)
        slot = [threading.Event(), None]
        self._pending[bridge_id] = slot
        try:
            request = {"jsonrpc": "2.0", "id": bridge_id, "method": method}
            if params is not None:
                request["params"] = params
            try:
                self._write(proc, request)
            except OSError as e:
                return rpc_error(None, -32000, f"El servidor stdio no acepta datos: {e}")
            if not slot[0].wait(timeout):
                return rpc_error(None, -32001, f"Sin respuesta del servidor stdio en {timeout:.0f}s")
            if slot[1] is None:
                return rpc_error(None, -32000, "El servidor stdio terminó antes de responder")
            return slot[1]
        finally:
            self._pending.pop(bridge_id, None)

    # -- interfaz que consume serve() -------------------------------------------

    def handle_message(self, message):
        method = message.get("method")
        req_id = message.get("id")
        if method is None or req_id is None:
            return None  # notificaciones y respuestas del cliente: nada que reenviar

        if method == "ping":
            return {"jsonrpc": "2.0", "id": req_id, "result": {}}

        try:
            self._ensure_started()
        except Exception as e:
            return rpc_error(req_id, -32000, f"No se pudo iniciar el servidor stdio: {e}")

        if method == "initialize":
            return {"jsonrpc": "2.0", "id": req_id, "result": self._init_result}

        params = message.get("params")
        if method == "tools/call" and (params or {}).get("name") in self.excluded_tools:
            return {"jsonrpc": "2.0", "id": req_id, "result": {"isError": True, "content": [
                {"type": "text", "text": "Herramienta deshabilitada en este servidor."}]}}

        resp = dict(self._call(self._proc, method, params, self.timeout))
        resp["id"] = req_id
        if method == "tools/list" and self.excluded_tools and isinstance(resp.get("result"), dict):
            result = dict(resp["result"])
            result["tools"] = [t for t in result.get("tools", []) if t.get("name") not in self.excluded_tools]
            resp["result"] = result
        return resp


# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------

def add_http_arguments(parser, default_port):
    parser.add_argument("--host", default="127.0.0.1",
                        help="Dirección de escucha (0.0.0.0 para exponer a la LAN; usar con --token)")
    parser.add_argument("--port", type=int, default=default_port)
    parser.add_argument("--path", default="/mcp")
    parser.add_argument("--token", default=os.environ.get("MCP_HTTP_TOKEN"),
                        help="Exigir 'Authorization: Bearer <token>' (o variable MCP_HTTP_TOKEN)")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Puente MCP stdio -> Streamable HTTP (solo biblioteca estándar).")
    sub = parser.add_subparsers(dest="command", required=True)
    bridge = sub.add_parser("bridge", help="Publica por HTTP un servidor MCP stdio")
    add_http_arguments(bridge, default_port=8092)
    bridge.add_argument("--name", default="mcp-bridge")
    bridge.add_argument("--cwd", default=None, help="Directorio de trabajo del servidor stdio")
    bridge.add_argument("--timeout", type=float, default=120.0,
                        help="Segundos máximos por llamada a herramienta")
    bridge.add_argument("--exclude-tools", default="",
                        help="Herramientas del servidor stdio a ocultar, separadas por coma")
    bridge.add_argument("cmd", nargs=argparse.REMAINDER,
                        help="Comando del servidor stdio, después de '--'")
    args = parser.parse_args(argv)

    cmd = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
    if not cmd:
        parser.error("falta el comando del servidor stdio (después de '--')")

    excluded = [t.strip() for t in args.exclude_tools.split(",") if t.strip()]
    stdio = StdioBridge(cmd, cwd=args.cwd, timeout=args.timeout, excluded_tools=excluded)
    stdio.start_in_background()
    try:
        serve(stdio.handle_message, host=args.host, port=args.port, path=args.path,
              name=args.name, token=args.token, is_ready=stdio.is_ready)
    finally:
        stdio.close()


if __name__ == "__main__":
    main()
