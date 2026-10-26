"""QA-01 (review 26/10/2026): raising the target while the server stops at
the old one must never leave the outlet ON without a session. These tests
reproduced the race first (they failed before the fix) and now guard it."""
from __future__ import annotations

import pytest

from shelly.providers.base import ProviderError
from shelly.providers.fake import FakeShellyProvider
from shelly.service import SmartChargeError
from tests.test_shelly_live_safety import setup  # noqa: F401  (fixture)
from tests.test_task126_charge_model import _service, _start_target


def test_extend_never_reenergizes_an_outlet_switched_off_after_its_safety_read(setup):  # noqa: F811
    """The worker's OFF (target reached) can land in the Cloud queue between
    extend_timer's live safety read and its command; OFF has priority there.
    The extension must then be refused, not turn the outlet back ON."""
    _repo, provider, binding, _profile, device, _now, calls, _evidence = setup
    provider.turn_on_with_timer(binding, 600)
    real_read = provider._live_safety_context

    def read_then_worker_turns_off(b, **kwargs):
        context = real_read(b, **kwargs)
        provider.turn_off(b)  # the worker's verified OFF, right after the read
        return context

    provider._live_safety_context = read_then_worker_turns_off
    try:
        provider.extend_timer(binding, 3600)
    except ProviderError:
        pass  # refusing is the correct outcome
    assert device["status"]["switch:0"]["output"] is False, (
        "extend_timer sent on:true after the outlet was switched off: "
        + str([p for _, url, p in calls if url.endswith("/set/switch")]))


class _SplitCheckProvider(FakeShellyProvider):
    """Behaves like the Cloud provider: reads the relay first, sends the
    command later (the fake provider does both in one atomic step)."""

    between_read_and_command = None

    def extend_timer(self, binding, duration_seconds):
        if self.status.relay is not True:
            raise ProviderError("relayNotOn", "Bộ sạc không còn bật")
        if self.between_read_and_command:
            self.between_read_and_command()
        self.command_count += 1
        self.status.relay = True  # the command payload is {"on": True, "toggle_after": n}
        self.status.timer_remaining = duration_seconds


def test_raising_the_target_as_the_server_stops_at_the_old_target_leaves_no_outlet_on():
    service, repo, _fake, clock = _service()
    provider = _SplitCheckProvider()
    provider.status = _fake.status
    service.provider = provider
    _preview, session = _start_target(service, target=50)
    clock.advance(minutes=10)
    provider.status.power_w = 440

    def server_reaches_the_old_target():
        provider.status.energy_wh += 26 * 40  # 20 % -> 60 %, past the old 50 % target
        clock.advance(minutes=150)
        done = service.current("owner", vehicle_id="car")
        assert done.state == "completed" and provider.status.relay is False

    provider.between_read_and_command = server_reaches_the_old_target
    try:
        service.update_target("owner", session.session_id, 95)
    except (SmartChargeError, RuntimeError):
        pass
    final = repo.get_session("owner", session.session_id)
    assert final.state == "completed"
    assert provider.status.relay is False, (
        "outlet left ON with a %ss timer and no active session" % provider.status.timer_remaining)


def test_the_owner_is_told_the_session_ended_instead_of_a_vague_conflict():
    service, _repo, _fake, clock = _service()
    provider = _SplitCheckProvider()
    provider.status = _fake.status
    service.provider = provider
    _preview, session = _start_target(service, target=50)
    clock.advance(minutes=10)
    provider.status.power_w = 440

    def server_reaches_the_old_target():
        provider.status.energy_wh += 26 * 40
        clock.advance(minutes=150)
        service.current("owner", vehicle_id="car")

    provider.between_read_and_command = server_reaches_the_old_target
    with pytest.raises(SmartChargeError) as caught:
        service.update_target("owner", session.session_id, 95)
    assert caught.value.code == "sessionNotActive" and "đã tắt" in caught.value.message


def test_a_save_conflict_on_a_running_session_keeps_the_outlet_on():
    service, repo, provider, clock = _service()
    _preview, session = _start_target(service, target=50)
    clock.advance(minutes=10)
    provider.status.power_w = 440
    real_save = repo.save_session
    calls = []

    def conflict_once(uid, value):
        calls.append(1)
        if len(calls) == 1:
            raise RuntimeError("sessionRevisionConflict")
        return real_save(uid, value)

    repo.save_session = conflict_once
    with pytest.raises(RuntimeError):
        service.update_target("owner", session.session_id, 95)
    repo.save_session = real_save
    assert repo.get_session("owner", session.session_id).state == "active"
    assert provider.status.relay is True  # still a monitored session
