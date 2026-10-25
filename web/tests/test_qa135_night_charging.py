"""QA 135 — sạc đêm an toàn (Ultra): late start to finish before waking,
one confirmation, 80–90 %, stricter night limits, urgent alerts."""
from datetime import datetime, time, timedelta, timezone

import pytest

from billing.entitlements import EntitlementService
from shelly import night
from shelly.push_notifications import send_terminal_push, terminal_message
from shelly.service import SmartChargeError
from tests.test_task126_charge_model import _service

VN = timezone(timedelta(hours=7))


def _at(hour, minute=0, day=25):
    return datetime(2026, 10, day, hour, minute, tzinfo=VN).astimezone(timezone.utc)


def test_schedule_finishes_before_waking_and_starts_as_late_as_possible():
    start, finish = night.schedule(_at(22), time(6, 30), 3 * 3600)
    assert finish == _at(6, 10, day=26)
    assert start == _at(3, 10, day=26)
    # Not enough night left: start now (it will end after waking).
    start, finish = night.schedule(_at(4, day=26), time(6, 30), 3 * 3600)
    assert finish == _at(6, 10, day=26) and start == _at(4, day=26)
    # Wake-up already passed today: the next morning.
    start, finish = night.schedule(_at(7), time(6, 30), 3600)
    assert finish == _at(6, 10, day=26)
    assert night.parse_wake("6:30") == time(6, 30) and night.parse_wake("25:00") is None


def _clock_at(clock, when):
    clock.now = when


def _due(service):
    """What the worker does each loop: heartbeat, then the night plans."""
    service.repository.claim_worker_lease("qa-worker", now=service.clock())
    service.repository.publish_worker_heartbeat("qa-worker", healthy=True, now=service.clock())
    return service.run_due_night_plans()


def test_a_busy_moment_retries_instead_of_failing():
    service, _repo, provider, clock = _service()
    _clock_at(clock, _at(22))
    plan = service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    start = datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00"))
    _clock_at(clock, start + timedelta(minutes=1))
    assert service.run_due_night_plans() == 0  # stale heartbeat: worker not ready
    stored = service.night_plan("owner", "car")
    assert stored["state"] == "armed" and stored["lastError"] == "workerUnavailable"
    _clock_at(clock, start + timedelta(minutes=2))
    assert _due(service) == 1 and provider.status.relay is True


def test_arm_needs_confirmation_range_and_a_charger():
    service, _repo, _provider, clock = _service()
    _clock_at(clock, _at(22))
    body = {"wakeAt": "06:30", "targetSoc": 85, "currentSoc": 30, "confirmed": True}
    for bad in ({**body, "confirmed": False}, {**body, "targetSoc": 95}, {**body, "targetSoc": 75},
                {**body, "wakeAt": "6h"}, {**body, "currentSoc": 82}):
        with pytest.raises(SmartChargeError):
            service.arm_night_plan("owner", "car", bad)
    plan = service.arm_night_plan("owner", "car", body)
    assert plan["state"] == "armed" and plan["targetSoc"] == 85 and plan["wakeAt"] == "06:30"
    assert "uid" not in plan
    start = datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00"))
    finish = datetime.fromisoformat(plan["finishBy"].replace("Z", "+00:00"))
    assert finish == _at(6, 10, day=26) and _at(22) < start < finish
    assert service.night_plan("owner", "car")["planId"] == plan["planId"]


def test_worker_starts_the_plan_on_time_through_the_normal_on_path():
    service, repo, provider, clock = _service()
    _clock_at(clock, _at(22))
    plan = service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "targetSoc": 85,
                                                   "currentSoc": 30, "confirmed": True})
    assert _due(service) == 0 and provider.status.relay is False
    _clock_at(clock, datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00")) + timedelta(minutes=1))
    assert _due(service) == 1
    assert provider.status.relay is True and provider.status.timer_remaining > 0
    stored = service.night_plan("owner", "car")
    session = repo.get_session("owner", stored["sessionId"])
    assert stored["state"] == "started"
    assert session.strategy == night.NIGHT_STRATEGY and session.stop_mode == "target"
    assert session.target_soc == 85
    assert _due(service) == 0  # started once


def test_a_late_worker_skips_the_plan_and_alerts():
    service, _repo, provider, clock = _service()
    alerts = []
    service.night_alert = lambda uid, **kw: alerts.append((uid, kw["title"]))
    _clock_at(clock, _at(22))
    plan = service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    start = datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00"))
    _clock_at(clock, start + timedelta(minutes=45))
    assert _due(service) == 0
    assert provider.status.relay is False
    assert service.night_plan("owner", "car")["state"] == "missed"
    assert alerts == [("owner", "Chưa bật được sạc đêm")]


def test_cancel_before_start():
    service, _repo, provider, clock = _service()
    _clock_at(clock, _at(22))
    service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    assert service.cancel_night_plan("owner", "car")["state"] == "cancelled"
    _clock_at(clock, _at(6, 0, day=26))
    assert _due(service) == 0 and provider.status.relay is False


def test_night_is_ultra():
    service, _repo, _provider, clock = _service()
    service.entitlements = EntitlementService(enforced=True)
    _clock_at(clock, _at(22))
    with pytest.raises(SmartChargeError) as caught:
        service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    assert caught.value.code == "premiumRequired" and "Ultra" in caught.value.message


def _started(service, clock):
    _clock_at(clock, _at(22))
    plan = service.arm_night_plan("owner", "car", {"wakeAt": "06:30", "currentSoc": 30, "confirmed": True})
    _clock_at(clock, datetime.fromisoformat(plan["startAt"].replace("Z", "+00:00")))
    _due(service)
    return service.night_plan("owner", "car")["sessionId"]


def _reconcile(service, provider):
    """What the worker does each poll for the running session."""
    session = service.repository.current_session("owner", device_id=provider.status.device_id)
    binding = service.session_binding("owner", session)
    service._apply_safety("owner", binding, provider.get_status(binding), [session])
    return service.repository.get_session("owner", session.session_id)


def test_night_cuts_at_60_degrees_not_75():
    service, repo, provider, clock = _service()
    session_id = _started(service, clock)
    provider.status.power_w = 440
    provider.status.temperature_c = 62
    _reconcile(service, provider)
    assert provider.status.relay is True  # one sample is not enough
    clock.advance(seconds=30)
    _reconcile(service, provider)
    assert provider.status.relay is False
    assert repo.get_session("owner", session_id).stop_reason == "night_safety_cutoff"


def test_night_cuts_at_once_far_past_the_prediction():
    service, repo, provider, clock = _service()
    session_id = _started(service, clock)
    provider.status.power_w = 440
    session = repo.get_session("owner", session_id)
    clock.advance(seconds=int(session.predicted_duration_seconds * 1.3) + 16 * 60)
    try:
        _reconcile(service, provider)
    except SmartChargeError:
        pass
    assert provider.status.relay is False
    assert repo.get_session("owner", session_id).stop_reason == "night_safety_cutoff"


def test_a_day_charge_keeps_the_general_limits():
    from tests.test_task126_charge_model import _start_target
    service, _repo, provider, _clock = _service()
    _start_target(service)
    provider.status.power_w = 440
    provider.status.temperature_c = 62
    _reconcile(service, provider)
    _reconcile(service, provider)
    assert provider.status.relay is True


def test_safety_cutoff_pushes_ring_on_the_urgent_channel():
    sent = []

    class Messaging:
        class MulticastMessage:
            def __init__(self, **kw):
                sent.append(kw)

        class Notification:
            def __init__(self, **kw):
                self.kw = kw

        class AndroidConfig:
            def __init__(self, **kw):
                self.kw = kw

        class AndroidNotification:
            def __init__(self, **kw):
                self.kw = kw

        @staticmethod
        def send_each_for_multicast(message, **_):
            return type("R", (), {"success_count": 1, "failure_count": 0, "responses": []})()

    tokens = {("u1", "phone"): {"token": "t"}}
    send_terminal_push("u1", session_id="s1", state="interrupted", stop_reason="night_safety_cutoff",
                       messaging=Messaging, local_tokens=tokens)
    assert sent[-1]["data"]["urgent"] == "1"
    assert sent[-1]["android"].kw["notification"].kw["channel_id"] == "pinova_urgent"
    send_terminal_push("u1", session_id="s2", state="completed", stop_reason="target_reached",
                       messaging=Messaging, local_tokens=tokens)
    assert "urgent" not in sent[-1]["data"] and sent[-1]["android"] is None
    assert "Sạc đêm đã ngắt" in terminal_message("interrupted", stop_reason="night_safety_cutoff")
