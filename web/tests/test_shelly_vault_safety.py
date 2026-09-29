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
