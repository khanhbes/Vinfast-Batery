from datetime import datetime, timezone, timedelta
from shelly.shadow_promotion import evaluate_shadow_promotion
from shelly.models import ChargingSession, DeviceBinding, DeviceStatus, SmartChargeSafetyEvent


def test_shadow_promotion_insufficient_sessions():
    sessions = [
        {
            "state": "completed",
            "created_at": datetime(2026, 9, 1, 10, tzinfo=timezone.utc),
            "stopped_at": datetime(2026, 9, 1, 11, tzinfo=timezone.utc),
            "predicted_minutes": 60,
        }
    ]
    res = evaluate_shadow_promotion(sessions)
    assert res["ready"] is False
    assert res["criteria"]["successful_sessions"]["met"] is False


def test_shadow_promotion_ready():
    now = datetime(2026, 9, 1, 10, tzinfo=timezone.utc)
    sessions = []
    # 5 successful sessions across 4 days, with 60 min predicted, 62 min actual (error ~3.3%)
    for i in range(5):
        t0 = now + timedelta(days=i)
        t1 = t0 + timedelta(minutes=62)
        sessions.append({
            "state": "completed",
            "created_at": t0,
            "stopped_at": t1,
            "predicted_minutes": 60,
            "safety_events": [],
            "last_error": None,
        })
    res = evaluate_shadow_promotion(sessions)
    assert res["ready"] is True
    assert res["criteria"]["successful_sessions"]["met"] is True
    assert res["criteria"]["days_in_shadow"]["met"] is True
    assert res["criteria"]["mape_pct"]["met"] is True
    assert len(res["missing"]) == 0
