"""Soft-hide junk Shelly charge logs and repair shifted start times (Task 126).

Dry-run is the default and prints counts only (no email, name or uid; owners
appear as a short hash). Nothing is ever deleted:

* junk (``shelly.history_quality``: < 30 Wh and no confirmed %) gets
  ``hiddenAt``/``hiddenBy='system'``/``hiddenReason='junk:<reason>'``;
  ``--restore`` removes exactly those system flags again;
* a log whose embedded runtime session stored naive UTC+7 times (old app
  builds) gets ``startTime`` rebuilt from that session, with the previous
  value kept in ``startTimeRepair`` — only when the embedded stop time is
  exactly the ChargeLog end time + 7 h, which proves the offset.

Usage::

    python scripts/hide_junk_charge_logs.py [--email owner@example.com]
    python scripts/hide_junk_charge_logs.py --apply [--email ...]
    python scripts/hide_junk_charge_logs.py --restore [--email ...]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import firebase_admin  # noqa: E402
from firebase_admin import auth, credentials, firestore  # noqa: E402

from shelly import history_quality  # noqa: E402

LOCAL_OFFSET = timedelta(hours=7)
SCAN_LIMIT = 500


def initialize_firestore():
    if not firebase_admin._apps:
        raw = os.environ.get("FIREBASE_CREDENTIALS_JSON", "").strip()
        if raw:
            firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))
        else:
            path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
            firebase_admin.initialize_app(credentials.Certificate(path)) if path else firebase_admin.initialize_app()
    return firestore.client()


def owner_tag(uid: str) -> str:
    return hashlib.sha256(uid.encode("utf-8")).hexdigest()[:8]


def as_utc(value) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    return None


def naive(value) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is None else None


def start_time_repair(data: dict) -> dict | None:
    """Patch for a log whose startTime came from a naive UTC+7 session."""
    session = data.get("smartChargingSession")
    if not isinstance(session, dict):
        return None
    created, stopped = naive(session.get("created_at")), naive(session.get("stopped_at"))
    end = as_utc(data.get("endTime")) or as_utc(data.get("actualStopAt"))
    start = as_utc(data.get("startTime"))
    if not (created and stopped and end and start):
        return None
    # Proof of the offset: the naive stop is the real end shifted by +7 h.
    if abs((stopped - end.replace(tzinfo=None)) - LOCAL_OFFSET) > timedelta(seconds=2):
        return None
    real_start = (created - LOCAL_OFFSET).replace(tzinfo=timezone.utc)
    if abs(real_start - start) < timedelta(minutes=2) or real_start >= end:
        return None
    return {
        "startTime": real_start,
        "startTimeRepair": {
            "version": 1,
            "previousStartTime": start,
            "reason": "naive_utc_plus_7_runtime_session",
            "repairedAt": datetime.now(timezone.utc),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Write the system hide flags and time repairs")
    mode.add_argument("--restore", action="store_true", help="Remove system hide flags written by --apply")
    parser.add_argument("--email", help="Limit to one account (looked up, never printed)")
    args = parser.parse_args()
    db = initialize_firestore()
    query = db.collection("ChargeLogs").where("source", "==", history_quality.SHELLY_SOURCE)
    target_tag = None
    if args.email:
        uid = auth.get_user_by_email(args.email).uid
        target_tag = owner_tag(uid)
        query = query.where("ownerUid", "==", uid)
    report = {
        "mode": "apply" if args.apply else ("restore" if args.restore else "dry-run"),
        "account": target_tag, "scanned": 0, "standard": 0, "active": 0, "junk": {},
        "alreadyHidden": 0, "hiddenNow": 0, "restored": 0, "startTimeRepairs": 0,
        "standardAfter": None, "owners": {},
    }
    snapshots = list(query.limit(SCAN_LIMIT).stream())
    batch, pending = db.batch(), 0

    def queue(ref, patch):
        nonlocal batch, pending
        batch.set(ref, patch, merge=True)
        pending += 1
        if pending >= 400:
            batch.commit()
            batch, pending = db.batch(), 0

    for snapshot in snapshots:
        data = snapshot.to_dict() or {}
        report["scanned"] += 1
        tag = owner_tag(str(data.get("ownerUid") or ""))
        owner = report["owners"].setdefault(tag, {"standard": 0, "junk": 0})
        if args.restore:
            if data.get("hiddenBy") == "system":
                queue(snapshot.reference, {"hiddenAt": firestore.DELETE_FIELD,
                                           "hiddenBy": firestore.DELETE_FIELD,
                                           "hiddenReason": firestore.DELETE_FIELD})
                report["restored"] += 1
            continue
        kind, reason = history_quality.classify(data)
        if kind == "active":
            report["active"] += 1
            continue
        if kind == "standard":
            report["standard"] += 1
            owner["standard"] += 1
            repair = start_time_repair(data)
            if repair:
                report["startTimeRepairs"] += 1
                if args.apply:
                    queue(snapshot.reference, repair)
            continue
        owner["junk"] += 1
        report["junk"][reason] = report["junk"].get(reason, 0) + 1
        if history_quality.is_hidden(data):
            report["alreadyHidden"] += 1
            continue
        if args.apply:
            queue(snapshot.reference, {"hiddenAt": datetime.now(timezone.utc), "hiddenBy": "system",
                                       "hiddenReason": f"junk:{reason}"})
            report["hiddenNow"] += 1
    if pending:
        batch.commit()
    if args.apply:
        # Re-read and prove that no standard session was hidden.
        after = [item.to_dict() or {} for item in query.limit(SCAN_LIMIT).stream()]
        report["standardAfter"] = sum(1 for item in after if history_quality.is_visible(item)
                                      and history_quality.classify(item)[0] == "standard")
    report["scanLimitReached"] = len(snapshots) >= SCAN_LIMIT
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if args.apply and report["standardAfter"] != report["standard"]:
        print("ERROR: visible standard count changed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
