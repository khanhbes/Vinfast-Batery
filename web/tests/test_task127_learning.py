"""Task 127: full-battery tail cutoff, collected data + owner-triggered training,
battery/ODO readings and imported rides."""
from __future__ import annotations

import csv
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from assistant import trip_model
from shelly import charge_model
from shelly.providers.fake import FakeShellyProvider
from shelly.push_notifications import terminal_message
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeError, SmartChargeService

OWNER_RIDES = Path(__file__).parent / "fixtures" / "owner_rides_sample.csv"


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


def _poll(service, provider, clock, *, power, minutes, wh_per_min=None, step=1):
    """Advance in ``step``-minute polls at ``power`` W."""
    session = None
    for _ in range(int(minutes / step)):
        clock.advance(minutes=step)
        provider.status.power_w = power
        provider.status.energy_wh += (wh_per_min if wh_per_min is not None else power / 60) * step
        session = service.current("owner", vehicle_id="car")
        if session is None or session.state != "active":
            break
    return session


# ── full-battery tail ─────────────────────────────────────────────────────

def test_full_tail_needs_real_charging_and_a_sustained_tail():
    t0 = datetime(2026, 10, 16, tzinfo=timezone.utc)
    hold = timedelta(seconds=charge_model.FULL_HOLD_SECONDS)
    # Never charged (peak 30 W): not a full battery.
    assert charge_model.full_tail_update(None, peak_w=30, power_w=20, now=t0) == (None, False)
    since, full = charge_model.full_tail_update(None, peak_w=420, power_w=28, now=t0)
    assert since == t0 and not full
    # 40-60 W keeps waiting without resetting; >= 60 W resets.
    assert charge_model.full_tail_update(since, peak_w=420, power_w=50, now=t0 + hold / 2) == (t0, False)
    assert charge_model.full_tail_update(since, peak_w=420, power_w=90, now=t0 + hold / 2) == (None, False)
    assert charge_model.full_tail_update(since, peak_w=420, power_w=20, now=t0 + hold) == (t0, True)


def test_timer_charge_stops_when_the_charger_tapers_to_full():
    service, repo, provider, clock = _service()
    session = service.manual_on("owner", 6 * 3600, "full-1", vehicle_id="car", current_soc=40)
    assert session.stop_mode == "timer"
    # Constant current, then the owner's described tail: 400 -> 30 -> 20 W.
    # ~24.5 Wh per minute keeps the energy realistic (60 % x ~25 Wh).
    assert _poll(service, provider, clock, power=420, minutes=60, wh_per_min=24.5).state == "active"
    assert _poll(service, provider, clock, power=150, minutes=4).state == "active"
    assert _poll(service, provider, clock, power=32, minutes=2).state == "active"
    done = _poll(service, provider, clock, power=21, minutes=8)
    assert done.state == "completed" and done.stop_reason == "battery_full"
    assert done.estimated_soc == 100 and done.end_soc_source == "taper_full"
    assert provider.status.relay is False
    assert "Pin đã đầy" in terminal_message(done.state, stop_reason=done.stop_reason)
    # The tail is a free label: 100 % at the measured energy, not censored.
    pending = charge_model.LearnedProfile.from_dict(repo.get_personal_profile("owner", "car").learned).pending
    assert len(pending) == 1
    assert pending[0]["labelSource"] == "taper_full" and pending[0]["censored"] is False
    assert pending[0]["actualEndPct"] == 100


def test_unplugged_scooter_is_not_mistaken_for_full():
    service, _repo, provider, clock = _service()
    service.manual_on("owner", 6 * 3600, "full-2", vehicle_id="car", current_soc=40)
    _poll(service, provider, clock, power=420, minutes=30)
    # Abrupt 420 W -> 0 W: the scooter was unplugged, not full. A timed
    # charge keeps its device timer (the owner chose the time).
    session = _poll(service, provider, clock, power=0, minutes=10)
    assert session.state == "active"


def test_target_charge_ends_as_full_when_the_tail_then_stops():
    service, _repo, provider, clock = _service()
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 90, "targetSoc": 100,
                                               "historyPowerW": 440})
    service.start("owner", preview.preview_id, "full-3")
    _poll(service, provider, clock, power=300, minutes=20, wh_per_min=1)  # under the target energy
    _poll(service, provider, clock, power=25, minutes=2, wh_per_min=0.4)
    done = _poll(service, provider, clock, power=3, minutes=6, wh_per_min=0)
    assert done.state == "completed" and done.stop_reason == "battery_full"


# ── collect, then train on demand ─────────────────────────────────────────

def _finished_target_session(service, provider, clock, key, start=20, gain_wh=1559):
    # Starting needs a fresh worker heartbeat (published at real time).
    clock.now = max(clock.now - timedelta(minutes=10), datetime.now(timezone.utc))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": start, "targetSoc": 80,
                                               "historyPowerW": 440})
    session = service.start("owner", preview.preview_id, key)
    provider.status.power_w = 440
    provider.status.energy_wh += gain_wh
    # Target energy decides the cut; keep the clock near the worker heartbeat.
    clock.advance(minutes=5)
    done = service.current("owner", vehicle_id="car")
    assert done.state == "completed"
    return session


def test_confirmations_wait_for_training_and_report_readiness():
    service, repo, provider, clock = _service()
    for index, end in enumerate((79, 80)):
        session = _finished_target_session(service, provider, clock, f"c{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
        clock.advance(minutes=1)
    status = service.learning_status("owner", "car")["charge"]
    assert status["pending"] == 2 and status["ready"] and status["whPerPct"] is None
    result = service.train_model("owner", "car", "charge", "finetune")
    assert result["report"]["decision"] == "promoted" and result["report"]["added"] == 2
    after = result["status"]["charge"]
    assert after["pending"] == 0 and after["whPerPct"] == pytest.approx(26.2, abs=0.3)
    assert after["required"] == charge_model.TRAINING_MIN_NEW_SAMPLES
    with pytest.raises(SmartChargeError) as caught:
        service.train_model("owner", "car", "charge", "finetune")
    assert caught.value.code == "nothingNew"
    # Retrain is always allowed and keeps the data.
    again = service.train_model("owner", "car", "charge", "retrain")
    assert again["report"]["mode"] == "retrain" and again["report"]["used"] == 2


def test_training_respects_the_personal_ai_switch():
    service, _repo, _provider, _clock = _service()
    service.update_personal_consent("owner", "car", False)
    with pytest.raises(SmartChargeError) as caught:
        service.train_model("owner", "car", "charge")
    assert caught.value.code == "consentDisabled"


def test_charge_train_keeps_a_proven_profile_when_new_data_is_worse():
    now = datetime(2026, 10, 16, tzinfo=timezone.utc)
    profile = charge_model.LearnedProfile()
    for index in range(4):
        profile, _ = charge_model.learn(profile, {
            "sessionId": f"good-{index}", "energyWh": 26.0 * 50, "startPct": 20,
            "actualEndPct": 70, "at": now.isoformat()}, base_wh_per_pct=26.0, now=now)
    for index in range(3):
        profile, decision = charge_model.queue_sample(profile, {
            "sessionId": f"odd-{index}", "energyWh": 26.0 * 50, "startPct": 20,
            "actualEndPct": 58, "at": now.isoformat()}, base_wh_per_pct=26.0, now=now)
        assert decision == "queued"
    assert profile.wh_per_pct == pytest.approx(26.0)  # queued data changes nothing
    trained, report = charge_model.train(profile, base_wh_per_pct=26.0, now=now)
    assert report["decision"] in ("promoted", "rejected_worse")
    assert trained.pending == [] and len(trained.samples) == 7


# ── battery / ODO readings ────────────────────────────────────────────────

def test_two_readings_without_a_charge_become_a_ride():
    service, repo, _provider, clock = _service()
    service.add_battery_reading("owner", "car", {"soc": 80, "odoKm": 1000, "source": "photo"})
    clock.advance(hours=5)
    result = service.add_battery_reading("owner", "car", {"soc": 62, "odoKm": 1021.5, "source": "chat"})
    ride = result["segment"]
    assert ride["source"] == "odo_segment" and ride["distanceKm"] == 21.5 and ride["socUsed"] == 18
    assert result["training"]["trip"]["pending"] == 1
    with pytest.raises(SmartChargeError) as caught:
        service.add_battery_reading("owner", "car", {"odoKm": 990})
    assert caught.value.code == "odoDecreased"
    # Undo voids the reading and drops its ride.
    service.void_battery_reading("owner", "car", result["reading"]["id"])
    assert service.learning_status("owner", "car")["trip"]["pending"] == 0


def test_a_charge_between_readings_is_not_a_ride():
    service, _repo, provider, clock = _service()
    service.add_battery_reading("owner", "car", {"soc": 30, "odoKm": 1000})
    _finished_target_session(service, provider, clock, "between")
    result = service.add_battery_reading("owner", "car", {"soc": 75, "odoKm": 1004})
    assert result["segment"] is None


def test_reading_validation():
    service, _repo, _provider, _clock = _service()
    for body, code in (({}, "readingEmpty"), ({"soc": 140}, "invalidSoc"), ({"odoKm": -3}, "invalidOdo")):
        with pytest.raises(SmartChargeError) as caught:
            service.add_battery_reading("owner", "car", body)
        assert caught.value.code == code
    with pytest.raises(SmartChargeError):
        service.add_battery_reading("owner", "someone-else", {"soc": 50})


# ── rides: owner's CSV, recorded trips and trip training ──────────────────

def _owner_rows():
    with OWNER_RIDES.open(encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def test_owner_csv_import_is_idempotent_and_trains_the_trip_model():
    service, _repo, _provider, _clock = _service()
    rows = _owner_rows()
    first = service.add_trip_samples("owner", "car", rows, source="csv")
    assert first["accepted"] == len(rows) and first["added"] == len(rows) and first["rejected"] == 0
    again = service.add_trip_samples("owner", "car", rows, source="csv")
    assert again["added"] == 0 and again["duplicates"] == len(rows)
    status = again["training"]["trip"]
    assert status["pending"] == len(rows) and status["ready"]
    assert status["sources"] == {"csv": len(rows)}
    result = service.train_model("owner", "car", "trip")
    report = result["report"]
    assert report["used"] == len(rows) and report["decision"] in ("promoted", "rejected_worse")
    evaluation = report["evaluation"]
    assert evaluation["testSet"] == "new" and evaluation["currentSawTest"] is False
    assert evaluation["new"]["n"] == len(rows) and evaluation["flat"]["mae"] > 0
    assert result["status"]["trip"]["pending"] == 0


def test_recorded_trip_and_bad_rows():
    service, _repo, _provider, _clock = _service()
    result = service.add_trip_samples("owner", "car", [
        {"clientId": "t1", "distanceKm": 12.4, "startSoc": 70, "endSoc": 59, "durationMin": 34,
         "riders": 2, "payloadKg": 127, "weather": "rain", "predictedUsePct": 11.6},
        {"clientId": "t2", "distanceKm": 0.1, "socUsed": 1},  # too short
        {"clientId": "t3", "distanceKm": 10, "socUsed": 80},  # 8 %/km: a typo
    ], source="trip")
    assert result["accepted"] == 1 and result["rejected"] == 2
    with pytest.raises(SmartChargeError):
        service.add_trip_samples("owner", "car", [], source="trip")


def test_trip_training_on_the_owners_rides_beats_a_flat_km_per_percent():
    rows = [trip_model.normalize_sample(row) for row in _owner_rows()]
    flat = trip_model.TripModelParams(ref_pct_per_km=1 / 1.2, speed=0, speed2=0,
                                      load_per_10kg=0, rain=0)
    flat_error = sum(abs(trip_model.predict_use(flat, row) - row["socUsed"]) for row in rows) / len(rows)
    # Against a flat km/% in use, the fitted model wins on unseen rides.
    fitted, report = trip_model.train_trip_model(rows, flat, mode="retrain")
    evaluation = report["evaluation"]
    # Out-of-fold error on rides the new model never saw, vs a flat km/%.
    assert evaluation["new"]["mae"] < evaluation["flat"]["mae"] < flat_error + 0.1
    assert evaluation["new"]["n"] == len(rows) and len(evaluation["examples"]) == 8
    assert report["decision"] == "promoted" and fitted.source == "model"
    assert evaluation["new"]["mae"] < evaluation["current"]["mae"]
    # The shipped prior was fitted on these very rides: refitting is not
    # better on them, so the model in use is kept (honest report).
    prior = trip_model.params_from_km_per_pct(1.2, "catalog")
    kept, report = trip_model.train_trip_model(rows, prior, mode="retrain")
    assert report["decision"] == "rejected_worse" and kept is prior


def test_history_mixes_legacy_naive_and_aware_timestamps():
    """Real ChargeLogs: old rows have naive times; status must not crash."""
    service, repo, provider, clock = _service()
    _finished_target_session(service, provider, clock, "aware")
    legacy = next(iter(repo._sessions["owner"].values()))
    from copy import deepcopy
    old = deepcopy(legacy)
    old.session_id = "legacy-naive"
    old.created_at = legacy.created_at.replace(tzinfo=None) - timedelta(days=3)
    old.stopped_at = old.created_at + timedelta(hours=2)
    repo._sessions["owner"][old.session_id] = old
    assert [item.session_id for item in repo.history("owner")][-1] == "legacy-naive"
    assert service.learning_status("owner", "car")["trip"]["pending"] == 0


def test_charge_training_reports_an_objective_comparison():
    service, repo, provider, clock = _service()
    for index, end in enumerate((79, 80, 78)):
        session = _finished_target_session(service, provider, clock, f"e{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    status = service.learning_status("owner", "car")["charge"]
    assert len(status["pendingSamples"]) == 3 and status["samples"] == []
    report = service.train_model("owner", "car", "charge")["report"]
    evaluation = report["evaluation"]
    # Nothing trained before: no "current" score, new vs catalog default.
    assert evaluation["current"]["n"] == 0 and evaluation["new"]["n"] == 3
    assert evaluation["base"]["n"] == 3 and len(evaluation["examples"]) == 3
    row = evaluation["examples"][0]
    assert row["tested"] and row["actual"] in (79, 80, 78) and row["new"] is not None
    after = service.learning_status("owner", "car")["charge"]
    assert len(after["samples"]) == 3 and after["pendingSamples"] == []


def test_charge_log_summary_repairs_a_stale_embedded_session():
    """12/09 showed 0 Wh and naive local times from an older embedded copy."""
    from shelly.repositories import _session_from_charge_log
    start = datetime(2026, 9, 12, 14, 12, 13, tzinfo=timezone.utc)
    end = datetime(2026, 9, 12, 17, 46, 21, tzinfo=timezone.utc)
    service, repo, provider, clock = _service()
    embedded = _finished_target_session(service, provider, clock, "stale").to_dict()
    embedded.update({"created_at": "2026-09-12T21:12:13.407373", "started_at": None,
                     "energy_used_wh": 0.0})
    session = _session_from_charge_log({
        "smartChargingSession": embedded, "startTime": start, "endTime": end,
        "energyWh": 1555.97, "gridEnergyWh": 1555.97, "vehicleId": "car",
        "source": "shelly_smart_charging"}, "doc", "owner")
    assert session.created_at == start and session.created_at.tzinfo is not None
    assert session.energy_used_wh == pytest.approx(1555.97)
