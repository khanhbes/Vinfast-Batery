"""Small, private worker probe; no Firebase/AI imports or account data."""
from __future__ import annotations

import json
import math
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen


class WorkerHealthMonitor:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self._lock = threading.Lock()
        self._scan_at = None
        self._lease_until = None
        self._healthy = False

    def mark_unhealthy(self):
        with self._lock:
            self._healthy = False

    def mark_healthy(self, *, lease_remaining_seconds: float):
        now = self.clock()
        with self._lock:
            if (type(lease_remaining_seconds) not in (int, float)
                    or not math.isfinite(lease_remaining_seconds) or lease_remaining_seconds <= 0):
                self._healthy = False
                return
            self._scan_at = now
            self._lease_until = now + max(0, min(180, lease_remaining_seconds))
            self._healthy = True

    def ready(self) -> bool:
        now = self.clock()
        with self._lock:
            return bool(self._healthy and self._scan_at is not None
                        and 0 <= now - self._scan_at <= 90
                        and self._lease_until is not None and now < self._lease_until)

    def start_server(self, *, host="127.0.0.1", port=8090):
        monitor = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path not in {"/health", "/ready"}:
                    self.send_error(404)
                    return
                ready = self.path == "/health" or monitor.ready()
                status = "alive" if self.path == "/health" else "ready" if ready else "unavailable"
                payload = json.dumps({"success": ready, "status": status}).encode()
                self.send_response(200 if ready else 503)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer((host, port), Handler)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        return server


def main():
    # Container health check must not import server.py or load credentials.
    try:
        port = int(os.environ.get("SMART_CHARGE_WORKER_HEALTH_PORT", "8090"))
        with urlopen(f"http://127.0.0.1:{port}/ready", timeout=2) as response:
            return 0 if response.status == 200 else 1
    except Exception:
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
