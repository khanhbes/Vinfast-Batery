"""Pilot probes never acquire a control lease or call a hardware provider."""
import base64
import json
import threading
from unittest.mock import Mock
from urllib.error import HTTPError
from urllib.request import urlopen

import pytest

from shelly import worker_pilot


def configuration():
    return {
        "AZURE_STAGING_HARDWARE_DISABLED": "1",
        "FIREBASE_CREDENTIALS_JSON": json.dumps({"type": "service_account", "project_id": "vinfast-873db"}),
        "SHELLY_PROFILE_MASTER_KEY": base64.urlsafe_b64encode(bytes(32)).decode(),
    }


@pytest.mark.parametrize("base64_encoded", [False, True])
def test_valid_configuration_only_tests_synthetic_vault(base64_encoded):
    env = configuration()
    if base64_encoded:
        env["FIREBASE_CREDENTIALS_JSON"] = base64.b64encode(env["FIREBASE_CREDENTIALS_JSON"].encode()).decode()
    scope, document = worker_pilot.validate_environment(env)
    assert scope == "azure-staging-pilot"
    assert document["project_id"] == "vinfast-873db"


@pytest.mark.parametrize("field,value", [
    ("AZURE_STAGING_HARDWARE_DISABLED", "0"),
    ("AZURE_STAGING_HARDWARE_DISABLED", ""),
    ("FIRESTORE_EMULATOR_HOST", "localhost:8080"),
    ("FIREBASE_AUTH_EMULATOR_HOST", "localhost:9099"),
    ("SMART_CHARGE_PILOT_SCOPE", "../device"),
    ("FIREBASE_CREDENTIALS_JSON", "not-a-credential"),
    ("FIREBASE_CREDENTIALS_JSON", '{"type":"service_account","project_id":"wrong"}'),
    ("SHELLY_PROFILE_MASTER_KEY", ""),
])
def test_configuration_fails_closed(field, value):
    env = configuration()
    env[field] = value
    with pytest.raises(ValueError):
        worker_pilot.validate_environment(env)


def test_one_read_no_write_no_lease_and_error_does_not_leak():
    ref = Mock()
    monitor = worker_pilot.PilotMonitor()
    assert worker_pilot.read_probe(ref, monitor)
    assert ref.mock_calls == [("get", (), {"timeout": 10, "retry": None})]
    assert monitor.snapshot()["ready"]
    assert monitor.snapshot()["controlReady"] is False
    ref.get.side_effect = RuntimeError("synthetic-secret-must-not-appear")
    assert not worker_pilot.read_probe(ref, monitor)
    assert not monitor.snapshot()["ready"]
    assert "synthetic-secret" not in json.dumps(monitor.snapshot())


def test_stale_read_and_shutdown_never_grant_control():
    now = [0.0]
    monitor = worker_pilot.PilotMonitor(lambda: now[0])
    assert not monitor.snapshot()["ready"]
    monitor.record(True)
    assert monitor.snapshot()["ready"]
    now[0] = 90.01
    assert not monitor.snapshot()["ready"]
    monitor.record(True)
    monitor.stop()
    assert not monitor.snapshot()["alive"]
    assert not monitor.snapshot()["ready"]
    assert monitor.snapshot()["controlReady"] is False


def test_private_http_health_reports_readiness_separately():
    monitor = worker_pilot.PilotMonitor()
    server = worker_pilot.create_health_server(monitor, "127.0.0.1", 0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_port}"
    try:
        with urlopen(base + "/health", timeout=3) as response:
            assert response.status == 200
            assert json.load(response)["controlReady"] is False
        with pytest.raises(HTTPError) as error:
            urlopen(base + "/ready", timeout=3)
        assert error.value.code == 503
        monitor.record(True)
        with urlopen(base + "/ready", timeout=3) as response:
            assert json.load(response)["ready"] is True
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)


def test_production_image_has_no_actuator_or_ingress():
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    image = (root / "web/Dockerfile.worker-pilot").read_text()
    source = (root / "web/shelly/worker_pilot.py").read_text()
    deployment = (root / "deploy/azure/worker-pilot.bicep").read_text()
    code = "\n".join(line.split("//", 1)[0] for line in deployment.splitlines())
    assert "ingress:" not in code
    assert "minReplicas: 1, maxReplicas: 1" in deployment
    assert "memory: '0.5Gi'" in deployment
    assert "COPY shelly/ ./" not in image
    for forbidden in ("SmartChargeService", "VaultCloudControlProvider", "reconcile_sessions", "acquire_lease"):
        # The module docstring names the consumer explicitly; imports/code must not.
        assert forbidden not in source.split('"""', 2)[-1]
