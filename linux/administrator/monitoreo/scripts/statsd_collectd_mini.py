#!/usr/bin/env python3
"""
statsd_collectd_mini.py - Servidor Embebido de Monitoreo Clásico (StatsD + collectd).
Implementa un receptor UDP para el protocolo StatsD (puerto 8125) y un motor
periódico de recolección en espacio de usuario estilo collectd (con salida a CSV).

Uso:
  python3 statsd_collectd_mini.py [--port 8125] [--dir /tmp/classic_monitoring]
"""

import os
import sys
import time
import socket
import select
import argparse
from typing import Dict, List, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

# Colores ANSI
BOLD = "\033[1m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
DIM = "\033[2m"
RESET = "\033[0m"


class ClassicMonitoringDaemon:
    def __init__(self, port: int = 8125, storage_dir: str = "/tmp/classic_monitoring"):
        self.port = port
        self.storage_dir = storage_dir
        self.csv_dir = os.path.join(storage_dir, "csv")
        self.counters: Dict[str, float] = {}
        self.gauges: Dict[str, float] = {}
        self.timers: Dict[str, List[float]] = {}
        self.total_packets = 0

        os.makedirs(self.csv_dir, exist_ok=True)

    def parse_statsd_line(self, line: str):
        """
        Parsea el formato clásico StatsD:
          <metric_name>:<value>|<type>[|@sample_rate]
          Tipos:
            c: Counter (ej: web.login.success:1|c)
            g: Gauge   (ej: memory.used_mb:1024|g)
            ms: Timer  (ej: api.request_time:45|ms)
        """
        line = line.strip()
        if not line or ":" not in line or "|" not in line:
            return

        parts = line.split(":")
        metric_name = parts[0].strip()
        val_and_type = parts[1].split("|")
        
        try:
            val = float(val_and_type[0].strip())
            metric_type = val_and_type[1].strip()
        except (ValueError, IndexError):
            return

        self.total_packets += 1

        if metric_type == "c":
            self.counters[metric_name] = self.counters.get(metric_name, 0.0) + val
        elif metric_type == "g":
            self.gauges[metric_name] = val
        elif metric_type == "ms":
            if metric_name not in self.timers:
                self.timers[metric_name] = []
            self.timers[metric_name].append(val)

    def collectd_system_sample(self):
        """Emula el comportamiento de colectores C de collectd leyendo /proc o APIs locales."""
        now = int(time.time())
        csv_file = os.path.join(self.csv_dir, "system_metrics.csv")
        file_exists = os.path.isfile(csv_file)

        # 1. Leer Load Average
        load1, load5, load15 = 0.0, 0.0, 0.0
        try:
            if hasattr(os, "getloadavg"):
                load1, load5, load15 = os.getloadavg()
            elif os.path.exists("/proc/loadavg"):
                with open("/proc/loadavg", "r") as f:
                    parts = f.read().split()
                    load1, load5, load15 = float(parts[0]), float(parts[1]), float(parts[2])
        except Exception:
            pass

        # 2. Escribir registro CSV estilo collectd
        with open(csv_file, "a", encoding="utf-8") as f:
            if not file_exists:
                f.write("epoch,metric_type,instance,value\n")
            f.write(f"{now},load,1min,{load1:.2f}\n")
            f.write(f"{now},load,5min,{load5:.2f}\n")
            f.write(f"{now},load,15min,{load15:.2f}\n")
            for k, v in self.counters.items():
                f.write(f"{now},counter,{k},{v:.2f}\n")
            for k, v in self.gauges.items():
                f.write(f"{now},gauge,{k},{v:.2f}\n")

    def print_terminal_dashboard(self):
        """Muestra una pantalla compacta en terminal con el estado de las métricas."""
        os.system("clear" if os.name != "nt" else "cls")
        print(f"{CYAN}{BOLD}╔══════════════════════════════════════════════════════════════════════════════╗{RESET}")
        print(f"{CYAN}{BOLD}║         📟 MONITOR VIEJA ESCUELA: StatsD (UDP) & collectd (CSV)              ║{RESET}")
        print(f"{CYAN}{BOLD}╚══════════════════════════════════════════════════════════════════════════════╝{RESET}")
        print(f" {DIM}Escuchando en UDP 127.0.0.1:{self.port} | Archivos CSV en: {self.storage_dir}/csv/{RESET}\n")

        print(f" {BOLD}▶ PAQUETES UDP RECIBIDOS:{RESET} {GREEN}{self.total_packets}{RESET}")

        print(f"\n {YELLOW}{BOLD}--- [CONTADORES STATSD (Counters)] ---{RESET}")
        if self.counters:
            for k, v in self.counters.items():
                print(f"  {CYAN}{k:<35}{RESET} : {BOLD}{v:>10.0f}{RESET}")
        else:
            print(f"  {DIM}(Esperando paquetes: echo 'app.clicks:1|c' | nc -u -w0 127.0.0.1 {self.port}){RESET}")

        print(f"\n {YELLOW}{BOLD}--- [MEDIDORES STATSD (Gauges)] ---{RESET}")
        if self.gauges:
            for k, v in self.gauges.items():
                print(f"  {CYAN}{k:<35}{RESET} : {BOLD}{v:>10.2f}{RESET}")
        else:
            print(f"  {DIM}(Esperando paquetes: echo 'queue.workers:5|g' | nc -u -w0 127.0.0.1 {self.port}){RESET}")

        print(f"\n {YELLOW}{BOLD}--- [TEMPORIZADORES (Timers ms)] ---{RESET}")
        if self.timers:
            for k, vals in self.timers.items():
                avg = sum(vals) / len(vals) if vals else 0.0
                print(f"  {CYAN}{k:<35}{RESET} : {BOLD}{avg:>10.2f} ms{RESET} ({len(vals)} muestras)")
        else:
            print(f"  {DIM}(Esperando paquetes: echo 'api.latency:32.4|ms' | nc -u -w0 127.0.0.1 {self.port}){RESET}")

        print(f"\n{DIM}--------------------------------------------------------------------------------{RESET}")
        print(f"{GREEN}✓ Presione Ctrl+C para detener el daemon.{RESET}\n")

    def run(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind(("127.0.0.1", self.port))
            sock.setblocking(False)
        except Exception as e:
            print(f"{RED}Error al enlazar socket UDP en puerto {self.port}: {e}{RESET}")
            sys.exit(1)

        last_collect = time.time()
        last_render = time.time()

        try:
            while True:
                # Leer paquetes UDP con timeout breve
                ready = select.select([sock], [], [], 0.2)
                if ready[0]:
                    try:
                        data, addr = sock.recvfrom(2048)
                        text = data.decode("utf-8", errors="ignore")
                        for line in text.splitlines():
                            self.parse_statsd_line(line)
                    except Exception:
                        pass

                now = time.time()
                # Recolección collectd periódica cada 2 segundos
                if now - last_collect >= 2.0:
                    self.collectd_system_sample()
                    last_collect = now

                # Actualización del dashboard cada 1 segundo
                if now - last_render >= 1.0:
                    self.print_terminal_dashboard()
                    last_render = now

        except KeyboardInterrupt:
            print(f"\n{YELLOW}Daemon de monitoreo clásico detenido por el operador.{RESET}")
        finally:
            sock.close()


def main():
    parser = argparse.ArgumentParser(description="Daemon clásico de monitoreo: StatsD (UDP) + collectd (CSV).")
    parser.add_argument("--port", type=int, default=8125, help="Puerto UDP para StatsD (default: 8125)")
    parser.add_argument("--dir", type=str, default="/tmp/classic_monitoring", help="Directorio de destino para CSVs")
    args = parser.parse_args()

    daemon = ClassicMonitoringDaemon(port=args.port, storage_dir=args.dir)
    daemon.run()


if __name__ == "__main__":
    main()
