"""QA 148: the whole loop of a charge to a chosen %: a charge to 100 % ends on the
charger's signal, full charges cannot pull Wh/% down alone, everyone's Wh/% follows
their vehicle without a button, and a model is judged on charges it has not seen."""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from shelly import charge_ai, charge_model, learning
from shelly.charge_model import LearnedProfile
from shelly.providers.fake import FakeShellyProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService

SAMPLES = json.loads((Path(__file__).parent / "fixtures" / "owner_charge_samples.json").read_text("utf-8"))
NOW = datetime(2026, 11, 6, 6, 0, tzinfo=timezone.utc)
BASE = charge_model.default_wh_per_pct(2400, 100)


class _Clock:
    def __init__(self):
        self.now = datetime.now(timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, **kwargs):
        self.now += timedelta(**kwargs)


class _Plan:
    def __init__(self, allowed):
        self.allowed = allowed

    def allows(self, uid, feature):
        return feature != "learning_train" or self.allowed


def _service(capacity=2400):
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("owner")[0]
    binding.vehicle_id = "car"
    repo.register_vehicle_owner("owner", "car", verified_capacity_wh=capacity)
    repo.save_binding("owner", binding)
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    clock = _Clock()
    return SmartChargeService(repo, provider, None, sleeper=lambda _: None, clock=clock), repo, provider, clock


def _start(service, clock, key, *, current=20, target=80, **extra):
    # Starting needs a fresh worker heartbeat (published at real time).
    clock.now = max(clock.now - timedelta(minutes=10), datetime.now(timezone.utc))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": current,
                                               "targetSoc": target, "historyPowerW": 440, **extra})
    return preview, service.start("owner", preview.preview_id, key)


def _read(service, provider, clock, power, wh, *, seconds=20):
    clock.advance(seconds=seconds)
    provider.status.power_w = power
    provider.status.energy_wh += wh
    return service.current("owner", vehicle_id="car")


def _finish(service, provider, clock, key, *, current=20, target=80, wh=1600):
    _, session = _start(service, clock, key, current=current, target=target)
    done = _read(service, provider, clock, 440, wh, seconds=300)
    assert done.state == "completed" and done.stop_reason == "target_reached"
    return session


def _learned(repo):
    profile = repo.get_personal_profile("owner", "car")
    return LearnedProfile.from_dict(profile.learned if profile else None)


def _store(service, repo, learned, **fields):
    profile = service.personal_profile("owner", "car")
    profile.consent_enabled = True
    profile.learned = learned.to_dict()
    for name, value in fields.items():
        setattr(profile, name, value)
    repo.save_personal_profile(profile)


# ── a charge to 100 % ──────────────────────────────────────────────────────

def test_a_charge_to_full_is_not_cut_on_energy_and_ends_on_the_charger_signal():
    service, repo, provider, clock = _service()
    _, session = _start(service, clock, "full", current=20, target=100)
    assert session.target_energy_wh == pytest.approx(2133.33, abs=1)
    # Far past the estimate, as the owner's charges were: still charging, not yet 100.
    running = _read(service, provider, clock, 450, 2500, seconds=700)
    assert running.state == "active" and running.estimated_soc == 99
    for power in (178, 136, 87):
        assert _read(service, provider, clock, power, 2).state == "active"
    assert _read(service, provider, clock, 30, 1).state == "active"
    done = _read(service, provider, clock, 25, 2, seconds=310)
    assert done.state == "completed" and done.stop_reason == "battery_full"
    assert done.estimated_soc == 100 and done.end_soc_source == "taper_full"
    assert [item["labelSource"] for item in _learned(repo).pending] == ["taper_full"]


def test_a_charge_to_full_keeps_its_device_timer():
    service, repo, provider, clock = _service()
    preview, session = _start(service, clock, "ceiling", current=20, target=100)
    assert preview.device_timer_seconds == charge_model.ceiling_seconds(
        preview.predicted_duration_seconds, service.max_minutes)
    assert session.hardware_timeout_seconds == preview.device_timer_seconds


def test_any_target_below_full_still_cuts_on_energy():
    service, repo, provider, clock = _service()
    for target in (30, 80, 95, 99):
        _, session = _start(service, clock, f"t{target}", current=20, target=target)
        done = _read(service, provider, clock, 440, session.target_energy_wh + 1, seconds=120)
        assert done.state == "completed" and done.stop_reason == "target_reached", target


def test_no_eta_while_waiting_for_the_charger_full_signal():
    service, repo, provider, clock = _service()
    _, session = _start(service, clock, "eta", current=20, target=100)
    running = _read(service, provider, clock, 450, 2500, seconds=700)
    assert service._remaining_seconds(running, provider.status) is None


# ── Wh/% ───────────────────────────────────────────────────────────────────

def _full(index, wh, *, source="taper_full"):
    return {"sessionId": f"f{index}", "whPerPct": wh, "energyWh": wh * 100, "startPct": 0.0,
            "actualEndPct": 100.0, "censored": source != "taper_full", "labelSource": source,
            "at": (NOW - timedelta(days=index)).isoformat()}


def test_one_full_charge_cannot_pull_the_estimate_but_two_can():
    assert charge_model._robust_wh([_full(1, 22.84)], BASE, NOW) == BASE
    assert charge_model._robust_wh([_full(1, 22.84), _full(2, 23.0)], BASE, NOW) == pytest.approx(23.0)


def test_a_full_charge_counts_the_same_however_it_was_labelled():
    assert (charge_model._robust_wh([_full(1, 22.84, source="user")], BASE, NOW)
            == charge_model._robust_wh([_full(1, 22.84)], BASE, NOW))


def test_the_owner_stays_near_the_value_his_charges_agree_on():
    assert charge_model._robust_wh(SAMPLES, BASE, NOW) == pytest.approx(26.5, abs=0.1)


def test_a_full_charge_is_not_scored_when_training_decides():
    partial = {"sessionId": "p", "whPerPct": 26.5, "energyWh": 1325.0, "startPct": 20.0, "actualEndPct": 70.0,
               "censored": False, "labelSource": "user", "at": NOW.isoformat()}
    profile = LearnedProfile(wh_per_pct=26.5, samples=[partial], pending=[_full(1, 22.84)])
    updated, report = charge_model.train(profile, base_wh_per_pct=BASE, now=NOW)
    # The partial charge is what is scored, and it agrees with 26.5.
    assert report["evaluation"]["testSet"] == "all"
    assert [row["tested"] for row in report["evaluation"]["examples"] if row["actual"] == 100] == [False]
    assert updated.wh_per_pct == pytest.approx(26.5, abs=0.2)


def test_correcting_an_old_charge_does_not_push_out_a_newer_one():
    rows = [{"sessionId": f"s{i}", "whPerPct": 26.0, "energyWh": 1300.0, "startPct": 20.0, "actualEndPct": 70.0,
             "censored": False, "at": (NOW - timedelta(days=20 - i)).isoformat()} for i in range(14)]
    # The oldest was re-read, so it sits last in the queue.
    profile = LearnedProfile(samples=rows[1:], pending=[rows[0]])
    updated, _ = charge_model.train(profile, base_wh_per_pct=BASE, now=NOW)
    assert [item["sessionId"] for item in updated.samples] == [f"s{i}" for i in range(2, 14)]


def test_a_first_training_worse_than_the_catalog_keeps_the_catalog():
    rows = [{"sessionId": f"s{i}", "whPerPct": wh, "energyWh": wh * 50, "startPct": 20.0, "actualEndPct": 70.0,
             "censored": False, "at": NOW.isoformat()} for i, wh in enumerate((34.0, 20.0))]
    updated, report = charge_model.train(LearnedProfile(pending=rows), base_wh_per_pct=BASE, now=NOW)
    assert report["decision"] == "rejected_worse" and updated.wh_per_pct is None
    assert updated.pending == [] and len(updated.samples) == 2


def test_health_reads_none_of_this():
    result = charge_model.battery_health(SAMPLES, 2400)
    assert result["estimate"]["sohPct"] == 99.4 and result["estimate"]["capacityWh"] == 2385


# ── capacity ───────────────────────────────────────────────────────────────

def test_the_vehicle_record_decides_the_capacity_not_the_app():
    service, repo, provider, clock = _service(capacity=2400)
    preview, _ = _start(service, clock, "cap", estimatedCapacityWh=2600)
    assert preview.wh_per_pct == pytest.approx(BASE, abs=0.01)


# ── the offset is spent once ───────────────────────────────────────────────

def test_an_offset_is_not_applied_again_after_a_charge_nobody_labelled():
    service, repo, provider, clock = _service()
    _store(service, repo, LearnedProfile(wh_per_pct=26.0, samples=[], layer="offset", gauge_offset_pct=5.0,
                                         gauge_offset_at=(clock.now - timedelta(days=1)).isoformat()),
           auto_train=False)
    preview, session = _start(service, clock, "a")
    assert preview.soc_correction_pct == 5.0 and session.carried_offset_pct == 5.0
    done = _read(service, provider, clock, 440, session.target_energy_wh + 1, seconds=300)
    assert done.state == "completed"
    assert _learned(repo).gauge_offset_pct == 0.0
    later, _ = _start(service, clock, "b")
    assert later.soc_correction_pct == 0.0


def test_a_label_typed_later_still_scores_what_its_charge_carried():
    service, repo, provider, clock = _service()
    _store(service, repo, LearnedProfile(wh_per_pct=26.0, layer="offset", gauge_offset_pct=5.0,
                                         gauge_offset_at=(clock.now - timedelta(days=1)).isoformat()),
           auto_train=False)
    _, session = _start(service, clock, "a")
    _read(service, provider, clock, 440, session.target_energy_wh + 1, seconds=300)
    service.confirm_actual_soc("owner", session.session_id, 80)
    learned = _learned(repo)
    assert learned.pending[0]["shadowOffsetPct"] == 5.0
    assert learned.gauge_offset_pct != 5.0  # what this charge itself left


def test_a_short_test_does_not_spend_the_offset():
    service, repo, provider, clock = _service()
    _store(service, repo, LearnedProfile(wh_per_pct=26.0, layer="offset", gauge_offset_pct=5.0,
                                         gauge_offset_at=(clock.now - timedelta(days=1)).isoformat()),
           auto_train=False)
    _, session = _start(service, clock, "a")
    clock.advance(seconds=30)
    provider.status.energy_wh += 2
    service.stop("owner", session.session_id, user_stop_reason="none")
    assert _learned(repo).gauge_offset_pct == 5.0


def test_layers_need_the_plan_that_can_train():
    service, repo, provider, clock = _service()
    service.entitlements = _Plan(False)
    _store(service, repo, LearnedProfile(wh_per_pct=26.0, layer="offset", gauge_offset_pct=5.0))
    preview, _ = _start(service, clock, "a")
    assert preview.soc_correction_pct == 0.0


# ── a model is judged on charges it has not seen ───────────────────────────

def _rows(count, *, start_day=0):
    return [{"sessionId": f"c{start_day + i}", "whPerPct": 26.3, "energyWh": 26.3 * 50, "startPct": 20.0,
             "actualEndPct": 70.0, "censored": False, "avgPowerW": 440.0,
             "at": (NOW + timedelta(days=start_day + i)).isoformat()} for i in range(count)]


def _model(weights, at):
    return {"features": list(charge_ai.FEATURES), "weights": weights, "charges": 20, "version": 3, "at": at.isoformat()}


def test_a_model_that_misses_new_charges_is_paused_even_after_a_new_fit():
    rows = _rows(8)
    wrong = _model([5.0, 0, 0, 0, 0, 0], NOW - timedelta(days=1))
    profile = LearnedProfile(wh_per_pct=26.3, ledger=rows, samples=rows, layer="ai", ai_model=wrong)
    updated, report = charge_ai.select_layer(profile, base=BASE, now=NOW + timedelta(days=9))
    assert report["aiDecision"] == "paused_worse" and updated.layer == "base"
    assert updated.ai_model is not None  # the weights stay; a later training tries again
    # Judged on what it was fitted to, the same model looked fine.
    fitted = charge_ai.ridge([s["x"] for s in charge_ai.timeline(rows, BASE)],
                             [s["residual"] for s in charge_ai.timeline(rows, BASE)],
                             prior=wrong["weights"], strength=charge_ai.RIDGE_FINETUNE)
    assert abs(fitted[0]) < abs(wrong["weights"][0])


def test_too_few_new_charges_change_nothing():
    rows = _rows(8)
    model = _model([0.5, 0, 0, 0, 0, 0], NOW + timedelta(days=5, hours=12))
    profile = LearnedProfile(wh_per_pct=26.3, ledger=rows, samples=rows, layer="ai", ai_model=dict(model), layer_mae=1.2)
    updated, report = charge_ai.select_layer(profile, base=BASE, now=NOW + timedelta(days=9))
    assert report["aiDecision"] == "kept" and updated.layer == "ai" and updated.layer_mae == 1.2
    assert updated.ai_model["weights"] == model["weights"] and updated.ai_model["version"] == 3


def test_a_good_model_is_fine_tuned_and_stays():
    rows = _rows(8)
    # The gauge always rises 1 % more than the energy; the model knows.
    rows = [{**item, "actualEndPct": 71.0} for item in rows]
    model = _model([1.0, 0, 0, 0, 0, 0], NOW - timedelta(days=1))
    profile = LearnedProfile(wh_per_pct=26.3, ledger=rows, samples=rows, layer="ai", ai_model=model)
    updated, report = charge_ai.select_layer(profile, base=BASE, now=NOW + timedelta(days=9))
    assert report["aiDecision"] == "finetuned" and updated.layer == "ai" and updated.ai_model["version"] == 4
    assert report["ai"]["n"] == 8


# ── training by itself ─────────────────────────────────────────────────────

def test_enough_readings_train_by_themselves_for_every_plan():
    service, repo, provider, clock = _service()
    service.entitlements = _Plan(False)
    for index, end in enumerate((80, 81)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    profile = repo.get_personal_profile("owner", "car")
    learned = LearnedProfile.from_dict(profile.learned)
    assert learned.wh_per_pct is not None and learned.pending == [] and len(learned.samples) == 2
    assert profile.training_reports["charge"]["auto"] is True
    assert service.learning_status("owner", "car")["autoTrain"] is True


def test_one_reading_only_waits():
    service, repo, provider, clock = _service()
    session = _finish(service, provider, clock, "one")
    service.confirm_actual_soc("owner", session.session_id, 80)
    learned = _learned(repo)
    assert learned.wh_per_pct is None and len(learned.pending) == 1


def test_after_the_first_training_it_waits_for_three_new_charges():
    service, repo, provider, clock = _service()
    for index, end in enumerate((80, 81, 79, 80)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    assert len(_learned(repo).pending) == 2
    session = _finish(service, provider, clock, "p4")
    service.confirm_actual_soc("owner", session.session_id, 80)
    assert _learned(repo).pending == []


def test_the_switch_leaves_training_to_the_button():
    service, repo, provider, clock = _service()
    assert service.set_auto_train("owner", "car", False) == {"vehicleId": "car", "autoTrain": False}
    for index, end in enumerate((80, 81, 79)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    learned = _learned(repo)
    assert learned.wh_per_pct is None and len(learned.pending) == 3
    assert service.learning_status("owner", "car")["autoTrain"] is False
    # Switching it off is not switching learning off.
    assert repo.get_personal_profile("owner", "car").consent_enabled is True


def test_learning_switched_off_stops_everything():
    service, repo, provider, clock = _service()
    service.update_personal_consent("owner", "car", False)
    session = _finish(service, provider, clock, "p")
    service.confirm_actual_soc("owner", session.session_id, 80)
    assert _learned(repo).pending == [] and _learned(repo).wh_per_pct is None


def test_without_the_plan_the_layer_returns_to_the_plain_value_and_the_model_stays():
    service, repo, provider, clock = _service()
    service.entitlements = _Plan(False)
    kept = _model([1.0, 0, 0, 0, 0, 0], NOW)
    _store(service, repo, LearnedProfile(wh_per_pct=26.3, layer="ai", ai_model=kept, layer_mae=1.0))
    for index, end in enumerate((80, 81, 79)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    learned = _learned(repo)
    assert learned.pending == [] and learned.layer == "base" and learned.layer_mae is None
    assert learned.ai_model["weights"] == kept["weights"]


def test_with_the_plan_it_also_selects_the_layer():
    service, repo, provider, clock = _service()
    service.entitlements = _Plan(True)
    for index, end in enumerate((80, 81)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    assert repo.get_personal_profile("owner", "car").training_reports["charge"]["layer"]["selected"] == "base"


def test_the_worker_keeps_the_layer_and_never_needs_the_assistant_package(monkeypatch):
    class Boom:
        def __getattr__(self, name):
            raise AssertionError("the worker image has no assistant package")

    monkeypatch.setattr(learning, "trip_model", Boom())
    service, repo, provider, clock = _service()
    assert service.entitlements is None
    _store(service, repo, LearnedProfile(wh_per_pct=26.3, layer="offset", gauge_offset_pct=0.0))
    for index, end in enumerate((80, 81, 79)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    learned = _learned(repo)
    assert learned.pending == [] and learned.layer == "offset"


def test_a_training_that_fails_keeps_the_reading(monkeypatch):
    service, repo, provider, clock = _service()

    def broken(*args, **kwargs):
        raise RuntimeError("no")

    monkeypatch.setattr(charge_model, "train", broken)
    for index, end in enumerate((80, 81)):
        session = _finish(service, provider, clock, f"p{index}")
        service.confirm_actual_soc("owner", session.session_id, end)
    assert len(_learned(repo).pending) == 2


# ── readings ───────────────────────────────────────────────────────────────

def test_a_reading_after_riding_stays_in_history_but_is_not_learned_from():
    service, repo, provider, clock = _service()
    session = _finish(service, provider, clock, "ride")
    done = service.confirm_actual_soc("owner", session.session_id, 55, ridden_since_charge=True)
    assert done.actual_end_soc == 55 and done.training_reason == "ridden_after_charge"
    assert done.training_eligible is False and done.soc_error is None
    assert _learned(repo).pending == []
