#!/usr/bin/env python3
"""
test_hub.py - Pruebas del transporte HTTP y del puente stdio->HTTP (solo stdlib).

No necesita los otros repos: usa el servidor MCP de labs como servidor real, primero
con su HTTP nativo y después envuelto por el puente (como se hace con study y rag-tutor).

    python3 ai/tutor/hub/test_hub.py
"""

import json
import os
import socket
import subprocess
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

HUB_DIR = Path(__file__).resolve().parent
MCP_DIR = HUB_DIR.parent / "mcp"
LABS_SERVER = MCP_DIR / "labs_mcp_server.py"
BRIDGE = MCP_DIR / "mcp_http.py"

sys.path.insert(0, str(HUB_DIR))
import hub  # noqa: E402


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def post(url, payload, headers=None):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class ServerProcess:
    def __init__(self, cmd, port, env=None):
        self.port = port
        self.proc = subprocess.Popen(cmd, env={**os.environ, **(env or {})},
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1) as resp:
                    if resp.status == 200:
                        return
            except (OSError, urllib.error.URLError):
                time.sleep(0.2)
        self.stop()
        raise RuntimeError(f"el servidor no arrancó: {' '.join(map(str, cmd))}")

    @property
    def url(self):
        return f"http://127.0.0.1:{self.port}/mcp"

    def stop(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


class NativeHttpTest(unittest.TestCase):
    """labs_mcp_server.py --transport http"""

    @classmethod
    def setUpClass(cls):
        port = free_port()
        cls.server = ServerProcess([sys.executable, str(LABS_SERVER), "--transport", "http",
                                    "--port", str(port)], port)

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def test_handshake_tools_and_call(self):
        client = hub.McpClient(self.server.url)
        info = client.initialize()
        self.assertEqual(info["serverInfo"]["name"], "linux-labs-tutor")
        self.assertEqual(info["protocolVersion"], hub.CLIENT_PROTOCOL_VERSION)
        tools = client.request("tools/list")["tools"]
        self.assertEqual(len(tools), 7)
        result = client.request("tools/call", {"name": "search_curriculum", "arguments": {"query": "raid"}})
        self.assertFalse(result["isError"])
        self.assertGreater(json.loads(result["content"][0]["text"])["total_found"], 0)

    def test_notification_gets_202(self):
        status, body = post(self.server.url, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        self.assertEqual((status, body), (202, b""))

    def test_get_is_not_allowed(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(self.server.url, timeout=5)
        self.assertEqual(ctx.exception.code, 405)

    def test_foreign_host_header_is_rejected(self):
        status, _ = post(self.server.url, {"jsonrpc": "2.0", "id": 1, "method": "ping"},
                         {"Host": "evil.example:80"})
        self.assertEqual(status, 403)

    def test_unknown_method(self):
        status, body = post(self.server.url, {"jsonrpc": "2.0", "id": 9, "method": "resources/list"})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["error"]["code"], -32601)


class TokenAndExcludeTest(unittest.TestCase):
    """Modo compartido: token Bearer y herramientas ocultas."""

    @classmethod
    def setUpClass(cls):
        port = free_port()
        cls.server = ServerProcess(
            [sys.executable, str(LABS_SERVER), "--transport", "http", "--port", str(port),
             "--exclude-tools", "check_lab_environment"], port, env={"MCP_HTTP_TOKEN": "secreto-de-prueba"})

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def test_requires_token(self):
        ping = {"jsonrpc": "2.0", "id": 1, "method": "ping"}
        self.assertEqual(post(self.server.url, ping)[0], 401)
        self.assertEqual(post(self.server.url, ping, {"Authorization": "Bearer otro"})[0], 401)
        self.assertEqual(post(self.server.url, ping, {"Authorization": "Bearer secreto-de-prueba"})[0], 200)

    def test_excluded_tool_is_hidden_and_blocked(self):
        client = hub.McpClient(self.server.url, "secreto-de-prueba")
        client.initialize()
        names = [t["name"] for t in client.request("tools/list")["tools"]]
        self.assertNotIn("check_lab_environment", names)
        self.assertEqual(len(names), 6)
        result = client.request("tools/call", {"name": "check_lab_environment", "arguments": {}})
        self.assertTrue(result["isError"])


class BridgeTest(unittest.TestCase):
    """mcp_http.py bridge envolviendo un servidor MCP stdio real."""

    @classmethod
    def setUpClass(cls):
        port = free_port()
        cls.server = ServerProcess([sys.executable, str(BRIDGE), "bridge", "--name", "labs-stdio",
                                    "--port", str(port), "--", sys.executable, str(LABS_SERVER)], port)

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def test_handshake_tools_and_call(self):
        client = hub.McpClient(self.server.url)
        self.assertEqual(client.initialize()["serverInfo"]["name"], "linux-labs-tutor")
        self.assertEqual(len(client.request("tools/list")["tools"]), 7)
        result = client.request("tools/call", {"name": "get_lab_details",
                                                "arguments": {"lab_id": "lab-1.2-proceso-zombie"}})
        self.assertFalse(result["isError"])

    def test_concurrent_clients_do_not_mix_answers(self):
        queries = ["raid", "zombie", "luks", "borg", "lvm", "systemd", "cron", "zfs"]
        answers = {}

        def worker(query):
            client = hub.McpClient(self.server.url)
            client.initialize()
            # Todos los clientes usan los mismos ids JSON-RPC (1, 2): el puente debe separarlos.
            result = client.request("tools/call", {"name": "search_curriculum", "arguments": {"query": query}})
            answers[query] = result["content"][0]["text"]

        threads = [threading.Thread(target=worker, args=(q,)) for q in queries]
        for t in threads:
            t.start()
        for t in threads:
            t.join(60)

        self.assertEqual(sorted(answers), sorted(queries))
        expected = hub.McpClient(self.server.url)
        expected.initialize()
        for query in queries:
            solo = expected.request("tools/call", {"name": "search_curriculum", "arguments": {"query": query}})
            self.assertEqual(answers[query], solo["content"][0]["text"], f"respuesta cruzada para '{query}'")


class BridgeExcludeTest(unittest.TestCase):
    """El puente puede ocultar herramientas de un servidor stdio que no se puede modificar."""

    @classmethod
    def setUpClass(cls):
        port = free_port()
        cls.server = ServerProcess([sys.executable, str(BRIDGE), "bridge", "--port", str(port),
                                    "--exclude-tools", "read_lab_guide,check_lab_environment",
                                    "--", sys.executable, str(LABS_SERVER)], port)

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def test_excluded_tools_are_hidden_and_blocked(self):
        client = hub.McpClient(self.server.url)
        client.initialize()
        names = [t["name"] for t in client.request("tools/list")["tools"]]
        self.assertEqual(len(names), 5)
        self.assertNotIn("read_lab_guide", names)
        blocked = client.request("tools/call", {"name": "read_lab_guide",
                                                "arguments": {"lab_id": "lab-1.2-proceso-zombie"}})
        self.assertTrue(blocked["isError"])
        allowed = client.request("tools/call", {"name": "search_curriculum", "arguments": {"query": "raid"}})
        self.assertFalse(allowed["isError"])


class ManifestTest(unittest.TestCase):
    def test_manifest_is_consistent(self):
        manifest = json.loads((HUB_DIR / "hub.json").read_text(encoding="utf-8"))
        ids = [s["id"] for s in manifest["servers"]]
        ports = [s["port"] for s in manifest["servers"]]
        self.assertEqual(len(ids), len(set(ids)), "ids repetidos")
        self.assertEqual(len(ports), len(set(ports)), "puertos repetidos")
        self.assertNotIn(manifest["webui"]["port"], ports)
        for spec in manifest["servers"]:
            self.assertIn(spec["mode"], ("native", "bridge"))
            self.assertTrue(spec["description"], f"{spec['id']} sin descripción")
            self.assertIn("tool", spec["smoke"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
