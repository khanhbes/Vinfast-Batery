"""QA 140 (item 6): charge until a clock time, and move that time while
charging. The fake outlet that edits the timer reads the relay first and
sends later, like the Cloud (QA 138 rule)."""
from __future__ import annotations

from datetime import timedelta

import pytest

from shelly.providers.base import ProviderError
from shelly.providers.fake import FakeShellyProvider
from shelly.service import SmartChargeError
from tests.test_task126_charge_model import _service


def _timed(service, clock, minutes=150, key="t1"):
    stop_at = clock() + timedelta(minutes=minutes)
    session = service.manual_on("owner", 0, key, vehicle_id="car", current_soc=40, stop_at=stop_at)
    return session, stop_at


class _SplitCheckProvider(FakeShellyProvider):
    between_read_and_command = None

    def extend_timer(self, binding, duration_seconds):
        if self.status.relay is not True:
            raise ProviderError("relayNotOn", "Bộ sạc không còn bật")
        if self.between_read_and_command:
            self.between_read_and_command()
        self.command_count += 1
        self.status.relay = True  # {"on": True, "toggle_after": n}
        self.status.timer_remaining = duration_seconds


def test_on_with_a_clock_time_arms_the_timer_up_to_that_time():
    service, _repo, provider, clock = _service()
    session, stop_at = _timed(service, clock)
    assert session.state == "active" and session.strategy == "manual_timed"
    assert provider.status.timer_remaining == 150 * 60
    assert abs((session.effective_stop_at - stop_at).total_seconds()) <= 1


def test_a_clock_time_in_the_past_or_past_ten_hours_is_refused():
    service, _repo, provider, clock = _service()
    for minutes in (-5, 10 * 60 + 5):
        with pytest.raises(SmartChargeError) as caught:
            _timed(service, clock, minutes=minutes, key=f"bad{minutes}")
        assert caught.value.code == "unsafeDuration"
    assert provider.status.relay is False


def test_a_phone_clock_far_off_is_corrected_with_client_time():
    service, _repo, _provider, clock = _service()
    phone_now = clock() - timedelta(minutes=3)  # the phone runs 3 minutes late
    stop = service.client_instant((phone_now + timedelta(hours=2)).isoformat(), phone_now.isoformat())
    assert abs((stop - (clock() + timedelta(hours=2))).total_seconds()) < 1
    # A few seconds of difference is network delay: left alone.
    near = clock() - timedelta(seconds=2)
    assert service.client_instant((near + timedelta(hours=1)).isoformat(), near.isoformat()) == near + timedelta(hours=1)
    with pytest.raises(SmartChargeError):
        service.client_instant("9:30", None)


@pytest.mark.parametrize("delta_minutes", [60, -60])
def test_moving_the_end_later_or_sooner_rearms_the_outlet(delta_minutes):
    service, repo, provider, clock = _service()
    session, stop_at = _timed(service, clock)
    clock.advance(minutes=10)
    new_stop = stop_at + timedelta(minutes=delta_minutes)
    updated = service.update_stop_at("owner", session.session_id, new_stop)
    left = (new_stop - clock()).total_seconds()
    assert abs(provider.status.timer_remaining - left) <= 1
    assert abs((updated.effective_stop_at - new_stop).total_seconds()) <= 1
    assert updated.ai_stop_at == updated.effective_stop_at
    assert repo.get_session("owner", session.session_id).effective_stop_at == updated.effective_stop_at


def test_ending_within_a_minute_or_past_ten_hours_is_refused():
    service, _repo, provider, clock = _service()
    session, _stop = _timed(service, clock)
    before = provider.status.timer_remaining
    with pytest.raises(SmartChargeError) as soon:
        service.update_stop_at("owner", session.session_id, clock() + timedelta(seconds=30))
    assert soon.value.code == "stopAtTooSoon"
    with pytest.raises(SmartChargeError) as late:
        service.update_stop_at("owner", session.session_id, clock() + timedelta(hours=10, minutes=5))
    assert late.value.code == "safetyLimitReached"
    assert provider.status.timer_remaining == before


def test_a_target_charge_has_no_clock_time_to_move():
    from tests.test_task126_charge_model import _start_target
    service, _repo, _provider, clock = _service()
    _preview, session = _start_target(service)
    with pytest.raises(SmartChargeError) as caught:
        service.update_stop_at("owner", session.session_id, clock() + timedelta(hours=1))
    assert caught.value.code == "notTimedSession"


def test_the_session_ending_while_the_timer_is_rearmed_leaves_no_outlet_on():
    service, repo, fake, clock = _service()
    provider = _SplitCheckProvider()
    provider.status = fake.status
    service.provider = provider
    session, stop_at = _timed(service, clock)
    clock.advance(minutes=10)

    def stopped_on_another_phone():
        service.stop("owner", session.session_id)
        assert provider.status.relay is False
        provider.status.relay = True  # the queued re-arm still lands (on:true)

    provider.between_read_and_command = stopped_on_another_phone
    with pytest.raises(SmartChargeError) as caught:
        service.update_stop_at("owner", session.session_id, stop_at + timedelta(hours=1))
    assert caught.value.code == "sessionNotActive"
    assert repo.get_session("owner", session.session_id).state != "active"
    assert provider.status.relay is False


def test_an_unverified_rearm_keeps_the_old_end():
    service, repo, provider, clock = _service()
    session, stop_at = _timed(service, clock)
    provider.fail_extend = True  # the command is lost; the timer stays as it was
    with pytest.raises(SmartChargeError) as caught:
        service.update_stop_at("owner", session.session_id, stop_at + timedelta(hours=1))
    assert caught.value.code == "timerNotExtended"
    assert repo.get_session("owner", session.session_id).effective_stop_at == session.effective_stop_at
