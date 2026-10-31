"""QA 140: VinFast Feliz 2025 holds 2.4 kWh (50 Ah at 48 V), not 2.6 kWh.

Dry-run is the default: it only reads and prints what would change. With
``--apply`` it writes, in one batch per 400 documents:

- ``VehicleCatalog/feliz_2025``: capacity fields still at 2600 Wh / 54 Ah,
  plus a history revision (``VehicleCatalogHistory/feliz_2025/revisions``);
- ``VinFastModelSpecs/feliz_2025`` (legacy projection);
- every ``Vehicles`` document of that model whose capacity is still the old
  catalog default. A capacity the owner typed (anything but 2600) is left
  alone and listed.

Learned charging profiles are not touched: their Wh per % comes from real
charges, not from the catalog.
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

from migrate_vehicle_catalog import initialize_firestore  # noqa: E402
from vehicle_catalog import CATALOG_COLLECTION, HISTORY_COLLECTION, LEGACY_COLLECTION  # noqa: E402

MODEL_ID = "feliz_2025"
OLD_WH, NEW_WH = 2600.0, 2400.0
OLD_AH, NEW_AH = 54.0, 50.0
VEHICLE_WH_FIELDS = ("nominalCapacityWh", "batteryCapacityWh", "batteryCapacity")


def _is(value, old: float) -> bool:
    try:
        return abs(float(value) - old) < 0.5
    except (TypeError, ValueError):
        return False


def catalog_changes(data: dict) -> dict:
    """Dotted field paths -> new value, for fields still at the old spec."""
    out = {}
    for group in ("battery", "appDefaults"):
        values = data.get(group) or {}
        for key in ("grossCapacityWh", "usableCapacityWh", "calculationCapacityWh"):
            if _is(values.get(key), OLD_WH):
                out[f"{group}.{key}"] = NEW_WH
        if _is(values.get("capacityAh"), OLD_AH):
            out[f"{group}.capacityAh"] = NEW_AH
    return out


def vehicle_changes(data: dict) -> dict:
    out = {key: NEW_WH for key in VEHICLE_WH_FIELDS if _is(data.get(key), OLD_WH)}
    if _is(data.get("nominalCapacityAh"), OLD_AH):
        out["nominalCapacityAh"] = NEW_AH
    snapshot = data.get("catalogSnapshot") or {}
    if _is(snapshot.get("calculationCapacityWh"), OLD_WH):
        out["catalogSnapshot.calculationCapacityWh"] = NEW_WH
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Write the changes (default: dry-run)")
    parser.add_argument("--report", type=Path, help="Optional JSON report path")
    args = parser.parse_args()
    db = initialize_firestore()
    now = datetime.now(timezone.utc).isoformat()
    report = {"mode": "apply" if args.apply else "dry-run", "at": now,
              "catalog": {}, "legacy": {}, "vehicles": {"changed": {}, "ownerValue": {}}}
    writes = []

    catalog_ref = db.collection(CATALOG_COLLECTION).document(MODEL_ID)
    catalog = catalog_ref.get()
    if catalog.exists:
        data = catalog.to_dict() or {}
        changes = catalog_changes(data)
        report["catalog"] = changes
        if changes:
            revision = int(data.get("revision") or 1) + 1
            writes.append((catalog_ref, {**changes, "revision": revision, "updatedAt": now}))
            snapshot = json.loads(json.dumps(data, default=str))
            for path, value in changes.items():
                group, key = path.split(".")
                snapshot.setdefault(group, {})[key] = value
            snapshot["revision"] = revision
            writes.append((
                db.collection(HISTORY_COLLECTION).document(MODEL_ID).collection("revisions").document(str(revision)),
                {"revision": revision, "snapshot": snapshot, "publishedAt": now,
                 "publishedBy": "qa140-feliz-capacity", "note": "Feliz 2025: 2.4 kWh / 50 Ah"},
            ))

    legacy_ref = db.collection(LEGACY_COLLECTION).document(MODEL_ID)
    legacy = legacy_ref.get()
    if legacy.exists:
        data = legacy.to_dict() or {}
        changes = {}
        if _is(data.get("nominalCapacityWh"), OLD_WH):
            changes["nominalCapacityWh"] = NEW_WH
        if _is(data.get("nominalCapacityAh"), OLD_AH):
            changes["nominalCapacityAh"] = NEW_AH
        if "2.6kWh" in str(data.get("tagline") or ""):
            changes["tagline"] = str(data["tagline"]).replace("2.6kWh", "2.4kWh")
        report["legacy"] = changes
        if changes:
            writes.append((legacy_ref, changes))

    for field in ("vinfastModelId", "catalogId"):
        for snapshot in db.collection("Vehicles").where(field, "==", MODEL_ID).stream():
            if snapshot.id in report["vehicles"]["changed"] or snapshot.id in report["vehicles"]["ownerValue"]:
                continue
            data = snapshot.to_dict() or {}
            changes = vehicle_changes(data)
            if changes:
                report["vehicles"]["changed"][snapshot.id] = changes
                writes.append((snapshot.reference, {**changes, "updatedAt": now}))
            else:
                report["vehicles"]["ownerValue"][snapshot.id] = {
                    key: data.get(key) for key in VEHICLE_WH_FIELDS if data.get(key) is not None}

    report["writes"] = len(writes)
    if args.apply:
        for start in range(0, len(writes), 400):
            batch = db.batch()
            for ref, values in writes[start:start + 400]:
                if "snapshot" in values:
                    batch.set(ref, values)
                else:
                    batch.update(ref, values)
            batch.commit()
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
