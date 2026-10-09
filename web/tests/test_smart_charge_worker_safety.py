"""Fault tests only: no Firebase production, network or physical relay calls."""
from copy import deepcopy
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import Mock, patch

import pytest
from flask import Flask

from shelly.models import DeviceBinding, DeviceStatus, utcnow
from shelly.providers import FakeShellyProvider, ProviderError
from shelly.repositories import SmartChargeRepository
from shelly.routes import create_blueprint
from shelly.service import SmartChargeError, SmartChargeService
from smart_charge_worker import reconcile_once, run_forever


@pytest.fixture
def setup(monkeypatch):
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("qa-owner")[0]
    binding.vehicle_id = "qa-vehicle"
    repo.save_binding("qa-owner", binding)
    repo.register_vehicle_owner("qa-owner", "qa-vehicle")
    service = SmartChargeService(repo, provider, lambda _: {
        "predictedDurationSeconds": 300, "modelSource": "ai_model",
        "runtimeHealth": "loaded", "aiChargeEligible": True,
    }, sleeper=lambda _: None)
    return repo, provider, service, binding


def start(setup):
    repo, provider, service, binding = setup
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    session = service.manual_on("qa-owner", 300, "qa-op", "qa-vehicle", 20)
    return repo, provider, service, binding, session


@pytest.mark.parametrize("health", [
    {},
    {"schemaVersion": 1, "healthy": False, "workerId": "qa", "updatedAt": utcnow()},
    {"schemaVersion": 1, "healthy": True, "workerId": "qa", "updatedAt": utcnow() - timedelta(seconds=91)},
    {"schemaVersion": 1, "healthy": True, "workerId": "qa", "updatedAt": utcnow() + timedelta(seconds=120)},
    {"schemaVersion": 1, "healthy": True, "workerId": "qa", "updatedAt": utcnow().replace(tzinfo=None)},
    {"schemaVersion": 1, "healthy": "true", "workerId": "qa", "updatedAt": utcnow()},
    {"schemaVersion": 2, "healthy": True, "workerId": "qa", "updatedAt": utcnow()},
    {"schemaVersion": 1, "healthy": True, "workerId": "", "updatedAt": utcnow()},
])
def test_bad_heartbeat_blocks_both_on_paths_without_commands(setup, health):
    repo, provider, service, _ = setup
    repo._worker_heartbeat = health
    caps = service.capabilities("qa-owner", "qa-vehicle")
    assert caps["workerReady"] is False
    assert caps["readyForControl"] is False
    assert caps["canManualOff"] is True
    assert caps["controlBlockedCode"] == "workerUnavailable"
    with pytest.raises(SmartChargeError, match="Giám sát"):
        service.manual_on("qa-owner", 300, "qa-manual", "qa-vehicle")
    preview = service.create_preview("qa-owner", {
        "vehicleId": "qa-vehicle", "currentSoc": 20, "targetSoc": 80,
    })
    with pytest.raises(SmartChargeError, match="Giám sát"):
        service.start("qa-owner", preview.preview_id, "qa-ai")
    assert provider.command_count == 0
    assert repo.current_session("qa-owner") is None


def test_health_never_trusts_api_process_cache_when_firestore_fails(setup):
    repo, _, service, _ = setup
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    repo.db = Mock()
    repo.db.collection.side_effect = RuntimeError("qa datastore unavailable")
    assert repo.worker_health_ready(service.clock()) is False


def test_fresh_shared_heartbeat_and_boundary(setup):
    repo, _, _, _ = setup
    now = utcnow()
    repo.claim_worker_lease("qa-worker", now=now)
    repo.publish_worker_heartbeat("qa-worker", healthy=True, now=now)
    assert repo.worker_health_ready(now + timedelta(seconds=90)) is True
    assert repo.worker_health_ready(now + timedelta(seconds=90.01)) is False
    assert repo.worker_health_ready(now - timedelta(microseconds=1)) is False


def test_firestore_scope_required_and_cannot_reuse_other_environment_health(monkeypatch):
    monkeypatch.delenv("SMART_CHARGE_WORKER_SCOPE", raising=False)
    db = Mock()
    repo = SmartChargeRepository(db)
    with pytest.raises(RuntimeError, match="workerScopeNotConfigured"):
        repo.publish_worker_heartbeat("qa-worker", healthy=True)
    assert repo.worker_health_ready(utcnow()) is False
    db.collection.assert_not_called()
    api_repo = SmartChargeRepository(db, worker_scope="qa-staging")
    snapshot = db.collection.return_value.document.return_value.get.return_value
    snapshot.exists = True
    snapshot.to_dict.return_value = {
        "schemaVersion": 1, "scope": "qa-production", "healthy": True,
        "workerId": "qa-worker", "updatedAt": utcnow(), "leaseEpoch": 1,
        "epoch": 1, "expiresAt": utcnow() + timedelta(seconds=180),
    }
    assert api_repo.worker_health_ready(utcnow()) is False
    snapshot.to_dict.return_value["scope"] = "qa-staging"
    assert api_repo.worker_health_ready(utcnow()) is True
    db.collection.return_value.document.assert_called_with("qa-staging")


def test_off_remains_available_after_worker_dies(setup):
    repo, provider, service, _, session = start(setup)
    repo.publish_worker_heartbeat("qa-worker", healthy=False)
    result = service.stop("qa-owner", session.session_id)
    assert result.state == "cancelled" and result.relay_verified
    assert provider.status.relay is False
    assert provider.command_count == 2  # exactly one ON and one safe OFF


@pytest.mark.parametrize("off_fails", [False, True])
def test_lost_on_response_cleanup_uses_only_fresh_off_and_never_second_on(setup, off_fails):
    repo, provider, service, binding = setup
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    real_on = provider.turn_on_with_timer
    def lost_response(bound, duration):
        real_on(bound, duration)
        raise ProviderError("deviceOffline", "QA timeout after ON", True)
    provider.turn_on_with_timer = Mock(side_effect=lost_response)
    provider.off_rejected = off_fails
    with pytest.raises(SmartChargeError):
        service.manual_on("qa-owner", 300, "qa-lost-on", "qa-vehicle")
    saved = repo.get_by_idempotency("qa-owner", "qa-lost-on")
    assert saved.state == ("unknown" if off_fails else "failed")
    assert saved.relay_verified is (not off_fails)
    service.manual_on("qa-owner", 300, "qa-lost-on", "qa-vehicle")
    provider.turn_on_with_timer.assert_called_once()
    if off_fails:
        assert not repo.claim_device_session("qa-owner", binding.device_id, "qa-second")


def test_staging_policy_blocks_service_calls_even_with_healthy_worker(setup, monkeypatch):
    repo, provider, service, _ = setup
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    monkeypatch.setenv("AZURE_STAGING_HARDWARE_DISABLED", "1")
    with pytest.raises(SmartChargeError) as caught:
        service.manual_on("qa-owner", 300, "qa-op", "qa-vehicle")
    assert caught.value.code == "STAGING_HARDWARE_DISABLED"
    assert provider.command_count == 0


def test_worker_unavailable_blocks_safety_and_lan_authorization_before_lease(setup):
    repo, provider, service, binding = setup
    provider.run_no_load_test = Mock()
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ("qa-owner", None, "user")))
    client = app.test_client()
    safety = client.post(f"/api/shelly/devices/{binding.device_id}/safety-test", json={
        "confirmedUnplugged": True, "operationId": "qa-safety",
    })
    lan = client.post(f"/api/shelly/devices/{binding.device_id}/authorize", json={"operationId": "qa-lan"})
    for response in (safety, lan):
        assert response.status_code == 503
        assert response.json["error"]["code"] == "workerUnavailable"
    assert not repo._device_leases
    provider.run_no_load_test.assert_not_called()
    assert provider.command_count == 0


@pytest.mark.parametrize("relay,online,device", [
    (True, True, "fake-plug-s-gen3"),
    (False, False, "fake-plug-s-gen3"),
    (False, True, "qa-wrong-device"),
    (None, True, "fake-plug-s-gen3"),
])
def test_client_off_boolean_never_releases_operation_without_server_readback(setup, relay, online, device):
    repo, provider, service, binding = setup
    assert repo.claim_device_session("qa-owner", binding.device_id, "qa-lan", lease_kind="lan_control")
    provider.get_status = lambda _: DeviceStatus(online=online, relay=relay, device_id=device)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ("qa-owner", None, "user")))
    response = app.test_client().post(f"/api/shelly/devices/{binding.device_id}/release-control", json={
        "operationId": "qa-lan", "relayOffVerified": True,
    })
    assert response.status_code == 503
    assert response.json["error"]["code"] == "offReadbackRequired"
    assert not repo.claim_device_session("qa-owner", binding.device_id, "qa-second-on")
    assert provider.command_count == 0


def test_release_route_cannot_release_pending_charging_lease_even_with_off(setup):
    repo, provider, service, binding = setup
    assert repo.claim_device_session("qa-owner", binding.device_id, "qa-pending-on")
    provider.get_status = lambda _: DeviceStatus(online=True, relay=False, device_id=binding.device_id)
    with pytest.raises(SmartChargeError) as caught:
        service.release_control("qa-owner", binding.device_id, "qa-pending-on")
    assert caught.value.code == "activeSessionConflict"
    assert not repo.claim_device_session("qa-owner", binding.device_id, "qa-second-on")
    assert provider.command_count == 0


@pytest.mark.parametrize("provider_name", ["legacy", "vault"])
@pytest.mark.parametrize("bad_field,bad_value", [
    ("output", None), ("output", "false"), ("output", 0),
    ("apower", None), ("apower", float("nan")), ("current", float("inf")),
    ("aenergy", {}),
])
def test_cloud_readback_never_synthesizes_off_or_missing_meter(provider_name, bad_field, bad_value):
    from shelly.providers.legacy_cloud import LegacyCloudControlProvider
    from shelly.providers.vault_cloud import VaultCloudControlProvider
    from shelly.rate_limiter import PerDeviceRateLimiter
    raw = {"id": "qa-plug", "online": 1, "code": "S3PL-00112EU", "type": "relay",
           "status": {"switch:0": {"output": False, "apower": 0, "voltage": 230,
                                   "current": 0, "aenergy": {"total": 0}}}}
    raw["status"]["switch:0"][bad_field] = bad_value
    if provider_name == "legacy":
        http = Mock()
        http.post.return_value.status_code = 200
        http.post.return_value.json.return_value = [raw]
        provider = LegacyCloudControlProvider(host="https://qa.shelly.cloud", auth_key="qa-only",
                                              session=http, limiter=PerDeviceRateLimiter(0))
    else:
        provider = VaultCloudControlProvider(Mock())
        provider._post = Mock(return_value=[raw])
    with pytest.raises(ProviderError):
        provider.get_status(DeviceBinding("qa-plug", "QA", "S3PL-00112EU", 3, provider_name))


@pytest.mark.parametrize("online", [None, "true", "false", 0, False, 2])
def test_cloud_missing_or_invalid_online_is_not_fresh_readback(online):
    from shelly.providers.vault_cloud import VaultCloudControlProvider
    provider = VaultCloudControlProvider(Mock())
    provider._post = Mock(return_value=[{"id": "qa-plug", "online": online,
                                        "code": "S3PL-00112EU", "type": "relay"}])
    with pytest.raises(ProviderError, match="ngoại tuyến"):
        provider.get_snapshot(DeviceBinding("qa-plug", "QA", "S3PL-00112EU", 3, "vault_cloud"))


def test_legacy_provider_cannot_send_on_or_bypass_vault():
    from shelly.providers.legacy_cloud import LegacyCloudControlProvider
    http = Mock()
    provider = LegacyCloudControlProvider(host="https://qa.shelly.cloud", auth_key="qa-only", session=http)
    with pytest.raises(ProviderError) as caught:
        provider.turn_on_with_timer(DeviceBinding("qa-plug", "QA", "S3PL-00112EU", 3, "legacy"), 5)
    assert caught.value.code == "legacyEnrollmentRequired"
    assert provider.supports_manual_on is False
    http.post.assert_not_called()


def test_worker_uses_immutable_device_when_vehicle_has_new_binding(setup):
    repo, provider, service, old, session = start(setup)
    changed = deepcopy(old)
    changed.device_id = "qa-new-plug"
    repo.save_binding("qa-owner", changed)
    assert repo.get_binding("qa-owner", "qa-vehicle") is None  # ambiguous, not first wins
    provider.status.timer_remaining = 0
    observed = []
    turn_off = provider.turn_off
    provider.turn_off = lambda binding: observed.append(binding.device_id) or turn_off(binding)
    result = reconcile_once(service, "qa-owner")
    assert observed == [session.device_id]
    assert result.state == "failed" and result.relay_verified
    assert provider.command_count == 2


def test_missing_original_binding_does_not_send_off_to_replacement(setup):
    repo, provider, service, old, session = start(setup)
    old.revoked_at = utcnow()
    repo.save_binding("qa-owner", old)
    replacement = deepcopy(old)
    replacement.device_id, replacement.revoked_at = "qa-replacement", None
    repo.save_binding("qa-owner", replacement)
    result = reconcile_once(service, "qa-owner")
    assert result.state == "unknown" and not result.relay_verified
    assert provider.command_count == 1
    assert not repo.claim_device_session("qa-owner", session.device_id, "qa-second-on")


@pytest.mark.parametrize("status", [
    DeviceStatus(online=False, relay=False, device_id="fake-plug-s-gen3"),
    DeviceStatus(online=True, relay=False, device_id="qa-wrong-plug"),
    DeviceStatus(online=True, relay=None, device_id="fake-plug-s-gen3"),
    DeviceStatus(online=True, relay="false", device_id="fake-plug-s-gen3"),
    DeviceStatus(online=True, relay=0, device_id="fake-plug-s-gen3"),
    SimpleNamespace(online=True, device_id="fake-plug-s-gen3"),
])
def test_untrusted_readback_never_terminalizes_or_releases_device(setup, status):
    repo, provider, service, _, session = start(setup)
    provider.get_status = lambda _: status
    result = reconcile_once(service, "qa-owner")
    assert result.state == "unknown" and not result.relay_verified
    assert provider.command_count == 1
    assert not repo.claim_device_session("qa-owner", session.device_id, "qa-second-on")


def test_backup_off_requires_new_online_readback_and_retains_lock_on_failure(setup):
    repo, provider, service, binding, session = start(setup)
    before = DeviceStatus(online=True, relay=True, timer_remaining=0,
                          device_id=binding.device_id, voltage_v=230)
    after = DeviceStatus(online=False, relay=False, device_id=binding.device_id)
    provider.get_status = Mock(side_effect=[before, after])
    result = reconcile_once(service, "qa-owner")
    assert provider.get_status.call_count == 2
    assert result.state == "unknown" and not result.relay_verified
    assert not repo.claim_device_session("qa-owner", session.device_id, "qa-second-on")
    assert before.relay is True  # old pre-command snapshot is not OFF evidence


def test_failed_off_recovery_never_retries_on(setup):
    repo, provider, service, binding, session = start(setup)
    provider.status.timer_remaining = 0
    provider.off_rejected = True
    result = reconcile_once(service, "qa-owner")
    assert result.state == "unknown" and not result.relay_verified
    assert not repo.claim_device_session("qa-owner", session.device_id, "qa-second-on")
    provider.off_rejected = False
    on = Mock(wraps=provider.turn_on_with_timer)
    provider.turn_on_with_timer = on
    result = reconcile_once(service, "qa-owner")
    assert result.state == "interrupted" and result.relay_verified
    assert provider.status.relay is False
    on.assert_not_called()


def test_expired_deadline_with_relay_on_forces_off_and_readback(setup):
    repo, provider, service, _, session = start(setup)
    session.effective_stop_at = utcnow() - timedelta(seconds=1)
    result = reconcile_once(service, "qa-owner")
    assert result.state == "interrupted" and result.stop_reason == "deadline_cutoff"
    assert result.relay_verified and provider.status.relay is False


def test_terminal_readback_cannot_write_active_again(setup):
    repo, provider, service, binding, session = start(setup)
    service.stop("qa-owner", session.session_id)
    version = session.version
    service._reconcile_with_status("qa-owner", DeviceStatus(
        online=True, relay=True, timer_remaining=120, device_id=binding.device_id,
    ), session=session)
    assert session.state == "cancelled" and session.version == version
    assert provider.command_count == 2


def test_stale_worker_copy_cannot_overwrite_terminal_or_unknown(setup):
    repo, provider, service, binding, session = start(setup)
    stale = deepcopy(session)
    service.stop("qa-owner", session.session_id)
    stale.version = session.version + 1  # revision alone cannot resurrect terminal
    with pytest.raises(RuntimeError, match="sessionAlreadyTerminal"):
        repo.save_session("qa-owner", stale)
    assert repo.get_session("qa-owner", session.session_id).state == "cancelled"
    assert provider.command_count == 2


def test_stale_active_copy_cannot_overwrite_unknown_or_device_identity(setup):
    repo, _, service, _, session = start(setup)
    stale = deepcopy(session)
    service.mark_session_unknown("qa-owner", session, "qa-timeout")
    stale.version = session.version + 1
    with pytest.raises(RuntimeError, match="sessionRecoveryRequired"):
        repo.save_session("qa-owner", stale)
    changed = deepcopy(session)
    changed.device_id = "qa-replacement"
    with pytest.raises(PermissionError, match="sessionIdentityMismatch"):
        repo.save_session("qa-owner", changed)
    assert repo.get_session("qa-owner", session.session_id).state == "unknown"


def test_worker_loop_has_no_automatic_ai_training_or_ingestion(setup):
    repo, provider, service, _ = setup
    service.ingest_personal_session = Mock()
    def stop(_):
        assert repo.worker_health_ready(service.clock()) is True
        raise KeyboardInterrupt
    with patch("smart_charge_worker.process_personal_training_jobs_once") as training:
        with pytest.raises(KeyboardInterrupt):
            run_forever(service, user_ids=lambda: [], sleeper=stop)
        training.assert_not_called()
    service.ingest_personal_session.assert_not_called()
    assert repo.worker_health_ready(service.clock()) is False  # graceful stop releases lease
    assert provider.command_count == 0


def test_scan_failure_publishes_unhealthy_and_cannot_hide_cached_health(setup):
    repo, _, service, _ = setup
    users = Mock(side_effect=RuntimeError("qa scan failure"))
    with pytest.raises(KeyboardInterrupt):
        run_forever(service, user_ids=users, sleeper=Mock(side_effect=KeyboardInterrupt))
    assert repo.worker_health_ready(service.clock()) is False


def test_account_scan_failure_propagates_for_worker_instead_of_empty_cache(setup):
    repo, _, _, _ = setup
    repo.db = Mock()
    repo.db.collection.side_effect = RuntimeError("qa index unavailable")
    with pytest.raises(RuntimeError):
        repo.active_sessions("qa-owner", strict=True)
