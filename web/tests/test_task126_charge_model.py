"""Task 126: unified charge model, target cutoff, learning and junk history."""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

import smart_charge_worker
from shelly import charge_model, history_quality
from shelly.providers.fake import FakeShellyProvider
from shelly.push_notifications import terminal_message
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeError, SmartChargeService

FIXTURES = Path(__file__).parent / "fixtures"


def _vectors(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


# ── history quality (shared with the app) ────────────────────────────────

@pytest.mark.parametrize("vector", _vectors("charge_history_quality_vectors.json")["vectors"],
                         ids=lambda item: item["name"])
def test_history_quality_vectors(vector):
    assert history_quality.classify(vector["log"]) == (vector["expect"], vector["reason"])


@pytest.mark.parametrize("vector", _vectors("charge_history_quality_vectors.json")["hidden"])
def test_hidden_vectors(vector):
    assert history_quality.is_hidden(vector["log"]) is vector["hidden"]


# ── charge model ─────────────────────────────────────────────────────────

@pytest.mark.parametrize("vector", _vectors("charge_model_vectors.json")["estimates"],
                         ids=lambda item: item["name"])
def test_charge_model_estimate_vectors(vector):
    params = charge_model.ChargeParams(**vector["params"])
    result = charge_model.estimate(params, vector["start"], vector["target"])
    assert result.seconds == vector["seconds"]
    assert charge_model.ceiling_seconds(result.seconds, 600) == vector["ceilingSeconds"]


def test_default_wh_per_pct_uses_capacity_soh_and_efficiency():
    assert charge_model.default_wh_per_pct(2340) == pytest.approx(26.0)
    assert charge_model.default_wh_per_pct(2340, 90) == pytest.approx(23.4)
    assert charge_model.default_wh_per_pct(None) is None


def test_learning_from_real_feliz_sessions():
    """Two confirmed readings from the owner's history (Task 126 survey)."""
    base = charge_model.default_wh_per_pct(2600)
    now = datetime(2026, 10, 16, tzinfo=timezone.utc)
    profile = charge_model.LearnedProfile()
    profile, decision = charge_model.learn(profile, {
        "sessionId": "s-0906", "energyWh": 2615.1, "startPct": 0, "actualEndPct": 100,
        "avgPowerW": 434, "at": "2026-09-06T06:43:39+00:00"}, base_wh_per_pct=base, now=now)
    assert decision == "promoted"
    profile, decision = charge_model.learn(profile, {
        "sessionId": "s-0912", "energyWh": 1556.0, "startPct": 22, "actualEndPct": 81,
        "estimatedEndPct": 75.9, "avgPowerW": 440, "at": "2026-09-12T17:46:21+00:00"},
        base_wh_per_pct=base, now=now)
    assert decision == "promoted"
    # The 0 -> 100 reading is censored (an upper bound), the 22 -> 81 one exact.
    assert profile.wh_per_pct == pytest.approx(26.15, abs=0.01)
    assert profile.power_w == pytest.approx(437)
    params = charge_model.params_for(capacity_wh=2600, learned=profile)
    assert params.source == "personal" and params.power_source == "personal"
    # The model now reproduces the confirmed 81 % within 1 %.
    assert charge_model.soc_after(params, 22, 1556.0) == pytest.approx(81, abs=1)


def test_learning_rejects_outliers_and_small_gains():
    base = 26.0
    profile = charge_model.LearnedProfile()
    same, decision = charge_model.learn(profile, {"sessionId": "a", "energyWh": 100,
                                                  "startPct": 50, "actualEndPct": 55}, base_wh_per_pct=base)
    assert decision == "soc_gain_too_small" and same is profile
    same, decision = charge_model.learn(profile, {"sessionId": "b", "energyWh": 3000,
                                                  "startPct": 20, "actualEndPct": 40}, base_wh_per_pct=base)
    assert decision == "outlier" and same.wh_per_pct is None


def test_one_bad_reading_cannot_degrade_a_proven_profile():
    base = 26.0
    now = datetime(2026, 10, 16, tzinfo=timezone.utc)
    profile = charge_model.LearnedProfile()
    for index in range(4):
        profile, _ = charge_model.learn(profile, {
            "sessionId": f"good-{index}", "energyWh": 26.0 * 50, "startPct": 20,
            "actualEndPct": 70, "at": now.isoformat()}, base_wh_per_pct=base, now=now)
    proven = profile.wh_per_pct
    profile, decision = charge_model.learn(profile, {
        # 32.5 Wh/% is inside the plausibility band, so it is not an outlier.
        "sessionId": "bad", "energyWh": 26.0 * 50, "startPct": 20, "actualEndPct": 60,
        "at": now.isoformat()}, base_wh_per_pct=base, now=now)
    # A median ignores one outlier; either way the estimate stays put.
    assert profile.wh_per_pct == pytest.approx(proven)
    assert decision in ("promoted", "rejected_worse")


def test_target_reached_counts_the_poll_lead():
    assert not charge_model.target_reached(1550, 1560, 440, 20)
    assert charge_model.target_reached(1558, 1560, 440, 20)


def test_learn_taper_from_curve():
    curve = [{"wh": i * 7.3, "p": 440} for i in range(40)]
    curve += [{"wh": 292 + i * 4, "p": 250} for i in range(10)]
    taper = charge_model.learn_taper(curve, 80, 26.0)
    assert taper is not None
    start, ratio = taper
    assert 90 <= start <= 92 and ratio == pytest.approx(250 / 440, abs=0.01)


# ── service: target charging end to end ──────────────────────────────────

class _Clock:
    def __init__(self):
        self.now = datetime.now(timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, **kwargs):
        self.now += timedelta(**kwargs)


def _service(capacity=2340):
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("owner")[0]
    binding.vehicle_id = "car"
    repo.register_vehicle_owner("owner", "car", verified_capacity_wh=capacity)
    repo.save_binding("owner", binding)
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    clock = _Clock()
    service = SmartChargeService(repo, provider, None, sleeper=lambda _: None, clock=clock)
    return service, repo, provider, clock


def _start_target(service, target=80, start=20, key="k1"):
    preview = service.create_preview("owner", {
        "vehicleId": "car", "currentSoc": start, "targetSoc": target, "historyPowerW": 440})
    return preview, service.start("owner", preview.preview_id, key)


def test_target_preview_and_start_arm_a_ceiling_timer():
    service, _repo, provider, _clock = _service()
    preview, session = _start_target(service)
    assert preview.stop_mode == "target" and preview.ai_charge_eligible
    assert preview.wh_per_pct == pytest.approx(26.0)
    assert preview.power_source == "vehicle"
    # 60 % x 26 Wh / 440 W = 3.545 h; ceiling = x1.5 + 20 min.
    assert preview.predicted_duration_seconds == 12764
    assert preview.device_timer_seconds == 20346
    assert provider.status.timer_remaining == 20346
    assert session.strategy == "target_soc" and session.stop_mode == "target"
    assert session.target_energy_wh == pytest.approx(1560)
    assert session.ai_stop_at < session.effective_stop_at <= session.absolute_safety_stop_at


def test_server_cuts_at_target_and_learns_from_the_confirmed_reading():
    service, repo, provider, clock = _service()
    _preview, session = _start_target(service)
    provider.status.power_w = 440
    provider.status.energy_wh += 1000
    clock.advance(minutes=136)
    live = service.current("owner", vehicle_id="car")
    assert live.state == "active"
    assert live.estimated_soc == pytest.approx(20 + 1000 / 26, abs=0.01)
    assert live.telemetry_samples and live.telemetry_samples[-1]["wh"] == pytest.approx(1000)
    provider.status.energy_wh += 559
    clock.advance(minutes=76)
    done = service.current("owner", vehicle_id="car")
    assert done.state == "completed" and done.stop_reason == "target_reached"
    assert provider.status.relay is False
    with pytest.raises(SmartChargeError) as caught:
        service.confirm_actual_soc("owner", session.session_id, 150)
    assert caught.value.code == "invalidSoc"
    confirmed = service.confirm_actual_soc("owner", session.session_id, 79, odo_km=1234)
    # Task 127: the reading is collected; the estimate waits for training.
    assert confirmed.training_state == "queued" and confirmed.end_soc_source == "user"
    assert confirmed.soc_error == pytest.approx(80 - 79, abs=0.1)
    assert confirmed.end_odo_km == 1234
    profile = repo.get_personal_profile("owner", "car")
    assert profile.consent_enabled and profile.consent_source == "default"
    assert profile.learned.get("whPerPct") is None and len(profile.learned["pending"]) == 1
    status = service.learning_status("owner", "car")
    assert status["charge"]["pending"] == 1 and status["charge"]["required"] == 2
    assert not status["charge"]["ready"]
    # The owner trains anyway (button is enabled with any new data).
    result = service.train_model("owner", "car", "charge")
    assert result["report"]["decision"] == "promoted"
    profile = repo.get_personal_profile("owner", "car")
    assert profile.learned["whPerPct"] == pytest.approx(1559 / 59, abs=0.01)
    assert profile.learned["pending"] == []
    # The next preview uses what the vehicle taught the model.
    nxt = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 30, "targetSoc": 80})
    assert nxt.model_source == "personal_physics" and nxt.learned_samples == 1
    assert nxt.wh_per_pct == pytest.approx(1559 / 59, abs=0.01)
    assert nxt.power_source == "personal"


def test_learning_respects_an_explicit_opt_out():
    service, repo, provider, clock = _service()
    service.update_personal_consent("owner", "car", False)
    _preview, session = _start_target(service)
    provider.status.power_w = 440
    provider.status.energy_wh += 1600
    clock.advance(hours=4)
    service.current("owner", vehicle_id="car")
    confirmed = service.confirm_actual_soc("owner", session.session_id, 80)
    assert confirmed.training_reason == "consent_disabled"
    assert repo.get_personal_profile("owner", "car").learned == {}


def test_confirm_rejects_an_active_session():
    service, _repo, _provider, _clock = _service()
    _preview, session = _start_target(service)
    with pytest.raises(SmartChargeError) as caught:
        service.confirm_actual_soc("owner", session.session_id, 60)
    assert caught.value.code == "sessionNotFinished"


def test_idle_charger_switches_the_outlet_off():
    service, _repo, provider, clock = _service()
    _start_target(service)
    provider.status.power_w = 0
    clock.advance(seconds=60)
    assert service.current("owner", vehicle_id="car").state == "active"
    clock.advance(seconds=185)
    done = service.current("owner", vehicle_id="car")
    assert done.state == "completed" and done.stop_reason == "charger_idle"
    assert provider.status.relay is False


def test_ceiling_timer_is_reported_as_interrupted():
    service, _repo, provider, clock = _service()
    _preview, session = _start_target(service)
    provider.status.power_w = 300
    clock.advance(seconds=session.hardware_timeout_seconds + 5)
    provider.status.relay = False  # the Shelly timer fired
    provider.status.timer_remaining = 0
    done = service.current("owner", vehicle_id="car")
    assert (done.state, done.stop_reason) == ("interrupted", "ceiling_timer")


def test_unsafe_streak_survives_another_process():
    service, repo, provider, clock = _service()
    _start_target(service)
    provider.status.power_w = 2600  # over the 2450 W cutoff
    service.current("owner", vehicle_id="car")
    service.live("owner", "car")
    session = repo.active_sessions("owner")[0] if repo.active_sessions("owner") else None
    # First bad sample is stored on the session; a fresh service (other
    # replica, empty memory) continues the streak and cuts.
    other = SmartChargeService(repo, provider, None, sleeper=lambda _: None, clock=clock)
    other.live("owner", "car")
    assert provider.status.relay is False
    assert session is None or session.unsafe_samples >= 1


# ── worker isolation ─────────────────────────────────────────────────────

def test_one_failing_session_does_not_block_the_others(monkeypatch):
    class _Repo:
        def active_sessions(self, uid, strict=False):
            return [type("S", (), {"session_id": "a"})(), type("S", (), {"session_id": "b"})()]

    class _Service:
        repository = _Repo()

        def session_binding(self, uid, session):
            return object()

    seen = []

    def fake_reconcile(service, uid, session, binding, *, lease_guard=None):
        seen.append(session.session_id)
        if session.session_id == "a":
            raise ValueError("boom")
        return session

    monkeypatch.setattr(smart_charge_worker, "_reconcile_session", fake_reconcile)
    smart_charge_worker.reconcile_once(_Service(), "owner")
    assert seen == ["a", "b"]


def test_lease_loss_still_stops_the_cycle(monkeypatch):
    class _Repo:
        def active_sessions(self, uid, strict=False):
            return [type("S", (), {"session_id": "a"})()]

    class _Service:
        repository = _Repo()

        def session_binding(self, uid, session):
            raise RuntimeError("workerLeaseLost")

    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        smart_charge_worker.reconcile_once(_Service(), "owner")


# ── push copy ────────────────────────────────────────────────────────────

def test_terminal_push_copy_by_stop_reason():
    assert "khoảng 80%" in terminal_message("completed", stop_reason="target_reached", estimated_soc=79.6)
    assert "ngừng nhận điện" in terminal_message("completed", stop_reason="charger_idle")
    assert "giới hạn thời gian an toàn" in terminal_message("interrupted", stop_reason="ceiling_timer")
    assert "hẹn giờ" in terminal_message("completed", stop_reason="planned_timer")


def test_read_only_charge_estimate_for_batterybot():
    service, repo, _provider, _clock = _service()
    estimate = service.estimate_charge("owner", "car", 20, 80, 440)
    assert estimate["minutes"] == round(12764 / 60)
    assert estimate["powerSource"] == "vehicle" and estimate["learnedSamples"] == 0
    assert estimate["safetyCeilingMinutes"] == round(20346 / 60)
    # Nothing stored: no preview can be started from an estimate.
    assert repo._previews.get("owner", {}) == {}


def test_worker_pushes_progress_every_two_minutes_only():
    import threading
    service, _repo, provider, clock = _service()
    sent, ready = [], threading.Event()

    def notifier(uid, *, payload):
        sent.append((uid, payload))
        ready.set()

    service.progress_notifier = notifier
    _start_target(service)
    provider.status.power_w = 440
    provider.status.energy_wh += 520
    clock.advance(minutes=71)
    service.current("owner", vehicle_id="car")
    assert not ready.wait(0.3)  # API / app polls never push
    service._worker_lease_guard = lambda: None
    service.current("owner", vehicle_id="car")
    assert ready.wait(2)
    uid, payload = sent[0]
    assert uid == "owner" and payload["event"] == "smart_charge_progress"
    assert payload["soc"] == "40.0" and payload["targetSoc"] == "80" and payload["powerW"] == "440"
    # 40 -> 80 % x 26 Wh / 440 W = 2.36 h.
    assert int(payload["remainingSeconds"]) == 8509
    ready.clear()
    clock.advance(seconds=60)
    service.current("owner", vehicle_id="car")
    assert not ready.wait(0.3)  # throttled
    clock.advance(seconds=61)
    service.current("owner", vehicle_id="car")
    assert ready.wait(2) and len(sent) == 2


def test_progress_push_is_data_only_high_priority_and_expires():
    from datetime import timedelta as _td
    from shelly.push_notifications import send_progress_push

    class _Messaging:
        def __init__(self):
            self.messages = []

        class AndroidConfig:
            def __init__(self, **kwargs):
                self.kwargs = kwargs

        class MulticastMessage:
            def __init__(self, **kwargs):
                self.kwargs = kwargs

        def send_each_for_multicast(self, message, **_):
            self.messages.append(message)
            return type("R", (), {"success_count": len(message.kwargs["tokens"]), "failure_count": 0})()

    messaging = _Messaging()
    result = send_progress_push("u1", payload={"sessionId": "s1", "soc": 50.5}, messaging=messaging,
                                local_tokens={("u1", "d1"): {"token": "t1"}, ("u2", "d2"): {"token": "t2"}})
    assert result == {"sent": 1, "failed": 0}
    message = messaging.messages[0].kwargs
    assert message["tokens"] == ["t1"] and message["data"] == {"sessionId": "s1", "soc": "50.5"}
    assert "notification" not in message
    android = message["android"].kwargs
    assert android["priority"] == "high" and android["ttl"] == _td(seconds=150)
    assert android["collapse_key"] == "progress-s1"


# ── ride-through: Shelly unreachable while charging ──────────────────────

def _offline_service():
    import threading
    service, repo, provider, clock = _service()
    events, ready = [], threading.Event()

    def notifier(uid, *, payload):
        events.append(payload)
        ready.set()

    service.progress_notifier = notifier
    _preview, session = _start_target(service)
    provider.status.power_w = 440
    return service, repo, provider, clock, session, events, ready


def test_wifi_blip_never_cuts_a_healthy_charge():
    service, repo, provider, clock, session, _events, _ready = _offline_service()
    commands = provider.command_count
    provider.status.online = False  # Wi-Fi / Cloud drop
    clock.advance(seconds=30)
    lost = smart_charge_worker.reconcile_once(service, "owner")
    assert lost.state == "active" and lost.link_lost_since is not None
    assert lost.last_link_error == "deviceOffline" and lost.link_gap_count == 1
    clock.advance(seconds=90)
    smart_charge_worker.reconcile_once(service, "owner")
    provider.status.online = True  # back; the relay kept charging on its own timer
    provider.status.energy_wh += 30
    clock.advance(seconds=30)
    back = smart_charge_worker.reconcile_once(service, "owner")
    assert back.state == "active" and back.link_lost_since is None
    assert back.link_gap_seconds == pytest.approx(120)
    assert back.energy_used_wh == pytest.approx(30)  # energy from the gap is kept
    assert provider.command_count == commands  # no OFF was sent
    assert provider.status.relay is True


def test_long_gap_alerts_once_and_keeps_the_notification_alive():
    service, _repo, provider, clock, _session, events, ready = _offline_service()
    service._worker_lease_guard = lambda: None  # worker process
    provider.status.online = False
    for _ in range(12):  # 6 minutes of failed reads
        clock.advance(seconds=30)
        smart_charge_worker.reconcile_once(service, "owner")
    ready.wait(2)
    import time as _time
    _time.sleep(0.3)
    kinds = [(e["event"], e.get("state") or e.get("link")) for e in events]
    assert kinds.count(("smart_charge_link", "lost")) == 1
    assert ("smart_charge_progress", "lost") in kinds
    provider.status.online = True
    clock.advance(seconds=30)
    smart_charge_worker.reconcile_once(service, "owner")
    _time.sleep(0.3)
    assert ("smart_charge_link", "restored") in [(e["event"], e.get("state")) for e in events]


def test_live_reports_the_gap_with_last_readings():
    service, _repo, provider, clock, session, _events, _ready = _offline_service()
    clock.advance(seconds=70)
    service.live("owner", "car")  # one good sample
    provider.status.online = False
    clock.advance(seconds=30)
    live = service.live("owner", "car")
    assert live["active"] is True and live["link"]["state"] == "lost"
    assert live["status"]["online"] is False and live["status"]["stale"] is True
    assert live["status"]["relay"] is True and live["status"]["power_w"] == 440
    assert live["session"]["state"] == "active"


def test_ceiling_fired_while_offline_is_finalized_on_reconnect():
    service, _repo, provider, clock, session, _events, _ready = _offline_service()
    provider.status.online = False
    clock.advance(seconds=30)
    smart_charge_worker.reconcile_once(service, "owner")
    clock.advance(seconds=session.hardware_timeout_seconds)
    provider.status.online = True
    provider.status.relay = False
    provider.status.timer_remaining = 0
    done = smart_charge_worker.reconcile_once(service, "owner")
    assert (done.state, done.stop_reason) == ("interrupted", "ceiling_timer")


def test_identity_or_auth_failures_still_escalate():
    service, _repo, _provider, _clock, session, _events, _ready = _offline_service()
    result = service.note_read_failure("owner", session, "needsReauthentication")
    assert result.state == "unknown"
