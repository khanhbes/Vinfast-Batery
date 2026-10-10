"""Offline smoke fixture, mounted for QA only; NOT in the production image."""
import base64
import json
import signal
import threading
from importlib.util import find_spec

from shelly.worker_pilot import PilotMonitor, create_health_server, read_probe, validate_environment


class ReadOnlyDocument:
    def get(self, *, timeout, retry):
        assert timeout == 10 and retry is None


validate_environment({
    "AZURE_STAGING_HARDWARE_DISABLED": "1",
    "FIREBASE_CREDENTIALS_JSON": json.dumps({"type": "service_account", "project_id": "vinfast-873db"}),
    "SHELLY_PROFILE_MASTER_KEY": base64.urlsafe_b64encode(bytes(32)).decode(),
})
for module in ("shelly.service", "shelly.providers", "shelly.repositories", "smart_charge_worker"):
    assert find_spec(module) is None
monitor = PilotMonitor()
stop = threading.Event()


def shutdown(*_):
    monitor.stop()
    stop.set()


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)
server = create_health_server(monitor, "127.0.0.1")
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
assert read_probe(ReadOnlyDocument(), monitor)
print(json.dumps({"event": "offline_pilot_ready", "controlReady": False}), flush=True)
stop.wait(60)
server.shutdown()
server.server_close()
thread.join(timeout=3)
assert not monitor.snapshot()["ready"]
assert monitor.snapshot()["controlReady"] is False
