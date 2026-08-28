from __future__ import annotations

from ..models import DeviceBinding, DeviceStatus
from .base import ProviderError


class FakeShellyProvider:
    name = "fake"
    supports_status = True
    supports_manual_off = True
    supports_manual_on = True
    supports_device_timer = True

    def __init__(self):
        self.status = DeviceStatus(
            online=True,
            relay=False,
            voltage_v=230,
            device_id="fake-plug-s-gen3",
        )
        self.fail_readback = False
        self.off_rejected = False
        self.command_count = 0

    def list_devices(self, uid: str) -> list[DeviceBinding]:
        return [DeviceBinding(
            device_id=self.status.device_id,
            display_name="Shelly sạc xe (Demo)",
            model="S3PL-00112EU",
            generation=3,
            provider=self.name,
            online=self.status.online,
            power_meter_verified=True,
            safe_boot_verified=True,
            no_load_test_verified=True,
        )]

    def get_status(self, binding: DeviceBinding) -> DeviceStatus:
        if not self.status.online:
            raise ProviderError("deviceOffline", "Shelly đang Offline", True)
        if self.fail_readback:
            return DeviceStatus(online=True, relay=True, timer_remaining=0, device_id=binding.device_id)
        self.status.device_id = binding.device_id
        return self.status

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        if not self.status.online:
            raise ProviderError("deviceOffline", "Shelly đang Offline", True)
        self.command_count += 1
        self.status.relay = True
        self.status.timer_remaining = duration_seconds

    def turn_off(self, binding: DeviceBinding) -> None:
        self.command_count += 1
        if self.off_rejected:
            raise ProviderError("relayUnverified", "Shelly từ chối OFF", True)
        self.status.relay = False
        self.status.timer_remaining = 0

    def revoke(self, binding: DeviceBinding) -> None:
        self.status.online = False
