from __future__ import annotations

from pathlib import Path
import pytest
from graduation_policy import GraduationPolicy
from telemetry_writer import TelemetryWriter


def test_telemetry_writer_append_read(tmp_path: Path):
    writer = TelemetryWriter(base_dir=tmp_path / "telemetry")
    session_id = "test-session-123"

    sample1 = {"t": 1000, "v": 230.0, "p": 450.0}
    sample2 = {"t": 1010, "v": 230.5, "p": 455.0}

    assert writer.count(session_id) == 0
    count1 = writer.append(session_id, sample1)
    assert count1 == 1
    assert writer.count(session_id) == 1

    count2 = writer.append(session_id, sample2)
    assert count2 == 2
    assert writer.count(session_id) == 2

    samples = writer.read_all(session_id)
    assert len(samples) == 2
    assert samples[0]["p"] == 450.0
    assert samples[1]["p"] == 455.0


def test_graduation_policy_lifecycle(tmp_path: Path):
    policy = GraduationPolicy(
        db_path=tmp_path / "grad.sqlite3",
        mape_threshold=15.0,
        min_sessions_for_canary=3,
        canary_sessions_needed=2,
    )
    vehicle_id = "VF-TEST-1"

    # Default is shadow
    assert policy.get_state(vehicle_id) == "shadow"
    assert policy.should_use_shadow_mode(vehicle_id) is True

    # Completed session but not enough sessions -> still shadow
    state = policy.record_session_completed(
        vehicle_id,
        predicted_minutes=60,
        actual_minutes=62.0,
        validation_mape=3.3,
        total_eligible_sessions=2,
    )
    assert state == "shadow"

    # Reaches 3 sessions with good MAPE -> promotes to canary
    state = policy.record_session_completed(
        vehicle_id,
        predicted_minutes=60,
        actual_minutes=61.0,
        validation_mape=2.0,
        total_eligible_sessions=3,
    )
    assert state == "canary"
    assert policy.should_use_shadow_mode(vehicle_id) is False

    # Second successful canary session -> promotes to live
    state = policy.record_session_completed(
        vehicle_id,
        predicted_minutes=60,
        actual_minutes=62.0,
        validation_mape=3.3,
        total_eligible_sessions=4,
    )
    assert state == "live"
    assert policy.should_use_shadow_mode(vehicle_id) is False

    # Safety event -> immediate rollback to shadow!
    policy.record_safety_event(vehicle_id, "over_temperature")
    assert policy.get_state(vehicle_id) == "shadow"
    assert policy.should_use_shadow_mode(vehicle_id) is True
