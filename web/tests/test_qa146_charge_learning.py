"""QA 146: charge learning on the owner's real charges.

One charge that ended at 100 % no longer decides the model, a worn battery is
followed training by training, a vehicle without its own data says so
("Đang học"), the gauge-offset test never moves a cutoff, and neither the fix nor
a capacity correction changes "Dung lượng pin còn lại".
"""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from shelly import charge_model
from shelly.charge_model import LearnedProfile
from shelly.providers.fake import FakeShellyProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService

SAMPLES = json.loads((Path(__file__).parent / "fixtures" / "owner_charge_samples.json").read_text("utf-8"))
NOW = datetime(2026, 11, 4, 6, 3, tzinfo=timezone.utc)
BASE_2400 = charge_model.default_wh_per_pct(2400, 100)
BASE_2600 = charge_model.default_wh_per_pct(2600, 100)
# What production held before the training of 04/11: four trained, five waiting.
TRAINED, WAITING = SAMPLES[:4], SAMPLES[4:]


def _profile() -> LearnedProfile:
    return LearnedProfile(wh_per_pct=26.151, power_w=440.0, samples=list(TRAINED),
                          pending=list(WAITING), soc_mae=0.55, version=7)


class _Clock:
    def __init__(self):
        self.now = datetime.now(timezone.utc)

    def __call__(self):
        return self.now

    def advance(self, **kwargs):
        self.now += timedelta(**kwargs)


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


def _store(repo, service, learned: LearnedProfile, *, consent=True):
    profile = service.personal_profile("owner", "car")
    profile.consent_enabled = consent
    profile.learned = learned.to_dict()
    repo.save_personal_profile(profile)


def _charge(service, provider, clock, key, *, start, wh, end=None):
    """One finished timed charge, labelled with the % read on the scooter."""
    session = service.manual_on("owner", 6 * 3600, key, vehicle_id="car", current_soc=start)
    # Short steps: the worker heartbeat in this harness runs on real time.
    clock.advance(seconds=10)
    provider.status.power_w = 440
    provider.status.energy_wh += wh
    service.current("owner", vehicle_id="car")
    done = service.stop("owner", session.session_id)
    clock.advance(seconds=10)
    if end is not None:
        return service.confirm_actual_soc("owner", done.session_id, end)
    return done


# ── the 04/11 training, replayed ───────────────────────────────────────────

def test_one_full_charge_no_longer_decides_the_model():
    assert charge_model._robust_wh(SAMPLES, BASE_2400, NOW) == pytest.approx(26.5, abs=0.2)
    trained, report = charge_model.train(_profile(), base_wh_per_pct=BASE_2400, now=NOW)
    # The old rule fell to 22.84, scored 12.45 and refused the training.
    assert report["decision"] == "promoted"
    assert trained.wh_per_pct == pytest.approx(26.5, abs=0.2)
    assert report["evaluation"]["new"]["mae"] < 8
    assert trained.pending == []
    assert len(trained.samples) == len(SAMPLES)


def test_the_error_shown_is_the_real_one():
    profile = _profile()
    assert profile.soc_mae == 0.55
    honest = charge_model.honest_mae(profile)
    assert honest == pytest.approx(3.56, abs=0.01)
    assert charge_model.training_status(profile)["mae"] == honest
    params = charge_model.params_for(capacity_wh=2400, learned=profile)
    assert params.soc_mae == honest
    # No trained model yet: nothing to score, nothing invented.
    assert charge_model.honest_mae(LearnedProfile(pending=list(WAITING))) is None


def test_a_refused_training_stores_the_real_error():
    charges = [_sample(i, wh, days=-i) for i, wh in enumerate((20.0, 26.0, 32.0))]
    profile = LearnedProfile(wh_per_pct=26.0, pending=charges, soc_mae=0.1, version=2)
    kept, report = charge_model.train(profile, base_wh_per_pct=BASE_2400, now=NOW)
    assert report["decision"] == "rejected_worse"
    assert kept.wh_per_pct == 26.0 and kept.pending == [] and len(kept.samples) == 3
    assert kept.soc_mae == pytest.approx(9.23, abs=0.01)


# ── battery wear ───────────────────────────────────────────────────────────

def _sample(i: int, wh_per_pct: float, *, days: int, gain=60.0, censored=False) -> dict:
    return {"sessionId": f"w{i}", "whPerPct": wh_per_pct, "energyWh": wh_per_pct * gain, "startPct": 20.0,
            "actualEndPct": 20.0 + gain, "censored": censored,
            "at": (NOW + timedelta(days=days)).isoformat()}


def test_a_worn_battery_is_followed_training_by_training():
    profile = LearnedProfile(wh_per_pct=26.3, samples=[_sample(i, 26.3, days=i * 3 - 60) for i in range(9)],
                             version=1)
    values, seconds = [], []
    for step in range(14):
        wh = 26.3 * (1 - 0.02 * (step + 1))  # needs 2 % fewer Wh each round
        at = NOW + timedelta(days=30 * (step + 1))
        for i in range(3):
            profile, decision = charge_model.queue_sample(
                profile,
                {"sessionId": f"n{step}-{i}", "energyWh": wh * 60, "startPct": 20, "actualEndPct": 80,
                 "at": (at + timedelta(days=i)).isoformat()},
                base_wh_per_pct=BASE_2400, now=at)
            assert decision == "queued"
        profile, report = charge_model.train(profile, base_wh_per_pct=BASE_2400, now=at + timedelta(days=3))
        assert report["decision"] == "promoted"
        values.append(profile.wh_per_pct)
        params = charge_model.params_for(capacity_wh=2400, learned=profile)
        seconds.append(charge_model.estimate(params, 20, 80).seconds)
    assert values == sorted(values, reverse=True)
    assert values[-1] == pytest.approx(26.3 * (1 - 0.02 * 14), abs=0.8)
    # The same charger fills the smaller battery sooner.
    assert seconds[-1] < seconds[0]


def test_one_odd_reading_does_not_look_like_wear():
    samples = [_sample(i, 26.3, days=-i * 3) for i in range(1, 8)]
    assert charge_model._robust_wh(samples, BASE_2400, NOW) == pytest.approx(26.3)
    assert charge_model._robust_wh([*samples, _sample(99, 20.0, days=0)], BASE_2400, NOW) == pytest.approx(26.3)
    assert charge_model._robust_wh([*samples, _sample(99, 32.4, days=0)], BASE_2400, NOW) == pytest.approx(26.3)


# ── "Dung lượng pin còn lại" stays as it is ────────────────────────────────

def test_remaining_capacity_is_not_touched_by_training():
    before = charge_model.battery_health(SAMPLES, 2400)
    assert before["estimate"] == {"sohPct": 99.4, "capacityWh": 2385, "samples": 7, "confidence": "high"}
    assert before["test"] is None
    trained, _ = charge_model.train(_profile(), base_wh_per_pct=BASE_2400, now=NOW)
    after = charge_model.battery_health([*trained.samples, *trained.pending], 2400)
    assert after["estimate"] == before["estimate"]
    assert after["trend"] == before["trend"] and after["test"] is None


def test_shadow_fields_stay_out_of_remaining_capacity():
    with_shadow = [{**item, "shadowOffsetPct": 12.0, "shadowWhPerPct": 26.151} for item in SAMPLES]
    assert charge_model.battery_health(with_shadow, 2400) == charge_model.battery_health(SAMPLES, 2400)


# ── 2600 -> 2400 Wh ────────────────────────────────────────────────────────

def test_correcting_the_capacity_only_moves_what_depends_on_it():
    learned = LearnedProfile(wh_per_pct=26.5, power_w=440.0, samples=list(SAMPLES))
    old = charge_model.params_for(capacity_wh=2600, learned=learned)
    new = charge_model.params_for(capacity_wh=2400, learned=learned)
    # A vehicle that learned keeps its number: cutoff and time do not move.
    assert old.wh_per_pct == new.wh_per_pct == 26.5
    assert charge_model.estimate(old, 20, 80).seconds == charge_model.estimate(new, 20, 80).seconds
    # A vehicle that has not learned starts from the corrected catalog value.
    assert charge_model.params_for(capacity_wh=2600).wh_per_pct == pytest.approx(BASE_2600)
    assert charge_model.params_for(capacity_wh=2400).wh_per_pct == pytest.approx(BASE_2400)
    # The measured Wh/% is unchanged; only the % of the nominal capacity moves.
    health_old = charge_model.battery_health(SAMPLES, 2600)["estimate"]
    health_new = charge_model.battery_health(SAMPLES, 2400)["estimate"]
    assert health_old["capacityWh"] == health_new["capacityWh"] == 2385
    assert health_old["sohPct"] == pytest.approx(91.7) and health_new["sohPct"] == pytest.approx(99.4)


def test_the_fit_barely_depends_on_the_capacity():
    assert charge_model._robust_wh(SAMPLES, BASE_2600, NOW) == pytest.approx(
        charge_model._robust_wh(SAMPLES, BASE_2400, NOW), abs=0.2)


# ── "Đang học" ─────────────────────────────────────────────────────────────

def test_a_new_vehicle_is_learning_until_a_full_cycle_of_its_own():
    assert charge_model.learning_progress(LearnedProfile()) == {
        "charges": 0, "needCharges": 5, "gainPct": 0, "needGainPct": 100.0, "done": False}
    # Five short top-ups are not a full cycle yet.
    short = [_sample(i, 26.0, days=i, gain=15.0) for i in range(5)]
    progress = charge_model.learning_progress(LearnedProfile(pending=short))
    assert progress["charges"] == 5 and progress["gainPct"] == 75 and not progress["done"]
    enough = [*short, _sample(9, 26.0, days=9, gain=30.0)]
    assert charge_model.learning_progress(LearnedProfile(pending=enough))["done"]
    # A charge held in both lists counts once.
    both = LearnedProfile(samples=short[:1], pending=short[:1])
    assert charge_model.learning_progress(both)["charges"] == 1


def test_learning_state_for_each_kind_of_vehicle():
    service, repo, _, _ = _service()
    charge = service.learning_status("owner", "car")["charge"]
    assert charge["learning"]["state"] == "learning" and charge["learning"]["charges"] == 0

    five = [_sample(i, 26.0, days=i, gain=30.0) for i in range(5)]
    _store(repo, service, LearnedProfile(pending=five))
    assert service.learning_status("owner", "car")["charge"]["learning"]["state"] == "enough"

    _store(repo, service, LearnedProfile(wh_per_pct=26.5, samples=list(SAMPLES)))
    assert service.learning_status("owner", "car")["charge"]["learning"]["state"] == "learned"

    _store(repo, service, LearnedProfile(wh_per_pct=26.5, samples=five[:2]))
    assert service.learning_status("owner", "car")["charge"]["learning"]["state"] == "learning"

    _store(repo, service, LearnedProfile(), consent=False)
    assert service.learning_status("owner", "car")["charge"]["learning"]["state"] == "off"


def test_a_vehicle_with_only_full_charges_can_still_learn():
    full = [_sample(i, 25.0, days=i, gain=90.0, censored=True) for i in range(4)]
    assert charge_model._robust_wh(full, BASE_2400, NOW) == pytest.approx(25.0)


# ── gauge offset: shadow only ──────────────────────────────────────────────

def test_gauge_offset_replayed_on_the_owner_charges():
    offset, wh = 0.0, 26.151
    pairs = []
    for item in SAMPLES:
        start, energy, actual = item["startPct"], item["energyWh"], item["actualEndPct"]
        pairs.append((min(100.0, start + energy / wh), min(100.0, start + offset + energy / wh), actual))
        offset = charge_model.gauge_offset_after(start, offset, energy, wh, actual)
    assert offset == 0.0  # the last charge reached 100 %
    plain = sum(abs(p - a) for p, _, a in pairs) / len(pairs)
    carried = sum(abs(c - a) for _, c, a in pairs) / len(pairs)
    assert carried < plain
    assert charge_model.gauge_offset_after(10, 0, 100, 26, 80) == -15.0  # bounded both ways
    assert charge_model.gauge_offset_after(10, 0, 3000, 26, 80) == 15.0


def test_gauge_offset_never_moves_the_estimate_or_the_cutoff():
    plain = LearnedProfile(wh_per_pct=26.5, power_w=440.0, samples=list(SAMPLES))
    shifted = LearnedProfile(wh_per_pct=26.5, power_w=440.0, samples=list(SAMPLES), gauge_offset_pct=12.0)
    a, b = (charge_model.params_for(capacity_wh=2400, learned=item) for item in (plain, shifted))
    assert a == b
    assert charge_model.energy_needed_wh(a, 20, 80) == charge_model.energy_needed_wh(b, 20, 80)
    assert charge_model.estimate(a, 20, 80).seconds == charge_model.estimate(b, 20, 80).seconds


def test_gauge_offset_survives_storage_and_training():
    profile = _profile()
    profile.gauge_offset_pct, profile.gauge_offset_at = -4.5, "2026-11-01T00:00:00+00:00"
    assert LearnedProfile.from_dict(profile.to_dict()).gauge_offset_pct == -4.5
    trained, _ = charge_model.train(profile, base_wh_per_pct=BASE_2400, now=NOW)
    assert trained.gauge_offset_pct == -4.5 and trained.gauge_offset_at == "2026-11-01T00:00:00+00:00"
    assert LearnedProfile.from_dict(None).gauge_offset_pct == 0.0


def test_gauge_offset_through_the_service():
    service, repo, provider, clock = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES)))

    def learned():
        return LearnedProfile.from_dict(repo.get_personal_profile("owner", "car").learned)

    # Energy says 8 -> 70, the gauge reads 58: it owes 12.
    first = _charge(service, provider, clock, "g1", start=8, wh=62 * 26.0, end=58)
    assert first.training_state == "queued"
    assert learned().gauge_offset_pct == pytest.approx(12.0)
    # Reading the same charge again starts from the same offset, not its own result.
    service.confirm_actual_soc("owner", first.session_id, 60)
    assert learned().gauge_offset_pct == pytest.approx(10.0)
    entry = next(item for item in learned().pending if item["sessionId"] == first.session_id)
    assert entry["shadowOffsetPct"] == 0.0
    service.confirm_actual_soc("owner", first.session_id, 58)

    # The next charge carries it; reaching 100 % settles it.
    second = _charge(service, provider, clock, "g2", start=0, wh=88 * 26.0, end=100)
    assert second.training_state == "queued"
    entry = next(item for item in learned().pending if item["sessionId"] == second.session_id)
    assert entry["shadowOffsetPct"] == pytest.approx(12.0)
    assert learned().gauge_offset_pct == 0.0

    report = service.learning_status("owner", "car")["charge"]["shadow"]
    assert report["n"] == 2 and report["ready"] is False
    assert report["withOffset"]["mae"] < report["plain"]["mae"]


def test_a_late_reading_of_an_older_charge_leaves_the_offset_alone():
    service, repo, provider, clock = _service()
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES)))
    older = _charge(service, provider, clock, "o1", start=20, wh=40 * 26.0)
    newer = _charge(service, provider, clock, "o2", start=10, wh=40 * 26.0, end=44)
    before = LearnedProfile.from_dict(repo.get_personal_profile("owner", "car").learned)
    assert newer.training_state == "queued" and before.gauge_offset_pct == pytest.approx(6.0)
    service.confirm_actual_soc("owner", older.session_id, 60)
    after = LearnedProfile.from_dict(repo.get_personal_profile("owner", "car").learned)
    assert after.gauge_offset_pct == before.gauge_offset_pct
    entry = next(item for item in after.pending if item["sessionId"] == older.session_id)
    assert "shadowOffsetPct" not in entry


# ── timed charging ─────────────────────────────────────────────────────────

def test_timed_charge_shows_the_learned_percent_and_stays_a_timer():
    service, repo, provider, clock = _service(capacity=2600)
    _store(repo, service, LearnedProfile(wh_per_pct=26.0, power_w=440.0, samples=list(SAMPLES)))
    session = service.manual_on("owner", 3600, "t1", vehicle_id="car", current_soc=20)
    assert session.stop_mode == "timer" and session.target_energy_wh is None
    assert session.model_wh_per_pct == pytest.approx(26.0)
    clock.advance(minutes=30)
    provider.status.power_w = 440
    provider.status.energy_wh += 520  # 20 % at 26 Wh/%, 18 % with the 2600 Wh nominal
    live = service.current("owner", vehicle_id="car")
    assert live.state == "active" and live.estimated_soc == pytest.approx(40, abs=0.1)


def test_timed_charge_without_learning_keeps_the_capacity_estimate():
    service, _, provider, clock = _service(capacity=2400)
    session = service.manual_on("owner", 3600, "t2", vehicle_id="car", current_soc=20)
    assert session.model_wh_per_pct is None
    clock.advance(minutes=30)
    provider.status.power_w = 440
    provider.status.energy_wh += 400
    live = service.current("owner", vehicle_id="car")
    assert live.estimated_soc == pytest.approx(20 + 400 * 0.9 / 2400 * 100, abs=0.1)


def test_a_failed_profile_read_never_stops_a_timed_charge(monkeypatch):
    service, repo, _, _ = _service()

    def broken(*_args, **_kwargs):
        raise RuntimeError("firestore down")

    monkeypatch.setattr(service, "learned_profile", broken)
    session = service.manual_on("owner", 3600, "t3", vehicle_id="car", current_soc=20)
    assert session.state == "active" and session.model_wh_per_pct is None


# ── a charge left to finish by itself is not "interrupted" ─────────────────

def _target_session(service, provider, clock, *, current=0, target=100):
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": current, "targetSoc": target})
    return service.start("owner", preview.preview_id, f"tgt-{current}-{target}")


def _read(service, provider, clock, power, wh, *, seconds=20):
    clock.advance(seconds=seconds)
    provider.status.power_w = power
    provider.status.energy_wh += wh
    return service.current("owner", vehicle_id="car")


def _charge_into_the_tail(service, provider, clock):
    """Constant power, then the taper the owner's charger really draws."""
    # The tail only counts after 10 minutes of real charging.
    assert _read(service, provider, clock, 450, 2280, seconds=700).state == "active"
    for power in (178, 136, 87):
        assert _read(service, provider, clock, power, 2).state == "active"
    return _read(service, provider, clock, 4, 0)


def test_relay_seen_off_after_the_full_tail_is_a_full_battery():
    service, repo, provider, clock = _service()
    session = _target_session(service, provider, clock)
    assert _charge_into_the_tail(service, provider, clock).state == "active"
    # The server's OFF reached the device; this reader still has it "active".
    provider.status.relay = False
    clock.advance(seconds=20)
    done = service.current("owner", vehicle_id="car") or repo.get_session("owner", session.session_id)
    assert done.state == "completed" and done.stop_reason == "battery_full"
    assert done.estimated_soc == 100 and done.end_soc_source == "taper_full"
    pending = LearnedProfile.from_dict(repo.get_personal_profile("owner", "car").learned).pending
    assert [item["labelSource"] for item in pending] == ["taper_full"]


def test_relay_seen_off_after_the_target_energy_is_target_reached():
    service, repo, provider, clock = _service()
    session = _target_session(service, provider, clock, current=20, target=30)
    assert session.target_energy_wh and session.target_energy_wh > 100
    assert _read(service, provider, clock, 450, session.target_energy_wh - 50).state == "active"
    # OFF landed with the last Wh still unread: the fresh meter reading counts.
    provider.status.energy_wh += 60
    provider.status.power_w = 0
    provider.status.relay = False
    clock.advance(seconds=20)
    done = service.current("owner", vehicle_id="car") or repo.get_session("owner", session.session_id)
    assert done.state == "completed" and done.stop_reason == "target_reached"


def test_the_servers_own_stop_cut_short_keeps_the_result():
    service, repo, provider, clock = _service()
    session = _target_session(service, provider, clock)
    live = _charge_into_the_tail(service, provider, clock)
    live.state = "stopping"
    repo.save_session("owner", live)
    provider.status.relay = False
    clock.advance(seconds=20)
    done = service.current("owner", vehicle_id="car") or repo.get_session("owner", session.session_id)
    assert done.state == "completed" and done.stop_reason == "battery_full"


def test_a_real_interruption_is_still_reported():
    service, repo, provider, clock = _service()
    session = _target_session(service, provider, clock)
    assert _read(service, provider, clock, 450, 500).state == "active"
    # Cut mid-charge at full power, no tail, target far away.
    provider.status.relay = False
    clock.advance(seconds=20)
    done = service.current("owner", vehicle_id="car") or repo.get_session("owner", session.session_id)
    assert done.state == "interrupted" and done.stop_reason == "relay_off"
    learned = repo.get_personal_profile("owner", "car")
    assert learned is None or not (learned.learned or {}).get("pending")


def test_unplugging_the_scooter_is_not_a_full_battery():
    service, repo, provider, clock = _service()
    session = _target_session(service, provider, clock)
    assert _read(service, provider, clock, 450, 500).state == "active"
    # 450 -> 0 W with no taper before the tail.
    assert _read(service, provider, clock, 0, 0).state == "active"
    provider.status.relay = False
    clock.advance(seconds=20)
    done = service.current("owner", vehicle_id="car") or repo.get_session("owner", session.session_id)
    assert done.state == "interrupted" and done.stop_reason == "relay_off"


def test_the_users_own_off_stays_manual():
    service, repo, provider, clock = _service()
    session = _target_session(service, provider, clock)
    assert _read(service, provider, clock, 450, 500).state == "active"
    done = service.stop("owner", session.session_id)
    assert done.state == "cancelled" and done.stop_reason == "manual"
