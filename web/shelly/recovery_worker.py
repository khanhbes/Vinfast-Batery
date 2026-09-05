"""Startup recovery worker for Smart Charge sessions.

When the web server or cloud service restarts, this worker checks all
active charging sessions, verifies the real hardware state on Shelly,
and brings Firestore sessions to a consistent terminal or active state.
"""
from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("SmartChargeRecoveryWorker")


def run_recovery(service: Any, repository: Any) -> dict[str, int]:
    """Scan and recover active sessions.
    
    Returns a dict with recovery statistics:
    {"scanned": int, "recovered": int, "errors": int}
    """
    stats = {"scanned": 0, "recovered": 0, "errors": 0}
    try:
        # In Firestore repository, get list of active sessions
        active_sessions = getattr(repository, "list_all_active_sessions", None)
        if callable(active_sessions):
            sessions = active_sessions()
        else:
            logger.info("list_all_active_sessions not implemented on repository; skipping global scan")
            return stats

        stats["scanned"] = len(sessions)
        for item in sessions:
            uid = item.get("owner_uid") or item.get("uid")
            vehicle_id = item.get("vehicle_id")
            if not uid:
                continue
            try:
                recovered = service.recover(uid, vehicle_id=vehicle_id)
                if recovered is not None:
                    stats["recovered"] += 1
                    logger.info("Recovered session %s for user %s: state=%s", recovered.session_id, uid, recovered.state)
            except Exception as exc:
                stats["errors"] += 1
                logger.warning("Failed to recover session for user %s: %s", uid, exc)
    except Exception as exc:
        logger.error("Error during Smart Charge recovery scan: %s", exc)
        stats["errors"] += 1
    return stats
