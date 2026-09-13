"""Safely repair legacy Shelly terminal SOC estimates.

Dry-run is the default.  The script never writes ``Vehicles`` and never
touches a session with a user-confirmed SOC.  Use ``--apply`` only after
reviewing the JSON report printed by the dry run.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, firestore


def initialize_firestore():
    if not firebase_admin._apps:
        raw = os.environ.get("FIREBASE_CREDENTIALS_JSON", "").strip()
        if raw:
            firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
        else:
            path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
            firebase_admin.initialize_app(credentials.Certificate(path)) if path else firebase_admin.initialize_app()
    return firestore.client()


def positive(*values):
    for value in values:
        try:
            value = float(value)
            if value > 0:
                return value
        except (TypeError, ValueError):
            pass
    return None


def soc_value(*values):
    for value in values:
        try:
            value = float(value)
            if 0 <= value <= 100:
                return value
        except (TypeError, ValueError):
            pass
    return None


def terminal(data: dict) -> bool:
    return str(data.get("sessionState") or data.get("status") or "") in {
        "completed", "cancelled", "interrupted", "failed", "terminal",
    }


def repair_candidate(db, data: dict) -> tuple[dict | None, str]:
    if not terminal(data):
        return None, "not_terminal"
    if soc_value(data.get("actualEndSoc"), data.get("confirmedEndSoc")) is not None:
        return None, "user_confirmed"
    session = data.get("smartChargingSession") if isinstance(data.get("smartChargingSession"), dict) else {}
    capacity = positive(
        session.get("effective_capacity_wh"), session.get("estimated_capacity_wh"),
        session.get("nominal_capacity_wh"), data.get("effectiveCapacityWh"),
        data.get("nominalCapacityWh"),
    )
    if capacity is None:
        vehicle_id = str(data.get("vehicleId") or session.get("vehicle_id") or "")
        vehicle = db.collection("Vehicles").document(vehicle_id).get() if vehicle_id else None
        vehicle_data = vehicle.to_dict() or {} if vehicle and vehicle.exists else {}
        capacity = positive(vehicle_data.get("calibratedCapacityWh"), vehicle_data.get("nominalCapacityWh"))
        catalog_id = vehicle_data.get("catalogId") or vehicle_data.get("vinfastModelId")
        if capacity is None and catalog_id:
            catalog = db.collection("VehicleCatalog").document(str(catalog_id)).get()
            catalog_data = catalog.to_dict() or {} if catalog.exists else {}
            defaults = catalog_data.get("appDefaults") or {}
            battery = catalog_data.get("battery") or {}
            capacity = positive(defaults.get("calculationCapacityWh"), battery.get("calculationCapacityWh"))
        if capacity is None and catalog_id:
            legacy = db.collection("VinFastModelSpecs").document(str(catalog_id)).get()
            capacity = positive((legacy.to_dict() or {}).get("nominalCapacityWh") if legacy.exists else None)
    energy = positive(data.get("gridEnergyWh"), data.get("energyWh"), session.get("energy_used_wh"))
    start = soc_value(data.get("startBatteryPercent"), data.get("startSoc"), session.get("start_soc"))
    if capacity is None:
        return None, "capacity_unavailable"
    if energy is None:
        return None, "energy_unavailable"
    if start is None:
        return None, "start_soc_unavailable"
    efficiency = positive(session.get("charging_efficiency"), data.get("chargingEfficiency")) or .90
    efficiency = min(.98, max(.65, efficiency))
    stored = energy * efficiency
    estimate = min(100.0, max(start, start + stored / capacity * 100))
    return {
        "estimatedEndSoc": estimate,
        "endBatteryPercent": round(estimate),
        "actual_end_soc_auto": estimate,
        "estimatedStoredWh": stored,
        "socEstimateAvailable": True,
        "socEstimateSource": "shelly_energy",
        "socEstimateQuality": "backfilled",
        "socEstimationVersion": 2,
        "socRepair": {
            "version": 1,
            "formula": "start + gridWh * efficiency / capacityWh * 100",
            "previousEstimatedEndSoc": data.get("estimatedEndSoc"),
            "capacityWh": capacity,
            "energyWh": energy,
            "efficiency": efficiency,
            "repairedAt": datetime.now(timezone.utc).isoformat(),
        },
    }, "eligible"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Persist safe eligible repairs")
    args = parser.parse_args()
    db = initialize_firestore()
    report = {"mode": "apply" if args.apply else "dry-run", "eligible": 0, "updated": 0, "skipped": {}}
    for snapshot in db.collection("ChargeLogs").where("source", "==", "shelly_smart_charging").stream():
        patch, reason = repair_candidate(db, snapshot.to_dict() or {})
        if patch is None:
            report["skipped"][reason] = report["skipped"].get(reason, 0) + 1
            continue
        report["eligible"] += 1
        if args.apply:
            patch["updatedAt"] = firestore.SERVER_TIMESTAMP
            snapshot.reference.set(patch, merge=True)
            report["updated"] += 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
