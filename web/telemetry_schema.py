"""Stable, versioned battery telemetry schema with legacy-payload support."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

SCHEMA_VERSION = "battery-telemetry/v1"
SOURCES = {"manual_entry", "shelly_meter", "bms", "ai_estimate"}
SOURCE_ALIASES = {
    "manual_entry": "manual_entry", "flutter_app": "manual_entry", "mobile_app": "manual_entry",
    "user_input": "manual_entry", "shelly_meter": "shelly_meter", "shelly": "shelly_meter",
    "bms": "bms", "ai_estimate": "ai_estimate", "ai_model": "ai_estimate",
}

METRICS = {
    "soc": {"unit": "%", "min": 0.0, "max": 100.0, "aliases": ("soc", "currentSoc", "currentSOC", "current_soc", "batteryPercent", "currentBattery", "percentage")},
    "soh": {"unit": "%", "min": 0.0, "max": 100.0, "aliases": ("soh", "stateOfHealth", "batteryHealth", "battery_health")},
    "voltage": {"unit": "V", "min": 0.0, "max": 1500.0, "aliases": ("voltage", "voltageV", "voltage_v")},
    "power": {"unit": "W", "min": -1000000.0, "max": 1000000.0, "aliases": ("power", "powerKw", "powerKW", "power_kw", "powerW", "power_w")},
    "energy": {"unit": "Wh", "min": 0.0, "max": 1000000000.0, "aliases": ("energy", "energyKwh", "energyKWh", "energy_kwh", "energyWh", "energy_wh", "energyUsedWh")},
}
LEGACY_ALIAS_UNITS = {
    "powerKw": "kW", "powerKW": "kW", "power_kw": "kW",
    "energyKwh": "kWh", "energyKWh": "kWh", "energy_kwh": "kWh",
}


class TelemetryValidationError(ValueError):
    pass


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def normalize_timestamp(value: Any) -> str:
    if value is None:
        return utc_now_iso()
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise TelemetryValidationError("measuredAt phải là ISO-8601 hợp lệ") from exc
    else:
        raise TelemetryValidationError("measuredAt phải là chuỗi ISO-8601")
    if parsed.tzinfo is None:
        raise TelemetryValidationError("measuredAt phải có timezone, ví dụ ...Z")
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _number(value: Any, field: str) -> float:
    if isinstance(value, bool):
        raise TelemetryValidationError(f"{field}.value phải là số")
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise TelemetryValidationError(f"{field}.value phải là số") from exc


def _canonical_value(metric: str, value: float, input_unit: str | None) -> float:
    unit = (input_unit or METRICS[metric]["unit"]).strip()
    target = METRICS[metric]["unit"]
    if unit != target:
        if metric == "power" and unit == "kW":
            value *= 1000.0
        elif metric == "energy" and unit == "kWh":
            value *= 1000.0
        else:
            raise TelemetryValidationError(f"{metric}.unit phải là {target}" + (", W hoặc kW" if metric == "power" else ", Wh hoặc kWh" if metric == "energy" else ""))
    bounds = METRICS[metric]
    if not bounds["min"] <= value <= bounds["max"]:
        raise TelemetryValidationError(f"{metric}.value phải trong khoảng {bounds['min']}–{bounds['max']} {target}")
    return round(value, 6)


def normalize_measurement(metric: str, raw: Any, *, default_source: str, default_measured_at: Any = None) -> dict[str, Any]:
    if metric not in METRICS:
        raise TelemetryValidationError(f"Metric không hỗ trợ: {metric}")
    descriptor = dict(raw) if isinstance(raw, dict) else {"value": raw}
    source = SOURCE_ALIASES.get(descriptor.get("source", default_source), descriptor.get("source", default_source))
    if source not in SOURCES:
        raise TelemetryValidationError(f"source không hợp lệ: {source}")
    value = _canonical_value(metric, _number(descriptor.get("value"), metric), descriptor.get("unit"))
    confidence = descriptor.get("confidence")
    if confidence is None:
        confidence = 0.7 if source == "ai_estimate" else (0.98 if source == "shelly_meter" else 1.0)
    confidence = _number(confidence, metric + ".confidence")
    if not 0.0 <= confidence <= 1.0:
        raise TelemetryValidationError(f"{metric}.confidence phải trong khoảng 0–1")
    result = {
        "value": value,
        "unit": METRICS[metric]["unit"],
        "source": source,
        "confidence": round(confidence, 4),
        "measuredAt": normalize_timestamp(descriptor.get("measuredAt", default_measured_at)),
    }
    model_version = descriptor.get("modelVersion")
    if source == "ai_estimate":
        result["modelVersion"] = str(model_version or "unknown")
    return result


def normalize_telemetry(payload: dict[str, Any], *, default_source: str = "manual_entry") -> dict[str, Any]:
    """Return v1 telemetry while retaining legacy top-level fields unchanged."""
    default_source = SOURCE_ALIASES.get(default_source, default_source)
    if default_source not in SOURCES:
        raise TelemetryValidationError("default source không hợp lệ")
    raw = dict(payload or {})
    vehicle_id = raw.get("vehicleId") or raw.get("vehicle_id")
    if not vehicle_id:
        raise TelemetryValidationError("vehicleId bắt buộc")
    measured_at = raw.get("measuredAt") or raw.get("recordedAt") or raw.get("timestamp")
    readings_input = raw.get("measurements") if isinstance(raw.get("measurements"), dict) else {}
    measurements: dict[str, dict[str, Any]] = {}
    for metric, meta in METRICS.items():
        candidate = readings_input.get(metric)
        if candidate is None:
            for alias in meta["aliases"]:
                if alias in raw and raw[alias] is not None:
                    candidate = raw[alias]
                    if alias in LEGACY_ALIAS_UNITS and not isinstance(candidate, dict):
                        candidate = {"value": candidate, "unit": LEGACY_ALIAS_UNITS[alias]}
                    break
        if candidate is not None:
            measurements[metric] = normalize_measurement(
                metric, candidate, default_source=SOURCE_ALIASES.get(raw.get("source", default_source), raw.get("source", default_source)), default_measured_at=measured_at
            )
    if not measurements:
        raise TelemetryValidationError("Cần ít nhất một giá trị SOC, SoH, điện áp, công suất hoặc năng lượng")
    canonical = dict(raw)  # Preserve old clients and historical readers.
    canonical.update({
        "schemaVersion": SCHEMA_VERSION,
        "vehicleId": str(vehicle_id),
        "chargerId": raw.get("chargerId") or raw.get("charger_id"),
        "chargingSessionId": raw.get("chargingSessionId") or raw.get("charging_session_id") or raw.get("sessionId"),
        "measurements": measurements,
        "recordedAt": normalize_timestamp(measured_at),
    })
    return canonical
