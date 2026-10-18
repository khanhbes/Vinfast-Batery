"""Import an owner's ride log (CSV) as trip-model training data (Task 127).

Same path as the app's "Nhập file chuyến đi (CSV)": every row goes through
``assistant.trip_model.normalize_sample`` and is stored under
``users/{uid}/tripSamples`` for one owned vehicle. Re-running is a no-op
(rows are keyed by ``trip_id``). Training still happens only when the owner
presses "Huấn luyện" in the app.

Dry run (default) prints counts only; ``--apply`` writes::

    python scripts/import_trip_csv.py --email owner@example.com --vehicle VID \\
        --csv path/to/trip3.csv [--apply]
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from assistant import trip_model  # noqa: E402


def _rows(path: Path) -> list[dict]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    who = parser.add_mutually_exclusive_group(required=True)
    who.add_argument("--email")
    who.add_argument("--uid")
    parser.add_argument("--vehicle", default="auto",
                        help="vehicle id; 'auto' = the account's only active vehicle")
    parser.add_argument("--csv", required=True, type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    rows = _rows(args.csv)
    valid = [row for row in rows if trip_model.normalize_sample(row) is not None]
    km = sum(float(trip_model.normalize_sample(row)["distanceKm"]) for row in valid)
    print(f"rows={len(rows)} valid={len(valid)} rejected={len(rows) - len(valid)} km={km:.1f}")
    if not args.apply:
        print("dry run: nothing written (add --apply)")
        return 0

    import firebase_admin
    from firebase_admin import auth, firestore

    from shelly.repositories import SmartChargeRepository
    from shelly.service import SmartChargeService

    firebase_admin.initialize_app()
    uid = args.uid or auth.get_user_by_email(args.email).uid
    print(f"owner=uid#{hashlib.sha256(uid.encode()).hexdigest()[:8]}")
    db = firestore.client()
    if args.vehicle == "auto":
        active = []
        for snapshot in db.collection("Vehicles").where("ownerUid", "==", uid).limit(20).stream():
            data = snapshot.to_dict() or {}
            if data.get("isDeleted") or data.get("isArchived") or data.get("archivedAt"):
                continue
            active.append((snapshot.id, data.get("vinfastModelId") or data.get("vehicleName") or "?"))
        if len(active) != 1:
            print("pick one with --vehicle:", [(vid, model) for vid, model in active])
            return 2
        args.vehicle = active[0][0]
        print(f"vehicle={args.vehicle} model={active[0][1]}")
    service = SmartChargeService(SmartChargeRepository(db), None, None)
    total = {"added": 0, "duplicates": 0, "rejected": 0}
    for start in range(0, len(rows), 500):
        batch = rows[start:start + 500]
        for row in batch:
            if row.get("trip_id"):
                row["clientId"] = row["trip_id"]
        result = service.add_trip_samples(uid, args.vehicle, batch, source="csv")
        for key in total:
            total[key] += int(result[key])
    status = service.learning_status(uid, args.vehicle)["trip"]
    print(f"added={total['added']} duplicates={total['duplicates']} rejected={total['rejected']} "
          f"pending={status['pending']} ready={status['ready']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
