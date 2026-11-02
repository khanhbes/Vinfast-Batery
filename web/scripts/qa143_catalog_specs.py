"""QA 143: VinFast catalog figures (owner's choice, 02/11/2026).

The catalog had capacities that did not match VinFast (Evo200 1.9 kWh, Feliz S
1.4 kWh; VinFast publishes 3.5 kWh LFP), km/1 % that did not match the
published range (Feliz 2025 270 km with 1.35 km/1 %) and lead-acid models
listed as LFP. Range is VinFast's published figure (30 km/h, 65 kg rider, one
battery); km/1 % is that range / 100.

Dry-run is the default: it only reads and prints. ``--apply`` writes, in
batches of 400:

- ``VehicleCatalog/<id>``: each field still at the old value, plus a history
  revision;
- ``VinFastModelSpecs/<id>`` (legacy projection);
- ``Vehicles`` of that model: capacity, Ah, km/1 % and chemistry still at the
  old catalog default. A value the owner changed is left alone and listed.

Learned profiles and trip models are not touched: they come from real rides
and charges.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

WEB_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB_ROOT))
sys.path.insert(0, str(WEB_ROOT / "scripts"))

# field -> (old, new)
SPECS = {
    'evo200': {
        'nominalCapacityWh': (1872, 3500),
        'nominalCapacityAh': (39, 73),
        'defaultEfficiencyKmPerPercent': (1.2, 2.03),
    },
    'evo_lite_neo': {
        'nominalCapacityWh': (1488, 1260),
        'nominalCapacityAh': (31, 21),
        'nominalVoltageV': (48, 60),
        'defaultEfficiencyKmPerPercent': (1.3, 0.78),
        'rangeKm': (110, 78),
        'batteryChemistry': ('LFP', 'Lead-acid'),
    },
    'evo_grand': {
        'defaultEfficiencyKmPerPercent': (1.1, 1.34),
        'rangeKm': (262, 134),
        'tagline': ('Bản nâng cấp đi xa, tiện nghi hơn', 'Pin LFP 2.4kWh, thêm pin phụ đi tới 262 km'),
    },
    'feliz_2025': {
        'defaultEfficiencyKmPerPercent': (1.35, 1.34),
        'topSpeedKmh': (65, 70),
        'rangeKm': (270, 134),
        'tagline': ('Feliz thế hệ mới — pin 2.4kWh, đi xa hơn', 'Feliz thế hệ mới — pin 2.4kWh, thêm pin phụ đi tới 262 km'),
    },
    'feliz_s': {
        'nominalCapacityWh': (1440, 3500),
        'nominalCapacityAh': (30, 73),
        'defaultEfficiencyKmPerPercent': (1.2, 1.98),
        'topSpeedKmh': (60, 78),
    },
    'klara_s': {
        'nominalCapacityWh': (1920, 3500),
        'nominalCapacityAh': (40, 73),
        'defaultEfficiencyKmPerPercent': (1.0, 1.94),
    },
    'klara_a2': {
        'nominalCapacityWh': (1680, 960),
        'nominalCapacityAh': (35, 20),
        'defaultEfficiencyKmPerPercent': (1.1, 0.8),
        'rangeKm': (120, 80),
        'batteryChemistry': ('LFP', 'Lead-acid'),
    },
    'vento_s': {
        'nominalCapacityWh': (1872, 3500),
        'nominalCapacityAh': (39, 73),
        'defaultEfficiencyKmPerPercent': (1.0, 1.6),
        'topSpeedKmh': (80, 89),
        'rangeKm': (152, 160),
    },
    'theon_s': {
        'nominalCapacityAh': (72, 73),
        'defaultEfficiencyKmPerPercent': (0.95, 1.5),
    },
    'tempest': {
        'nominalCapacityWh': (2880, 1260),
        'nominalCapacityAh': (60, 21),
        'nominalVoltageV': (48, 60),
        'defaultEfficiencyKmPerPercent': (0.9, 0.8),
        'topSpeedKmh': (95, 49),
        'rangeKm': (140, 80),
        'peakMotorPowerW': (5000, 1600),
        'batteryChemistry': ('LFP', 'Lead-acid'),
    },
    'ludo': {
        'defaultEfficiencyKmPerPercent': (1.4, 0.7),
        'batteryChemistry': ('LFP', 'Li-ion'),
    },
}

# Where each figure lives in a catalog document, the legacy projection and a
# vehicle (a vehicle keeps a copy of the catalog defaults at selection).
CATALOG_PATHS = {
    "nominalCapacityWh": ("battery.grossCapacityWh", "battery.usableCapacityWh",
                          "battery.calculationCapacityWh", "appDefaults.calculationCapacityWh"),
    "nominalCapacityAh": ("battery.capacityAh",),
    "nominalVoltageV": ("battery.voltageV",),
    "batteryChemistry": ("battery.chemistry",),
    "defaultEfficiencyKmPerPercent": ("appDefaults.defaultEfficiencyKmPerPercent",),
    "topSpeedKmh": ("performance.topSpeedKmh",),
    "rangeKm": ("performance.rangeKm",),
    "peakMotorPowerW": ("performance.peakMotorPowerW",),
    "tagline": ("localized.vi.tagline", "localized.en.tagline"),
}
VEHICLE_PATHS = {
    "nominalCapacityWh": ("nominalCapacityWh", "batteryCapacityWh", "batteryCapacity",
                          "catalogSnapshot.calculationCapacityWh"),
    "nominalCapacityAh": ("nominalCapacityAh",),
    "batteryChemistry": ("batteryType", "catalogSnapshot.batteryChemistry"),
    "defaultEfficiencyKmPerPercent": ("defaultEfficiency", "catalogSnapshot.defaultEfficiencyKmPerPercent"),
}


def _same(value, old) -> bool:
    if isinstance(old, str):
        return isinstance(value, str) and value == old
    try:
        return abs(float(value) - float(old)) < 0.005 * max(1.0, abs(float(old)))
    except (TypeError, ValueError):
        return False


def _get(data: dict, path: str):
    for part in path.split("."):
        if not isinstance(data, dict):
            return None
        data = data.get(part)
    return data


def _changes(data: dict, model_id: str, paths: dict) -> dict:
    """Dotted path -> new value, for fields still at the old figure."""
    out = {}
    for key, (old, new) in SPECS.get(model_id, {}).items():
        for path in paths.get(key, ()):
            if _same(_get(data, path), old):
                out[path] = new
    return out


def catalog_changes(model_id: str, data: dict) -> dict:
    return _changes(data, model_id, CATALOG_PATHS)


def legacy_changes(model_id: str, data: dict) -> dict:
    return _changes(data, model_id, {key: (key,) for key in SPECS.get(model_id, {})})


def vehicle_changes(model_id: str, data: dict) -> dict:
    return _changes(data, model_id, VEHICLE_PATHS)


def _apply_dotted(snapshot: dict, changes: dict) -> dict:
    for path, value in changes.items():
        node = snapshot
        *parents, leaf = path.split(".")
        for part in parents:
            node = node.setdefault(part, {})
        node[leaf] = value
    return snapshot


def main() -> int:
    from migrate_vehicle_catalog import initialize_firestore
    from vehicle_catalog import CATALOG_COLLECTION, HISTORY_COLLECTION, LEGACY_COLLECTION

    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Write the changes (default: dry-run)")
    parser.add_argument("--catalog-only", action="store_true", help="Leave Vehicles documents alone")
    args = parser.parse_args()
    db = initialize_firestore()
    now = datetime.now(timezone.utc).isoformat()
    report = {"mode": "apply" if args.apply else "dry-run", "at": now,
              "catalog": {}, "legacy": {}, "vehicles": {}, "ownerValue": 0}
    writes = []
    for model_id in SPECS:
        ref = db.collection(CATALOG_COLLECTION).document(model_id)
        snap = ref.get()
        if snap.exists:
            data = snap.to_dict() or {}
            changes = catalog_changes(model_id, data)
            report["catalog"][model_id] = changes
            if changes:
                revision = int(data.get("revision") or 1) + 1
                writes.append((ref, {**changes, "revision": revision, "updatedAt": now}, False))
                snapshot = _apply_dotted(json.loads(json.dumps(data, default=str)), changes)
                snapshot["revision"] = revision
                writes.append((
                    db.collection(HISTORY_COLLECTION).document(model_id).collection("revisions")
                    .document(str(revision)),
                    {"revision": revision, "snapshot": snapshot, "publishedAt": now,
                     "publishedBy": "qa143-catalog-specs", "note": "VinFast published figures"},
                    True,
                ))
        legacy_ref = db.collection(LEGACY_COLLECTION).document(model_id)
        legacy = legacy_ref.get()
        if legacy.exists:
            changes = legacy_changes(model_id, legacy.to_dict() or {})
            report["legacy"][model_id] = changes
            if changes:
                writes.append((legacy_ref, changes, False))
        if args.catalog_only:
            continue
        seen = set()
        for field in ("vinfastModelId", "catalogId"):
            for vehicle in db.collection("Vehicles").where(field, "==", model_id).stream():
                if vehicle.id in seen:
                    continue
                seen.add(vehicle.id)
                changes = vehicle_changes(model_id, vehicle.to_dict() or {})
                if changes:
                    report["vehicles"][vehicle.id] = {"model": model_id, "fields": sorted(changes)}
                    writes.append((vehicle.reference, {**changes, "updatedAt": now}, False))
                else:
                    report["ownerValue"] += 1
    report["writes"] = len(writes)
    if args.apply:
        for start in range(0, len(writes), 400):
            batch = db.batch()
            for ref, values, whole in writes[start:start + 400]:
                batch.set(ref, values) if whole else batch.update(ref, values)
            batch.commit()
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
