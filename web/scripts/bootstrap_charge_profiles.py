"""Seed the Task 126 learned charge profile from already-confirmed sessions.

Owners who typed the real battery % after earlier charges (``actualEndSoc`` /
``confirmedEndSoc`` on a ChargeLog) get a learned wall-Wh-per-% right away
instead of after the next confirmation. Dry-run is the default and prints
counts and the learned values only (owners as a short hash). An owner who
switched Personal AI off is skipped.

Usage::

    python scripts/bootstrap_charge_profiles.py [--email owner@example.com] [--apply]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from firebase_admin import auth  # noqa: E402

from scripts.hide_junk_charge_logs import as_utc, initialize_firestore  # noqa: E402
from shelly import charge_model, history_quality  # noqa: E402
from shelly.models import PersonalChargingProfile  # noqa: E402
from shelly.repositories import SmartChargeRepository  # noqa: E402


def _number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--email")
    args = parser.parse_args()
    db = initialize_firestore()
    repo = SmartChargeRepository(db)
    query = db.collection("ChargeLogs").where("source", "==", history_quality.SHELLY_SOURCE)
    if args.email:
        query = query.where("ownerUid", "==", auth.get_user_by_email(args.email).uid)
    groups: dict[tuple[str, str], list[dict]] = {}
    for snapshot in query.limit(500).stream():
        data = snapshot.to_dict() or {}
        if history_quality.confirmed_end_soc(data) is None or not history_quality.is_visible(data):
            continue
        key = (str(data.get("ownerUid") or ""), str(data.get("vehicleId") or ""))
        if all(key):
            groups.setdefault(key, []).append({"id": snapshot.id, **data})
    now = datetime.now(timezone.utc)
    report = {"mode": "apply" if args.apply else "dry-run", "profiles": []}
    for (uid, vehicle_id), logs in groups.items():
        tag = hashlib.sha256(f"{uid}:{vehicle_id}".encode()).hexdigest()[:8]
        existing = repo.get_personal_profile(uid, vehicle_id)
        if existing is not None and not existing.consent_enabled:
            report["profiles"].append({"profile": tag, "skipped": "consent_disabled"})
            continue
        vehicle = repo.vehicle_for_owner(uid, vehicle_id) or {}
        base = charge_model.default_wh_per_pct(_number(vehicle.get("nominalCapacityWh")),
                                               _number(vehicle.get("stateOfHealth")))
        learned = charge_model.LearnedProfile.from_dict(existing.learned if existing else None)
        decisions = {}
        logs.sort(key=lambda item: as_utc(item.get("endTime")) or now)
        for log in logs:
            session = log.get("smartChargingSession") if isinstance(log.get("smartChargingSession"), dict) else {}
            learned, decision = charge_model.learn(learned, {
                "sessionId": log.get("sessionId") or log["id"],
                "energyWh": history_quality.energy_wh(log) or 0,
                "startPct": _number(log.get("startBatteryPercent")) or _number(session.get("start_soc")) or 0,
                "actualEndPct": history_quality.confirmed_end_soc(log),
                "estimatedEndPct": _number(log.get("estimatedEndSoc")),
                "avgPowerW": _number(log.get("averagePowerW")),
                "at": (as_utc(log.get("endTime")) or now).isoformat(),
            }, base_wh_per_pct=base, now=now)
            decisions[decision] = decisions.get(decision, 0) + 1
        report["profiles"].append({
            "profile": tag, "confirmedLogs": len(logs), "decisions": decisions,
            "baseWhPerPct": round(base, 2) if base else None,
            "learnedWhPerPct": learned.wh_per_pct, "powerW": learned.power_w,
            "socMae": learned.soc_mae, "samples": len(learned.samples),
        })
        if args.apply and learned.samples:
            profile = existing or PersonalChargingProfile(
                owner_uid=uid, vehicle_id=vehicle_id, consent_enabled=True,
                nominal_capacity_wh=_number(vehicle.get("nominalCapacityWh")),
            )
            if existing is None:
                profile.consent_source = "default"
            profile.learned = learned.to_dict()
            profile.valid_sessions = len(learned.samples)
            profile.median_power_w = learned.power_w
            profile.validation_mape = learned.soc_mae
            profile.active = learned.wh_per_pct is not None
            profile.profile_version += 1
            profile.last_trained_at = now
            profile.updated_at = now
            repo.save_personal_profile(profile)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
