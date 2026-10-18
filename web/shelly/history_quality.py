"""Charge-history quality rules shared by the API, scripts and the app.

A "junk" log is a session that delivered (almost) no energy and carries no
user-confirmed battery reading: relay tests without a load, double taps,
commands cancelled within seconds. It is hidden from normal history and from
training, never deleted (Task 126). The Dart twin lives in
``app/lib/data/services/charge_history_quality.dart``; both are checked
against ``tests/fixtures/charge_history_quality_vectors.json``.
"""

from __future__ import annotations

JUNK_MAX_ENERGY_WH = 30.0
SHELLY_SOURCE = "shelly_smart_charging"
NONTERMINAL_STATES = frozenset({"arming", "starting", "active", "stopping", "unknown"})


def _number(value) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None  # NaN guard


def energy_wh(log: dict) -> float | None:
    session = log.get("smartChargingSession")
    session = session if isinstance(session, dict) else {}
    for value in (log.get("gridEnergyWh"), log.get("energyWh"),
                  session.get("energy_used_wh")):
        number = _number(value)
        if number is not None:
            return max(0.0, number)
    kwh = _number(log.get("energyKwh"))
    return max(0.0, kwh * 1000) if kwh is not None else None


def confirmed_end_soc(log: dict) -> float | None:
    session = log.get("smartChargingSession")
    session = session if isinstance(session, dict) else {}
    for value in (log.get("actualEndSoc"), log.get("confirmedEndSoc"),
                  session.get("actual_end_soc")):
        number = _number(value)
        if number is not None and 0 <= number <= 100:
            return number
    return None


def state(log: dict) -> str:
    session = log.get("smartChargingSession")
    session = session if isinstance(session, dict) else {}
    return str(log.get("sessionState") or session.get("state") or log.get("status") or "")


def is_hidden(log: dict) -> bool:
    """User- or system-hidden, deleted or archived."""
    return bool(
        log.get("isDeleted") is True or log.get("isArchived") is True
        or log.get("archivedAt") or log.get("hiddenByUserAt") or log.get("hiddenAt")
    )


def classify(log: dict) -> tuple[str, str]:
    """Return ``("standard"|"junk"|"active", reason)`` for one ChargeLog.

    Only metered Shelly sessions can be junk: a manual log typed by the user
    has no meter and is always kept.
    """
    if log.get("source") not in (None, SHELLY_SOURCE):
        return "standard", "manual"
    if state(log) in NONTERMINAL_STATES:
        return "active", "in_progress"
    if confirmed_end_soc(log) is not None:
        return "standard", "user_confirmed"
    energy = energy_wh(log)
    if energy is None:
        return "junk", "no_energy_data"
    if energy < JUNK_MAX_ENERGY_WH:
        return "junk", "below_min_energy"
    return "standard", "energy"


def is_visible(log: dict) -> bool:
    """Shown in normal history: not hidden and not junk."""
    return not is_hidden(log) and classify(log)[0] != "junk"
