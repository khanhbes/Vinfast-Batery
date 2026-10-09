"""Production entry point for the Smart Charge reconciliation worker.

The Flask API and this process intentionally construct the same Cloud-First
service.  The worker only reconciles existing sessions; it never arms a relay.
"""
from __future__ import annotations

import os

from server import app
from smart_charge_worker import run_forever
from shelly.worker_health import WorkerHealthMonitor


if __name__ == "__main__":
    service = app.extensions["smart_charge_service"]
    interval = max(15, min(60, int(os.environ.get("SMART_CHARGE_WORKER_POLL_SECONDS", "60"))))
    monitor = WorkerHealthMonitor()
    probe = monitor.start_server(
        host=os.environ.get("SMART_CHARGE_WORKER_HEALTH_HOST", "127.0.0.1"),
        port=int(os.environ.get("SMART_CHARGE_WORKER_HEALTH_PORT", "8090")),
    )
    try:
        run_forever(service, interval_seconds=interval, health_monitor=monitor)
    finally:
        probe.shutdown()
        probe.server_close()
