"""Shadow mode promotion evaluator for Smart Charge.

Assesses whether a vehicle or user is ready to be promoted from Shadow Mode
(monitor only) to Live Mode (automatic relay cutoff).
"""
from __future__ import annotations

from typing import Any


PROMOTION_CRITERIA = {
    "min_successful_sessions": 5,      # Tối thiểu 5 phiên hoàn thành
    "min_days_in_shadow": 3,           # Tối thiểu 3 ngày chạy shadow
    "max_safety_events_allowed": 0,    # Không được có safety event nào
    "max_relay_fail_rate": 0.0,        # Không relay failure
    "max_mape_pct": 20.0,              # Sai số MAPE <= 20% (độ chính xác >= 80%)
}


def evaluate_shadow_promotion(sessions: list[Any]) -> dict[str, Any]:
    """Evaluate a list of historical ChargingSession objects or dicts for promotion readiness.
    
    Returns:
    {
        "ready": bool,
        "criteria": {
            "successful_sessions": {"current": int, "required": int, "met": bool},
            "days_in_shadow": {"current": float, "required": int, "met": bool},
            "safety_events": {"current": int, "required": int, "met": bool},
            "relay_failures": {"current": int, "required": int, "met": bool},
            "mape_pct": {"current": float | None, "required": float, "met": bool},
        },
        "missing": list[str],
    }
    """
    if not sessions:
        return {
            "ready": False,
            "criteria": {
                "successful_sessions": {"current": 0, "required": 5, "met": False},
                "days_in_shadow": {"current": 0.0, "required": 3, "met": False},
                "safety_events": {"current": 0, "required": 0, "met": True},
                "relay_failures": {"current": 0, "required": 0, "met": True},
                "mape_pct": {"current": None, "required": 20.0, "met": False},
            },
            "missing": ["Chưa có phiên sạc nào được ghi nhận."],
        }

    successful = 0
    safety_events_count = 0
    relay_failures = 0
    timestamps: list[float] = []
    mape_errors: list[float] = []

    for s in sessions:
        # Support both object and dict
        state = getattr(s, "state", None) or (s.get("state") if isinstance(s, dict) else "")
        created_at = getattr(s, "created_at", None) or (s.get("created_at") if isinstance(s, dict) else None)
        stopped_at = getattr(s, "stopped_at", None) or (s.get("stopped_at") if isinstance(s, dict) else None)
        events = getattr(s, "safety_events", None) or (s.get("safety_events") if isinstance(s, dict) else [])
        last_error = getattr(s, "last_error", None) or (s.get("last_error") if isinstance(s, dict) else None)
        predicted_minutes = getattr(s, "predicted_minutes", None) or (s.get("predicted_minutes") if isinstance(s, dict) else 0)

        if state == "completed":
            successful += 1
            if created_at and stopped_at:
                try:
                    t_start = created_at.timestamp() if hasattr(created_at, "timestamp") else float(created_at)
                    t_end = stopped_at.timestamp() if hasattr(stopped_at, "timestamp") else float(stopped_at)
                    actual_min = max(1.0, (t_end - t_start) / 60)
                    if predicted_minutes and predicted_minutes > 0:
                        err = abs(actual_min - predicted_minutes) / predicted_minutes * 100
                        mape_errors.append(err)
                except (ValueError, TypeError, AttributeError):
                    pass

        if events:
            safety_events_count += len(events)
        if last_error and ("relay" in str(last_error).lower() or "verification" in str(last_error).lower()):
            relay_failures += 1

        if created_at:
            try:
                t = created_at.timestamp() if hasattr(created_at, "timestamp") else float(created_at)
                timestamps.append(t)
            except (ValueError, TypeError, AttributeError):
                pass

    days_in_shadow = 0.0
    if len(timestamps) >= 2:
        days_in_shadow = round((max(timestamps) - min(timestamps)) / 86400, 1)

    avg_mape = round(sum(mape_errors) / len(mape_errors), 1) if mape_errors else None

    met_sessions = successful >= PROMOTION_CRITERIA["min_successful_sessions"]
    met_days = days_in_shadow >= PROMOTION_CRITERIA["min_days_in_shadow"]
    met_safety = safety_events_count <= PROMOTION_CRITERIA["max_safety_events_allowed"]
    met_relay = relay_failures <= PROMOTION_CRITERIA["max_relay_fail_rate"]
    met_mape = (avg_mape is not None) and (avg_mape <= PROMOTION_CRITERIA["max_mape_pct"])

    missing: list[str] = []
    if not met_sessions:
        missing.append(f"Cần tối thiểu {PROMOTION_CRITERIA['min_successful_sessions']} phiên sạc thành công (hiện có {successful}).")
    if not met_days:
        missing.append(f"Cần tối thiểu {PROMOTION_CRITERIA['min_days_in_shadow']} ngày chạy thử nghiệm (hiện tại {days_in_shadow} ngày).")
    if not met_safety:
        missing.append(f"Có {safety_events_count} sự cố an toàn cần kiểm tra xử lý.")
    if not met_relay:
        missing.append(f"Có {relay_failures} lần lỗi relay.")
    if not met_mape:
        mape_str = f"{avg_mape}%" if avg_mape is not None else "chưa đủ dữ liệu"
        missing.append(f"Độ chính xác AI (MAPE) cần <= 20% (hiện tại: {mape_str}).")

    ready = met_sessions and met_days and met_safety and met_relay and met_mape

    return {
        "ready": ready,
        "criteria": {
            "successful_sessions": {
                "current": successful,
                "required": PROMOTION_CRITERIA["min_successful_sessions"],
                "met": met_sessions,
            },
            "days_in_shadow": {
                "current": days_in_shadow,
                "required": PROMOTION_CRITERIA["min_days_in_shadow"],
                "met": met_days,
            },
            "safety_events": {
                "current": safety_events_count,
                "required": PROMOTION_CRITERIA["max_safety_events_allowed"],
                "met": met_safety,
            },
            "relay_failures": {
                "current": relay_failures,
                "required": int(PROMOTION_CRITERIA["max_relay_fail_rate"]),
                "met": met_relay,
            },
            "mape_pct": {
                "current": avg_mape,
                "required": PROMOTION_CRITERIA["max_mape_pct"],
                "met": met_mape,
            },
        },
        "missing": missing,
    }
