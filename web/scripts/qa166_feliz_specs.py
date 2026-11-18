"""QA 166 (2), owner's choice (18/11/2026): the Feliz 2025 catalog holds only
what VinFast publishes, and the wall power the owner's Shelly measured for
charging-time estimates.

VinFast publishes 2.4 kWh LFP, a 400 W charger and about 6 h 30 min from 0 to
100 % (Evo Grand TSKT 07/2025, the same pack; the press for the Feliz 2025).
It publishes no voltage, Ah or cell count: the catalog's 48 V / 50 Ah had no
source and leave (the app shows "Chưa công bố"). The stock charger draws about
444 W at the wall on the owner's Shelly: the estimate's fallback power goes
600 -> 450 W. Feliz 2025 vehicles get ``chargerRatedW`` 400 (battery health
caps the wall-to-battery factor with it), the owner's too although it keeps its
model in another field (QA 140): it is named explicitly and must say Feliz and
hold 2400 Wh (a Feliz S holds 3500).

Only values still at the old, unsourced figures change; what an admin or an
owner set stays.

Runs inside the production API container (tools/update_feliz_specs.ps1 sends
it there). DRY-RUN unless __APPLY__ is 1. Prints the report, zlib + base64
between <<< and >>>; no account id, name or email.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone

MODEL_ID = "feliz_2025"
CHARGER_W = 400.0
CHARGE_MINUTES = 390.0
OLD_WALL_W, NEW_WALL_W = 600.0, 450.0
OLD_VOLTAGE_V, OLD_AMP_HOURS = 48.0, 50.0
NOMINAL_WH = 2400.0
CATALOG = "VehicleCatalog"
HISTORY = "VehicleCatalogHistory"
LEGACY = "VinFastModelSpecs"
NOTE = ("QA 166 (2): VinFast cong bo 2,4 kWh LFP, bo sac 400 W, sac 0-100% khoang "
        "6 gio 30 phut; khong cong bo V/Ah. Cong suat o o cam 450 W do tren xe.")


def _number(value) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None


def _is(value, expected: float) -> bool:
    number = _number(value)
    return number is not None and abs(number - expected) < 0.5


def _missing(value) -> bool:
    number = _number(value)
    return number is None or number <= 0


def catalog_changes(data: dict) -> dict:
    """Dotted path -> new value for ``VehicleCatalog/feliz_2025``; ``None``
    removes the field."""
    battery = data.get("battery") or {}
    charging = data.get("charging") or {}
    out: dict = {}
    if _missing(charging.get("maxDcPowerW")):
        out["charging.maxDcPowerW"] = CHARGER_W
    if _missing(charging.get("chargeTimeMinutes")):
        out["charging.chargeTimeMinutes"] = CHARGE_MINUTES
    for group in ("appDefaults", "charging"):
        if _is((data.get(group) or {}).get("maxSafeChargePowerW"), OLD_WALL_W):
            out[f"{group}.maxSafeChargePowerW"] = NEW_WALL_W
    if _is(battery.get("voltageV"), OLD_VOLTAGE_V):
        out["battery.voltageV"] = None
    if _is(battery.get("capacityAh"), OLD_AMP_HOURS):
        out["battery.capacityAh"] = None
    return out


def legacy_changes(data: dict) -> dict:
    """The same for the legacy projection ``VinFastModelSpecs/feliz_2025``
    (flat keys; 0 = not published)."""
    out: dict = {}
    if _is(data.get("nominalVoltageV"), OLD_VOLTAGE_V):
        out["nominalVoltageV"] = 0.0
    if _is(data.get("nominalCapacityAh"), OLD_AMP_HOURS):
        out["nominalCapacityAh"] = 0.0
    if _is(data.get("maxChargePowerW"), OLD_WALL_W):
        out["maxChargePowerW"] = NEW_WALL_W
    if _missing(data.get("chargerOutputW")):
        out["chargerOutputW"] = CHARGER_W
    if _missing(data.get("chargeTimeMinutes")):
        out["chargeTimeMinutes"] = CHARGE_MINUTES
    return out


def vehicle_changes(data: dict) -> dict:
    """``chargerRatedW`` for a Feliz 2025 that has none; a rating set stays."""
    return {} if not _missing(data.get("chargerRatedW")) else {"chargerRatedW": CHARGER_W}


def named_feliz_2025(data: dict) -> bool:
    """A vehicle named explicitly (the owner's keeps its model elsewhere):
    linked to the model, or called Feliz and holding the Feliz 2025's 2400 Wh."""
    if MODEL_ID in (data.get("catalogId"), data.get("vinfastModelId")):
        return True
    snapshot = data.get("catalogSnapshot") or {}
    text = " ".join(str(value or "") for value in (
        data.get("model"), data.get("modelName"), data.get("vehicleName"), snapshot.get("displayName"),
    )).lower()
    capacity = next((_number(data.get(key)) for key in ("nominalCapacityWh", "batteryCapacityWh", "batteryCapacity")
                     if _number(data.get(key))), None)
    return "feliz" in text and capacity is not None and abs(capacity - NOMINAL_WH) < 1


def _snapshot_with(data: dict, changes: dict) -> dict:
    snapshot = json.loads(json.dumps(data, default=str))
    for path, value in changes.items():
        group, key = path.split(".")
        target = snapshot.setdefault(group, {})
        if value is None:
            target.pop(key, None)
        else:
            target[key] = value
    return snapshot


def run(db, vehicle_id: str, *, apply: bool, delete_field=None, now: datetime | None = None) -> dict:
    """Read, then (with ``apply``) write in one batch. ``delete_field`` is
    Firestore's DELETE_FIELD sentinel."""
    stamp = (now or datetime.now(timezone.utc)).isoformat()
    report: dict = {"mode": "apply" if apply else "dry-run", "at": stamp,
                    "catalog": {}, "legacy": {}, "vehicles": {}, "named": None}
    writes: list[tuple] = []

    catalog_ref = db.collection(CATALOG).document(MODEL_ID)
    catalog = catalog_ref.get()
    if catalog.exists:
        data = catalog.to_dict() or {}
        changes = catalog_changes(data)
        report["catalog"] = changes
        if changes:
            revision = int(data.get("revision") or 1) + 1
            values = {path: (delete_field if value is None else value) for path, value in changes.items()}
            writes.append(("update", catalog_ref, {**values, "revision": revision, "updatedAt": stamp}))
            snapshot = {**_snapshot_with(data, changes), "revision": revision}
            history = db.collection(HISTORY).document(MODEL_ID).collection("revisions").document(str(revision))
            writes.append(("set", history, {"revision": revision, "snapshot": snapshot, "publishedAt": stamp,
                                            "publishedBy": "qa166-feliz-specs", "note": NOTE}))

    legacy_ref = db.collection(LEGACY).document(MODEL_ID)
    legacy = legacy_ref.get()
    if legacy.exists:
        changes = legacy_changes(legacy.to_dict() or {})
        report["legacy"] = changes
        if changes:
            writes.append(("update", legacy_ref, changes))

    seen: set[str] = set()
    for field in ("vinfastModelId", "catalogId"):
        for snapshot in db.collection("Vehicles").where(field, "==", MODEL_ID).stream():
            if snapshot.id in seen:
                continue
            seen.add(snapshot.id)
            changes = vehicle_changes(snapshot.to_dict() or {})
            report["vehicles"][snapshot.id] = changes or "kept"
            if changes:
                writes.append(("update", snapshot.reference, {**changes, "updatedAt": stamp}))
    if vehicle_id and vehicle_id not in seen:
        named_ref = db.collection("Vehicles").document(vehicle_id)
        named = named_ref.get()
        data = (named.to_dict() or {}) if named.exists else {}
        matches = named.exists and named_feliz_2025(data)
        changes = vehicle_changes(data) if matches else {}
        report["named"] = {"vehicle": vehicle_id, "found": bool(named.exists), "feliz2025": matches,
                           "changes": changes or "kept"}
        if changes:
            writes.append(("update", named_ref, {**changes, "updatedAt": stamp}))

    report["writes"] = len(writes)
    if apply and writes:
        batch = db.batch()
        for kind, ref, values in writes:
            if kind == "set":
                batch.set(ref, values)
            else:
                batch.update(ref, values)
        batch.commit()
    return report


if __name__ == "__main__":
    import base64
    import os
    import zlib

    import firebase_admin
    from firebase_admin import credentials, firestore

    raw = os.environ["FIREBASE_CREDENTIALS_JSON"].strip()
    cred = json.loads(raw if raw.startswith("{") else base64.b64decode(raw))
    app = firebase_admin.initialize_app(credentials.Certificate(cred), name="qa166specs")
    result = run(firestore.client(app), "__VEHICLE__", apply="__APPLY__" == "1",
                 delete_field=firestore.DELETE_FIELD)
    packed = base64.b64encode(zlib.compress(json.dumps(result, default=str).encode(), 9)).decode()
    print("<<<" + packed + ">>>")
