"""Read-only Azure pilot. Deliberately has no control provider, worker or lease.

Readiness here proves only a recent Firestore read and an in-memory vault test.
It MUST NOT be consumed as readiness/heartbeat by SmartChargeService.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen

from .profile_vault import ShellyProfileVault


def validate_environment(env):
    if env.get("AZURE_STAGING_HARDWARE_DISABLED") != "1":
        raise ValueError("Pilot requires the hardware-disabled policy")
    if any(env.get(key) for key in ("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST")):
        raise ValueError("Pilot refuses emulator configuration")
    scope = env.get("SMART_CHARGE_PILOT_SCOPE", "azure-staging-pilot")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", scope):
        raise ValueError("Invalid pilot scope")
    raw = env.get("FIREBASE_CREDENTIALS_JSON", "")
    try:
        document = json.loads(raw) if raw.lstrip().startswith("{") else json.loads(base64.b64decode(raw, validate=True))
        if document.get("type") != "service_account" or document.get("project_id") != "vinfast-873db":
            raise ValueError()
    except Exception:
        raise ValueError("Pilot Firebase configuration is missing or invalid") from None
    vault = ShellyProfileVault(env.get("SHELLY_PROFILE_MASTER_KEY", ""))
    if not vault.configured:
        raise ValueError("Pilot vault configuration is missing")
    synthetic = {"probe": "read-only-pilot-v1"}
    sealed = vault.encrypt("pilot-synthetic", "not-a-device", synthetic)
    if vault.decrypt("pilot-synthetic", "not-a-device", sealed) != synthetic:
        raise ValueError("Pilot vault self-test failed")
    return scope, document


class PilotMonitor:
    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._lock = threading.Lock()
        self._last_success = None
        self._last_result = False
        self._stopped = False

    def record(self, success):
        with self._lock:
            self._last_result = bool(success)
            if success:
                self._last_success = self._clock()

    def stop(self):
        with self._lock:
            self._stopped = True

    def snapshot(self):
        with self._lock:
            age = None if self._last_success is None else max(0, self._clock() - self._last_success)
            return {
                "mode": "pilot_read_only", "controlReady": False,
                "alive": not self._stopped,
                "ready": not self._stopped and self._last_result and age is not None and age <= 90,
                "lastSuccessfulReadAgeSeconds": None if age is None else round(age, 1),
            }


def read_probe(document_ref, monitor):
    # Exactly one bounded Get; no data(), set(), transaction(), list or actuation.
    try:
        document_ref.get(timeout=10, retry=None)
    except Exception:
        monitor.record(False)
        return False
    monitor.record(True)
    return True


def create_health_server(monitor, host="0.0.0.0", port=8090):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            state = monitor.snapshot()
            if self.path not in ("/health", "/ready"):
                self.send_error(404)
                return
            ok = state["alive"] if self.path == "/health" else state["ready"]
            payload = json.dumps(state, separators=(",", ":")).encode()
            self.send_response(200 if ok else 503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_):
            pass

    return ThreadingHTTPServer((host, port), Handler)


def healthcheck():
    try:
        with urlopen("http://127.0.0.1:8090/ready", timeout=3) as response:
            state = json.load(response)
            return 0 if state.get("mode") == "pilot_read_only" and state.get("controlReady") is False and state.get("ready") is True else 1
    except Exception:
        return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--healthcheck", action="store_true")
    if parser.parse_args().healthcheck:
        return healthcheck()
    app = None
    db = None
    server = None
    try:
        scope, credential_document = validate_environment(os.environ)
        # Lazy imports let configuration fail before any network access.
        import firebase_admin
        from firebase_admin import credentials, firestore

        app = firebase_admin.initialize_app(credentials.Certificate(credential_document),
                                            {"projectId": "vinfast-873db", "httpTimeout": 10},
                                            name="smart-charge-read-only-pilot")
        db = firestore.client(app=app)
        probe = db.collection("smartChargeWorkerPilotChecks").document(scope)
        monitor = PilotMonitor()
        stop = threading.Event()

        def shutdown(*_):
            monitor.stop()
            stop.set()

        for signum in (signal.SIGTERM, signal.SIGINT):
            signal.signal(signum, shutdown)
        server = create_health_server(monitor)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        print(json.dumps({"event": "pilot_started", "mode": "pilot_read_only", "controlReady": False}), flush=True)
        previous = None
        while not stop.is_set():
            ok = read_probe(probe, monitor)
            if ok != previous:
                print(json.dumps({"event": "pilot_read_result", "success": ok, "controlReady": False}), flush=True)
                previous = ok
            stop.wait(60)
        return 0
    except Exception:
        # No exception text: credentials, request bodies and account IDs stay private.
        print(json.dumps({"event": "pilot_start_failed", "controlReady": False}), flush=True)
        return 1
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        if app is not None:
            if db is not None:
                db.close()
            firebase_admin.delete_app(app)


if __name__ == "__main__":
    raise SystemExit(main())
