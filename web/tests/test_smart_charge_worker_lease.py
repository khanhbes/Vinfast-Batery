"""Worker fencing/probes only: no real account, provider, cloud or relay."""
from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock
from urllib.error import HTTPError
from urllib.request import urlopen

import pytest

from shelly.models import utcnow
from shelly.repositories import SmartChargeRepository
from shelly.providers.fake import FakeShellyProvider
from shelly.service import SmartChargeService
from shelly.worker_health import WorkerHealthMonitor, main
from smart_charge_worker import run_forever, reconcile_once


def test_single_holder_epoch_takeover_blocks_old_heartbeat_renew_and_release():
    repo = SmartChargeRepository()
    now = utcnow()
    assert repo.claim_worker_lease("qa-a", now=now) == 1
    assert repo.claim_worker_lease("qa-b", now=now) is None
    repo.publish_worker_heartbeat("qa-a", healthy=True, now=now)
    assert repo.worker_health_ready(now)
    later = now + timedelta(seconds=181)
    assert repo.claim_worker_lease("qa-b", now=later) == 2
    assert not repo.worker_health_ready(later)  # old holder's health is not inherited
    for healthy in (True, False):
        with pytest.raises(RuntimeError, match="workerLeaseLost"):
            repo.publish_worker_heartbeat("qa-a", healthy=healthy, now=later)
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        repo.renew_worker_lease("qa-a", now=later)
    assert not repo.release_worker_lease("qa-a", now=later)
    repo.publish_worker_heartbeat("qa-b", healthy=True, now=later)
    assert repo.worker_health_ready(later)


def test_release_preserves_epoch_and_invalidates_previous_health():
    repo = SmartChargeRepository()
    now = utcnow()
    assert repo.claim_worker_lease("qa-a", now=now) == 1
    repo.publish_worker_heartbeat("qa-a", healthy=True, now=now)
    assert repo.release_worker_lease("qa-a", now=now)
    assert not repo.worker_health_ready(now)
    assert repo.claim_worker_lease("qa-a", now=now) == 2
    assert not repo.worker_health_ready(now)  # requires a new successful scan


def test_same_process_threads_only_one_holder():
    repo = SmartChargeRepository()
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(repo.claim_worker_lease, ["qa-a", "qa-b"]))
    assert sum(result is not None for result in results) == 1


@pytest.mark.parametrize("field,value", [
    ("epoch", True), ("epoch", 0), ("schemaVersion", True), ("schemaVersion", 2),
    ("expiresAt", None), ("expiresAt", utcnow().replace(tzinfo=None)),
    ("expiresAt", utcnow() + timedelta(seconds=600)), ("scope", "wrong-environment"),
])
def test_malformed_lease_never_authorizes_on_or_takeover(field, value):
    repo = SmartChargeRepository()
    now = utcnow()
    repo.claim_worker_lease("qa-a", now=now)
    repo.publish_worker_heartbeat("qa-a", healthy=True, now=now)
    repo._worker_lease[field] = value
    assert not repo.worker_health_ready(now)
    with pytest.raises(RuntimeError, match="workerLeaseMalformed"):
        repo.claim_worker_lease("qa-b", now=now)


def test_missing_lease_cannot_publish_even_healthy_boolean():
    repo = SmartChargeRepository()
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        repo.publish_worker_heartbeat("qa-a", healthy=True)
    assert not repo.worker_health_ready(utcnow())


def test_loser_loop_does_not_poll_or_destroy_live_holder_health():
    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-a")
    repo.publish_worker_heartbeat("qa-a", healthy=True)
    service = SmartChargeService(repo, FakeShellyProvider(), lambda _: {})
    users = Mock(return_value=[])
    monitor = WorkerHealthMonitor()
    with pytest.raises(KeyboardInterrupt):
        run_forever(service, users, sleeper=Mock(side_effect=KeyboardInterrupt), health_monitor=monitor)
    users.assert_not_called()
    assert repo.worker_health_ready(utcnow())
    assert not monitor.ready()
    assert service.provider.command_count == 0
    assert service._worker_lease_guard is None


def test_loop_probe_ready_only_after_scan_then_unhealthy_on_exit():
    repo = SmartChargeRepository()
    service = SmartChargeService(repo, FakeShellyProvider(), lambda _: {})
    monitor = WorkerHealthMonitor()
    def stop(_):
        assert monitor.ready() and repo.worker_health_ready(utcnow())
        raise KeyboardInterrupt
    with pytest.raises(KeyboardInterrupt):
        run_forever(service, lambda: [], sleeper=stop, health_monitor=monitor)
    assert not monitor.ready() and not repo.worker_health_ready(utcnow())
    assert service.provider.command_count == 0


def test_healthy_scan_does_not_flap_unavailable_during_next_scan():
    repo = SmartChargeRepository()
    service = SmartChargeService(repo, FakeShellyProvider(), lambda _: {})
    monitor = WorkerHealthMonitor()
    scans, sleeps = [0], [0]
    def users():
        if scans[0] > 0:
            assert monitor.ready() and repo.worker_health_ready(utcnow())
        scans[0] += 1
        return []
    def sleep(_):
        sleeps[0] += 1
        if sleeps[0] == 2:
            raise KeyboardInterrupt
    with pytest.raises(KeyboardInterrupt):
        run_forever(service, users, sleeper=sleep, health_monitor=monitor)
    assert scans[0] == 2
    assert not monitor.ready() and not repo.worker_health_ready(utcnow())


def test_fresh_lease_checks_do_not_write_or_renew_per_request():
    repo = SmartChargeRepository()
    service = SmartChargeService(repo, FakeShellyProvider(), lambda _: {})
    real_change = repo._change_worker_lease
    repo._change_worker_lease = Mock(wraps=real_change)
    repo.renew_worker_lease = Mock(wraps=repo.renew_worker_lease)
    def stop(_):
        assert repo._change_worker_lease.call_count == 1  # claim only, before shutdown
        repo.renew_worker_lease.assert_not_called()
        raise KeyboardInterrupt
    with pytest.raises(KeyboardInterrupt):
        run_forever(service, lambda: [], sleeper=stop)


def test_read_only_fence_rejects_new_holder_instead_of_trusting_cache():
    repo = SmartChargeRepository()
    now = utcnow()
    repo.claim_worker_lease("qa-a", now=now)
    assert repo.worker_lease_deadline("qa-a", now=now) == now + timedelta(seconds=180)
    later = now + timedelta(seconds=181)
    repo.claim_worker_lease("qa-b", now=later)
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        repo.worker_lease_deadline("qa-a", now=later)


def test_lease_lost_during_readback_sends_no_backup_off(monkeypatch):
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("qa-owner")[0]
    binding.vehicle_id = "qa-car"
    repo.save_binding("qa-owner", binding)
    repo.register_vehicle_owner("qa-owner", "qa-car")
    repo.claim_worker_lease("qa-a")
    repo.publish_worker_heartbeat("qa-a", healthy=True)
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    service.manual_on("qa-owner", 300, "qa-op", "qa-car")  # fake ON only
    provider.status.timer_remaining = 0
    def read(_):
        repo.release_worker_lease("qa-a")
        assert repo.claim_worker_lease("qa-b") == 2
        return provider.status
    provider.get_status = read
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        reconcile_once(service, "qa-owner", lease_guard=lambda: repo.renew_worker_lease("qa-a"))
    assert provider.command_count == 1  # no OFF/second ON from stale worker


def test_probe_stale_lease_and_invalid_deadline_fail_closed():
    now = [0.0]
    monitor = WorkerHealthMonitor(clock=lambda: now[0])
    assert not monitor.ready()
    monitor.mark_healthy(lease_remaining_seconds=180)
    assert monitor.ready()
    now[0] = 90
    assert monitor.ready()
    now[0] = 90.01
    assert not monitor.ready()
    for value in (None, True, -1, 0, float("nan"), float("inf")):
        monitor.mark_healthy(lease_remaining_seconds=value)
        assert not monitor.ready()
    monitor.mark_healthy(lease_remaining_seconds=1)
    now[0] += 1
    assert not monitor.ready()


def test_private_http_probe_and_cli_reject_unready(monkeypatch):
    monitor = WorkerHealthMonitor()
    server = monitor.start_server(port=0)
    port = server.server_address[1]
    monkeypatch.setenv("SMART_CHARGE_WORKER_HEALTH_PORT", str(port))
    try:
        with urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as response:
            assert response.status == 200
        with pytest.raises(HTTPError) as caught:
            urlopen(f"http://127.0.0.1:{port}/ready", timeout=2)
        assert caught.value.code == 503
        assert main() == 1
        monitor.mark_healthy(lease_remaining_seconds=180)
        assert main() == 0
        monitor.mark_unhealthy()
        assert main() == 1
    finally:
        server.shutdown()
        server.server_close()


def test_probe_invalid_config_is_failure_not_success(monkeypatch):
    monkeypatch.setenv("SMART_CHARGE_WORKER_HEALTH_PORT", "not-a-port")
    assert main() == 1


def test_backup_off_rechecks_worker_lease_at_command_boundary(monkeypatch):
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("qa-owner")[0]
    binding.vehicle_id = "qa-car"
    repo.save_binding("qa-owner", binding)
    repo.register_vehicle_owner("qa-owner", "qa-car")
    repo.claim_worker_lease("qa-a")
    repo.publish_worker_heartbeat("qa-a", healthy=True)
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    session = service.manual_on("qa-owner", 300, "qa-op", "qa-car")
    repo.release_worker_lease("qa-a")
    repo.claim_worker_lease("qa-b")
    service._worker_lease_guard = lambda: repo.renew_worker_lease("qa-a")
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        service._backup_stop_session("qa-owner", session, state="interrupted", stop_reason="qa-timeout")
    assert provider.command_count == 1
    assert repo.get_session("qa-owner", session.session_id).state == "stopping"
    assert not repo.claim_device_session("qa-owner", binding.device_id, "qa-second-on")


def test_vault_transport_checks_lease_after_rate_limiter_sleep():
    from shelly.providers.vault_cloud import VaultCloudControlProvider
    from shelly.models import DeviceBinding
    repo, http = Mock(), Mock()
    def admit(_, operation, **kwargs):
        kwargs["sleeper"](1.1)
        return operation()
    repo.run_cloud_request.side_effect = admit
    valid = [True]
    provider = VaultCloudControlProvider(repo, session=http, sleeper=lambda _: valid.__setitem__(0, False))
    provider._profile = Mock(return_value=("https://qa.shelly.cloud", "qa-only"))
    def guard():
        if not valid[0]:
            raise RuntimeError("workerLeaseLost")
    provider.worker_lease_guard = guard
    with pytest.raises(RuntimeError) as caught:
        provider.turn_off(DeviceBinding("qa-plug", "QA", "S3PL-00112EU", 3, "vault_cloud"))
    assert caught.value.code == "cloudRateLimiterUnavailable"
    http.post.assert_not_called()


def test_health_probe_import_does_not_boot_api_or_ai():
    import subprocess
    import sys
    result = subprocess.run([sys.executable, "-c",
        "import sys; import shelly.worker_health; assert 'server' not in sys.modules; "
        "assert 'tensorflow' not in sys.modules; assert 'keras' not in sys.modules"],
        capture_output=True, timeout=10)
    assert result.returncode == 0
