"""Explicit offline fixture, never bootstraps ADC/vault or creates a session.

Run only as a separate QA container command, not the production entry point.
"""
import argparse
import json
from pathlib import Path
import signal
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import firebase_admin  # dependency/import cost only; no initialize_app call
from firebase_admin import firestore, messaging  # SDK import cost; no client/ADC
from shelly.models import utcnow
from shelly.providers.fake import FakeShellyProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService
from shelly.worker_health import WorkerHealthMonitor
from smart_charge_worker_entry import run_worker


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hold-seconds", type=float, default=2)
    args = parser.parse_args()
    assert not firebase_admin._apps, "fixture must not initialize Firebase"
    stop = threading.Event()
    monitor = WorkerHealthMonitor()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: (monitor.mark_unhealthy(), stop.set()))
    repository = SmartChargeRepository(worker_scope="offline-fixture")
    provider = FakeShellyProvider()
    service = SmartChargeService(repository, provider, lambda _: {})
    failures = []
    def run():
        try:
            run_worker(service, port=8090, interval=60, user_ids=lambda: [],
                       monitor=monitor, stop_event=stop)
        except Exception as error:
            failures.append(type(error).__name__)
    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    deadline = time.monotonic() + 10
    while not monitor.ready() and time.monotonic() < deadline and not failures:
        stop.wait(0.02)
    ready = monitor.ready()
    memory = {}
    status = Path("/proc/self/status")
    if status.exists():
        memory = {line.split(':')[0]: line.split(':')[1].strip()
                  for line in status.read_text().splitlines() if line.startswith(("VmRSS:", "VmHWM:"))}
    forbidden = [name for name in ("server", "flask", "numpy", "pandas", "sklearn", "tensorflow")
                 if name in sys.modules]
    print(json.dumps({"fixture": True, "ready": ready, "memory": memory,
                      "forbiddenImports": forbidden, "relayCommands": provider.command_count}), flush=True)
    stop.wait(min(120, max(0, args.hold_seconds)))
    stop.set()
    thread.join(10)
    result = {"fixture": True, "stopped": not thread.is_alive(),
              "readinessCleared": not monitor.ready(),
              "leaseReleased": not repository.worker_health_ready(utcnow()),
              "relayCommands": provider.command_count, "errors": failures}
    print(json.dumps(result), flush=True)
    return 0 if (ready and not forbidden and not failures and result["stopped"]
                 and result["readinessCleared"] and result["leaseReleased"]
                 and provider.command_count == 0) else 1


if __name__ == "__main__":
    raise SystemExit(main())
