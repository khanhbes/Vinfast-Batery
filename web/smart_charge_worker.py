"""Smart Charge reconciliation worker.

The Shelly device timer remains the primary cutoff. This worker only reconciles
state and sends a best-effort backup OFF; it never sends ON.
"""
from __future__ import annotations

import time

from shelly.models import utcnow
from shelly.providers import ProviderError


def reconcile_once(service, uid: str):
    session = service.repository.current_session(uid)
    binding = service.binding(uid)
    if not session or not binding:
        return None
    try:
        status = service.provider.get_status(binding)
    except ProviderError:
        return session
    now = utcnow()
    if status.relay and status.timer_remaining <= 0:
        try:
            service.provider.turn_off(binding)
        except ProviderError:
            session.last_error = "relayUnverified"
            service.repository.save_session(uid, session)
            return session
    if not status.relay:
        session.state = "completed" if now >= session.effective_stop_at else "interrupted"
        session.stop_reason = "planned_timer" if session.state == "completed" else "relay_off"
        session.stopped_at = now
        session.updated_at = now
        session.relay_verified = True
        session.version += 1
        service.repository.save_session(uid, session)
    return session


def run_forever(service, user_ids, interval_seconds: int = 15):
    while True:
        for uid in user_ids():
            reconcile_once(service, uid)
        time.sleep(interval_seconds)

