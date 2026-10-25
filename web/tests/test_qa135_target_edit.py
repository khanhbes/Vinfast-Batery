"""QA 135 — change the target % while charging (lower at once; higher
re-arms the Shelly ceiling through the live safety checks, verified)."""
from __future__ import annotations

import pytest
from flask import Flask

from billing.entitlements import EntitlementService
from shelly.routes import create_blueprint
from shelly.service import SmartChargeError
from tests.test_task126_charge_model import _service, _start_target


def test_lowering_the_target_cuts_there():
    service, _repo, provider, clock = _service()
    _preview, session = _start_target(service, target=90)
    ceiling = provider.status.timer_remaining
    updated = service.update_target("owner", session.session_id, 60)
    assert updated.target_soc == 60
    assert updated.target_energy_wh == pytest.approx(26 * 40)
    assert provider.status.timer_remaining == ceiling  # the ceiling stays
    assert getattr(provider, "extend_calls", 0) == 0
    provider.status.power_w = 440
    provider.status.energy_wh += 1040
    clock.advance(minutes=150)
    done = service.current("owner", vehicle_id="car")
    assert done.state == "completed" and done.stop_reason == "target_reached"
    assert provider.status.relay is False


def test_raising_the_target_extends_the_verified_ceiling():
    service, repo, provider, clock = _service()
    _preview, session = _start_target(service, target=50)
    old_ceiling = provider.status.timer_remaining
    clock.advance(minutes=10)
    provider.status.power_w = 440
    updated = service.update_target("owner", session.session_id, 95)
    assert updated.target_soc == 95
    assert updated.target_energy_wh == pytest.approx(26 * 75)
    assert provider.extend_calls == 1
    assert provider.status.relay is True
    assert provider.status.timer_remaining > old_ceiling
    assert updated.effective_stop_at <= updated.absolute_safety_stop_at
    assert updated.ai_stop_at < updated.effective_stop_at
    assert repo.get_session("owner", session.session_id).target_soc == 95


def test_a_failed_extension_keeps_the_old_target():
    service, repo, provider, _clock = _service()
    _preview, session = _start_target(service, target=50)
    provider.fail_extend = True  # command accepted, timer not changed
    with pytest.raises(SmartChargeError) as caught:
        service.update_target("owner", session.session_id, 95)
    assert caught.value.code == "timerNotExtended" and caught.value.retryable
    assert "50%" in caught.value.message
    assert repo.get_session("owner", session.session_id).target_soc == 50


def test_offline_outlet_keeps_the_old_target():
    service, repo, provider, _clock = _service()
    _preview, session = _start_target(service, target=50)
    provider.status.online = False
    with pytest.raises(SmartChargeError) as caught:
        service.update_target("owner", session.session_id, 95)
    assert caught.value.code == "timerNotExtended"
    assert repo.get_session("owner", session.session_id).target_soc == 50


def test_invalid_targets_and_sessions():
    service, _repo, provider, clock = _service()
    _preview, session = _start_target(service, start=20, target=80)
    for bad in (0, 101, "x", None, 21):
        with pytest.raises(SmartChargeError):
            service.update_target("owner", session.session_id, bad)
    with pytest.raises(SmartChargeError) as caught:
        service.update_target("owner", "missing", 70)
    assert caught.value.status == 404
    assert service.update_target("owner", session.session_id, 80).target_soc == 80  # no-op


def test_target_edit_is_a_pro_feature():
    service, _repo, _provider, _clock = _service()
    _preview, session = _start_target(service)
    service.entitlements = EntitlementService(enforced=True)
    with pytest.raises(SmartChargeError) as caught:
        service.update_target("owner", session.session_id, 70)
    assert caught.value.code == "premiumRequired"


def test_route_patch_target():
    service, repo, _provider, _clock = _service()
    _preview, session = _start_target(service, target=60)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(service, repo, lambda: ("owner", None, "user")))
    http = app.test_client()
    ok = http.patch(f"/api/smart-charging/sessions/{session.session_id}/target", json={"targetSoc": 70})
    assert ok.status_code == 200 and ok.get_json()["data"]["target_soc"] == 70
    bad = http.patch(f"/api/smart-charging/sessions/{session.session_id}/target", json={"targetSoc": 5})
    assert bad.status_code == 400 and bad.get_json()["error"]["code"] == "targetBelowCurrent"


def test_vault_extend_timer_uses_the_live_context_with_relay_on():
    from unittest.mock import Mock

    from shelly.models import DeviceBinding
    from shelly.providers.base import ProviderError
    from shelly.providers.vault_cloud import VaultCloudControlProvider

    provider = VaultCloudControlProvider(Mock(), sleeper=lambda _s: None, clock=lambda: 0.0)
    provider._live_safety_context = Mock(return_value={"observedAt": 0.0})
    provider._post = Mock()
    binding = DeviceBinding("dev-1", "Test", "S3PL-00112EU", 3, "vault_cloud")
    provider.extend_timer(binding, 3600)
    provider._live_safety_context.assert_called_once_with(binding, relay_on=True)
    path, payload = provider._post.call_args.args[1:3]
    assert path == "/v2/devices/api/set/switch"
    assert payload == {"id": "dev-1", "channel": 0, "on": True, "toggle_after": 3600}
    assert provider._post.call_args.kwargs["command"] is True
    for bad in (0, 4, 36001, 12.5):
        with pytest.raises(ProviderError):
            provider.extend_timer(binding, bad)


# -- the real vault provider against a fake Shelly Cloud (no hardware) ----
from tests.test_shelly_live_safety import setup  # noqa: E402,F401  (fixture)


def test_extend_needs_the_relay_on_and_sends_no_command_otherwise(setup):  # noqa: F811
    from shelly.providers import ProviderError
    _repo, provider, binding, _profile, _device, _now, calls, _evidence = setup
    with pytest.raises(ProviderError) as caught:
        provider.extend_timer(binding, 3600)
    assert caught.value.code == "relayNotOn"
    assert not any(url.endswith("/set/switch") for _, url, _ in calls)


def test_extend_rearms_a_running_outlet_through_the_live_checks(setup):  # noqa: F811
    _repo, provider, binding, _profile, _device, _now, calls, _evidence = setup
    provider.turn_on_with_timer(binding, 600)
    provider.extend_timer(binding, 3600)
    commands = [payload for _, url, payload in calls if url.endswith("/set/switch")]
    assert commands == [
        {"id": "qa-plug", "channel": 0, "on": True, "toggle_after": 600},
        {"id": "qa-plug", "channel": 0, "on": True, "toggle_after": 3600},
    ]


def test_extend_refuses_unsafe_measurements(setup):  # noqa: F811
    from shelly.providers import ProviderError
    _repo, provider, binding, _profile, device, _now, calls, _evidence = setup
    provider.turn_on_with_timer(binding, 600)
    device["status"]["switch:0"]["voltage"] = 180
    with pytest.raises(ProviderError):
        provider.extend_timer(binding, 3600)
    assert sum(1 for _, url, p in calls if url.endswith("/set/switch") and p.get("on")) == 1
