"""Local fixtures only. No production Firebase, Cloud credentials or relay."""
import base64
from copy import deepcopy
from unittest.mock import Mock

import pytest
import requests

from shelly.models import DeviceBinding
from shelly.providers import ProviderError
from shelly.providers.vault_cloud import VaultCloudControlProvider
from shelly.repositories import SmartChargeRepository
from shelly.safety_fingerprint import cloud_safety_fingerprint
from shelly.service import SmartChargeError, SmartChargeService
from shelly.routes import create_blueprint
from flask import Flask


def snapshot():
    return {"id": "qa-plug", "code": "S3PL-00112EU", "gen": "G2", "type": "relay", "online": 1,
            "settings": {"switch:0": {"initial_state": "off", "auto_on": False, "auto_off": False}},
            "status": {"switch:0": {"output": False, "apower": 0, "voltage": 230,
                                    "current": 0, "aenergy": {"total": 0}}}}


@pytest.fixture
def setup(monkeypatch):
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    monkeypatch.setenv("SHELLY_PROFILE_MASTER_KEY", base64.urlsafe_b64encode(b"q" * 32).decode())
    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    repo.register_vehicle_owner("qa-owner", "qa-vehicle")
    profile = {"deviceId": "qa-plug", "model": "S3PL-00112EU", "vehicleId": "qa-vehicle",
               "cloudHost": "https://qa.shelly.cloud", "cloudAuthKey": "fixture-not-a-real-key"}
    repo.save_synced_profile("qa-owner", profile)
    binding = DeviceBinding("qa-plug", "QA", "S3PL-00112EU", 3, "vault_cloud",
                            owner_uid="qa-owner", vehicle_id="qa-vehicle",
                            power_meter_verified=True, safe_boot_verified=True, no_load_test_verified=True)
    repo.save_binding("qa-owner", binding)
    now = [1800000000.0]
    device = snapshot()
    calls = []
    timer = [None]

    def sleep(seconds):
        now[0] += seconds

    def post(url, **kwargs):
        calls.append((now[0], url, deepcopy(kwargs["json"])))
        if timer[0] is not None and now[0] >= timer[0]:
            device["status"]["switch:0"]["output"] = False
        response = Mock(status_code=200)
        if url.endswith("/get"):
            value = deepcopy(device)
            if timer[0] is not None:
                value["status"]["switch:0"]["timer_remaining"] = max(0, timer[0] - now[0])
            response.json.return_value = [value]
        else:
            on = kwargs["json"]["on"]
            device["status"]["switch:0"]["output"] = on
            timer[0] = now[0] + kwargs["json"]["toggle_after"] if on else None
            response.json.return_value = {}
        return response

    http = Mock()
    http.post.side_effect = post
    def admit(_, operation, **kwargs):
        kwargs["sleeper"](1.1)
        return operation()
    repo.run_cloud_request = Mock(side_effect=admit)
    repo.defer_cloud_requests = Mock()
    provider = VaultCloudControlProvider(repo, session=http, clock=lambda: now[0], sleeper=sleep)
    evidence = {"verifiedDeviceId": "qa-plug", "verifiedModel": "S3PL-00112EU",
                "verificationFingerprint": cloud_safety_fingerprint("qa-plug", profile["cloudHost"], profile["cloudAuthKey"], device),
                "verificationFingerprintVersion": 1,
                **{key: True for key in ("cloudVerified", "powerMeterVerified", "safeBootVerified", "noLoadTestVerified",
                                       "onObserved", "timerObserved", "timerAutoOffObserved", "relayOffVerified")}}
    repo.verify_synced_profile("qa-owner", "qa-plug", evidence, expected_revision=1)
    return repo, provider, binding, profile, device, now, calls, evidence


def on_count(calls):
    return sum(payload.get("on") is True for _, _, payload in calls)


def test_zero_measurements_are_real_fields_and_valid_context_sends_exactly_one_on(setup):
    _, provider, binding, _, _, _, calls, _ = setup
    provider.turn_on_with_timer(binding, 60)
    assert on_count(calls) == 1
    assert calls[-1][2]["toggle_after"] == 60
    assert all(b[0] - a[0] >= 1.09 for a, b in zip(calls, calls[1:]))


@pytest.mark.parametrize("change", [
    lambda d: d.pop("gen"), lambda d: d.update(gen="G1"), lambda d: d.update(code="SNPL-00112EU"),
    lambda d: d.update(id="qa-other"), lambda d: d.update(online=0),
    lambda d: d.pop("settings"), lambda d: d["settings"]["switch:0"].update(initial_state="on"),
    lambda d: d["settings"]["switch:0"].update(auto_on=True),
    lambda d: d["settings"]["switch:0"].update(auto_on=0),
    lambda d: d["settings"]["switch:0"].update(auto_off=True),
    lambda d: d["status"]["switch:0"].pop("current"),
    lambda d: d["status"]["switch:0"].update(output=None),
    lambda d: d["status"]["switch:0"].update(output=True),
    lambda d: d["status"]["switch:0"].update(voltage=float("nan")),
    lambda d: d["status"]["switch:0"].update(current=float("inf")),
    lambda d: d["status"]["switch:0"].update(voltage=180),
    lambda d: d["status"]["switch:0"].update(apower=True),
    lambda d: d["status"]["switch:0"].update(aenergy={"total": -1}),
    lambda d: d["status"]["switch:0"].update(temperature={"tC": float("nan")}),
    lambda d: d["status"]["switch:0"].update(temperature={"tC": 76}),
])
def test_changed_or_incomplete_cloud_evidence_never_sends_on(setup, change):
    _, provider, binding, _, device, _, calls, _ = setup
    change(device)
    with pytest.raises(ProviderError):
        provider.turn_on_with_timer(binding, 60)
    assert on_count(calls) == 0


@pytest.mark.parametrize("field,value", [
    ("verificationFingerprintVersion", None), ("verificationFingerprintVersion", True),
    ("verificationFingerprintVersion", 2), ("verificationFingerprint", "legacy"),
    ("onObserved", False), ("timerAutoOffObserved", False), ("revokedAt", "qa-revoked"),
])
def test_historical_or_incomplete_evidence_does_not_grant_on(setup, field, value):
    repo, provider, binding, _, _, _, calls, _ = setup
    repo._synced_profiles[("qa-owner", "qa-plug")][field] = value
    with pytest.raises(ProviderError):
        provider.turn_on_with_timer(binding, 60)
    assert on_count(calls) == 0


@pytest.mark.parametrize("mutation", ["key", "host", "revision", "revoke", "worker", "delay"])
def test_change_while_waiting_for_on_slot_fails_closed(setup, mutation):
    repo, provider, binding, profile, _, now, calls, _ = setup
    original_sleep = provider.sleep
    sleeps = [0]

    def sleep(seconds):
        sleeps[0] += 1
        original_sleep(seconds)
        if sleeps[0] != 2:
            return
        if mutation in ("key", "host"):
            rotated = {**profile, "cloudAuthKey": "rotated-fixture"} if mutation == "key" else {**profile, "cloudHost": "https://other.shelly.cloud"}
            repo.save_synced_profile("qa-owner", rotated, expected_revision=2)
        elif mutation == "revision":
            repo._synced_profiles[("qa-owner", "qa-plug")]["revision"] += 1
        elif mutation == "revoke":
            repo._synced_profiles[("qa-owner", "qa-plug")]["revokedAt"] = "qa-revoked"
        elif mutation == "worker":
            repo.publish_worker_heartbeat("qa-worker", healthy=False)
        else:
            now[0] += 11

    provider.sleep = sleep
    with pytest.raises(ProviderError):
        provider.turn_on_with_timer(binding, 60)
    assert on_count(calls) == 0


@pytest.mark.parametrize("entry", ["manual", "prediction"])
def test_api_service_checks_live_config_before_creating_session(setup, entry):
    repo, provider, binding, _, device, _, calls, _ = setup
    device["settings"]["switch:0"]["auto_on"] = True
    service = SmartChargeService(repo, provider, lambda _: {
        "predictedDurationSeconds": 300, "modelSource": "ai_model",
        "runtimeHealth": "loaded", "aiChargeEligible": True,
    }, sleeper=lambda _: None)
    with pytest.raises(SmartChargeError):
        if entry == "manual":
            service.manual_on("qa-owner", 60, "qa-operation", "qa-vehicle")
        else:
            preview = service.create_preview("qa-owner", {"vehicleId": "qa-vehicle", "currentSoc": 20, "targetSoc": 80})
            service.start("qa-owner", preview.preview_id, "qa-operation")
    assert on_count(calls) == 0
    assert repo.current_session("qa-owner") is None
    assert service.capabilities("qa-owner", "qa-vehicle")["readyForControl"] is False


def test_no_load_uses_one_timed_on_observes_auto_off_and_returns_server_fingerprint(setup):
    repo, provider, binding, _, _, _, calls, _ = setup
    repo._synced_profiles[("qa-owner", "qa-plug")]["noLoadTestVerified"] = False
    result = provider.run_no_load_test(binding)
    assert on_count(calls) == 1
    assert result["onObserved"] and result["timerObserved"] and result["timerAutoOffObserved"]
    assert result["relayOffVerified"] and result["verificationFingerprintVersion"] == 1
    assert result["profileRevision"] == 2
    assert "fixture-not-a-real-key" not in str(result)


def test_timeout_after_on_never_sends_second_on_and_cleanup_reads_off(setup):
    _, provider, binding, _, _, _, calls, _ = setup
    post = provider.http.post.side_effect

    def timeout_once(url, **kwargs):
        response = post(url, **kwargs)
        if kwargs["json"].get("on") is True:
            raise requests.Timeout("qa-response-lost")
        return response

    provider.http.post.side_effect = timeout_once
    with pytest.raises(ProviderError):
        provider.run_no_load_test(binding)
    assert on_count(calls) == 1
    assert calls[-2][2]["on"] is False
    assert provider.get_status(binding).relay is False


def test_settings_order_is_canonical_but_config_and_credentials_changes_are_not(setup):
    _, _, _, profile, device, _, _, evidence = setup
    shuffled = deepcopy(device)
    shuffled["settings"]["switch:0"] = dict(reversed(list(device["settings"]["switch:0"].items())))
    assert cloud_safety_fingerprint("QA-PLUG", profile["cloudHost"], profile["cloudAuthKey"], shuffled) == evidence["verificationFingerprint"]
    assert cloud_safety_fingerprint("qa-plug", profile["cloudHost"], "other-fixture", shuffled) != evidence["verificationFingerprint"]


def test_safety_evidence_commit_rejects_rotated_profile_revision(setup):
    repo, _, _, profile, _, _, _, evidence = setup
    repo.save_synced_profile("qa-owner", {**profile, "cloudAuthKey": "rotated-fixture"}, expected_revision=2)
    with pytest.raises(RuntimeError, match="profileRevisionConflict"):
        repo.verify_synced_profile("qa-owner", "qa-plug", evidence, expected_revision=2)
    assert repo.list_synced_profiles("qa-owner")[0]["noLoadTestVerified"] is False


def test_off_remains_available_with_bad_settings_and_legacy_evidence(setup):
    repo, provider, binding, _, device, _, calls, _ = setup
    repo._synced_profiles[("qa-owner", "qa-plug")].pop("verificationFingerprintVersion")
    device.pop("settings")
    provider.turn_off(binding)
    assert on_count(calls) == 0
    assert provider.get_status(binding).relay is False


@pytest.mark.parametrize("http_status", [400, 401, 403, 404, 429, 500])
def test_ambiguous_or_rejected_on_is_never_retried(setup, http_status):
    _, provider, binding, _, _, _, calls, _ = setup
    original_post = provider.http.post.side_effect

    def fail_command(url, **kwargs):
        response = original_post(url, **kwargs)
        if kwargs["json"].get("on") is True:
            response.status_code = http_status
        return response

    provider.http.post.side_effect = fail_command
    with pytest.raises(ProviderError):
        provider.turn_on_with_timer(binding, 60)
    assert on_count(calls) == 1


def test_no_load_config_change_before_final_read_invalidates_result(setup):
    _, provider, binding, _, device, _, calls, _ = setup
    original_post = provider.http.post.side_effect

    def change_after_cleanup(url, **kwargs):
        response = original_post(url, **kwargs)
        if kwargs["json"].get("on") is False:
            device["settings"]["switch:0"]["auto_off"] = True
        return response

    provider.http.post.side_effect = change_after_cleanup
    with pytest.raises(ProviderError, match="Cấu hình đã thay đổi"):
        provider.run_no_load_test(binding)
    assert on_count(calls) == 1
    assert provider.get_status(binding).relay is False


def test_safety_endpoint_persists_only_provider_evidence_after_off(setup):
    repo, provider, _, _, _, _, calls, _ = setup
    repo._synced_profiles[("qa-owner", "qa-plug")]["noLoadTestVerified"] = False
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ("qa-owner", None, "user")))
    response = app.test_client().post("/api/shelly/devices/qa-plug/safety-test", json={
        "confirmedUnplugged": True, "operationId": "qa-safety-operation",
    })
    assert response.status_code == 200
    result = response.get_json()["data"]["result"]
    stored = repo.list_synced_profiles("qa-owner")[0]
    assert stored["verificationFingerprint"] == result["verificationFingerprint"]
    assert stored["verificationFingerprintVersion"] == 1
    assert stored["timerAutoOffObserved"] is True and stored["relayOffVerified"] is True
    assert stored["revision"] == result["profileRevision"] + 1
    assert on_count(calls) == 1 and provider.get_status(repo.get_binding("qa-owner", "qa-vehicle")).relay is False


def test_safety_endpoint_rejects_boolean_only_result_without_rewriting_evidence(setup):
    repo, provider, _, _, _, _, calls, _ = setup
    original = deepcopy(repo.list_synced_profiles("qa-owner")[0])
    provider.run_no_load_test = Mock(return_value={"noLoadTestVerified": True, "relayOffVerified": True})
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ("qa-owner", None, "user")))
    response = app.test_client().post("/api/shelly/devices/qa-plug/safety-test", json={
        "confirmedUnplugged": True, "operationId": "qa-incomplete-operation",
    })
    assert response.status_code == 503
    assert repo.list_synced_profiles("qa-owner")[0] == original
    assert on_count(calls) == 0


def test_revoked_membership_blocks_on_but_does_not_erase_historical_proof(setup):
    repo, provider, binding, _, _, _, calls, evidence = setup
    repo.device_owned_by = Mock(return_value=False)
    with pytest.raises(ProviderError, match="quyền điều khiển"):
        provider.turn_on_with_timer(binding, 60)
    assert on_count(calls) == 0
    assert repo.list_synced_profiles("qa-owner")[0]["verificationFingerprint"] == evidence["verificationFingerprint"]


def _safety_app(repo, provider):
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ("qa-owner", None, "user")))
    return app.test_client()


def test_failed_safety_test_releases_lock_only_after_fresh_off_readback(setup):
    """Task108: a test failing before ON must not leave the device locked forever."""
    repo, provider, _, _, _, _, calls, _ = setup
    original_run = provider.run_no_load_test
    provider.run_no_load_test = Mock(side_effect=ProviderError("safetySnapshotStale", "stale"))
    client = _safety_app(repo, provider)
    first = client.post("/api/shelly/devices/qa-plug/safety-test", json={
        "confirmedUnplugged": True, "operationId": "safety-1"})
    assert first.status_code == 503
    assert first.get_json()["error"]["code"] == "safetySnapshotStale"
    assert repo.device_lock("qa-plug") == {}
    provider.run_no_load_test = original_run
    second = client.post("/api/shelly/devices/qa-plug/safety-test", json={
        "confirmedUnplugged": True, "operationId": "safety-2"})
    assert second.status_code == 200
    assert on_count(calls) == 1


def test_failed_safety_test_with_relay_on_keeps_lock(setup):
    repo, provider, binding, _, _, _, _, _ = setup
    provider.run_no_load_test = Mock(side_effect=ProviderError("relayUnverified", "unknown"))
    on_status = provider.get_status(binding)
    on_status.relay = True
    provider.get_status = Mock(return_value=on_status)
    client = _safety_app(repo, provider)
    response = client.post("/api/shelly/devices/qa-plug/safety-test", json={
        "confirmedUnplugged": True, "operationId": "safety-on"})
    assert response.status_code == 503
    assert repo.device_lock("qa-plug")["sessionId"] == "safety-on"


@pytest.mark.parametrize("stale_id, relay_on, expected", [
    ("safety-old", False, 200),          # own abandoned safety lock, verified OFF
    ("safety-old", True, 409),           # relay ON: never take over
    ("charging-session-1", False, 409),  # not a safety-test lock
])
def test_stale_safety_lock_recovery_requires_own_safety_lock_and_off(setup, stale_id, relay_on, expected):
    repo, provider, binding, _, _, _, calls, _ = setup
    assert repo.claim_device_session("qa-owner", "qa-plug", stale_id)
    if relay_on:
        on_status = provider.get_status(binding)
        on_status.relay = True
        provider.get_status = Mock(return_value=on_status)
    client = _safety_app(repo, provider)
    response = client.post("/api/shelly/devices/qa-plug/safety-test", json={
        "confirmedUnplugged": True, "operationId": "safety-new"})
    assert response.status_code == expected
    if expected == 409:
        assert repo.device_lock("qa-plug")["sessionId"] == stale_id
        assert on_count(calls) == 0
