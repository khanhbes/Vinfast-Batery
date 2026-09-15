"""Production entry point for the Smart Charge reconciliation worker.

The Flask API and this process intentionally construct the same Cloud-First
service.  The worker only reconciles existing sessions; it never arms a relay.
"""
from __future__ import annotations

import os

from server import app
from smart_charge_worker import run_forever


if __name__ == "__main__":
    service = app.extensions["smart_charge_service"]
    interval = max(60, int(os.environ.get("SMART_CHARGE_WORKER_POLL_SECONDS", "60")))
    run_forever(service, interval_seconds=interval)
