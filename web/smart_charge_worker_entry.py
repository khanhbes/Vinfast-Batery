"""Production entry point for the Smart Charge reconciliation worker.

Standalone Cloud-First runtime. It never imports Flask/AI or arms a relay.
"""
from __future__ import annotations

import os
import signal
import threading

from smart_charge_worker import run_forever
from shelly.worker_health import WorkerHealthMonitor
from shelly.worker_runtime import create_worker_service, validate_configuration, WorkerConfigurationError


def run_worker(service, *, interval=60, port=8090, stop_event=None, user_ids=None, monitor=None):
    stop_event = stop_event if stop_event is not None else threading.Event()
    monitor = monitor or WorkerHealthMonitor()
    probe = monitor.start_server(host="127.0.0.1", port=port)
    try:
        run_forever(service, user_ids, interval_seconds=interval, health_monitor=monitor,
                    stop_event=stop_event)
    finally:
        monitor.mark_unhealthy()
        probe.shutdown()
        probe.server_close()


def main():
    try:
        _, interval, port = validate_configuration(os.environ)
        service, cleanup = create_worker_service()
    except WorkerConfigurationError as error:
        print(f"[smart-charge-worker] startup blocked: {error}")
        return 1
    monitor = WorkerHealthMonitor()
    stop_event = threading.Event()
    def stop(*_):
        monitor.mark_unhealthy()
        stop_event.set()
    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        run_worker(service, interval=interval, port=port, stop_event=stop_event, monitor=monitor)
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
