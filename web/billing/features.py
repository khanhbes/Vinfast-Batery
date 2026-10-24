"""Pinova Premium tiers (QA 135): one table for what each plan unlocks.

The app mirrors this table in ``app/lib/data/models/entitlement.dart`` for
display only; the server decides. Safety and the core (verified start/stop,
timer charging, battery/ODO, dashboard scan, help) are free on every plan
and are never gated here.
"""
from __future__ import annotations

TIERS = ("free", "pro", "ultra")
RANK = {"free": 0, "pro": 1, "ultra": 2}
PAID_TIERS = ("pro", "ultra")
PERIODS = ("month", "year")
PERIOD_DAYS = {"month": 30, "year": 365}
TRIAL_DAYS = 7
# The trial opens everything so the owner sees what Ultra adds.
TRIAL_TIER = "ultra"

# VND, phase 1 shows prices only (no payment yet). No lifetime plan.
PRICES = {
    "pro": {"month": 29000, "year": 249000},
    "ultra": {"month": 49000, "year": 449000},
}

# Minimum tier per feature.
FEATURES = {
    "target_charging": "pro",      # charge to a % with automatic cut-off
    "target_edit": "pro",          # change the target while charging
    "progress_push": "pro",        # realtime "charging now" notifications
    "battery_health": "pro",       # % degradation estimate + guided test
    "appearance": "pro",           # dashboard / charge tab styles
    "history_export": "pro",       # CSV export
    "widget": "pro",
    "learning_train": "ultra",     # personal AI (owner-triggered training)
    "trip_estimate": "ultra",      # range along a route
    "cost_advanced": "ultra",
    "night_charging": "ultra",     # overnight safe charging
    "offpeak_schedule": "ultra",
    "share_vehicle": "ultra",
    "monthly_report": "ultra",
}

# Per-tier numeric limits; ``None`` means no limit.
LIMITS = {
    "assistant_daily": {"free": 10, "pro": 30, "ultra": 100},
    "scan_ai_daily": {"free": 5, "pro": 30, "ultra": 100},
    "history_days": {"free": 30, "pro": None, "ultra": None},
    # Ultra is "unlimited" for people; 10 keeps a hard ceiling for abuse.
    "max_vehicles": {"free": 1, "pro": 2, "ultra": 10},
    "support_daily": {"free": 5, "pro": 5, "ultra": 5},
}


def normalize_tier(value) -> str:
    tier = str(value or "").strip().lower()
    return tier if tier in RANK else "free"


def allows(tier: str, feature: str) -> bool:
    need = FEATURES.get(feature)
    if need is None:
        return True  # not a premium feature
    return RANK[normalize_tier(tier)] >= RANK[need]


def limit(tier: str, name: str):
    return LIMITS[name][normalize_tier(tier)]


def required_tier(feature: str) -> str:
    return FEATURES.get(feature, "free")


def feature_map(tier: str) -> dict[str, bool]:
    return {name: allows(tier, name) for name in FEATURES}


def limit_map(tier: str) -> dict:
    return {name: limit(tier, name) for name in LIMITS}


def discounted(price: int, percent_off: int) -> int:
    """Price after a promo, rounded down to 1.000đ (never below 1.000đ)."""
    value = int(price) * (100 - int(percent_off)) // 100
    return max(1000, value // 1000 * 1000)
