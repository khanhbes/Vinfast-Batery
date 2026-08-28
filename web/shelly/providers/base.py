from __future__ import annotations

from typing import Protocol

from ..models import DeviceBinding, DeviceStatus


class ProviderError(RuntimeError):
    def __init__(self, code: str, message: str, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.retryable = retryable


class ShellyControlProvider(Protocol):
    name: str
    supports_status: bool
    supports_manual_off: bool
    supports_manual_on: bool
    supports_device_timer: bool

    def list_devices(self, uid: str) -> list[DeviceBinding]: ...
    def get_status(self, binding: DeviceBinding) -> DeviceStatus: ...
    def turn_on_with_timer(self, binding: DeviceBinding, duration_seconds: int) -> None: ...
    def turn_off(self, binding: DeviceBinding) -> None: ...
    def revoke(self, binding: DeviceBinding) -> None: ...
