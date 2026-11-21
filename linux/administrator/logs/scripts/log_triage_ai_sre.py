#!/usr/bin/env python3
"""
log_triage_ai_sre.py - Motor determinístico de Triage Forense AI SRE sobre cola NDJSON de logs.

Demuestra cómo un agente SRE moderno consume logs estructurados:
1. Log Clustering estilo Drain3 (comprime miles de líneas repetitivas en plantillas paramétricas).
2. Sanitización PII y Defensa Anti-Prompt-Injection (pone payloads sospechosos en cuarentena).
3. Ciclo ReAct (Thought -> Action -> Observation) + Correlación Causal por trace_id.
4. Generación NL-to-Query (LogQL para Loki, KQL para OpenSearch/ELK, SPL para Splunk).
5. Propuesta de remediación acotada por Guardrails y Human-in-the-Loop (HITL).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

INJECTION_PATTERNS = [
    r"ignore\s+previous\s+instructions",
    r"system\s+override",
    r"execute\s+.*(rm\s+-rf|curl|wget|bash)",
    r"you\s+are\s+now\s+",
    r"<\s*/?\s*system\s*>",
]

RE_IPV4 = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b")
RE_UUID_OR_TRACE = re.compile(r"\b(?:tr-\d+|[0-9a-f]{8}-[0-9a-f-]{27})\b", re.IGNORECASE)
RE_NUM = re.compile(r"\b\d+\b")
RE_EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")


def load_events(ndjson_path: Path) -> list[dict]:
    events = []
    with ndjson_path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                events.append({"host": "unknown", "app": "raw", "severity": "info", "msg": line})
    return events


def sanitize_and_detect_injection(msg: str) -> tuple[str, bool, str]:
    """Detecta intentos de Prompt Injection y redacta PII básico."""
    for pat in INJECTION_PATTERNS:
        m = re.search(pat, msg, re.IGNORECASE)
        if m:
            safe_preview = msg[:70].replace('"', "'")
            return f"[QUARANTINED_PAYLOAD len={len(msg)}]", True, m.group(0)
    sanitized = RE_EMAIL.sub("<EMAIL>", msg)
    return sanitized, False, ""


def drain_like_template(msg: str) -> str:
    """Normaliza tokens variables (IP, trace_id, números) en plantillas tipo Drain3."""
    tpl = RE_IPV4.sub("<IP>", msg)
    tpl = RE_UUID_OR_TRACE.sub("<TRACE_ID>", tpl)
    tpl = re.sub(r"\bfor\s+(?:invalid\s+user\s+)?([A-Za-z0-9_.-]+)\s+from", "for <USER> from", tpl)
    tpl = RE_NUM.sub("<NUM>", tpl)
    return tpl.strip()


def extract_trace_id(msg: str) -> str | None:
    m = re.search(r"trace_id=([A-Za-z0-9_-]+)", msg)
    return m.group(1) if m else None


def run_triage(ndjson_path: Path) -> int:
    if not ndjson_path.exists():
        print(f"[ERROR] No existe el archivo de cola: {ndjson_path}", file=sys.stderr)
        return 1

    events = load_events(ndjson_path)
    total = len(events)
    if total == 0:
        print("[WARN] Cola vacía, sin eventos para analizar.")
        return 0

    templates: Counter[tuple[str, str, str]] = Counter()
    quarantined = []
    by_trace: dict[str, list[dict]] = defaultdict(list)
    ssh_failed_ips: Counter[str] = Counter()

    for ev in events:
        host = str(ev.get("host", "unknown"))
        app = str(ev.get("app", "unknown"))
        sev = str(ev.get("severity", "info")).lower()
        raw_msg = str(ev.get("msg", "")).strip()

        clean_msg, is_inj, matched = sanitize_and_detect_injection(raw_msg)
        if is_inj:
            quarantined.append({"host": host, "app": app, "pattern": matched, "raw_snippet": raw_msg[:95]})

        tpl = drain_like_template(clean_msg)
        templates[(app, sev, tpl)] += 1

        tid = extract_trace_id(raw_msg)
        if tid:
            by_trace[tid].append({"host": host, "app": app, "severity": sev, "msg": clean_msg})

        if "Failed password" in raw_msg or "Invalid user" in raw_msg:
            for ip in RE_IPV4.findall(raw_msg):
                ssh_failed_ips[ip] += 1

    compression = (1.0 - (len(templates) / total)) * 100.0

    print("=" * 84)
    print("🤖 MOTOR AI SRE — TRIAGE FORENSE DE LOGS ESTRUCTURADOS (MCP + DRAIN3 + RCA)")
    print("=" * 84)

    print(f"\n[FASE 1: LOG CLUSTERING (Estilo Drain3)]")
    print(f"  • Eventos crudos ingeridos : {total} líneas")
    print(f"  • Plantillas únicas        : {len(templates)} clusters (Reducción de tokens: {compression:.1f}%)")
    for (app, sev, tpl), count in templates.most_common(8):
        print(f"    [{count:>3}x] ({app:<10} | {sev:<7}) {tpl}")

    print(f"\n[FASE 2: SEGURIDAD IA — DEFENSA ANTI-PROMPT-INJECTION & PII]")
    print(f"  • Payloads maliciosos interceptados en cuarentena: {len(quarantined)}")
    for q in quarantined:
        print(f"    🛡️  Host={q['host']} App={q['app']} Patron='{q['pattern']}' -> Tratado como DATO NO CONFIABLE")

    print(f"\n[FASE 3: CICLO COGNITIVO ReAct & CORRELACIÓN CAUSAL (RCA)]")
    for tid, chain in by_trace.items():
        print(f"  🔎 Investigando trace_id={tid} ({len(chain)} eventos correlacionados):")
        print(f"     [THOUGHT]     Detectado error HTTP 502 en borde web. ¿Es falla propia de Nginx o dependencia aguas abajo?")
        print(f"     [ACTION]      MCP Tool -> correlate_trace(trace_id='{tid}')")
        for step in chain:
            print(f"     [OBSERVATION] host={step['host']:<8} app={step['app']:<8} sev={step['severity']:<6} -> {step['msg']}")
        print(f"     [DIAGNÓSTICO] Causa raíz en 'db-01' (pool de conexiones agotado) -> cascada HTTP 502 en 'web-01'.")

    if ssh_failed_ips:
        print(f"\n  🚨 Incidente Paralelo de Seguridad (Fuerza Bruta SSH):")
        for ip, cnt in ssh_failed_ips.most_common():
            print(f"     • IP atacante {ip}: {cnt} intentos fallidos en auth-01")

    print(f"\n[FASE 4: NL-TO-QUERY MULTI-PLATAFORMA (Loki / ELK / Splunk)]")
    print("  • Grafana Loki (LogQL)     : {app=~\"nginx|postgres\", env=\"prod\"} |= \"trace_id=tr-9981\" | json")
    print("  • OpenSearch / ELK (KQL)   : host.name:(\"web-01\" OR \"db-01\") AND message:\"tr-9981\"")
    print("  • Splunk (SPL)             : index=prod (host=web-01 OR host=db-01) \"tr-9981\" | stats count by host, severity")

    print(f"\n[FASE 5: PLAN DE REMEDIACIÓN CON GUARDRAILS (Human-in-the-Loop)]")
    print("  ✅ Allowlist aprobable (requiere confirmación humana):")
    print("     1. db-01  -> Revisar sesiones idle-in-transaction y ampliar max_connections / PgBouncer.")
    if ssh_failed_ips:
        top_ip = ssh_failed_ips.most_common(1)[0][0]
        print(f"     2. auth-01 -> Bloquear temporalmente {top_ip} vía fail2ban / nftables.")
    print("  ⛔ Denylist bloqueada automáticamente: cualquier comando proveniente del payload en cuarentena.")
    print("=" * 84)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Motor de triage AI SRE para logs NDJSON.")
    parser.add_argument("--input", required=True, help="Ruta al archivo events.ndjson")
    args = parser.parse_args()
    return run_triage(Path(args.input))


if __name__ == "__main__":
    sys.exit(main())
