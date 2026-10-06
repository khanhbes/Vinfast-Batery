from unittest.mock import Mock

import pytest

from shelly.models import DeviceBinding, DeviceStatus
from shelly.providers.base import ProviderError
from shelly.providers.vault_cloud import VaultCloudControlProvider
from shelly.repositories import SmartChargeRepository


def binding():
    return DeviceBinding("test-device", "Test", "S3PL-00112EU", 3, "vault_cloud")


def status(on=False, timer=0):
    return DeviceStatus(True, on, timer, 0, 230, 0, device_id="test-device")


def provider_with_readbacks(readbacks):
    provider = VaultCloudControlProvider(Mock(), sleeper=lambda _: None)
    provider.get_status = Mock(side_effect=readbacks)
    provider.get_snapshot = Mock(return_value={
        "settings": {"switch:0": {"initial_state": "off", "auto_on": False}}
    })
    provider.turn_on_with_timer = Mock()
    provider.turn_off = Mock()
    return provider


def test_no_load_requires_timer_to_switch_off_before_cleanup():
    provider = provider_with_readbacks([
        status(), status(True, 4), status(True, 2), status(), status(),
    ])
    result = provider.run_no_load_test(binding())
    assert result["noLoadTestVerified"] is True
    assert result["relayOffVerified"] is True
    provider.turn_on_with_timer.assert_called_once()
    provider.turn_off.assert_called_once()


def test_manual_cleanup_off_does_not_fake_timer_verification():
    provider = provider_with_readbacks([
        status(), status(True, 4), *[status(True, 1) for _ in range(8)], status(),
    ])
    with pytest.raises(ProviderError) as caught:
        provider.run_no_load_test(binding())
    assert caught.value.code == "timerAutoOffUnverified"
    provider.turn_on_with_timer.assert_called_once()
    provider.turn_off.assert_called_once()


def test_missing_on_readback_never_passes_even_after_off_cleanup():
    provider = provider_with_readbacks([
        status(), *[status() for _ in range(5)], status(),
    ])
    with pytest.raises(ProviderError) as caught:
        provider.run_no_load_test(binding())
    assert caught.value.code == "timerNotArmed"
    provider.turn_on_with_timer.assert_called_once()
    provider.turn_off.assert_called_once()


def test_unknown_session_lock_does_not_expire_locally():
    repository = SmartChargeRepository()
    assert repository.claim_device_session("owner", "test-device", "operation-a")
    # Simulate a lock acquired long ago. Time alone must not grant a second ON.
    repository._device_leases["test-device"] = ("owner", "operation-a")
    assert not repository.claim_device_session("owner", "test-device", "operation-b")
    assert not repository.claim_device_session("other", "test-device", "operation-c")
    assert repository.claim_device_session("owner", "test-device", "operation-a")


def test_gen3_timer_uses_live_utc_start_and_duration():
    provider = VaultCloudControlProvider(Mock(), clock=lambda: 1800000002.5)
    snapshot = {"status": {"sys": {"unixtime": 1800000002}}}
    switch = {"output": True, "timer_started_at": 1800000000,
              "timer_duration": 5}
    assert provider._timer_remaining(snapshot, switch) == 2


@pytest.mark.parametrize("switch,sys_status", [
    ({"output": True, "timer_duration": 5}, {"unixtime": 1800000002}),
    ({"output": True, "timer_started_at": 1800000000, "timer_duration": 5}, {}),
    ({"output": True, "timer_started_at": 1800000000, "timer_duration": 5},
     {"unixtime": 1799999900}),
    ({"output": True, "timer_started_at": 1800000090, "timer_duration": 5},
     {"unixtime": 1800000002}),
    ({"output": False, "timer_started_at": 1800000000, "timer_duration": 5},
     {"unixtime": 1800000002}),
])
def test_missing_stale_or_future_timer_evidence_never_arms(switch, sys_status):
    provider = VaultCloudControlProvider(Mock(), clock=lambda: 1800000002.5)
    assert provider._timer_remaining({"status": {"sys": sys_status}}, switch) == 0


def test_expired_timer_does_not_reset_to_configured_duration():
    provider = VaultCloudControlProvider(Mock(), clock=lambda: 1800000020)
    snapshot = {"status": {"sys": {"unixtime": 1800000020}}}
    assert provider._timer_remaining(snapshot, {"output": True,
        "timer_started_at": 1800000000, "timer_duration": 5}) == 0


@pytest.mark.parametrize("remaining", [True, float("nan"), float("inf"), -1, 40000])
def test_invalid_remaining_time_is_rejected(remaining):
    with pytest.raises(ProviderError):
        VaultCloudControlProvider(Mock())._timer_remaining(
            {}, {"output": True, "timer_remaining": remaining})


def test_nonzero_initial_load_never_sends_on():
    provider = provider_with_readbacks([
        DeviceStatus(True, False, 0, 6, 230, .11, device_id="test-device")
    ])
    with pytest.raises(ProviderError) as caught:
        provider.run_no_load_test(binding())
    assert caught.value.code == "unexpectedLoad"
    provider.turn_on_with_timer.assert_not_called()
    provider.turn_off.assert_not_called()


def test_timeout_after_on_does_not_retry_on_and_still_cleans_up():
    provider = provider_with_readbacks([status(), status()])
    provider.turn_on_with_timer.side_effect = ProviderError("deviceOffline", "timeout", True)
    target = binding()
    with pytest.raises(ProviderError):
        provider.run_no_load_test(target)
    provider.turn_on_with_timer.assert_called_once_with(target, 5)
    provider.turn_off.assert_called_once()


@pytest.mark.parametrize("command", [True, False])
def test_empty_200_is_command_acceptance_only_not_valid_status(command):
    repository = Mock()
    repository.reserve_cloud_request_slot.return_value = 0
    http = Mock()
    http.post.return_value.status_code = 200
    http.post.return_value.json.side_effect = ValueError("empty")
    provider = VaultCloudControlProvider(repository, session=http)
    provider._profile = Mock(return_value=("https://test.shelly.cloud", "fixture-key"))
    if command:
        assert provider._post(binding(), "/v2/devices/api/set/switch", {}, command=True) is None
    else:
        with pytest.raises(ProviderError) as caught:
            provider.get_snapshot(binding())
        assert caught.value.code == "malformedProviderResponse"
    http.post.assert_called_once()


@pytest.mark.parametrize("http_status", [201, 204, 400, 401, 403, 404, 429, 500])
def test_non_200_command_never_counts_as_acceptance(http_status):
    repository = Mock()
    repository.reserve_cloud_request_slot.return_value = 0
    http = Mock()
    http.post.return_value.status_code = http_status
    provider = VaultCloudControlProvider(repository, session=http)
    provider._profile = Mock(return_value=("https://test.shelly.cloud", "fixture-key"))
    with pytest.raises(ProviderError):
        provider.turn_on_with_timer(binding(), 5)
    http.post.assert_called_once()
