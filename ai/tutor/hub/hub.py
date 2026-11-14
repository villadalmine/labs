#!/usr/bin/env python3
"""
hub.py - Hub MCP del curso: levanta varios servidores MCP (labs, study.cybercirujas,
rag-tutor, oss-docs) por HTTP en una sola máquina y genera la configuración para
conectarlos a Open WebUI, VS Code, Cline, Goose y Claude Code.

Solo usa la biblioteca estándar de Python. El manifiesto hub.json es la única fuente
de verdad: los puertos, comandos y descripciones salen de ahí.

Uso rápido:
    python3 ai/tutor/hub/hub.py doctor          # qué hay y qué falta
    python3 ai/tutor/hub/hub.py setup           # clonar repos, crear venvs, índices
    python3 ai/tutor/hub/hub.py up              # levantar los MCP
    python3 ai/tutor/hub/hub.py verify          # probar cada MCP de punta a punta
    python3 ai/tutor/hub/hub.py webui up        # Open WebUI con todos los MCP conectados
    python3 ai/tutor/hub/hub.py webui agent     # modelo 'Tutor del Hub' con los MCP + prompt
    python3 ai/tutor/hub/hub.py config vscode   # config lista para pegar
    python3 ai/tutor/hub/hub.py down            # bajar todo

Configuración: variables de entorno o el archivo ai/tutor/hub/hub.env (ver hub.env.example).
"""

import argparse
import json
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HUB_DIR = Path(__file__).resolve().parent
LABS_ROOT = HUB_DIR.parents[2]
MCP_DIR = LABS_ROOT / "ai" / "tutor" / "mcp"
MANIFEST_PATH = HUB_DIR / "hub.json"
ENV_FILE = HUB_DIR / "hub.env"
PROMPT_PATH = HUB_DIR / "system_prompt_hub.md"

LOOPBACK = {"127.0.0.1", "localhost", "::1"}
CLIENT_PROTOCOL_VERSION = "2025-03-26"

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


# ------------------------------------------------------------------------------
# Configuración
# ------------------------------------------------------------------------------

def load_env_file(path):
    """Lee un archivo KEY=VALUE. Las variables ya definidas en el entorno ganan."""
    values = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[key] = value
    return values


class Settings:
    def __init__(self):
        self._file = load_env_file(ENV_FILE)
        self.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        self.repos_dir = Path(self.get("HUB_REPOS_DIR") or LABS_ROOT.parent).expanduser().resolve()
        self.state_dir = Path(self.get("HUB_STATE_DIR") or HUB_DIR / ".run").expanduser().resolve()
        self.bind = self.get("HUB_BIND", "127.0.0.1")
        self.shared = self.bind not in LOOPBACK
        self.public_host = self.get("HUB_PUBLIC_HOST", "127.0.0.1")
        token = self.get("HUB_TOKEN", "")
        self.token = "" if token.lower() == "none" else token
        self.token_explicitly_open = token.lower() == "none"

    def get(self, key, default=None):
        value = os.environ.get(key)
        if value is None:
            value = self._file.get(key)
        return default if value is None or value == "" else value

    def prefixed(self, prefix):
        merged = {k: v for k, v in self._file.items() if k.startswith(prefix)}
        merged.update({k: v for k, v in os.environ.items() if k.startswith(prefix)})
        return {k[len(prefix):]: v for k, v in merged.items() if v != ""}


class Server:
    def __init__(self, spec, settings):
        self.spec = spec
        self.s = settings
        self.id = spec["id"]
        self.title = spec.get("title", self.id)
        self.description = spec.get("description", "")
        self.port = int(spec["port"])
        self.mode = spec.get("mode", "bridge")
        key = self.id.upper().replace("-", "_")
        self.remote_url = settings.get(f"HUB_URL_{key}")
        self.token = settings.get(f"HUB_TOKEN_{key}", settings.token if not self.remote_url else "")
        if self.token.lower() == "none":
            self.token = ""
        repo = spec.get("repo")
        self.repo_dir = (settings.repos_dir / repo["dir"]) if repo else LABS_ROOT
        self.repo_url = repo.get("url") if repo else None
        self.has_repo = repo is not None

    @property
    def is_remote(self):
        return bool(self.remote_url)

    @property
    def local_url(self):
        return f"http://127.0.0.1:{self.port}/mcp"

    def url(self, host=None):
        """URL con la que un cliente llega a este MCP."""
        if self.is_remote:
            return self.remote_url
        return f"http://{host or self.s.public_host}:{self.port}/mcp"

    @property
    def probe_url(self):
        return self.remote_url if self.is_remote else self.local_url

    @property
    def pid_file(self):
        return self.s.state_dir / f"{self.id}.pid"

    @property
    def log_file(self):
        return self.s.state_dir / f"{self.id}.log"

    # -- estado local ------------------------------------------------------------

    def repo_present(self):
        return self.repo_dir.is_dir()

    def env_ready(self):
        check = self.spec.get("check")
        if not check:
            return True
        if not self.repo_present() or not (self.repo_dir / check[0]).exists():
            return False
        try:
            return subprocess.run(check, cwd=self.repo_dir, capture_output=True, timeout=120).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def data_ready(self):
        data = self.spec.get("data")
        return True if not data else (self.repo_dir / data["check"]).exists()

    def not_ready_reason(self):
        if not self.repo_present():
            if self.repo_url:
                return "falta clonar el repo (hub.py setup)"
            return (f"no está {self.repo_dir} y el repo no es público: "
                    f"usá el del docente con HUB_URL_{self.id.upper().replace('-', '_')}")
        if not self.env_ready():
            return "falta el entorno Python (hub.py setup)"
        if not self.data_ready():
            return self.spec["data"].get("hint", "faltan los datos")
        return None

    def pid(self):
        try:
            pid = int(self.pid_file.read_text().strip())
            os.kill(pid, 0)
            return pid
        except (OSError, ValueError):
            return None

    def command(self):
        if self.mode == "native":
            subst = {"python": sys.executable, "labs": str(LABS_ROOT), "bind": self.s.bind,
                     "port": str(self.port)}
            cmd = [part.format(**subst) for part in self.spec["cmd"]]
            excluded = self.spec.get("exclude_when_shared") or []
            if self.s.shared and excluded:
                cmd += ["--exclude-tools", ",".join(excluded)]
            return cmd
        cmd = [sys.executable, str(MCP_DIR / "mcp_http.py"), "bridge", "--name", self.id,
               "--host", self.s.bind, "--port", str(self.port), "--cwd", str(self.repo_dir)]
        if self.spec.get("timeout"):
            cmd += ["--timeout", str(self.spec["timeout"])]
        return cmd + ["--"] + list(self.spec["cmd"])


def load_servers(settings, ids=None):
    servers = [Server(spec, settings) for spec in settings.manifest["servers"]]
    wanted = ids or [i for i in (settings.get("HUB_SERVERS") or "").replace(",", " ").split() if i]
    if wanted:
        known = {s.id for s in servers}
        unknown = [i for i in wanted if i not in known]
        if unknown:
            die(f"Servidor desconocido: {', '.join(unknown)}. Disponibles: {', '.join(sorted(known))}")
        servers = [s for s in servers if s.id in wanted]
    return servers


# ------------------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------------------

def die(msg, code=1):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def say(msg=""):
    print(msg, flush=True)


def run(cmd, cwd=None, env=None):
    say(f"    $ {' '.join(str(c) for c in cmd)}")
    return subprocess.run(cmd, cwd=cwd, env=env).returncode == 0


def port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def http_json(url, payload=None, headers=None, timeout=10.0, method=None):
    """GET/POST JSON con urllib. Devuelve (status, headers, body-bytes)."""
    data = None
    hdrs = dict(headers or {})
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.headers, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()


class McpClient:
    """Cliente MCP Streamable HTTP mínimo (para verify). Entiende respuestas JSON y SSE."""

    def __init__(self, url, token="", timeout=60.0):
        self.url, self.token, self.timeout = url, token, timeout
        self.session_id = None
        self._next_id = 0

    def _post(self, message):
        headers = {"Accept": "application/json, text/event-stream"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        status, resp_headers, body = http_json(self.url, message, headers, self.timeout)
        if status >= 400:
            raise RuntimeError(f"HTTP {status}: {body[:200].decode('utf-8', 'replace')}")
        if resp_headers.get("Mcp-Session-Id"):
            self.session_id = resp_headers["Mcp-Session-Id"]
        text = body.decode("utf-8", "replace")
        if "text/event-stream" in (resp_headers.get("Content-Type") or ""):
            for line in text.splitlines():
                if line.startswith("data:"):
                    try:
                        candidate = json.loads(line[5:].strip())
                    except ValueError:
                        continue
                    if isinstance(candidate, dict) and candidate.get("id") == message.get("id"):
                        return candidate
            return None
        return json.loads(text) if text.strip() else None

    def request(self, method, params=None):
        self._next_id += 1
        message = {"jsonrpc": "2.0", "id": self._next_id, "method": method}
        if params is not None:
            message["params"] = params
        resp = self._post(message)
        if resp is None:
            raise RuntimeError(f"sin respuesta a {method}")
        if "error" in resp:
            raise RuntimeError(f"{method}: {resp['error'].get('message', resp['error'])}")
        return resp["result"]

    def initialize(self):
        result = self.request("initialize", {
            "protocolVersion": CLIENT_PROTOCOL_VERSION, "capabilities": {},
            "clientInfo": {"name": "labs-hub-verify", "version": "1.0"}})
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return result


# ------------------------------------------------------------------------------
# Comandos: doctor / setup
# ------------------------------------------------------------------------------

def container_engine(settings):
    forced = settings.get("HUB_ENGINE")
    if forced:
        return forced if shutil.which(forced) else None
    for engine in ("docker", "podman"):
        if shutil.which(engine):
            return engine
    return None


def cmd_doctor(settings, args):
    say("Hub MCP - diagnóstico")
    say(f"  repo labs        : {LABS_ROOT}")
    say(f"  repos hermanos   : {settings.repos_dir}   (HUB_REPOS_DIR)")
    say(f"  escucha (bind)   : {settings.bind}   (HUB_BIND){'  <- compartido en la red' if settings.shared else ''}")
    say(f"  host para clientes: {settings.public_host}   (HUB_PUBLIC_HOST)")
    say(f"  token            : {'definido' if settings.token else 'sin token'}   (HUB_TOKEN)")
    say()
    say("Herramientas:")
    for tool, why in (("git", "clonar repos"), ("uv", "crear entornos Python (si falta se usa python -m venv + pip)")):
        say(f"  {'OK ' if shutil.which(tool) else '-- '} {tool:<8} {why}")
    engine = container_engine(settings)
    say(f"  {'OK ' if engine else '-- '} {engine or 'docker/podman':<8} contenedor de Open WebUI (hub.py webui up)")
    say(f"  OK  python   {sys.version.split()[0]}")
    say()
    say("Servidores MCP:")
    ok = True
    for srv in load_servers(settings, args.ids):
        if srv.is_remote:
            say(f"  {srv.id:<10} REMOTO  {srv.remote_url}")
            continue
        reason = srv.not_ready_reason()
        if srv.pid():
            state = "corriendo"
        elif reason:
            state = "NO LISTO"
        elif port_in_use(srv.port):
            state, ok = "PUERTO OCUPADO", False
        else:
            state = "listo"
        say(f"  {srv.id:<10} {state:<14} :{srv.port}  {srv.repo_dir}")
        if reason and not srv.pid():
            say(f"             -> {reason}")
    return 0 if ok else 1


def make_venv(srv):
    venv = srv.spec.get("venv")
    if not venv:
        return True
    py = srv.repo_dir / ".venv" / "bin" / "python"
    if shutil.which("uv"):
        if not py.exists():
            cmd = ["uv", "venv", ".venv"]
            if venv.get("python"):
                cmd += ["--python", venv["python"]]
            if not run(cmd, cwd=srv.repo_dir):
                return False
        return run(["uv", "pip", "install", "--python", str(py)] + venv["install"], cwd=srv.repo_dir)
    if not py.exists() and not run([sys.executable, "-m", "venv", ".venv"], cwd=srv.repo_dir):
        return False
    return run([str(py), "-m", "pip", "install", "--quiet"] + venv["install"], cwd=srv.repo_dir)


def cmd_setup(settings, args):
    failed = []
    for srv in load_servers(settings, args.ids):
        say(f"== {srv.id}")
        if srv.is_remote:
            say("    remoto: nada que instalar")
            continue
        if not srv.has_repo:
            say("    vive en este repo: nada que instalar")
            continue
        if not srv.repo_present():
            if not srv.repo_url:
                say(f"    OMITIDO: {srv.not_ready_reason()}")
                continue
            if not shutil.which("git"):
                die("falta git")
            settings.repos_dir.mkdir(parents=True, exist_ok=True)
            if not run(["git", "clone", "--depth", "1", srv.repo_url, str(srv.repo_dir)]):
                failed.append(srv.id)
                continue
        else:
            say(f"    repo presente: {srv.repo_dir} (no se toca)")
        if srv.env_ready():
            say("    entorno Python: ya está")
        elif not make_venv(srv) or not srv.env_ready():
            say("    FALLÓ la creación del entorno Python")
            failed.append(srv.id)
            continue
        data = srv.spec.get("data")
        if data and not srv.data_ready():
            if data.get("build"):
                say("    construyendo datos/índice (puede tardar)...")
                if not run(data["build"], cwd=srv.repo_dir) or not srv.data_ready():
                    failed.append(srv.id)
                    continue
            else:
                say(f"    PENDIENTE (manual): {data.get('hint')}")
                continue
        say("    listo")
    if failed:
        say(f"\nCon errores: {', '.join(failed)}")
        return 1
    return 0


# ------------------------------------------------------------------------------
# Comandos: up / down / status / logs / verify
# ------------------------------------------------------------------------------

def guard_exposure(settings):
    if settings.shared and not settings.token and not settings.token_explicitly_open:
        die("HUB_BIND expone los MCP a la red y no hay HUB_TOKEN.\n"
            "       Generá uno con 'hub.py token' y ponelo en hub.env,\n"
            "       o escribí HUB_TOKEN=none si de verdad querés dejarlo abierto.")


def wait_healthy(srv, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if srv.pid() is None:
            return False
        try:
            status, _, _ = http_json(f"http://127.0.0.1:{srv.port}/healthz", timeout=2.0)
            if status == 200:
                return True
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.5)
    return False


def cmd_up(settings, args):
    guard_exposure(settings)
    settings.state_dir.mkdir(parents=True, exist_ok=True)
    failed = []
    for srv in load_servers(settings, args.ids):
        if srv.is_remote:
            say(f"  {srv.id:<10} remoto ({srv.remote_url})")
            continue
        if srv.pid():
            say(f"  {srv.id:<10} ya estaba corriendo (pid {srv.pid()})")
            continue
        reason = srv.not_ready_reason()
        if reason:
            say(f"  {srv.id:<10} OMITIDO: {reason}")
            if args.ids:
                failed.append(srv.id)
            continue
        if port_in_use(srv.port):
            say(f"  {srv.id:<10} ERROR: el puerto {srv.port} ya está en uso")
            failed.append(srv.id)
            continue
        env = dict(os.environ)
        for key, value in (srv.spec.get("env") or {}).items():
            env.setdefault(key, value)
        env.pop("MCP_HTTP_TOKEN", None)
        if srv.token:
            env["MCP_HTTP_TOKEN"] = srv.token  # por entorno, no por argv: no queda en `ps`
        with open(srv.log_file, "ab") as log:
            proc = subprocess.Popen(srv.command(), cwd=srv.repo_dir, env=env, stdin=subprocess.DEVNULL,
                                    stdout=log, stderr=log, start_new_session=True)
        srv.pid_file.write_text(str(proc.pid))
        say(f"  {srv.id:<10} iniciando (pid {proc.pid})...")
        if wait_healthy(srv, float(srv.spec.get("start_timeout", 120))):
            say(f"  {srv.id:<10} OK  {srv.url()}")
        else:
            say(f"  {srv.id:<10} ERROR: no quedó sano. Mirá: hub.py logs {srv.id}")
            failed.append(srv.id)
    return 1 if failed else 0


def stop(srv):
    pid = srv.pid()
    if pid is None:
        srv.pid_file.unlink(missing_ok=True)
        return False
    try:
        os.killpg(pid, signal.SIGTERM)
    except OSError:
        pass
    for _ in range(50):
        if srv.pid() is None:
            break
        time.sleep(0.1)
    else:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass
    srv.pid_file.unlink(missing_ok=True)
    return True


def cmd_down(settings, args):
    for srv in load_servers(settings, args.ids):
        if not srv.is_remote:
            say(f"  {srv.id:<10} {'detenido' if stop(srv) else 'no estaba corriendo'}")
    return 0


def cmd_status(settings, args):
    for srv in load_servers(settings, args.ids):
        if srv.is_remote:
            say(f"  {srv.id:<10} REMOTO     {srv.remote_url}")
        elif srv.pid():
            say(f"  {srv.id:<10} corriendo  pid {srv.pid():<7} {srv.url()}")
        else:
            say(f"  {srv.id:<10} detenido   {srv.not_ready_reason() or ''}")
    return 0


def cmd_logs(settings, args):
    srv = load_servers(settings, [args.id])[0]
    if not srv.log_file.exists():
        die(f"todavía no hay log para {srv.id}")
    lines = srv.log_file.read_text(encoding="utf-8", errors="replace").splitlines()
    say("\n".join(lines[-args.lines:]))
    return 0


def cmd_verify(settings, args):
    failed = []
    for srv in load_servers(settings, args.ids):
        if not srv.is_remote and not srv.pid():
            say(f"  {srv.id:<10} --   no está corriendo ({srv.not_ready_reason() or 'hub.py up'})")
            if args.ids:
                failed.append(srv.id)
            continue
        try:
            client = McpClient(srv.probe_url, srv.token)
            info = client.initialize().get("serverInfo", {})
            tools = [t["name"] for t in client.request("tools/list").get("tools", [])]
            detail = ""
            smoke = srv.spec.get("smoke")
            if smoke:
                result = client.request("tools/call", {"name": smoke["tool"], "arguments": smoke["arguments"]})
                if result.get("isError"):
                    raise RuntimeError(f"{smoke['tool']} devolvió error")
                size = sum(len(c.get("text", "")) for c in result.get("content", []))
                detail = f" | {smoke['tool']} -> {size} caracteres"
            say(f"  {srv.id:<10} OK   {info.get('name', '?')} | {len(tools)} herramientas{detail}")
            if args.verbose:
                say(f"             {', '.join(tools)}")
        except Exception as e:
            say(f"  {srv.id:<10} FALLA {e}")
            failed.append(srv.id)
    return 1 if failed else 0


# ------------------------------------------------------------------------------
# Comando: config (genera la configuración de cada cliente)
# ------------------------------------------------------------------------------

def openwebui_connections(servers, host=None):
    """Lista para TOOL_SERVER_CONNECTIONS de Open WebUI (MCP nativo, Streamable HTTP)."""
    connections = []
    for srv in servers:
        connections.append({
            "type": "mcp",
            "url": srv.url(host),
            "path": "",
            "auth_type": "bearer" if srv.token else "none",
            "key": srv.token or "",
            "config": {
                "enable": True,
                "access_grants": [{"principal_type": "user", "principal_id": "*", "permission": "read"}],
            },
            "info": {"id": srv.id, "name": srv.title, "description": srv.description},
        })
    return connections


def token_inputs(servers):
    """Agrupa tokens iguales en un mismo 'input' de VS Code (no se escriben en el archivo)."""
    by_token, mapping = {}, {}
    for srv in servers:
        if srv.token:
            if srv.token not in by_token:
                by_token[srv.token] = "hub-token" if not by_token else f"hub-token-{len(by_token) + 1}"
            mapping[srv.id] = by_token[srv.token]
    return mapping, list(by_token.values())


def cmd_config(settings, args):
    servers = load_servers(settings, args.ids)
    host = args.host

    def secret(srv):
        return srv.token if args.show_token else "<HUB_TOKEN>"

    if args.client == "openwebui":
        connections = openwebui_connections(servers, host)
        if not args.show_token:
            for conn in connections:
                if conn["key"]:
                    conn["key"] = "<HUB_TOKEN>"
        say(json.dumps(connections, ensure_ascii=False, indent=None if args.compact else 2))
    elif args.client == "vscode":
        mapping, inputs = token_inputs(servers)
        doc = {"servers": {}}
        for srv in servers:
            entry = {"type": "http", "url": srv.url(host)}
            if srv.id in mapping:
                entry["headers"] = {"Authorization": "Bearer ${input:%s}" % mapping[srv.id]}
            doc["servers"][srv.id] = entry
        if inputs:
            doc["inputs"] = [{"type": "promptString", "id": i, "description": "Token del hub MCP",
                              "password": True} for i in inputs]
        say(json.dumps(doc, ensure_ascii=False, indent=2))
    elif args.client == "cline":
        doc = {"mcpServers": {}}
        for srv in servers:
            entry = {"type": "streamableHttp", "url": srv.url(host), "disabled": False}
            if srv.token:
                entry["headers"] = {"Authorization": f"Bearer {secret(srv)}"}
            doc["mcpServers"][srv.id] = entry
        say(json.dumps(doc, ensure_ascii=False, indent=2))
    elif args.client == "goose":
        say("extensions:")
        for srv in servers:
            say(f"  {srv.id}:")
            say(f"    name: {srv.id}")
            say("    type: streamable_http")
            say(f"    uri: {srv.url(host)}")
            if srv.token:
                say("    headers:")
                say(f"      Authorization: \"Bearer {secret(srv)}\"")
            say("    enabled: true")
            say("    timeout: 300")
    elif args.client == "claude-code":
        for srv in servers:
            header = f' --header "Authorization: Bearer {secret(srv)}"' if srv.token else ""
            say(f"claude mcp add --transport http {srv.id} {srv.url(host)}{header}")
    return 0


def cmd_corpus(settings, args):
    """Indexa los laboratorios y el código de este repo como un "libro" de rag-tutor (corpus de ejemplo)."""
    srv = load_servers(settings, ["rag-tutor"])[0]
    if not srv.repo_present() or not srv.env_ready():
        die("Falta rag-tutor: corré primero 'hub.py setup rag-tutor'.")
    if srv.data_ready() and not args.force:
        say("rag-tutor ya tiene un índice: no lo toco (usá --force para sumar el corpus de los labs).")
        return 0
    out = srv.repo_dir / "books" / ".corpus-labs"
    if not run([sys.executable, str(MCP_DIR / "prepare_rag_corpus.py"), "--output-dir", str(out)]):
        die("No se pudo generar el corpus de los labs.")
    dest = srv.repo_dir / "books" / "labs-practicos"
    shutil.copytree(out / "labs_practicos", dest, dirs_exist_ok=True)
    shutil.rmtree(out, ignore_errors=True)
    say("Indexando los laboratorios como libro 'labs-practicos' (tarda 1 a 2 minutos)...")
    if not run([str(srv.repo_dir / ".venv" / "bin" / "python"), "src/ingest.py"], cwd=srv.repo_dir) or not srv.data_ready():
        die("Falló la indexación.")
    say("Listo: 'hub.py up rag-tutor' ya contesta sobre los laboratorios.")
    return 0


def cmd_token(settings, args):
    say(secrets.token_urlsafe(24))
    return 0


# ------------------------------------------------------------------------------
# Comando: webui (Open WebUI en contenedor, configurado como código)
# ------------------------------------------------------------------------------

def webui_settings(settings):
    spec = settings.manifest["webui"]
    return {
        "image": settings.get("WEBUI_IMAGE", spec["image"]),
        "container": settings.get("WEBUI_CONTAINER", spec["container"]),
        "volume": settings.get("WEBUI_VOLUME", spec["volume"]),
        "port": int(settings.get("WEBUI_PORT", spec["port"])),
    }


def webui_url(settings):
    return f"http://{settings.public_host}:{webui_settings(settings)['port']}"


def cmd_webui(settings, args):
    engine = container_engine(settings)
    if not engine:
        die("No encontré docker ni podman. Instalá uno, o conectá un Open WebUI que ya tengas con:\n"
            "       hub.py config openwebui --show-token   (pegar en TOOL_SERVER_CONNECTIONS)")
    w = webui_settings(settings)

    if args.action == "agent":
        return cmd_webui_agent(settings, args)
    if args.action == "down":
        subprocess.run([engine, "rm", "-f", w["container"]], capture_output=True)
        say(f"  Open WebUI detenido (los datos quedan en el volumen {w['volume']})")
        return 0
    if args.action == "logs":
        return subprocess.run([engine, "logs", "--tail", str(args.lines), w["container"]]).returncode
    if args.action == "status":
        out = subprocess.run([engine, "ps", "--filter", f"name=^{w['container']}$", "--format", "{{.Status}}"],
                             capture_output=True, text=True).stdout.strip()
        say(f"  Open WebUI: {out or 'detenido'}   {webui_url(settings) if out else ''}")
        return 0

    # up
    servers = [s for s in load_servers(settings) if s.is_remote or s.pid()]
    if not servers:
        die("No hay ningún MCP corriendo. Primero: hub.py up")
    # El contenedor usa la red del host, así que llega a los MCP locales por 127.0.0.1.
    connections = openwebui_connections(servers, host="127.0.0.1")
    auth = settings.get("WEBUI_AUTH", "false").lower()
    # Sin login, quien llega a la página es administrador: en ese caso solo se escucha en loopback.
    webui_public = settings.shared and auth != "false"
    env = {
        "PORT": str(w["port"]),
        "HOST": "0.0.0.0" if webui_public else "127.0.0.1",
        "WEBUI_NAME": settings.get("WEBUI_NAME", "Tutor del Hub MCP"),
        "WEBUI_AUTH": auth,
        # Config como código: lo que manda es este entorno, no lo que se toque en el panel.
        "ENABLE_PERSISTENT_CONFIG": settings.get("WEBUI_PERSISTENT_CONFIG", "false"),
        "TOOL_SERVER_CONNECTIONS": json.dumps(connections, ensure_ascii=False),
        "OLLAMA_BASE_URL": settings.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
    }
    if settings.get("OPENAI_API_BASE_URL"):
        env["OPENAI_API_BASE_URL"] = settings.get("OPENAI_API_BASE_URL")
        env["OPENAI_API_KEY"] = settings.get("OPENAI_API_KEY", "")
    env.update(settings.prefixed("OWUI_"))  # escape: OWUI_FOO=bar -> FOO=bar en el contenedor

    subprocess.run([engine, "rm", "-f", w["container"]], capture_output=True)
    if port_in_use(w["port"]):
        # Con --network host el contenedor no puede escuchar y queda reiniciándose: mejor avisar.
        die(f"El puerto {w['port']} ya está en uso por otro programa. Elegí otro con WEBUI_PORT en hub.env.")
    cmd = [engine, "run", "-d", "--name", w["container"], "--network", "host",
           "--restart", "unless-stopped", "-v", f"{w['volume']}:/app/backend/data"]
    for key in env:
        cmd += ["-e", key]  # solo el nombre: el valor viaja por el entorno, no por argv
    cmd.append(w["image"])
    say(f"  iniciando Open WebUI ({w['image']}) con {len(servers)} MCP: {', '.join(s.id for s in servers)}")
    proc = subprocess.run(cmd, env={**os.environ, **env}, capture_output=True, text=True)
    if proc.returncode != 0:
        die(f"no arrancó el contenedor:\n{proc.stderr.strip()}")
    deadline = time.time() + float(settings.get("WEBUI_START_TIMEOUT", "300"))
    while time.time() < deadline:
        try:
            status, _, _ = http_json(f"http://127.0.0.1:{w['port']}/health", timeout=3.0)
            if status == 200:
                say(f"  OK  {webui_url(settings) if webui_public else 'http://127.0.0.1:%d' % w['port']}")
                if auth == "false":
                    say("      sin login (WEBUI_AUTH=false): escucha solo en esta máquina.")
                    if settings.shared:
                        say("      Para abrirlo a la red poné WEBUI_AUTH=true en hub.env (el primer usuario "
                            "que se registra queda como administrador).")
                return 0
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(2)
    die(f"Open WebUI no respondió a tiempo. Mirá: hub.py webui logs")


def webui_api(settings):
    """Devuelve call(path, payload=None) autenticado contra la API de Open WebUI."""
    base = f"http://127.0.0.1:{webui_settings(settings)['port']}"
    key = settings.get("WEBUI_API_KEY")
    if not key:
        if settings.get("WEBUI_AUTH", "false").lower() != "false":
            die("Con WEBUI_AUTH=true hace falta WEBUI_API_KEY (Open WebUI > Ajustes > Cuenta > Claves de API).")
        try:
            status, _, body = http_json(f"{base}/api/v1/auths/signin", {"email": "", "password": ""}, timeout=60.0)
        except (OSError, urllib.error.URLError) as e:
            die(f"Open WebUI no responde en {base}: {e}. ¿Corriste 'hub.py webui up'?")
        if status != 200:
            die(f"no pude entrar a Open WebUI (HTTP {status})")
        key = json.loads(body)["token"]

    def call(path, payload=None):
        try:
            status, _, body = http_json(base + path, payload, {"Authorization": f"Bearer {key}"}, timeout=120.0)
        except (OSError, urllib.error.URLError) as e:
            die(f"Open WebUI no respondió en {path}: {e}")
        try:
            return status, json.loads(body) if body else None
        except ValueError:
            return status, body.decode("utf-8", "replace")
    return call


def cmd_webui_agent(settings, args):
    """Crea (o actualiza) el modelo 'Tutor del Hub': modelo base + todos los MCP + prompt del tutor."""
    call = webui_api(settings)
    status, tools = call("/api/v1/tools/")
    if status != 200:
        die(f"Open WebUI no responde (HTTP {status}). ¿Corriste 'hub.py webui up'?")
    tool_ids = [t["id"] for t in tools if str(t.get("id", "")).startswith("server:mcp:")]
    if not tool_ids:
        die("Open WebUI no tiene ningún MCP conectado. Corré 'hub.py up' y 'hub.py webui up'.")

    base_model = args.base or settings.get("WEBUI_BASE_MODEL")
    if not base_model:
        status, models = call("/api/models")
        available = [m["id"] for m in (models or {}).get("data", []) if not m.get("info", {}).get("base_model_id")]
        if not available:
            die("Open WebUI no ve ningún modelo. Levantá Ollama (ollama pull qwen2.5:7b) o configurá\n"
                "       OPENAI_API_BASE_URL + OPENAI_API_KEY en hub.env, y volvé a correr 'hub.py webui up'.\n"
                "       También podés indicar el modelo a mano: hub.py webui agent --base <modelo>")
        base_model = available[0]

    form = {
        "id": args.id,
        "base_model_id": base_model,
        "name": args.name,
        "params": {
            "system": PROMPT_PATH.read_text(encoding="utf-8").strip(),
            "function_calling": "native",   # imprescindible para que el modelo llame a los MCP
            "temperature": 0.2,
        },
        "meta": {
            "description": "Tutor del curso con todos los MCP del hub conectados.",
            "toolIds": tool_ids,
            "capabilities": {"vision": False},
        },
        "access_grants": [{"principal_type": "user", "principal_id": "*", "permission": "read"}],
        "is_active": True,
    }
    status, existing = call(f"/api/v1/models/model?id={args.id}")
    if status == 200 and existing:
        status, result = call(f"/api/v1/models/model/update?id={args.id}", form)
        action = "actualizado"
    else:
        status, result = call("/api/v1/models/create", form)
        action = "creado"
    if status != 200 or not result:
        die(f"no se pudo guardar el modelo (HTTP {status}): {result}")
    say(f"  OK  modelo '{args.name}' {action} sobre {base_model} con {len(tool_ids)} MCP: "
        f"{', '.join(t.split(':')[-1] for t in tool_ids)}")
    say(f"      Abrí {webui_url(settings)} y elegilo en el selector de modelos.")
    return 0



# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(description="Hub MCP del curso (labs + study + rag-tutor + oss-docs).")
    sub = parser.add_subparsers(dest="command", required=True)

    def with_ids(p):
        p.add_argument("ids", nargs="*", help="ids de servidores (default: todos)")
        return p

    with_ids(sub.add_parser("doctor", help="qué hay instalado y qué falta")).set_defaults(fn=cmd_doctor)
    with_ids(sub.add_parser("setup", help="clonar repos, crear entornos e índices")).set_defaults(fn=cmd_setup)
    with_ids(sub.add_parser("up", help="levantar los MCP por HTTP")).set_defaults(fn=cmd_up)
    with_ids(sub.add_parser("down", help="detener los MCP")).set_defaults(fn=cmd_down)
    with_ids(sub.add_parser("status", help="estado de cada MCP")).set_defaults(fn=cmd_status)

    verify = with_ids(sub.add_parser("verify", help="probar cada MCP: initialize, tools/list y una llamada"))
    verify.add_argument("-v", "--verbose", action="store_true", help="listar las herramientas")
    verify.set_defaults(fn=cmd_verify)

    logs = sub.add_parser("logs", help="últimas líneas del log de un MCP")
    logs.add_argument("id")
    logs.add_argument("-n", "--lines", type=int, default=40)
    logs.set_defaults(fn=cmd_logs)

    config = sub.add_parser("config", help="generar la configuración de un cliente")
    config.add_argument("client", choices=["openwebui", "vscode", "cline", "goose", "claude-code"])
    config.add_argument("ids", nargs="*")
    config.add_argument("--host", help="host con el que el cliente llega al hub (default: HUB_PUBLIC_HOST)")
    config.add_argument("--show-token", action="store_true", help="escribir el token real en la salida")
    config.add_argument("--compact", action="store_true", help="[openwebui] JSON en una sola línea")
    config.set_defaults(fn=cmd_config)

    corpus = sub.add_parser("corpus", help="indexar los labs de este repo como libro de ejemplo de rag-tutor")
    corpus.add_argument("--force", action="store_true", help="sumarlo aunque rag-tutor ya tenga un índice")
    corpus.set_defaults(fn=cmd_corpus)
    sub.add_parser("token", help="generar un token aleatorio para HUB_TOKEN").set_defaults(fn=cmd_token)

    webui = sub.add_parser("webui", help="Open WebUI en contenedor con los MCP ya conectados")
    webui.add_argument("action", choices=["up", "down", "status", "logs", "agent"],
                       help="agent: crea el modelo 'Tutor del Hub' con todos los MCP y el prompt del tutor")
    webui.add_argument("-n", "--lines", type=int, default=40)
    webui.add_argument("--base", help="[agent] modelo base (default: WEBUI_BASE_MODEL o el primero disponible)")
    webui.add_argument("--id", default="tutor-hub", help="[agent] id del modelo")
    webui.add_argument("--name", default="Tutor del Hub", help="[agent] nombre visible")
    webui.set_defaults(fn=cmd_webui)

    args = parser.parse_args(argv)
    sys.exit(args.fn(Settings(), args))


if __name__ == "__main__":
    main()
