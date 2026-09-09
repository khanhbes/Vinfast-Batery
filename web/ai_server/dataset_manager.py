"""Dataset Manager for Charging Time AI Model.

Manages physical dataset files (web/data/charging_time_dataset.json and .csv).
Automatically updates dataset records whenever actual SOC is confirmed by users,
and provides APIs for viewing, editing, and fine-tuning in Developer Mode.
"""
from __future__ import annotations

import json
import logging
import os
import threading
from datetime import datetime, timezone
from typing import Any

from csv_security import csv_text

logger = logging.getLogger("DatasetManager")

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
JSON_PATH = os.path.join(DATA_DIR, "charging_time_dataset.json")
CSV_PATH = os.path.join(DATA_DIR, "charging_time_dataset.csv")

_lock = threading.Lock()


def _ensure_dir():
    os.makedirs(DATA_DIR, exist_ok=True)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _calculate_features(start_soc: float, end_soc: float, duration_s: float, ambient_c: float) -> tuple[float, float, float]:
    delta_soc = max(0.1, round(end_soc - start_soc, 2))
    hours = duration_s / 3600.0
    avg_charge_rate = (delta_soc / hours) if hours > 0 else 22.5
    avg_charge_rate = max(5.0, min(50.0, round(avg_charge_rate, 2)))
    temp_deviation = round(abs(ambient_c - 27.0), 2)
    return delta_soc, avg_charge_rate, temp_deviation


def _generate_seed_dataset() -> list[dict[str, Any]]:
    """Generate initial verified charging dataset for bootstrapping if file is new."""
    seeds = [
        {"session_id": "seed-chg-001", "vehicle_id": "VF_FELIZ_2025", "start_soc": 20.0, "target_soc": 100.0, "actual_end_soc": 100.0, "duration_seconds": 12600, "energy_wh": 2600.0, "ambient_temp_c": 28.5, "is_user_confirmed": True, "created_at": "2026-09-01T08:00:00Z"},
        {"session_id": "seed-chg-002", "vehicle_id": "VF_FELIZ_2025", "start_soc": 35.0, "target_soc": 90.0, "actual_end_soc": 90.0, "duration_seconds": 8800, "energy_wh": 1820.0, "ambient_temp_c": 31.0, "is_user_confirmed": True, "created_at": "2026-09-02T13:30:00Z"},
        {"session_id": "seed-chg-003", "vehicle_id": "VF_FELIZ_2025", "start_soc": 15.0, "target_soc": 80.0, "actual_end_soc": 82.0, "duration_seconds": 10200, "energy_wh": 2150.0, "ambient_temp_c": 29.0, "is_user_confirmed": True, "created_at": "2026-09-03T19:00:00Z"},
        {"session_id": "seed-chg-004", "vehicle_id": "VF_FELIZ_2025", "start_soc": 40.0, "target_soc": 100.0, "actual_end_soc": 98.0, "duration_seconds": 9600, "energy_wh": 1980.0, "ambient_temp_c": 33.5, "is_user_confirmed": True, "created_at": "2026-09-04T07:15:00Z"},
        {"session_id": "seed-chg-005", "vehicle_id": "VF_FELIZ_2025", "start_soc": 25.0, "target_soc": 90.0, "actual_end_soc": 89.0, "duration_seconds": 10500, "energy_wh": 2180.0, "ambient_temp_c": 27.0, "is_user_confirmed": True, "created_at": "2026-09-05T20:00:00Z"},
        {"session_id": "seed-chg-006", "vehicle_id": "VF_FELIZ_2025", "start_soc": 50.0, "target_soc": 100.0, "actual_end_soc": 100.0, "duration_seconds": 7800, "energy_wh": 1650.0, "ambient_temp_c": 26.5, "is_user_confirmed": True, "created_at": "2026-09-06T14:40:00Z"},
    ]
    records = []
    for s in seeds:
        start = s["start_soc"]
        end = s["actual_end_soc"]
        dur = s["duration_seconds"]
        amb = s["ambient_temp_c"]
        delta, rate, dev = _calculate_features(start, end, dur, amb)
        rec = {
            **s,
            "delta_soc": delta,
            "avg_charge_rate": rate,
            "temp_deviation": dev,
            "avg_power_w": round(s["energy_wh"] / (dur / 3600.0), 1),
            "training_eligible": True,
            "training_excluded": False,
            "developer_note": "Seed baseline sample",
            "confirmed_at": s["created_at"],
            "updated_at": s["created_at"],
        }
        records.append(rec)
    return records


def load_dataset() -> list[dict[str, Any]]:
    """Load the complete list of charging session records from the JSON dataset file."""
    _ensure_dir()
    with _lock:
        if not os.path.exists(JSON_PATH):
            seeds = _generate_seed_dataset()
            _write_files_unlocked(seeds)
            return seeds
        try:
            with open(JSON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
                return []
        except Exception as e:
            logger.error("Failed to read dataset from %s: %s", JSON_PATH, e)
            return []


def _write_files_unlocked(records: list[dict[str, Any]]) -> None:
    _ensure_dir()
    # Write JSON
    tmp_json = JSON_PATH + ".tmp"
    with open(tmp_json, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=2)
    os.replace(tmp_json, JSON_PATH)

    # Write CSV
    if records:
        fieldnames = [
            "session_id", "vehicle_id", "start_soc", "target_soc", "actual_end_soc",
            "delta_soc", "duration_seconds", "energy_wh", "avg_power_w",
            "ambient_temp_c", "avg_charge_rate", "temp_deviation",
            "is_user_confirmed", "training_eligible", "training_excluded",
            "developer_note", "created_at", "confirmed_at", "updated_at"
        ]
        tmp_csv = CSV_PATH + ".tmp"
        with open(tmp_csv, "w", encoding="utf-8", newline="") as f:
            f.write(csv_text(records, fieldnames))
        os.replace(tmp_csv, CSV_PATH)


def save_dataset(records: list[dict[str, Any]]) -> None:
    """Save records atomically to JSON and CSV."""
    with _lock:
        _write_files_unlocked(records)


def upsert_session_record(session_data: dict[str, Any], actual_soc: float | None = None) -> dict[str, Any]:
    """Insert or update a session record in the dataset file.
    
    Called automatically whenever user confirms actual SOC or a session finishes.
    """
    session_id = str(session_data.get("sessionId") or session_data.get("session_id") or "")
    if not session_id:
        return {}

    records = load_dataset()
    now = _now_iso()

    start_soc = float(session_data.get("startSoc") or session_data.get("start_soc") or 0.0)
    target_soc = float(session_data.get("targetSoc") or session_data.get("target_soc") or 100.0)
    
    # Priority: explicitly passed actual_soc > session_data confirmedEndSoc > actual_end_soc > targetSoc
    confirmed_soc = actual_soc
    if confirmed_soc is None:
        raw_conf = session_data.get("confirmedEndSoc") or session_data.get("actual_end_soc") or session_data.get("actualEndSoc")
        if raw_conf is not None:
            confirmed_soc = float(raw_conf)
    
    end_soc = confirmed_soc if confirmed_soc is not None else target_soc
    is_confirmed = confirmed_soc is not None

    duration_s = float(
        session_data.get("actualDurationSeconds")
        or session_data.get("durationSeconds")
        or session_data.get("actual_duration_seconds")
        or 3600.0
    )
    if duration_s < 300:
        duration_s = 3600.0

    ambient_c = float(
        session_data.get("ambientTempStartC")
        or session_data.get("ambient_temp_start_c")
        or session_data.get("ambient_temp_c")
        or 28.0
    )
    energy_wh = float(
        session_data.get("energyUsedWh")
        or session_data.get("energy_used_wh")
        or session_data.get("energyWh")
        or 0.0
    )
    avg_power_w = float(
        session_data.get("averagePowerW")
        or session_data.get("average_power_w")
        or (round(energy_wh / (duration_s / 3600.0), 1) if duration_s > 0 and energy_wh > 0 else 400.0)
    )

    delta_soc, avg_charge_rate, temp_deviation = _calculate_features(start_soc, end_soc, duration_s, ambient_c)
    vehicle_id = str(session_data.get("vehicleId") or session_data.get("vehicle_id") or "VF_FELIZ_2025")

    # Check if record already exists
    existing_idx = next((i for i, r in enumerate(records) if r.get("session_id") == session_id), None)

    if existing_idx is not None:
        target = records[existing_idx]
        target["start_soc"] = start_soc
        target["target_soc"] = target_soc
        if confirmed_soc is not None:
            target["actual_end_soc"] = confirmed_soc
            target["is_user_confirmed"] = True
            target["confirmed_at"] = now
        target["delta_soc"] = delta_soc
        target["duration_seconds"] = duration_s
        target["energy_wh"] = energy_wh
        target["avg_power_w"] = avg_power_w
        target["ambient_temp_c"] = ambient_c
        target["avg_charge_rate"] = avg_charge_rate
        target["temp_deviation"] = temp_deviation
        target["training_eligible"] = delta_soc > 5.0 and duration_s >= 600
        target["updated_at"] = now
        record = target
    else:
        record = {
            "session_id": session_id,
            "vehicle_id": vehicle_id,
            "start_soc": start_soc,
            "target_soc": target_soc,
            "actual_end_soc": end_soc,
            "delta_soc": delta_soc,
            "duration_seconds": duration_s,
            "energy_wh": energy_wh,
            "avg_power_w": avg_power_w,
            "ambient_temp_c": ambient_c,
            "avg_charge_rate": avg_charge_rate,
            "temp_deviation": temp_deviation,
            "is_user_confirmed": is_confirmed,
            "training_eligible": delta_soc > 5.0 and duration_s >= 600,
            "training_excluded": False,
            "developer_note": "Tự động thu thập từ phiên sạc thực tế",
            "created_at": session_data.get("createdAt") or session_data.get("created_at") or now,
            "confirmed_at": now if is_confirmed else None,
            "updated_at": now,
        }
        records.append(record)

    save_dataset(records)
    logger.info("Updated dataset record for session %s (confirmed: %s)", session_id, is_confirmed)
    return record


def update_record(session_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
    """Update fields of an existing record from Developer Mode."""
    records = load_dataset()
    target_idx = next((i for i, r in enumerate(records) if r.get("session_id") == session_id), None)
    if target_idx is None:
        return None

    target = records[target_idx]
    # Allowed editable fields
    for field in ["start_soc", "actual_end_soc", "duration_seconds", "ambient_temp_c", "energy_wh", "avg_power_w", "training_excluded", "developer_note", "vehicle_id"]:
        if field in updates:
            target[field] = updates[field]

    start = float(target.get("start_soc", 0.0))
    end = float(target.get("actual_end_soc", target.get("target_soc", 100.0)))
    dur = float(target.get("duration_seconds", 3600.0))
    amb = float(target.get("ambient_temp_c", 28.0))

    delta, rate, dev = _calculate_features(start, end, dur, amb)
    target["delta_soc"] = delta
    target["avg_charge_rate"] = rate
    target["temp_deviation"] = dev
    target["updated_at"] = _now_iso()

    save_dataset(records)
    return target


def add_manual_record(record_data: dict[str, Any]) -> dict[str, Any]:
    """Add a new manual sample into dataset from Developer Mode."""
    records = load_dataset()
    now = _now_iso()
    session_id = record_data.get("session_id") or f"manual-{int(datetime.now().timestamp())}"
    start = float(record_data.get("start_soc", 20.0))
    end = float(record_data.get("actual_end_soc", 100.0))
    dur = float(record_data.get("duration_seconds", 10800.0))
    amb = float(record_data.get("ambient_temp_c", 30.0))
    energy = float(record_data.get("energy_wh", 2400.0))
    delta, rate, dev = _calculate_features(start, end, dur, amb)

    new_rec = {
        "session_id": session_id,
        "vehicle_id": record_data.get("vehicle_id", "VF_FELIZ_2025"),
        "start_soc": start,
        "target_soc": float(record_data.get("target_soc", end)),
        "actual_end_soc": end,
        "delta_soc": delta,
        "duration_seconds": dur,
        "energy_wh": energy,
        "avg_power_w": round(energy / (dur / 3600.0), 1) if dur > 0 else 400.0,
        "ambient_temp_c": amb,
        "avg_charge_rate": rate,
        "temp_deviation": dev,
        "is_user_confirmed": True,
        "training_eligible": True,
        "training_excluded": False,
        "developer_note": record_data.get("developer_note", "Thêm thủ công từ Developer Studio"),
        "created_at": now,
        "confirmed_at": now,
        "updated_at": now,
    }
    records.append(new_rec)
    save_dataset(records)
    return new_rec


def get_dataset_stats() -> dict[str, Any]:
    """Return statistical summary of dataset."""
    records = load_dataset()
    total = len(records)
    confirmed = sum(1 for r in records if r.get("is_user_confirmed"))
    eligible = sum(1 for r in records if r.get("training_eligible") and not r.get("training_excluded"))
    excluded = sum(1 for r in records if r.get("training_excluded"))

    vehicles = list({r.get("vehicle_id", "unknown") for r in records})
    avg_duration = round(sum(r.get("duration_seconds", 0) for r in records) / total, 1) if total else 0.0

    return {
        "totalRecords": total,
        "confirmedRecords": confirmed,
        "eligibleRecords": eligible,
        "excludedRecords": excluded,
        "vehicles": vehicles,
        "averageDurationSeconds": avg_duration,
        "jsonPath": JSON_PATH,
        "csvPath": CSV_PATH,
        "lastModified": _now_iso(),
    }


def export_csv_text() -> str:
    """Return a freshly sanitized CSV representation of the JSON dataset."""
    records = load_dataset()
    if not records:
        return ""
    fieldnames = [
        "session_id", "vehicle_id", "start_soc", "target_soc", "actual_end_soc",
        "delta_soc", "duration_seconds", "energy_wh", "avg_power_w",
        "ambient_temp_c", "avg_charge_rate", "temp_deviation",
        "is_user_confirmed", "training_eligible", "training_excluded",
        "developer_note", "created_at", "confirmed_at", "updated_at",
    ]
    return csv_text(records, fieldnames)
