"""Seed Global EV Catalog and report/migrate legacy Vehicles safely.

Dry-run is the default. Use ``--apply`` only after reviewing the match report.
The script never changes ambiguous or unmatched vehicle records.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

WEB_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = WEB_ROOT.parent
sys.path.insert(0, str(WEB_ROOT))

from vehicle_catalog import (  # noqa: E402
    CATALOG_COLLECTION,
    HISTORY_COLLECTION,
    KEY_COLLECTION,
    LEGACY_COLLECTION,
    MANUFACTURER_COLLECTION,
    META_COLLECTION,
    legacy_projection,
    normalize_catalog_document,
)

DEFAULT_SOURCE = REPO_ROOT / "app" / "assets" / "vinfast_specs_fallback.json"


def initialize_firestore():
    if not firebase_admin._apps:
        raw = os.environ.get("FIREBASE_CREDENTIALS_JSON", "").strip()
        if raw:
            firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
        else:
            path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
            firebase_admin.initialize_app(credentials.Certificate(path)) if path else firebase_admin.initialize_app()
    return firestore.client()


def as_global_spec(item: dict) -> dict:
    catalog_id = str(item["modelId"])
    name = str(item.get("modelName") or catalog_id)
    source_url = "https://vinfastauto.com/vn_vi/xe-may-dien"
    capacity = float(item.get("nominalCapacityWh") or 0)
    range_km = float(item.get("rangeKm") or 0)
    max_charge = float(item.get("maxChargePowerW") or 0)
    data = normalize_catalog_document({
        "brandId": "vinfast",
        "brandName": "VinFast",
        "model": item.get("modelLine") or name.replace("VinFast ", ""),
        "variant": name.replace("VinFast ", ""),
        "modelYear": item.get("releaseYear") or 2024,
        "market": "VN",
        "vehicleType": "scooter",
        "aliases": item.get("aliases") or [],
        "localized": {
            "vi": {"displayName": name, "tagline": item.get("tagline") or "", "description": ""},
            "en": {"displayName": name, "tagline": item.get("tagline") or "", "description": ""},
        },
        "battery": {
            "grossCapacityWh": capacity,
            "calculationCapacityWh": capacity,
            "capacityAh": item.get("nominalCapacityAh"),
            "voltageV": item.get("nominalVoltageV"),
            "chemistry": "LFP",
            "packCount": 1,
            "removable": False,
        },
        "charging": {"maxAcPowerW": max_charge, "maxSafeChargePowerW": max_charge},
        "performance": {
            "ratedMotorPowerW": item.get("ratedMotorPowerW"),
            "peakMotorPowerW": item.get("peakMotorPowerW"),
            "topSpeedKmh": item.get("topSpeedKmh"),
            "rangeKm": range_km,
            "rangeTestCycle": "Manufacturer published",
        },
        "appDefaults": {
            "calculationCapacityWh": capacity,
            "defaultEfficiencyKmPerPercent": item.get("defaultEfficiencyKmPerPercent") or (range_km / 100 if range_km else 1.0),
            "maxSafeChargePowerW": max_charge,
        },
        "sources": [{"url": source_url, "publisher": "VinFast", "type": "manufacturer"}],
    })
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    data.update({
        "catalogId": catalog_id,
        "status": "published",
        "selectable": True,
        "revision": 1,
        "publishedAt": now,
        "publishedBy": "catalog-migration",
        "createdAt": now,
        "updatedAt": now,
        "verification": {"status": "legacy_reviewed", "reviewRequired": True},
    })
    return data


def normalized(value: object) -> str:
    return "".join(ch for ch in str(value or "").lower() if ch.isalnum())


def match_vehicle(vehicle: dict, specs: list[dict]) -> tuple[str, str | None]:
    linked = str(vehicle.get("catalogId") or vehicle.get("vinfastModelId") or "")
    by_id = {str(spec["catalogId"]): spec for spec in specs}
    if linked in by_id:
        return "matched", linked
    name = normalized(vehicle.get("model") or vehicle.get("vehicleName"))
    matches = []
    for spec in specs:
        candidates = [spec["catalogId"], spec.get("model"), spec.get("variant")]
        candidates.extend(spec.get("aliases") or [])
        if name and any(normalized(candidate) in name or name in normalized(candidate) for candidate in candidates if normalized(candidate)):
            matches.append(spec["catalogId"])
    matches = list(dict.fromkeys(matches))
    if len(matches) == 1:
        return "matched", matches[0]
    return ("ambiguous", None) if matches else ("unmatched", None)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--apply", action="store_true", help="Write catalog and unambiguous vehicle links")
    parser.add_argument("--report", type=Path, help="Optional JSON report path")
    args = parser.parse_args()

    legacy = json.loads(args.source.read_text(encoding="utf-8"))
    specs = [as_global_spec(item) for item in legacy]
    db = initialize_firestore()
    report = {"mode": "apply" if args.apply else "dry-run", "catalog": [spec["catalogId"] for spec in specs], "vehicles": {"matched": [], "ambiguous": [], "unmatched": []}}

    if args.apply:
        batch = db.batch()
        batch.set(db.collection(MANUFACTURER_COLLECTION).document("vinfast"), {
            "brandId": "vinfast", "name": "VinFast", "officialDomains": ["vinfastauto.com"], "updatedAt": datetime.now(timezone.utc).isoformat(),
        }, merge=True)
        for spec in specs:
            catalog_id = spec["catalogId"]
            batch.set(db.collection(CATALOG_COLLECTION).document(catalog_id), spec)
            batch.set(db.collection(HISTORY_COLLECTION).document(catalog_id).collection("revisions").document("1"), {"revision": 1, "snapshot": spec, "publishedAt": datetime.now(timezone.utc).isoformat(), "publishedBy": "catalog-migration"})
            batch.set(db.collection(KEY_COLLECTION).document(spec["identityKey"]), {"catalogId": catalog_id, "identityKey": spec["identityKey"], "updatedAt": datetime.now(timezone.utc).isoformat()})
            batch.set(db.collection(LEGACY_COLLECTION).document(catalog_id), legacy_projection(spec), merge=True)
        batch.set(db.collection(META_COLLECTION).document("current"), {"revision": 1, "updatedAt": datetime.now(timezone.utc).isoformat(), "lastCatalogId": specs[-1]["catalogId"]}, merge=True)
        batch.commit()

    for snapshot in db.collection("Vehicles").stream():
        vehicle = snapshot.to_dict() or {}
        state, catalog_id = match_vehicle(vehicle, specs)
        report["vehicles"][state].append(snapshot.id)
        if args.apply and state == "matched" and catalog_id:
            spec = next(item for item in specs if item["catalogId"] == catalog_id)
            snapshot.reference.update({
                "catalogId": catalog_id,
                "catalogRevisionAtSelection": spec["revision"],
                "catalogMigrationStatus": "matched",
                "updatedAt": datetime.now(timezone.utc).isoformat(),
            })
    if not args.apply:
        print(f"DRY RUN: would seed {len(specs)} reviewed catalog records; no Firestore writes were made.")

    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
