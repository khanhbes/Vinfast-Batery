from datetime import datetime, timedelta, timezone

import pytest

from models import (
    AutomaticChargingSessionRequest,
    ChargerCommandResponse,
    ChargerStatus,
    ChargingSessionPatchRequest,
    ChargingSessionState,
    ChargingStopReason,
    ChargingStrategy,
)
from shelly import ShellyUnavailableError
from smart_charging import GatewayError, SmartChargingConfig, SmartChargingController
from smart_session_store import SmartSessionStore


class MutableClock:
    def __init__(self):
        self.value = datetime(2030, 1, 1, 10, tzinfo=timezone.utc)

    def __call__(self):
        return self.value

    def advance(self, **kwargs):
        self.value += timedelta(**kwargs)


class FakeShelly:
    def __init__(self):
        self.relay = False
        self.online = True
        self.energy_wh = 100.0
        self.set_calls: list[bool] = []
        self.fail_set = False
        self.fail_read = False
        self.read_failures = 0

    def get_status(self):
        if self.read_failures > 0:
            self.read_failures -= 1
            raise ShellyUnavailableError("transient read failed")
        if self.fail_read:
            raise ShellyUnavailableError("read failed")
        return ChargerStatus(
            online=self.online,
            relay=self.relay,
            power_w=500 if self.relay else 0,
            voltage_v=230,
            current_a=2.2 if self.relay else 0,
            energy_wh=self.energy_wh,
        )

    def set_relay(self, on: bool):
        self.set_calls.append(on)
        previous = self.relay
        if self.fail_set:
            raise ShellyUnavailableError("set failed")
        self.relay = on
        return ChargerCommandResponse(success=True, relay=on, previous_state=previous)


def request(clock, strategy=ChargingStrategy.SMART_COMBINED, minutes=60, deadline_minutes=90):
    return AutomaticChargingSessionRequest(
        vehicle_id="VF-001",
        start_soc=20,
        target_soc=80,
        predicted_minutes=minutes,
        strategy=strategy,
        hard_deadline_at=clock() + timedelta(minutes=deadline_minutes),
        predicted_full_at=clock() + timedelta(minutes=minutes),
        prediction_source="ai_model",
        prediction_confidence=82,
        estimated_capacity_wh=2400,
        acknowledge_estimated_soc=True,
    )


def controller(tmp_path, *, shadow=True, cutoff=False, max_minutes=240):
    clock = MutableClock()
    shelly = FakeShelly()
    ctrl = SmartChargingController(
        SmartSessionStore(tmp_path / "sessions.sqlite3"),
        shelly,
        SmartChargingConfig(
            enabled=True,
            automatic_cutoff=cutoff,
            shadow_mode=shadow,
            max_session_minutes=max_minutes,
        ),
        clock,
    )
    return ctrl, shelly, clock


def test_requires_configured_safety_limit(tmp_path):
    ctrl, _, clock = controller(tmp_path, max_minutes=None)
    with pytest.raises(GatewayError, match="giới hạn") as raised:
        ctrl.start(request(clock), "key")
    assert raised.value.code == "SAFETY_LIMIT_NOT_CONFIGURED"


def test_requires_estimated_soc_acknowledgement(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    payload = request(clock).model_copy(update={"acknowledge_estimated_soc": False})
    with pytest.raises(GatewayError) as raised:
        ctrl.start(payload, "key")
    assert raised.value.code == "ESTIMATED_SOC_ACK_REQUIRED"


def test_start_persists_only_after_verified_on(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    session = ctrl.start(request(clock), "key")
    assert session.state == ChargingSessionState.ACTIVE
    assert session.relay_verified is True
    assert shelly.set_calls == [True]


def test_idempotency_key_never_sends_second_on(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    first = ctrl.start(request(clock), "same-key")
    second = ctrl.start(request(clock), "same-key")
    assert second.session_id == first.session_id
    assert shelly.set_calls == [True]


def test_rejects_second_active_session(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    ctrl.start(request(clock), "one")
    with pytest.raises(GatewayError) as raised:
        ctrl.start(request(clock), "two")
    assert raised.value.code == "ACTIVE_SESSION_EXISTS"


def test_rejects_past_deadline(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    payload = request(clock).model_copy(update={"hard_deadline_at": clock() - timedelta(seconds=1)})
    with pytest.raises(GatewayError) as raised:
        ctrl.start(payload, "key")
    assert raised.value.code == "INVALID_TIMESTAMP"


def test_cutoff_disabled_forces_shadow_mode(tmp_path):
    ctrl, _, clock = controller(tmp_path, shadow=False, cutoff=False)
    assert ctrl.start(request(clock), "key").shadow_mode is True


@pytest.mark.parametrize(
    ("strategy", "minutes", "deadline", "expected"),
    [
        (ChargingStrategy.TARGET_SOC, 60, 90, 60),
        (ChargingStrategy.DEADLINE, 60, 90, 90),
        (ChargingStrategy.SMART_COMBINED, 100, 40, 40),
    ],
)
def test_strategy_selects_effective_stop(tmp_path, strategy, minutes, deadline, expected):
    ctrl, _, clock = controller(tmp_path)
    session = ctrl.start(request(clock, strategy, minutes, deadline), "key")
    assert session.effective_stop_at == clock() + timedelta(minutes=expected)


def test_absolute_safety_clamps_plan(tmp_path):
    ctrl, _, clock = controller(tmp_path, max_minutes=30)
    session = ctrl.start(request(clock, minutes=80, deadline_minutes=90), "key")
    assert session.effective_stop_at == clock() + timedelta(minutes=30)


def test_manual_stop_is_verified_and_idempotent(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    stopped = ctrl.stop(active.session_id, expected_version=active.version)
    again = ctrl.stop(active.session_id)
    assert stopped.state == ChargingSessionState.CANCELLED
    assert stopped.stop_reason == ChargingStopReason.MANUAL
    assert again.version == stopped.version
    assert shelly.set_calls == [True, False]


def test_stop_retries_transient_readback_failure(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    shelly.read_failures = 2
    stopped = ctrl.stop(active.session_id)
    assert stopped.state == ChargingSessionState.CANCELLED
    assert shelly.relay is False


def test_stop_rejects_stale_version(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    with pytest.raises(GatewayError) as raised:
        ctrl.stop(active.session_id, expected_version=1)
    assert raised.value.code == "VERSION_CONFLICT"


def test_patch_requires_current_version(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    with pytest.raises(GatewayError) as raised:
        ctrl.patch(active.session_id, ChargingSessionPatchRequest(expected_version=1, target_soc=90))
    assert raised.value.code == "VERSION_CONFLICT"


def test_patch_extension_requires_confirmation(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    patch = ChargingSessionPatchRequest(
        expected_version=active.version,
        hard_deadline_at=active.hard_deadline_at + timedelta(hours=1),
    )
    with pytest.raises(GatewayError) as raised:
        ctrl.patch(active.session_id, patch)
    assert raised.value.code == "EXTENSION_ACK_REQUIRED"
    updated = ctrl.patch(active.session_id, patch.model_copy(update={"acknowledge_extension": True}))
    assert updated.hard_deadline_at > active.hard_deadline_at


def test_terminal_session_cannot_be_patched(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    stopped = ctrl.stop(active.session_id)
    with pytest.raises(GatewayError) as raised:
        ctrl.patch(stopped.session_id, ChargingSessionPatchRequest(expected_version=stopped.version, target_soc=90))
    assert raised.value.code == "SESSION_TERMINAL"


def test_unexpected_relay_off_interrupts_without_auto_on(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    shelly.relay = False
    result = ctrl.tick()
    assert result.state == ChargingSessionState.INTERRUPTED
    assert result.stop_reason == ChargingStopReason.RELAY_OFF
    assert shelly.set_calls == [True]
    assert ctrl.get(active.session_id).state == ChargingSessionState.INTERRUPTED


def test_energy_delta_and_estimated_soc_are_display_only(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    ctrl.start(request(clock), "key")
    shelly.energy_wh = 340
    result = ctrl.tick()
    assert result.energy_used_wh == 240
    assert result.estimated_soc == pytest.approx(30)
    assert result.state == ChargingSessionState.ACTIVE


def test_meter_reset_never_creates_negative_energy(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    ctrl.start(request(clock), "key")
    shelly.energy_wh = 10
    result = ctrl.tick()
    assert result.energy_used_wh == 0
    assert result.energy_quality == "meter_reset"
    shelly.energy_wh = 20
    result = ctrl.tick()
    assert result.energy_used_wh == 10


def test_shadow_mode_records_cutoff_without_turning_off(tmp_path):
    ctrl, shelly, clock = controller(tmp_path, shadow=True, cutoff=True)
    ctrl.start(request(clock, minutes=30, deadline_minutes=60), "key")
    clock.advance(minutes=31)
    result = ctrl.tick()
    assert result.would_have_turned_off_at == clock()
    assert result.state == ChargingSessionState.ACTIVE
    assert shelly.relay is True


def test_live_mode_turns_off_at_effective_stop(tmp_path):
    ctrl, shelly, clock = controller(tmp_path, shadow=False, cutoff=True)
    ctrl.start(request(clock, minutes=30, deadline_minutes=60), "key")
    clock.advance(minutes=31)
    result = ctrl.tick()
    assert result.state == ChargingSessionState.COMPLETED
    assert result.stop_reason == ChargingStopReason.SMART_COMBINED
    assert shelly.relay is False


def test_hard_deadline_reason_has_priority_over_ai(tmp_path):
    ctrl, _, clock = controller(tmp_path, shadow=False, cutoff=True)
    ctrl.start(request(clock, minutes=60, deadline_minutes=20), "key")
    clock.advance(minutes=21)
    result = ctrl.tick()
    assert result.stop_reason == ChargingStopReason.DEADLINE


def test_absolute_safety_reason_has_priority(tmp_path):
    ctrl, _, clock = controller(tmp_path, shadow=False, cutoff=True, max_minutes=10)
    ctrl.start(request(clock, minutes=60, deadline_minutes=90), "key")
    clock.advance(minutes=11)
    result = ctrl.tick()
    assert result.stop_reason == ChargingStopReason.ABSOLUTE_SAFETY


def test_restart_with_relay_off_marks_interrupted(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    shelly.relay = False
    restored = ctrl.recover()
    assert restored.state == ChargingSessionState.INTERRUPTED
    assert ctrl.get(active.session_id).stop_reason == ChargingStopReason.RELAY_OFF


def test_restart_with_relay_on_never_sends_on(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    ctrl.start(request(clock), "key")
    calls = list(shelly.set_calls)
    restored = ctrl.recover()
    assert restored.state == ChargingSessionState.ACTIVE
    assert shelly.set_calls == calls


def test_restart_recovers_starting_with_relay_on_without_second_on(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    ctrl.store.save(active.model_copy(update={"state": ChargingSessionState.STARTING}))
    calls = list(shelly.set_calls)
    restored = ctrl.recover()
    assert restored.state == ChargingSessionState.ACTIVE
    assert shelly.set_calls == calls


def test_restart_finishes_stopping_when_relay_is_already_off(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    active = ctrl.start(request(clock), "key")
    ctrl.store.save(active.model_copy(update={"state": ChargingSessionState.STOPPING}))
    shelly.relay = False
    restored = ctrl.recover()
    assert restored.state == ChargingSessionState.CANCELLED
    assert restored.stop_reason == ChargingStopReason.MANUAL


def test_restart_expired_live_session_turns_off(tmp_path):
    ctrl, shelly, clock = controller(tmp_path, shadow=False, cutoff=True)
    ctrl.start(request(clock, minutes=10, deadline_minutes=20), "key")
    clock.advance(minutes=11)
    restored = ctrl.recover()
    assert restored.stop_reason == ChargingStopReason.GATEWAY_RESTART_EXPIRED
    assert shelly.relay is False


def test_failed_on_attempts_compensating_off(tmp_path):
    ctrl, shelly, clock = controller(tmp_path)
    shelly.fail_set = True
    with pytest.raises(GatewayError) as raised:
        ctrl.start(request(clock), "key")
    assert raised.value.code == "RELAY_VERIFICATION_FAILED"
    stored = ctrl.store.get_by_idempotency_key("key")
    assert stored.state == ChargingSessionState.FAILED
    assert shelly.set_calls == [True, False]


def test_sqlite_restores_and_lists_newest_first(tmp_path):
    ctrl, _, clock = controller(tmp_path)
    first = ctrl.start(request(clock), "one")
    ctrl.stop(first.session_id)
    clock.advance(minutes=1)
    second = ctrl.start(request(clock), "two")
    reopened = SmartSessionStore(tmp_path / "sessions.sqlite3")
    assert reopened.get(second.session_id).state == ChargingSessionState.ACTIVE
    assert [item.session_id for item in reopened.list(2)] == [second.session_id, first.session_id]
