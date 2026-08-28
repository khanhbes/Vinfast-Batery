from __future__ import annotations

from ..models import DeviceBinding, DeviceStatus
from .base import ProviderError


class IntegratorShellyProvider:
    """External-gated provider.

    The public demo documents a one-shot ``timeout`` parameter, but this app
    must still prove timer readback with licensed credentials before exposing
    control. The unconfigured personal build therefore remains capability
    gated instead of pretending that consent alone is operational.
    """

    name = "integrator"
    supports_status = False
    supports_manual_off = False
    supports_manual_on = False
    supports_device_timer = False

    def _blocked(self):
        raise ProviderError(
            "providerTimerUnsupported",
            "Shelly Integrator chưa được xác minh hỗ trợ timer trên thiết bị; không thể Start an toàn.",
        )

    def list_devices(self, uid: str) -> list[DeviceBinding]:
        return []

    def get_status(self, binding: DeviceBinding) -> DeviceStatus:
        self._blocked()

    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None:
        self._blocked()

    def turn_off(self, binding: DeviceBinding) -> None:
        self._blocked()

    def revoke(self, binding: DeviceBinding) -> None:
        return None
