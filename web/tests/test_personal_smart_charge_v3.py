from datetime import timedelta

from shelly.charging_fusion import fuse_charging_eta
from shelly.models import ChargingSession, PersonalChargingProfile, utcnow
from shelly.personalization import evaluate_training, update_profile
from shelly.service import SmartChargeService


def _session(state="interrupted"):
    now = utcnow()
    return ChargingSession(
        session_id="session-partial", device_id="plug", vehicle_id="vehicle",
        state=state, start_soc=20, target_soc=80, actual_end_soc=55,
        predicted_minutes=240, predicted_duration_seconds=14400,
        prediction_source="ai_model", prediction_confidence=0.9,
        created_at=now - timedelta(hours=2), updated_at=now,
        stopped_at=now, ai_stop_at=now + timedelta(hours=2),
        effective_stop_at=now + timedelta(hours=2),
        absolute_safety_stop_at=now + timedelta(hours=8),
        idempotency_key="key", energy_used_wh=850,
        telemetry_coverage=0.85, nominal_capacity_wh=2400,
    )


def test_effective_capacity_uses_nominal_and_soh():
    result = fuse_charging_eta(
        {"currentSoc": 20, "targetSoc": 80, "nominalCapacityWh": 2400,
         "stateOfHealth": 90, "chargerPowerW": 500, "capacityConfidence": 90},
        {"confidence": 90, "runtimeHealth": "loaded", "modelVersion": "base-v1"},
        4 * 3600,
        None,
    )
    assert result.effective_capacity_wh == 2160
    assert {item.source for item in result.candidates} == {"global_ai", "physics"}


def test_unverified_onboarding_soh_is_not_sent_to_prediction():
    service = SmartChargeService.__new__(SmartChargeService)
    payload = service._prediction_payload(
        {"currentSoc": 20, "targetSoc": 80, "stateOfHealth": 100},
        {"stateOfHealth": 100, "hasSohData": False, "nominalCapacityWh": 2400},
    )
    assert "stateOfHealth" not in payload
    assert payload["nominalCapacityWh"] == 2400


def test_personal_stage_weights_grow_only_with_quality():
    profile = PersonalChargingProfile(
        owner_uid="owner", vehicle_id="vehicle", consent_enabled=True,
        valid_sessions=12, active=True, validation_mape=8,
        quality_confidence=0.9, global_time_scale=0.95,
    )
    result = fuse_charging_eta(
        {"currentSoc": 20, "targetSoc": 80, "nominalCapacityWh": 2400,
         "chargerPowerW": 500, "capacityConfidence": 90},
        {"confidence": 90, "runtimeHealth": "loaded", "modelVersion": "base-v1"},
        4 * 3600,
        profile,
    )
    assert result.stage == "personalized"
    assert max(result.candidates, key=lambda item: item.weight).source == "personal"
    assert abs(sum(item.weight for item in result.candidates) - 1) < 1e-9


def test_interrupted_session_learns_only_observed_bands():
    session = _session()
    decision = evaluate_training(session)
    assert decision.eligible
    assert decision.covered_bands == ("20_40", "40_60")
    profile = PersonalChargingProfile(
        owner_uid="owner", vehicle_id="vehicle", consent_enabled=True,
        nominal_capacity_wh=2400,
    )
    updated = update_profile(profile, session, decision, utcnow())
    assert updated.valid_sessions == 1
    assert set(updated.soc_bands) == {"20_40", "40_60"}
    assert "60_80" not in updated.soc_bands


def test_partial_session_without_actual_soc_is_not_training_truth():
    session = _session()
    session.actual_end_soc = None
    decision = evaluate_training(session)
    assert not decision.eligible
    assert decision.power_eligible
    assert decision.reason == "actual_soc_required"
    profile = PersonalChargingProfile(
        owner_uid="owner", vehicle_id="vehicle", consent_enabled=True,
    )
    updated = update_profile(profile, session, decision, utcnow())
    assert updated.power_sessions == 1
    assert updated.valid_sessions == 0
    assert updated.soc_bands == {}
