from datetime import datetime, timezone, timedelta
from shelly.shadow_promotion import evaluate_shadow_promotion
from shelly.recovery_worker import run_recovery
from shelly.models import ChargingSession, DeviceBinding, DeviceStatus, SmartChargeSafetyEvent


class MockRepository:
    def __init__(self, sessions):
        self._sessions = sessions

    def list_all_active_sessions(self):
        return [
            {"owner_uid": "user1", "vehicle_id": "v1", "session_id": s.session_id}
            for s in self._sessions
        ]


class MockService:
    def __init__(self):
        self.recovered = []

    def recover(self, uid, vehicle_id=None):
        self.recovered.append((uid, vehicle_id))
        return ChargingSession(
            session_id="rec_1",
            device_id="d1",
            vehicle_id=vehicle_id or "v1",
            state="completed",
            start_soc=20.0,
            target_soc=80.0,
            predicted_minutes=60,
            predicted_duration_seconds=3600,
            prediction_source="ai_model",
            prediction_confidence=90.0,
            created_at=datetime.now(timezone.utc),
            updated_at=datetime.now(timezone.utc),
            ai_stop_at=datetime.now(timezone.utc),
            effective_stop_at=datetime.now(timezone.utc),
            absolute_safety_stop_at=datetime.now(timezone.utc),
            idempotency_key="key",
        )


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


def test_recovery_worker():
    s = ChargingSession(
        session_id="s1",
        device_id="d1",
        vehicle_id="v1",
        state="active",
        start_soc=20.0,
        target_soc=80.0,
        predicted_minutes=60,
        predicted_duration_seconds=3600,
        prediction_source="ai_model",
        prediction_confidence=90.0,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
        ai_stop_at=datetime.now(timezone.utc),
        effective_stop_at=datetime.now(timezone.utc),
        absolute_safety_stop_at=datetime.now(timezone.utc),
        idempotency_key="key",
    )
    repo = MockRepository([s])
    service = MockService()
    stats = run_recovery(service, repo)
    assert stats["scanned"] == 1
    assert stats["recovered"] == 1
    assert len(service.recovered) == 1
