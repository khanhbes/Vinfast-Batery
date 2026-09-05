from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import os

from models import ChargerStatus


def _float_env(name: str, default: float) -> float:
    raw = os.getenv(name, "").strip()
    try:
        return float(raw) if raw else default
    except ValueError:
        return default


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name, "").strip()
    return int(raw) if raw.isdigit() else default


@dataclass(frozen=True)
class SafetyThresholds:
    max_plug_temp_c: float = 75.0
    max_battery_temp_c: float = 55.0
    min_voltage_v: float = 190.0
    max_voltage_v: float = 255.0
    max_current_a: float = 11.5
    max_power_w: float = 2450.0
    telemetry_stale_seconds: int = 45
    zero_power_grace_seconds: int = 120
    consecutive_samples: int = 2

    @classmethod
    def from_env(cls) -> "SafetyThresholds":
        return cls(
            max_plug_temp_c=_float_env("SMART_CHARGE_MAX_PLUG_TEMP_C", 75),
            max_battery_temp_c=_float_env("SMART_CHARGE_MAX_BATTERY_TEMP_C", 55),
            min_voltage_v=_float_env("SMART_CHARGE_MIN_VOLTAGE_V", 190),
            max_voltage_v=_float_env("SMART_CHARGE_MAX_VOLTAGE_V", 255),
            max_current_a=_float_env("SMART_CHARGE_MAX_CURRENT_A", 11.5),
            max_power_w=_float_env("SMART_CHARGE_MAX_POWER_W", 2450),
            telemetry_stale_seconds=_int_env("SMART_CHARGE_TELEMETRY_STALE_SECONDS", 45),
            zero_power_grace_seconds=_int_env("SMART_CHARGE_ZERO_POWER_GRACE_SECONDS", 120),
            consecutive_samples=max(1, _int_env("SMART_CHARGE_SAFETY_CONSECUTIVE_SAMPLES", 2)),
        )


@dataclass(frozen=True)
class SafetyViolation:
    kind: str
    observed_value: float | None
    threshold: float | None
    immediate: bool = False


class SafetyMonitor:
    def __init__(self, thresholds: SafetyThresholds | None = None):
        self.thresholds = thresholds or SafetyThresholds.from_env()
        self._kind: str | None = None
        self._count = 0

    def evaluate(
        self,
        status: ChargerStatus,
        battery_temperature_c: float | None = None,
    ) -> SafetyViolation | None:
        t = self.thresholds
        violation = None
        if battery_temperature_c is not None and battery_temperature_c >= t.max_battery_temp_c:
            violation = SafetyViolation("battery_over_temperature", battery_temperature_c, t.max_battery_temp_c)
        elif status.temperature_c is not None and status.temperature_c >= t.max_plug_temp_c:
            violation = SafetyViolation("over_temperature", status.temperature_c, t.max_plug_temp_c)
        elif status.current_a >= t.max_current_a:
            violation = SafetyViolation("over_current", status.current_a, t.max_current_a)
        elif status.power_w >= t.max_power_w:
            violation = SafetyViolation("over_power", status.power_w, t.max_power_w)
        elif status.voltage_v > 0 and status.voltage_v < t.min_voltage_v:
            violation = SafetyViolation("under_voltage", status.voltage_v, t.min_voltage_v)
        elif status.voltage_v > t.max_voltage_v:
            violation = SafetyViolation("over_voltage", status.voltage_v, t.max_voltage_v)
        if violation is None:
            self._kind = None
            self._count = 0
            return None
        if violation.kind == self._kind:
            self._count += 1
        else:
            self._kind = violation.kind
            self._count = 1
        return violation if violation.immediate or self._count >= t.consecutive_samples else None


    def stale(self, last_status_at: datetime | None, now: datetime) -> SafetyViolation | None:
        if last_status_at is None:
            return None
        age = (now - last_status_at).total_seconds()
        if age >= self.thresholds.telemetry_stale_seconds:
            return SafetyViolation("telemetry_stale", age, float(self.thresholds.telemetry_stale_seconds), True)
        return None
