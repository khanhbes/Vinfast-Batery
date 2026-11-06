"""QA 147: the layers over Wh/% (gauge offset, then a small model) only act after
beating the simpler layer on charges they had not seen, and never touch
"Dung lượng pin còn lại"."""
from __future__ import annotations

import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from shelly import charge_ai, charge_model
from shelly.charge_model import LearnedProfile
from shelly.providers.fake import FakeShellyProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService

SAMPLES = json.loads((Path(__file__).parent / "fixtures" / "owner_charge_samples.json").read_text("utf-8"))
NOW = datetime(2026, 11, 4, 6, 3, tzinfo=timezone.utc)
BASE = charge_model.default_wh_per_pct(2400, 100)


def _charge(i, *, day, start, gain, actual, wh=26.3, censored=False, **extra):
    return {"sessionId": f"c{i}", "whPerPct": wh * gain / max(1.0, actual - start), "energyWh": wh * gain,
            "startPct": float(start), "actualEndPct": float(actual), "censored": censored,
            "avgPowerW": 440.0, "at": (NOW + timedelta(days=day)).isoformat(), **extra}


def _fleet(count=60, *, lag=0.0, noise=1.0, wear_per_day=0.0, seed=7, every_days=3):
    """Charges to 80 % with a full one every 8th. ``lag`` = % the gauge falls behind
    per charge since the last full one; ``noise`` = random reading error."""
    rng = random.Random(seed)
    rows, partial = [], 0
    for i in range(count):
        day = i * every_days
        wh = 26.3 * (1 - wear_per_day * day)
        if (i + 1) % 8 == 0:
            rows.append(_charge(i, day=day, start=20, gain=80, actual=100, wh=wh, censored=True))
            partial = 0
            continue
        start = rng.choice([10, 20, 30])
        actual = 80.0 - lag * partial + rng.gauss(0, noise)
        rows.append(_charge(i, day=day, start=start, gain=80 - start, actual=actual, wh=wh))
        partial += 1
    return rows


class _Clock:
    def __init__(self):
        self.now = datetime.now(timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, **kwargs):
        self.now += timedelta(**kwargs)


def _service():
    repo = SmartChargeRepository()
    provider = FakeShellyProvider()
    binding = provider.list_devices("owner")[0]
    binding.vehicle_id = "car"
    repo.register_vehicle_owner("owner", "car", verified_capacity_wh=2400)
    repo.save_binding("owner", binding)
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    clock = _Clock()
    return SmartChargeService(repo, provider, None, sleeper=lambda _: None, clock=clock), repo, provider, clock


def _store(repo, service, learned):
    profile = service.personal_profile("owner", "car")
    profile.consent_enabled = True
    profile.learned = learned.to_dict()
    repo.save_personal_profile(profile)


# ── offset ─────────────────────────────────────────────────────────────────

def test_settling_the_offset_on_the_next_charge_fits_the_owner():
    steps = [step for step in charge_ai.timeline(SAMPLES, BASE) if step["scored"]]
    plain = sum(abs(step["residual"]) for step in steps) / len(steps)
    settled = sum(abs(step["residual"] - step["offset"]) for step in steps) / len(steps)
    assert plain == pytest.approx(3.29, abs=0.05)
    # 1.97 while a 100 % charge weighed 0.25; QA 148 made it 0.15, which also moved
    # the Wh/% this replay starts from.
    assert settled == pytest.approx(2.13, abs=0.05)


def test_the_owner_keeps_the_plain_layer_until_real_charges_prove_it():
    profile = LearnedProfile(wh_per_pct=26.5, samples=list(SAMPLES))
    updated, report = charge_ai.select_layer(profile, base=BASE, now=NOW)
    assert updated.layer == "base" and report["selected"] == "base"
    # A replay of old charges does not count: nothing was recorded as it ran.
    assert charge_ai.correction(updated, 20, 80, NOW) == 0.0


def _shadowed(errors, *, offsets):
    return [_charge(i, day=i, start=20, gain=50, actual=70 - error, shadowOffsetPct=offsets[i], shadowWhPerPct=26.3)
            for i, error in enumerate(errors)]


def test_offset_needs_five_real_charges_and_a_real_win():
    # The gauge rises 5 % more than the energy, as the recorded offset said.
    explained = _shadowed([-5.0] * 5, offsets=[5.0] * 5)
    chosen, report = charge_ai.select_layer(LearnedProfile(wh_per_pct=26.3, samples=explained), base=BASE, now=NOW)
    assert report["base"]["mae"] == pytest.approx(5.0, abs=0.01) and report["offset"]["mae"] < 0.1
    assert chosen.layer == "offset" and chosen.layer_mae == report["offset"]["mae"]
    # An offset that points the wrong way is refused.
    wrong = _shadowed([5.0] * 5, offsets=[5.0] * 5)
    assert charge_ai.select_layer(LearnedProfile(wh_per_pct=26.3, samples=wrong), base=BASE, now=NOW)[0].layer == "base"
    # Four are not enough, however good.
    few = LearnedProfile(wh_per_pct=26.3, samples=explained[:4])
    assert charge_ai.select_layer(few, base=BASE, now=NOW)[0].layer == "base"


def test_a_full_charge_is_not_scored_for_the_offset():
    full = _charge(1, day=1, start=0, gain=87.3, actual=100, censored=True, shadowOffsetPct=12.0, shadowWhPerPct=26.3)
    report = charge_model.shadow_report(LearnedProfile(samples=[full]))
    assert report["n"] == 0 and report["plain"]["mae"] is None


def test_correction_is_bounded_and_leaves_a_charge_to_full_alone():
    profile = LearnedProfile(layer="offset", gauge_offset_pct=12.0)
    assert charge_ai.correction(profile, 20, 80, NOW) == 12.0
    assert charge_ai.correction(profile, 70, 80, NOW) == 5.0  # at most half of the gain
    assert charge_ai.correction(profile, 20, 100, NOW) == 0.0
    assert charge_ai.correction(LearnedProfile(layer="offset", gauge_offset_pct=-40.0), 0, 90, NOW) == -15.0
    assert charge_ai.correction(None, 20, 80, NOW) == 0.0
    assert charge_ai.correction(LearnedProfile(gauge_offset_pct=12.0), 20, 80, NOW) == 0.0


# ── the cutoff, end to end ─────────────────────────────────────────────────

def test_a_selected_offset_moves_the_cutoff_and_the_live_percent():
    service, repo, provider, clock = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES),
                                         layer="offset", gauge_offset_pct=5.0))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 20, "targetSoc": 80})
    assert preview.soc_correction_pct == 5.0
    session = service.start("owner", preview.preview_id, "o1")
    assert session.target_energy_wh == pytest.approx(55 * 26.0)
    clock.advance(seconds=20)
    provider.status.power_w = 440
    provider.status.energy_wh += 55 * 26.0 / 2
    live = service.current("owner", vehicle_id="car")
    assert live.state == "active" and live.estimated_soc == pytest.approx(20 + 27.5 + 2.5, abs=0.1)
    clock.advance(seconds=20)
    provider.status.energy_wh += 55 * 26.0 / 2
    done = service.current("owner", vehicle_id="car") or repo.get_session("owner", session.session_id)
    assert done.state == "completed" and done.stop_reason == "target_reached"
    assert done.estimated_soc == pytest.approx(80, abs=0.1)


def test_raising_the_target_keeps_the_correction():
    service, repo, provider, clock = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES),
                                         layer="offset", gauge_offset_pct=4.0))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 20, "targetSoc": 60})
    session = service.start("owner", preview.preview_id, "o2")
    assert session.target_energy_wh == pytest.approx(36 * 26.0)
    raised = service.update_target("owner", session.session_id, 70)
    assert raised.target_energy_wh == pytest.approx(46 * 26.0)


def test_the_plain_layer_cuts_exactly_as_before():
    service, repo, _, _ = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES), gauge_offset_pct=9.0))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 20, "targetSoc": 80})
    assert preview.soc_correction_pct == 0.0
    session = service.start("owner", preview.preview_id, "p1")
    assert session.target_energy_wh == pytest.approx(60 * 26.0)
    assert session.soc_correction_pct == 0.0


def test_a_timed_charge_is_never_corrected():
    service, repo, _, _ = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES),
                                         layer="offset", gauge_offset_pct=9.0))
    session = service.manual_on("owner", 3600, "t1", vehicle_id="car", current_soc=20)
    assert session.soc_correction_pct == 0.0 and session.target_energy_wh is None


def test_correction_survives_a_restart():
    service, repo, _, _ = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES),
                                         layer="offset", gauge_offset_pct=5.0))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 20, "targetSoc": 80})
    session = service.start("owner", preview.preview_id, "r1")
    from shelly.repositories import _session
    assert _session({**session.to_dict(), "idempotency_key": "r1"}).soc_correction_pct == 5.0


# ── the small model ────────────────────────────────────────────────────────

def _profile(rows, **fields):
    return LearnedProfile(wh_per_pct=26.3, samples=rows[-12:], ledger=rows, **fields)


def test_small_model_learns_a_real_pattern_and_beats_the_simple_layer():
    rows = _fleet(60, lag=1.0, noise=0.5, seed=1)
    updated, report = charge_ai.select_layer(_profile(rows), base=BASE, now=NOW + timedelta(days=200))
    assert report["aiDecision"] == "promoted" and updated.layer == "ai"
    assert report["ai"]["n"] >= charge_ai.AI_MIN_TEST
    assert report["ai"]["mae"] < report["aiBaseline"]["mae"] * 0.7
    assert len(updated.ai_model["weights"]) == len(charge_ai.FEATURES)
    assert charge_model.honest_mae(updated) == report["ai"]["mae"]


def test_most_vehicles_with_a_real_pattern_get_the_small_model():
    # The bias rule refuses it on some seeds even with a better error; that is the
    # gate being careful, so one seed proves little.
    won = sum(charge_ai.select_layer(_profile(_fleet(60, lag=1.0, noise=0.5, seed=seed)), base=BASE,
                                     now=NOW + timedelta(days=200))[0].layer == "ai"
              for seed in range(40))
    assert won >= 24


@pytest.mark.parametrize("noise", [1.0, 3.0])
def test_small_model_is_refused_on_pure_noise(noise):
    for seed in range(1, 21):
        updated, report = charge_ai.select_layer(_profile(_fleet(60, lag=0.0, noise=noise, seed=seed)),
                                                 base=BASE, now=NOW + timedelta(days=200))
        assert updated.layer == "base" and updated.ai_model is None
        assert report["aiDecision"] == "rejected_not_better"


def test_small_model_waits_for_enough_charges_and_days():
    too_few = _fleet(29, lag=1.0, noise=0.5)
    assert charge_ai.select_layer(_profile(too_few), base=BASE, now=NOW)[1]["aiDecision"] == "waiting_for_data"
    too_fast = _fleet(60, lag=1.0, noise=0.5, every_days=0.1)
    assert charge_ai.select_layer(_profile(too_fast), base=BASE, now=NOW)[1]["aiDecision"] == "waiting_for_data"


def test_once_trained_the_small_model_is_only_fine_tuned():
    rows = _fleet(60, lag=1.0, noise=0.5, seed=1)
    first, _ = charge_ai.select_layer(_profile(rows), base=BASE, now=NOW + timedelta(days=200))
    more = [*rows, *[{**item, "sessionId": f"n{index}",
                      "at": (NOW + timedelta(days=200 + index)).isoformat()}
                     for index, item in enumerate(rows[-6:])]]
    grown = LearnedProfile(**{**first.__dict__, "ledger": more, "samples": more[-12:]})
    second, report = charge_ai.select_layer(grown, base=BASE, now=NOW + timedelta(days=210))
    assert report["aiDecision"] in ("finetuned", "kept") and second.layer == "ai"
    # Judged only on the charges it had not seen, against the simple layer (QA 148).
    assert report["ai"]["n"] == report["aiBaseline"]["n"] == 4
    if report["aiDecision"] == "finetuned":
        assert second.ai_model["version"] == first.ai_model["version"] + 1
    # Starting from the current weights: it moves, it does not start over.
    moved = max(abs(a - b) for a, b in zip(first.ai_model["weights"], second.ai_model["weights"]))
    assert moved < 3


def test_a_small_model_that_stopped_helping_is_paused():
    rows = _fleet(40, lag=0.0, noise=0.3)
    wrong = {"features": list(charge_ai.FEATURES), "weights": [14.0, 0, 0, 0, 0, 0], "charges": 20, "version": 1}
    updated, report = charge_ai.select_layer(_profile(rows, layer="ai", ai_model=wrong), base=BASE,
                                             now=NOW + timedelta(days=130))
    assert report["aiDecision"] == "paused_worse" or updated.ai_model["weights"][0] < 14
    if report["aiDecision"] == "paused_worse":
        assert updated.layer == "base" and updated.ai_model is not None


def test_prediction_stays_close_while_the_battery_wears():
    rows = _fleet(80, lag=1.0, noise=0.5, wear_per_day=0.2 / 365)
    updated, report = charge_ai.select_layer(_profile(rows), base=BASE, now=NOW + timedelta(days=260))
    assert updated.layer == "ai"
    assert report["ai"]["mae"] < 2.0
    # Wh/% itself came down with the battery, charge by charge.
    steps = charge_ai.timeline(rows, BASE)
    assert charge_model._robust_wh(rows[-12:], BASE, steps[-1]["at"]) < 26.3 * 0.97


def test_training_through_the_service_reports_the_layer():
    service, repo, _, _ = _service()
    rows = _fleet(60, lag=1.0, noise=0.5, seed=1)
    _store(repo, service, LearnedProfile(wh_per_pct=26.3, samples=rows[-12:], ledger=rows))
    result = service.train_model("owner", "car", "charge", "retrain")
    assert result["report"]["layer"]["selected"] == "ai"
    charge = result["status"]["charge"]
    assert charge["model"]["layer"] == "ai" and charge["model"]["aiCharges"] >= 30


# ── nothing else moves ─────────────────────────────────────────────────────

def test_remaining_capacity_ignores_every_layer():
    before = charge_model.battery_health(SAMPLES, 2400)
    rows = _fleet(60, lag=1.0, noise=0.5, seed=1)
    updated, _ = charge_ai.select_layer(LearnedProfile(wh_per_pct=26.5, samples=list(SAMPLES), ledger=rows),
                                        base=BASE, now=NOW + timedelta(days=200))
    assert updated.layer == "ai"
    assert charge_model.battery_health([*updated.samples, *updated.pending], 2400) == before
    assert before["estimate"]["sohPct"] == 99.4 and before["estimate"]["capacityWh"] == 2385


def test_ledger_keeps_more_than_the_training_window():
    profile = LearnedProfile()
    for i in range(30):
        profile, decision = charge_model.queue_sample(
            profile, {"sessionId": f"s{i}", "energyWh": 1300, "startPct": 20, "actualEndPct": 70,
                      "at": (NOW + timedelta(days=i)).isoformat()}, base_wh_per_pct=BASE, now=NOW)
        assert decision == "queued"
    assert len(profile.pending) == charge_model.MAX_PENDING_SAMPLES and len(profile.ledger) == 30
    trained, _ = charge_model.train(profile, base_wh_per_pct=BASE, now=NOW + timedelta(days=31))
    assert len(trained.samples) == charge_model.MAX_PROFILE_SAMPLES and len(trained.ledger) == 30
    restored = LearnedProfile.from_dict(trained.to_dict())
    assert len(restored.ledger) == 30 and len(charge_ai.charges(restored)) == 30
    # A second reading of one charge replaces it.
    again, _ = charge_model.queue_sample(restored, {"sessionId": "s3", "energyWh": 1300, "startPct": 20,
                                                    "actualEndPct": 72, "at": NOW.isoformat()},
                                         base_wh_per_pct=BASE, now=NOW)
    assert len(again.ledger) == 30
    capped = LearnedProfile(ledger=[{"sessionId": str(i)} for i in range(500)])
    assert len(capped.to_dict()["ledger"]) == charge_model.MAX_LEDGER_CHARGES


def test_older_profiles_read_as_the_plain_layer():
    profile = LearnedProfile.from_dict({"whPerPct": 26.1, "samples": SAMPLES})
    assert profile.layer == "base" and profile.ai_model is None and profile.ledger == []
    assert len(charge_ai.charges(profile)) == len(SAMPLES)


# ── suggesting a full charge ───────────────────────────────────────────────

def test_full_charge_is_suggested_after_several_partial_ones():
    partial = [_charge(i, day=i, start=20, gain=50, actual=70) for i in range(4)]
    assert charge_ai.status(LearnedProfile())["suggestFull"] is False
    assert charge_ai.status(LearnedProfile(ledger=partial))["chargesSinceFull"] == 4
    assert charge_ai.status(LearnedProfile(ledger=partial))["suggestFull"] is False
    five = [*partial, _charge(4, day=4, start=20, gain=50, actual=70)]
    assert charge_ai.status(LearnedProfile(ledger=five))["suggestFull"] is True
    full = [*five, _charge(5, day=5, start=10, gain=90, actual=100, censored=True)]
    settled = charge_ai.status(LearnedProfile(ledger=full))
    assert settled["chargesSinceFull"] == 0 and settled["suggestFull"] is False
    # The owner's last charge reached 100 %.
    assert charge_ai.status(LearnedProfile(samples=list(SAMPLES)))["suggestFull"] is False


def test_ridge_recovers_a_known_answer():
    rows = [[1.0, i / 10, 0, 0, 0, 0] for i in range(20)]
    targets = [2.0 + 3.0 * row[1] for row in rows]
    weights = charge_ai.ridge(rows, targets, strength=1e-6)
    assert weights[0] == pytest.approx(2.0, abs=0.01) and weights[1] == pytest.approx(3.0, abs=0.01)
    assert charge_ai.ridge(rows, targets, prior=weights, strength=1e6) == pytest.approx(weights, abs=1e-3)
