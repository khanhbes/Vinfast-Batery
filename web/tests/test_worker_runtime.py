"""Standalone import/config/shutdown tests; no ADC, account or relay network."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from shelly.worker_runtime import validate_configuration, create_worker_service, WorkerConfigurationError
from shelly.push_notifications import send_terminal_push
from shelly.worker_health import WorkerHealthMonitor
from shelly.repositories import SmartChargeRepository
from shelly.providers.fake import FakeShellyProvider
from shelly.service import SmartChargeService
from smart_charge_worker import run_forever


def config():
    return {"SMART_CHARGE_WORKER_SCOPE": "qa-runtime",
            "SHELLY_PROFILE_MASTER_KEY": base64.urlsafe_b64encode(bytes(range(32))).decode()}


@pytest.mark.parametrize("changes,code", [
    ({"SMART_CHARGE_WORKER_SCOPE": ""}, "workerScopeNotConfigured"),
    ({"SMART_CHARGE_WORKER_SCOPE": "bad/scope"}, "workerScopeNotConfigured"),
    ({"SHELLY_PROVIDER": "fake"}, "workerProviderUnsupported"),
    ({"SHELLY_PROVIDER": "integrator"}, "workerProviderUnsupported"),
    ({"SHELLY_PROFILE_MASTER_KEY": "broken"}, "workerVaultNotConfigured"),
    ({"FIRESTORE_EMULATOR_HOST": "localhost:8080"}, "workerEmulatorForbidden"),
    ({"SMART_CHARGE_WORKER_HEALTH_HOST": "0.0.0.0"}, "workerProbeMustBePrivate"),
    ({"SMART_CHARGE_WORKER_HEALTH_PORT": "0"}, "workerTimingInvalid"),
    ({"SMART_CHARGE_WORKER_POLL_SECONDS": "invalid"}, "workerTimingInvalid"),
])
def test_invalid_config_fails_before_sdk_access(changes, code, monkeypatch):
    env = config() | changes
    monkeypatch.setattr(os, "environ", env)
    with pytest.raises(WorkerConfigurationError, match=f"^{code}$"):
        create_worker_service()


def test_configuration_clamps_poll_interval():
    assert validate_configuration(config() | {"SMART_CHARGE_WORKER_POLL_SECONDS": "1"}) == ("qa-runtime", 15, 8090)
    assert validate_configuration(config() | {"SMART_CHARGE_WORKER_POLL_SECONDS": "100"})[1] == 60


def test_import_does_not_initialize_firebase_flask_or_ml():
    command = "import sys; import smart_charge_worker_entry; assert not any(n in sys.modules for n in ['server','flask','numpy','pandas','sklearn','firebase_admin'])"
    result = subprocess.run([sys.executable, "-c", command], cwd=Path(__file__).resolve().parents[1],
                            capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr.decode()


def test_factory_uses_named_firebase_app_without_predictor(monkeypatch):
    import firebase_admin
    from firebase_admin import credentials, firestore
    monkeypatch.setattr(os, "environ", config())
    app, db = object(), Mock()
    initialize = Mock(return_value=app)
    cleanup = Mock()
    monkeypatch.setattr(credentials, "ApplicationDefault", Mock(return_value=object()))
    monkeypatch.setattr(firebase_admin, "initialize_app", initialize)
    monkeypatch.setattr(firebase_admin, "delete_app", cleanup)
    monkeypatch.setattr(firestore, "client", Mock(return_value=db))
    service, close = create_worker_service()
    assert service.repository.db is db
    assert service.repository.worker_scope == "qa-runtime"
    assert service.provider.name == "vault_cloud"
    assert initialize.call_args.kwargs["name"] == "smart-charge-worker"
    assert initialize.call_args.args[1]["httpTimeout"] == 10
    with pytest.raises(RuntimeError, match="workerPredictionDisabled"):
        service.predictor({})
    close()
    cleanup.assert_called_once_with(app)


def test_firebase_failure_redacted_no_memory_fallback(monkeypatch):
    import firebase_admin
    from firebase_admin import credentials, firestore
    monkeypatch.setattr(os, "environ", config())
    app = object()
    monkeypatch.setattr(credentials, "ApplicationDefault", Mock(return_value=object()))
    monkeypatch.setattr(firebase_admin, "initialize_app", Mock(return_value=app))
    cleanup = Mock()
    monkeypatch.setattr(firebase_admin, "delete_app", cleanup)
    monkeypatch.setattr(firestore, "client", Mock(side_effect=RuntimeError("sensitive-details")))
    with pytest.raises(WorkerConfigurationError, match="^workerFirebaseUnavailable$"):
        create_worker_service()
    cleanup.assert_called_once_with(app)


def test_stop_during_scan_never_publishes_ready_or_dispatches():
    stop = threading.Event()
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    monitor = WorkerHealthMonitor()
    service = SmartChargeService(repo, provider, lambda _: {})
    def users():
        stop.set()
        return ["qa-owner"]
    run_forever(service, users, stop_event=stop, health_monitor=monitor)
    assert provider.command_count == 0
    assert not monitor.ready() and not repo.worker_health_ready(service.clock())
    assert service.provider.worker_lease_guard is None


def test_stopped_before_boot_never_claims():
    repo = SmartChargeRepository()
    repo.claim_worker_lease = Mock()
    stop = threading.Event()
    stop.set()
    service = SmartChargeService(repo, FakeShellyProvider(), lambda _: {})
    run_forever(service, stop_event=stop)
    repo.claim_worker_lease.assert_not_called()


def test_shutdown_during_read_preserves_device_session_lock(monkeypatch):
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    stop = threading.Event()
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("qa-owner")[0]
    binding.vehicle_id = "qa-vehicle"
    repo.save_binding("qa-owner", binding)
    repo.register_vehicle_owner("qa-owner", "qa-vehicle")
    repo.claim_worker_lease("qa-bootstrap")
    repo.publish_worker_heartbeat("qa-bootstrap", healthy=True)
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    session = service.manual_on("qa-owner", 300, "qa-operation", "qa-vehicle")
    repo.release_worker_lease("qa-bootstrap")
    provider.status.timer_remaining = 0
    def read(_):
        stop.set()
        return provider.status
    provider.get_status = read
    run_forever(service, lambda: ["qa-owner"], stop_event=stop)
    assert provider.command_count == 1  # fixture ON only; no shutdown OFF or retry ON
    assert repo.get_session("qa-owner", session.session_id).state == "active"
    assert not repo.claim_device_session("qa-owner", binding.device_id, "qa-second-on")
    assert not repo.worker_health_ready(service.clock())


def test_push_preserves_uid_filter_and_dedupe():
    messaging = Mock()
    messaging.send_each_for_multicast.return_value = SimpleNamespace(success_count=1, failure_count=0, responses=[])
    deliveries = set()
    args = dict(session_id="qa-session", state="completed", messaging=messaging,
                local_tokens={("qa-a", "phone"): {"token": "qa-a-token"},
                              ("qa-b", "phone"): {"token": "qa-b-token"}},
                local_deliveries=deliveries)
    assert send_terminal_push("qa-a", **args)["sent"] == 1
    assert messaging.MulticastMessage.call_args.kwargs["tokens"] == ["qa-a-token"]
    assert send_terminal_push("qa-a", **args)["deduplicated"]
    messaging.send_each_for_multicast.assert_called_once()


def test_push_named_app_and_multicast_batches():
    messaging = Mock()
    messaging.send_each_for_multicast.return_value = SimpleNamespace(success_count=1, failure_count=0, responses=[])
    app = object()
    tokens = {("qa", str(i)): {"token": f"qa-token-{i}"} for i in range(501)}
    send_terminal_push("qa", session_id="qa", state="interrupted", messaging=messaging,
                       firebase_app=app, local_tokens=tokens)
    assert [len(c.kwargs["tokens"]) for c in messaging.MulticastMessage.call_args_list] == [500, 1]
    assert all(c.kwargs == {"app": app} for c in messaging.send_each_for_multicast.call_args_list)


def test_fixture_boot_and_shutdown():
    result = subprocess.run([sys.executable, "scripts/worker_fixture_smoke.py", "--hold-seconds", "0"],
                            cwd=Path(__file__).resolve().parents[1], capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr.decode()
    ready, stopped = [json.loads(line) for line in result.stdout.splitlines()]
    assert ready["ready"] and ready["forbiddenImports"] == []
    assert stopped["stopped"] and stopped["readinessCleared"] and stopped["relayCommands"] == 0
