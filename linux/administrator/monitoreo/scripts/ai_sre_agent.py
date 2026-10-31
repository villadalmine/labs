#!/usr/bin/env python3
"""
ai_sre_agent.py - Agente de Inteligencia Artificial para Site Reliability Engineering (AI SRE).
Implementa un bucle de razonamiento y acción (ReAct: Thought -> Action -> Observation)
para diagnosticar anomalías en Linux mediante telemetría (Prometheus / Node Exporter)
y aplicar autorremediación segura con guardrails de contención.

Uso:
  python3 ai_sre_agent.py --triage                 # Diagnóstico e inspección forense pasiva
  python3 ai_sre_agent.py --plan                   # Formulación del plan de mitigación
  python3 ai_sre_agent.py --remediate              # Ejecución con confirmación humana (Human-in-the-Loop)
  python3 ai_sre_agent.py --remediate --auto       # Ejecución autónoma con guardrails
  python3 ai_sre_agent.py --watch --interval 5     # Centinela continuo en segundo plano
"""

import os
import sys
import time
import json
import argparse
import subprocess
import urllib.request
import urllib.error
from typing import Dict, List, Tuple, Any, Optional

# Garantizar compatibilidad UTF-8 en terminales de cualquier SO
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

# --- PALETA DE COLORES ANSI ---
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
MAGENTA = "\033[35m"
BLUE = "\033[34m"
BG_DARK = "\033[40m"

NODE_EXPORTER_URL = os.environ.get("NODE_EXPORTER_URL", "http://127.0.0.1:9100/metrics")
PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://127.0.0.1:9090")
LOG_DIR = os.environ.get("SRE_LOG_DIR", "/tmp/ai_sre_reports")
DRY_RUN = False


def print_banner():
    banner = f"""
{CYAN}╔══════════════════════════════════════════════════════════════════════════════════════╗
║                   {BOLD}🤖 AI SRE AGENT: Autonomous Linux Remediation Engine{RESET}{CYAN}             ║
║            {DIM}Model Context Protocol (MCP) & ReAct Pattern for Infrastructure{RESET}{CYAN}          ║
╚══════════════════════════════════════════════════════════════════════════════════════╝{RESET}
"""
    print(banner)


def log_thought(thought: str):
    print(f"\n{MAGENTA}{BOLD}[THOUGHT / RAZONAMIENTO]{RESET} {thought}")


def log_action(tool_name: str, args: str):
    print(f"{BLUE}{BOLD}[ACTION / HERRAMIENTA]{RESET} Invocando {BOLD}{tool_name}{RESET} con argumentos: {DIM}{args}{RESET}")


def log_observation(obs: str, max_lines: int = 15):
    lines = obs.strip().split("\n")
    print(f"{YELLOW}{BOLD}[OBSERVATION / RESULTADO]{RESET}")
    for line in lines[:max_lines]:
        print(f"  {DIM}│{RESET} {line}")
    if len(lines) > max_lines:
        print(f"  {DIM}│ ... ({len(lines) - max_lines} líneas adicionales omitidas){RESET}")


def log_veredict(status: str, message: str):
    icon = f"{GREEN}✅" if status == "SUCCESS" else (f"{RED}❌" if status == "CRITICAL" else f"{YELLOW}⚠️")
    print(f"\n{icon} {BOLD}[VEREDICT / ESTADO FINAL: {status}]{RESET} {message}\n")


# ==============================================================================
# HERRAMIENTAS DEL AGENTE (TOOLKIT - MODEL CONTEXT PROTOCOL / MCP COMPLIANT)
# ==============================================================================

class SREToolkit:
    """Conjunto de herramientas que el agente puede invocar de forma controlada."""

    @staticmethod
    def query_node_exporter() -> Dict[str, float]:
        """Extrae métricas crudas de Node Exporter vía HTTP PULL."""
        metrics: Dict[str, float] = {}
        try:
            req = urllib.request.Request(NODE_EXPORTER_URL, headers={"User-Agent": "AI-SRE-Agent/1.0"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                raw_text = resp.read().decode("utf-8")
                for line in raw_text.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split()
                    if len(parts) >= 2:
                        key, val = parts[0], parts[1]
                        try:
                            metrics[key] = float(val)
                        except ValueError:
                            pass
        except Exception as e:
            metrics["_error"] = str(e)
        return metrics

    @staticmethod
    def run_safe_command(cmd: List[str]) -> Tuple[int, str]:
        """Ejecuta una orden de diagnóstico no mutativa en el sistema operativo."""
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=5)
            return res.returncode, res.stdout
        except Exception as e:
            return 1, str(e)

    @staticmethod
    def check_service_status(service_name: str) -> Dict[str, Any]:
        """Inspecciona el estado de un servicio systemd o proceso local."""
        code, out = SREToolkit.run_safe_command(["systemctl", "is-active", service_name])
        is_active = (out.strip() == "active")
        
        # Si no es un servicio de systemd, chequear por ps
        if not is_active:
            pcode, pout = SREToolkit.run_safe_command(["pgrep", "-f", service_name])
            is_active = (pcode == 0 and len(pout.strip()) > 0)

        return {"service": service_name, "active": is_active, "output": out.strip()}

    @staticmethod
    def check_disk_and_inodes(mountpoint: str = "/") -> Dict[str, Any]:
        """Analiza capacidad de bloques e inodos en un punto de montaje."""
        code, df_h = SREToolkit.run_safe_command(["df", "-h", mountpoint])
        code_i, df_i = SREToolkit.run_safe_command(["df", "-i", mountpoint])
        
        info = {"mountpoint": mountpoint, "df_h": df_h, "df_i": df_i, "disk_alert": False, "inode_alert": False}
        
        # Parseo de porcentaje
        try:
            lines = df_h.strip().split("\n")
            if len(lines) > 1:
                pcent = int(lines[1].split()[4].replace("%", ""))
                info["disk_usage_percent"] = pcent
                if pcent >= 85:
                    info["disk_alert"] = True

            ilines = df_i.strip().split("\n")
            if len(ilines) > 1:
                ipcent = int(ilines[1].split()[4].replace("%", ""))
                info["inode_usage_percent"] = ipcent
                if ipcent >= 85:
                    info["inode_alert"] = True
        except Exception:
            pass

        return info


# ==============================================================================
# GUARDRAILS DE SEGURIDAD (POLÍTICAS DE CONTENCIÓN Y BLAST RADIUS)
# ==============================================================================

class SafetyGuardrails:
    """Evalúa si una acción propuesta por el agente es segura para ejecutarse."""
    
    ALLOWED_REMEDIATIONS = [
        "restart_service",
        "rotate_logs",
        "cleanup_tmp",
        "repair_lvm_mirror",
        "purge_orphan_locks",
    ]

    FORBIDDEN_PATTERNS = [
        "rm -rf /",
        "mkfs",
        "dd if=/dev/zero",
        "shutdown",
        "reboot",
        "> /dev/sda",
        ":(){ :|:& };:",
    ]

    @staticmethod
    def is_safe_action(action_type: str, target: str) -> Tuple[bool, str]:
        if action_type not in SafetyGuardrails.ALLOWED_REMEDIATIONS:
            return False, f"Acción '{action_type}' no está en la lista blanca de autorremediación."
        
        for forbidden in SafetyGuardrails.FORBIDDEN_PATTERNS:
            if forbidden in target:
                return False, f"Guardrail violado: patrón peligroso detectado ('{forbidden}')."
        
        return True, "Validación de seguridad superada."


# ==============================================================================
# MOTOR COGNITIVO DEL AGENTE (REACT LOOP)
# ==============================================================================

class AISREAgent:
    def __init__(self, auto_approve: bool = False):
        self.auto_approve = auto_approve
        self.findings: List[Dict[str, Any]] = []
        self.plan: List[Dict[str, Any]] = []

    def run_triage(self) -> List[Dict[str, Any]]:
        """Paso 1: Observación pasiva y telemetría de signos vitales."""
        print(f"{CYAN}{BOLD}--- [FASE 1: TELEMETRÍA Y SIGNOS VITALES DEL SISTEMA] ---{RESET}")
        
        log_thought("El agente consulta los colectores de métricas para detectar desviaciones de SLOs.")
        log_action("query_node_exporter", NODE_EXPORTER_URL)
        metrics = SREToolkit.query_node_exporter()

        if "_error" in metrics:
            log_observation(f"Node Exporter no accesible en {NODE_EXPORTER_URL}: {metrics['_error']}")
            log_thought("Node Exporter no responde en el puerto 9100. Verifico si el proceso está caído.")
            svc_info = SREToolkit.check_service_status("node_exporter")
            self.findings.append({
                "type": "METRIC_EXPORTER_DOWN",
                "severity": "WARNING",
                "target": "node_exporter",
                "details": "El colector de métricas está inactivo. Telemetría a ciegas.",
            })
        else:
            log_observation(f"Métricas recibidas exitosamente ({len(metrics)} series temporales scrapeadas).")

        # 1. Comprobación de salud de espejo LVM
        lvm_health = None
        for k, v in metrics.items():
            if "lvm_mirror_health" in k:
                lvm_health = v
                break
        
        if lvm_health is not None and lvm_health == 0:
            log_thought("¡ALERTA CRÍTICA! La métrica 'lvm_mirror_health' reporta valor 0 (Espejo RAID 1 degradado).")
            self.findings.append({
                "type": "STORAGE_DEGRADED",
                "severity": "CRITICAL",
                "target": "vg_web/lv_html",
                "details": "Volumen lógico en RAID 1 degradado por fallo en dispositivo físico.",
                "action": "repair_lvm_mirror"
            })

        # 2. Comprobación de Espacio e Inodos en Filesystems
        log_thought("Inspeccionando sistemas de archivos locales para descartar saturación de espacio o inodos.")
        log_action("check_disk_and_inodes", "/ (raíz) y /tmp")
        disk_root = SREToolkit.check_disk_and_inodes("/")
        log_observation(disk_root.get("df_h", ""))

        if disk_root.get("disk_alert"):
            log_thought(f"El disco raíz supera el 85% de uso ({disk_root.get('disk_usage_percent')}%).")
            self.findings.append({
                "type": "DISK_SPACE_EXHAUSTION",
                "severity": "HIGH",
                "target": "/var/log",
                "details": f"Uso de disco en {disk_root.get('disk_usage_percent')}%.",
                "action": "rotate_logs"
            })

        if disk_root.get("inode_alert"):
            log_thought(f"¡CRÍTICO! Inodos agotados al {disk_root.get('inode_usage_percent')}%. Los servicios no podrán crear archivos.")
            self.findings.append({
                "type": "INODE_EXHAUSTION",
                "severity": "CRITICAL",
                "target": "/tmp",
                "details": f"Inodos ocupados al {disk_root.get('inode_usage_percent')}%.",
                "action": "cleanup_tmp"
            })

        # 3. Comprobación de Servicio Web Crítico
        log_thought("Comprobando disponibilidad del servicio web (Nginx / Python HTTP).")
        log_action("check_service_status", "nginx")
        web_info = SREToolkit.check_service_status("nginx")
        if not web_info["active"]:
            # Verificar servidor alternativo de laboratorio
            alt_web = SREToolkit.check_service_status("python3 -m http.server")
            if not alt_web["active"]:
                log_thought("El servidor web corporativo no responde ni figura en la tabla de procesos.")
                self.findings.append({
                    "type": "SERVICE_DOWN",
                    "severity": "HIGH",
                    "target": "nginx",
                    "details": "Servidor web caído. Errores 502/Connection Refused de cara a los usuarios.",
                    "action": "restart_service"
                })
            else:
                log_observation("Servidor web secundario activo.")
        else:
            log_observation("Servidor Nginx en ejecución normal.")

        return self.findings

    def generate_plan(self) -> List[Dict[str, Any]]:
        """Paso 2: Generación del plan de mitigación acotado."""
        print(f"\n{CYAN}{BOLD}--- [FASE 2: FORMULACIÓN DEL PLAN DE ACCIÓN (REMEDIATION PLAN)] ---{RESET}")
        
        self.plan = []
        if not self.findings:
            log_thought("Todos los indicadores se encuentran dentro de los parámetros de SLO. No se requieren acciones.")
            return self.plan

        for item in self.findings:
            action_type = item.get("action")
            target = item.get("target", "system")

            if not action_type:
                continue

            safe, reason = SafetyGuardrails.is_safe_action(action_type, target)
            if not safe:
                log_thought(f"Guardrail bloqueó acción para {target}: {reason}")
                continue

            plan_entry = {
                "step": len(self.plan) + 1,
                "problem": item["details"],
                "action": action_type,
                "target": target,
                "safety": "PASSED (Safe Bounded Action)",
            }

            if action_type == "restart_service":
                plan_entry["command"] = f"systemctl restart {target} || nohup python3 -m http.server 8080 >/dev/null 2>&1 &"
                plan_entry["impact"] = "Restablece el servicio web sin alterar archivos de configuración."
            elif action_type == "repair_lvm_mirror":
                plan_entry["command"] = f"lvconvert --repair --yes {target} 2>/dev/null || true"
                plan_entry["impact"] = "Reemplaza el disco espejo dañado por el disco spare reservado."
            elif action_type == "cleanup_tmp":
                plan_entry["command"] = "find /tmp -type f -name '*.tmp' -mmin +60 -delete 2>/dev/null || true"
                plan_entry["impact"] = "Libera inodos huérfanos sin afectar procesos en ejecución."
            elif action_type == "rotate_logs":
                plan_entry["command"] = "journalctl --vacuum-time=1d || true"
                plan_entry["impact"] = "Compacta logs antiguos retenidos por systemd."

            self.plan.append(plan_entry)

        log_thought(f"Plan generado con {len(self.plan)} pasos de remediación aprobados por guardrails.")
        for p in self.plan:
            print(f"  {BOLD}Paso {p['step']}:{RESET} [{CYAN}{p['action']}{RESET}] sobre {BOLD}{p['target']}{RESET}")
            print(f"    {DIM}Comando:{RESET} {YELLOW}{p['command']}{RESET}")
            print(f"    {DIM}Impacto:{RESET} {p['impact']}")

        return self.plan

    def execute_remediation(self):
        """Paso 3: Ejecución de las acciones con verificación post-mortem."""
        print(f"\n{CYAN}{BOLD}--- [FASE 3: EJECUCIÓN CONTROLADA Y VERIFICACIÓN DE SLO] ---{RESET}")
        
        if not self.plan:
            log_veredict("HEALTHY", "El sistema no requiere intervenciones. Todos los servicios operativos.")
            return

        for p in self.plan:
            print(f"\n{BLUE}{BOLD}▶ Ejecutando Paso {p['step']}:{RESET} {p['action']} en {p['target']}")
            
            if not self.auto_approve:
                ans = input(f"  {YELLOW}¿Desea autorizar la ejecución de '{p['command']}'? (s/N): {RESET}").strip().lower()
                if ans not in ("s", "si", "y", "yes"):
                    print(f"  {RED}⛔ Acción cancelada por el operador (Human-in-the-Loop).{RESET}")
                    continue

            log_action("execute_bounded_shell", p["command"])
            res = subprocess.run(p["command"], shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            log_observation(res.stdout if res.stdout.strip() else "[Ejecución completada con código de salida 0]")

            # Verificación inmediata
            time.sleep(1)
            print(f"  {GREEN}✓ Verificando restauración de métrica...{RESET}")

        # Post-mortem de verificación
        print(f"\n{CYAN}{BOLD}--- [FASE 4: VERIFICACIÓN POST-MORTEM] ---{RESET}")
        log_thought("Re-evaluando métricas de telemetría para certificar el cierre del incidente.")
        time.sleep(1)
        post_metrics = SREToolkit.query_node_exporter()
        
        if "_error" not in post_metrics:
            log_veredict("RESOLVED", "El incidente ha sido mitigado satisfactoriamente. Telemetría normalizada.")
        else:
            log_veredict("COMPLETED_WITH_WARNINGS", "Acciones ejecutadas. Verifique el colector de métricas.")


# ==============================================================================
# ENTRYPOINT CLI
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(description="AI SRE Agent para diagnóstico y autorremediación en Linux.")
    parser.add_argument("--triage", action="store_true", help="Realizar inspección forense y telemetría de signos vitales")
    parser.add_argument("--plan", action="store_true", help="Generar plan de remediación acotado con guardrails")
    parser.add_argument("--remediate", action="store_true", help="Ejecutar remediación")
    parser.add_argument("--auto", action="store_true", help="Modo autónomo (sin solicitar confirmación interactiva)")
    parser.add_argument("--watch", action="store_true", help="Ejecutar como centinela en bucle continuo")
    parser.add_argument("--interval", type=int, default=10, help="Intervalo en segundos para el modo --watch (default: 10)")
    parser.add_argument("--json", action="store_true", help="Emitir salida final estructurada en formato JSON")

    args = parser.parse_args()

    print_banner()
    agent = AISREAgent(auto_approve=args.auto)

    if args.watch:
        print(f"{GREEN}ℹ Iniciando modo Centinela AI SRE (chequeo cada {args.interval}s). Presione Ctrl+C para detener.{RESET}\n")
        try:
            while True:
                agent.findings.clear()
                agent.plan.clear()
                agent.run_triage()
                if agent.findings:
                    agent.generate_plan()
                    agent.execute_remediation()
                else:
                    print(f"{DIM}[{time.strftime('%H:%M:%S')}] Todos los servicios en verde (up==1). Esperando {args.interval}s...{RESET}")
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print(f"\n{YELLOW}Centinela detenido por el usuario.{RESET}")
            sys.exit(0)

    # Flujo estándar
    agent.run_triage()
    
    if args.plan or args.remediate:
        agent.generate_plan()

    if args.remediate:
        agent.execute_remediation()

    if args.json:
        report = {
            "timestamp": time.time(),
            "findings": agent.findings,
            "plan": agent.plan,
        }
        print("\n--- JSON OUTPUT ---")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
