"""Task 122 — faster Shelly ON/OFF with the same safety invariants.

Local fixtures only. No production Firebase, Cloud credentials or relay.
"""
from datetime import timedelta
from unittest.mock import Mock

import pytest

from shelly.models import DeviceStatus
from shelly.providers import FakeShellyProvider, ProviderError
from shelly.repositories import SmartChargeRepository
from shelly.service import (
    OFF_PENDING_READBACK,
    OFF_READBACK_GRACE_SECONDS,
    SmartChargeService,
)
from tests.test_shelly_live_safety import on_count, setup  # noqa: F401 (fixture)


def _gets(calls):
    return sum(1 for _, url, _ in calls if url.endswith("/get"))


def _service(repo, provider):
    return SmartChargeService(repo, provider, lambda _: {}, sleeper=provider.sleep)


def test_manual_on_uses_one_live_read_then_one_on_then_readback(setup):
    repo, provider, _, _, _, _, calls, _ = setup
    session = _service(repo, provider).manual_on(
        "qa-owner", 120, "qa-fast-on", "qa-vehicle", 40, target_soc=80)
    assert session.state == "active" and session.timer_verified
    assert on_count(calls) == 1
    # prepare (live safety read) + set/switch + readback = 3 Cloud calls.
    assert len(calls) == 3
    assert [url.endswith("/get") for _, url, _ in calls] == [True, False, True]
    # The gate spacing between Cloud calls is unchanged.
    assert all(b[0] - a[0] >= 1.09 for a, b in zip(calls, calls[1:]))
    assert session.target_soc == 80
    assert session.soc_estimate_source == "shelly_energy"


def test_target_soc_is_display_only_and_never_below_start(setup):
    repo, provider, _, _, _, _, _, _ = setup
    session = _service(repo, provider).manual_on(
        "qa-owner", 60, "qa-low-target", "qa-vehicle", 55, target_soc=20)
    assert session.target_soc == 55
    assert session.predicted_duration_seconds == 60


def test_stale_context_is_re_read_once_and_on_is_sent_once(setup):
    _, provider, binding, _, _, now, calls, _ = setup
    context = provider.prepare_on(binding)
    now[0] += 7  # older than the reuse window, younger than nothing else
    provider.turn_on_with_context(binding, 60, context)
    assert on_count(calls) == 1
    assert _gets(calls) == 2


def test_context_older_than_ten_seconds_inside_slot_never_sends_on(setup):
    repo, provider, binding, _, _, now, calls, _ = setup
    context = provider.prepare_on(binding)

    def slow_admit(_, operation, **kwargs):
        kwargs["sleeper"](11)  # queueing pushed the read past 10 s
        return operation()

    repo.run_cloud_request = Mock(side_effect=slow_admit)
    with pytest.raises(ProviderError):
        provider.turn_on_with_context(binding, 60, context)
    assert on_count(calls) == 0


def test_unsafe_live_read_blocks_on_before_a_session_exists(setup):
    repo, provider, _, _, device, _, calls, _ = setup
    device["status"]["switch:0"]["voltage"] = 180
    with pytest.raises(Exception):
        _service(repo, provider).manual_on("qa-owner", 60, "qa-unsafe", "qa-vehicle", 40)
    assert on_count(calls) == 0
    assert repo.current_session("qa-owner") is None


def test_lagging_cloud_readback_still_verifies_without_second_on(setup):
    repo, provider, _, _, _, _, calls, _ = setup
    http = provider.http
    original = http.post.side_effect
    lagging = [2]

    def lagging_post(url, **kwargs):
        response = original(url, **kwargs)
        if url.endswith("/get") and on_count(calls) == 1 and lagging[0] > 0:
            lagging[0] -= 1
            value = response.json.return_value
            value[0]["status"]["switch:0"]["output"] = False
        return response

    http.post.side_effect = lagging_post
    session = _service(repo, provider).manual_on("qa-owner", 120, "qa-lag", "qa-vehicle", 40)
    assert session.state == "active"
    assert on_count(calls) == 1


class _LaggingOffProvider(FakeShellyProvider):
    """OFF is accepted but Cloud keeps reporting ON for a while."""

    def __init__(self):
        super().__init__()
        self.off_commands = 0
        self.stale_on_reads = 0

    def turn_off(self, binding):
        self.off_commands += 1
        super().turn_off(binding)

    def get_status(self, binding):
        if self.stale_on_reads > 0:
            self.stale_on_reads -= 1
            return DeviceStatus(online=True, relay=True, voltage_v=230, timer_remaining=50,
                                device_id=binding.device_id)
        return super().get_status(binding)


@pytest.fixture
def lagging_off():
    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    provider = _LaggingOffProvider()
    clock = [None]
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    real_clock = service.clock
    service.clock = lambda: clock[0] or real_clock()
    binding = provider.list_devices("user-a")[0]
    repo.save_binding("user-a", binding)
    session = service.manual_on("user-a", 600, "qa-off-lag", "manual", 30)
    assert session.state == "active"
    return repo, provider, service, session, clock


def test_unverified_off_is_sent_once_and_kept_as_pending_manual_stop(lagging_off):
    repo, provider, service, session, _ = lagging_off
    provider.stale_on_reads = 5
    stopped = service.stop("user-a", session.session_id, user_stop_reason="enough_charge")
    assert provider.off_commands == 1
    assert stopped.state == "stopping"
    assert stopped.last_error == OFF_PENDING_READBACK
    assert stopped.user_stop_reason == "enough_charge"


def test_reconcile_waits_for_lagging_off_then_records_manual_stop(lagging_off):
    repo, provider, service, session, _ = lagging_off
    provider.stale_on_reads = 6
    service.stop("user-a", session.session_id, user_stop_reason="need_vehicle")
    # Within the grace window a stale ON read must not trigger a backup OFF.
    pending = service.current("user-a")
    assert pending.state == "stopping"
    assert provider.off_commands == 1
    # The next fresh read shows OFF: finished as a manual cancel.
    done = service.current("user-a")
    assert done is None or done.state == "cancelled"
    stored = repo.get_session("user-a", session.session_id)
    assert stored.state == "cancelled"
    assert stored.stop_reason == "manual"
    assert stored.user_stop_reason == "need_vehicle"
    assert stored.last_error is None
    assert provider.off_commands == 1


def test_still_on_after_grace_sends_backup_off_but_keeps_manual_reason(lagging_off):
    repo, provider, service, session, clock = lagging_off
    provider.stale_on_reads = 5
    service.stop("user-a", session.session_id, user_stop_reason="other")
    stored = repo.get_session("user-a", session.session_id)
    clock[0] = stored.updated_at + timedelta(seconds=OFF_READBACK_GRACE_SECONDS + 1)
    provider.stale_on_reads = 1
    service.current("user-a")
    final = repo.get_session("user-a", session.session_id)
    assert provider.off_commands == 2
    assert final.state == "cancelled"
    assert final.stop_reason == "manual"


def test_get_requests_reuse_a_recent_revocation_check(monkeypatch):
    import server

    seen = []

    class _Auth:
        @staticmethod
        def verify_id_token(token, check_revoked=False):
            seen.append(check_revoked)
            return {"uid": "qa-user"}

    monkeypatch.setattr(server, "_firebase_available", True)
    monkeypatch.setattr(server, "_firebase_auth", _Auth)
    monkeypatch.setattr(server, "_revocation_checked", {})
    headers = {"Authorization": "Bearer qa-token-fast"}
    for method in ("GET", "GET", "POST", "GET"):
        with server.app.test_request_context("/api/smart-charging/live", method=method, headers=headers):
            uid, _, _ = server._verify_token()
            assert uid == "qa-user"
    # First GET checks revocation, the next GET reuses it, POST always checks.
    assert seen == [True, False, True, False]


# --- Task 123: findings from the supervised relay run on 14/10/2026 ---------


class _ClockedProvider(FakeShellyProvider):
    """ON lands a while after the session row was created (Cloud round trips)."""

    def __init__(self, clock, on_delay_seconds=12):
        super().__init__()
        self.clock, self.on_delay = clock, on_delay_seconds
        self.off_commands = 0
        self.on_off = None

    def turn_on_with_timer(self, binding, duration_seconds):
        self.clock[0] += timedelta(seconds=self.on_delay)
        super().turn_on_with_timer(binding, duration_seconds)

    def turn_off(self, binding):
        self.off_commands += 1
        super().turn_off(binding)
        if self.on_off:
            self.on_off()


@pytest.fixture
def clocked():
    from shelly.models import utcnow

    repo = SmartChargeRepository()
    repo.claim_worker_lease("qa-worker")
    repo.publish_worker_heartbeat("qa-worker", healthy=True)
    clock = [utcnow()]
    provider = _ClockedProvider(clock)
    service = SmartChargeService(repo, provider, lambda _: {}, sleeper=lambda _: None)
    service.clock = lambda: clock[0]
    binding = provider.list_devices("user-a")[0]
    repo.save_binding("user-a", binding)
    return repo, provider, service, clock


def test_planned_stop_follows_the_verified_device_timer(clocked):
    repo, provider, service, clock = clocked
    created = clock[0]
    session = service.manual_on("user-a", 60, "qa-anchor", "manual", 40)
    # Shelly armed 60 s at created+12 s: the plan ends with the hardware.
    assert session.effective_stop_at == created + timedelta(seconds=72)
    assert session.effective_stop_at <= session.absolute_safety_stop_at
    # Shelly still counting at created+65 s: no premature backup OFF.
    clock[0] = created + timedelta(seconds=65)
    provider.status.timer_remaining = 7
    assert service.current("user-a").state == "active"
    assert provider.off_commands == 0
    # The timer cut the relay: a normal completion, not "interrupted".
    clock[0] = created + timedelta(seconds=75)
    provider.status.relay, provider.status.timer_remaining = False, 0
    service.current("user-a")
    stored = repo.get_session("user-a", session.session_id)
    assert (stored.state, stored.stop_reason) == ("completed", "planned_timer")
    assert provider.off_commands == 0


def test_expired_plan_with_relay_still_on_is_still_forced_off(clocked):
    repo, provider, service, clock = clocked
    session = service.manual_on("user-a", 60, "qa-expired", "manual", 40)
    clock[0] = session.effective_stop_at + timedelta(seconds=1)
    service.current("user-a")
    stored = repo.get_session("user-a", session.session_id)
    assert (stored.state, stored.stop_reason) == ("interrupted", "deadline_cutoff")
    assert provider.off_commands == 1 and provider.status.relay is False


def test_stop_racing_a_live_poll_reports_a_manual_off(clocked):
    """Bot OFF on a 2-minute session: /live saw OFF first and closed it."""
    repo, provider, service, clock = clocked
    session = service.manual_on("user-a", 120, "qa-race", "manual", 40)
    clock[0] += timedelta(seconds=30)
    provider.on_off = lambda: service.current("user-a")
    stopped = service.stop("user-a", session.session_id, user_stop_reason="need_vehicle")
    assert provider.off_commands == 1
    assert (stopped.state, stopped.stop_reason) == ("cancelled", "manual")
    stored = repo.get_session("user-a", session.session_id)
    assert (stored.state, stored.stop_reason) == ("cancelled", "manual")


def test_relay_switched_off_long_before_the_plan_is_not_a_completion(clocked):
    repo, provider, service, clock = clocked
    session = service.manual_on("user-a", 600, "qa-early", "manual", 40)
    clock[0] += timedelta(seconds=90)
    provider.status.relay, provider.status.timer_remaining = False, 0
    service.current("user-a")
    stored = repo.get_session("user-a", session.session_id)
    assert (stored.state, stored.stop_reason) == ("interrupted", "relay_off")


def test_one_on_reads_the_credential_vault_a_bounded_number_of_times(setup):
    """Task 123: each fresh vault read crosses to Firestore nam5 (~0.2 s).
    The same checks now share one fresh read per moment instead of ~10."""
    repo, provider, _, _, _, _, calls, _ = setup
    original = repo.restore_synced_profile
    reads = []

    def counting(*args, **kwargs):
        reads.append(kwargs.get("max_age_seconds", 0))
        return original(*args, **kwargs)

    repo.restore_synced_profile = counting
    session = _service(repo, provider).manual_on(
        "qa-owner", 60, "qa-vault-reads", "qa-vehicle", 40)
    assert session.state == "active" and on_count(calls) == 1
    fresh = [age for age in reads if age == 0]
    # prepare: 1 read + 1 inside the GET slot + 1 readiness re-check;
    # ON: 1 inside the admitted slot. Readback status reads may use the cache.
    assert len(fresh) <= 4, reads


@pytest.mark.parametrize("field,value", [
    ("verificationFingerprint", "legacy"), ("verificationFingerprintVersion", 2),
    ("noLoadTestVerified", False), ("timerAutoOffObserved", False), ("revokedAt", "qa-revoked"),
])
def test_light_prepare_still_never_energizes_without_full_evidence(setup, field, value):
    """Task 123: prepare no longer re-reads history; the ON slot must."""
    repo, provider, _, _, _, _, calls, _ = setup
    repo._synced_profiles[("qa-owner", "qa-plug")][field] = value
    with pytest.raises(Exception):
        _service(repo, provider).manual_on("qa-owner", 60, f"qa-evidence-{field}", "qa-vehicle", 40)
    assert on_count(calls) == 0
    active = repo.current_session("qa-owner")
    assert active is None or active.state != "active"
    # The device lock is never left held by a session that was not armed.
    lock = repo.device_lock("qa-plug")
    assert not lock or not lock.get("sessionId") or (active and lock["sessionId"] == active.session_id)


def _join_background(name):
    import threading
    for thread in list(threading.enumerate()):
        if thread.name == name:
            thread.join(timeout=5)


def test_verified_off_answers_before_the_terminal_write(clocked):
    repo, provider, service, clock = clocked
    session = service.manual_on("user-a", 120, "qa-defer", "manual", 40)
    service._defer_terminal_writes = lambda: True
    clock[0] += timedelta(seconds=20)
    reply = service.stop("user-a", session.session_id, user_stop_reason="need_vehicle")
    assert (reply.state, reply.stop_reason, reply.relay_verified) == ("cancelled", "manual", True)
    assert provider.off_commands == 1 and provider.status.relay is False
    _join_background("smart-charge-stop")
    stored = repo.get_session("user-a", session.session_id)
    assert (stored.state, stored.stop_reason, stored.user_stop_reason) == ("cancelled", "manual", "need_vehicle")


def test_failed_deferred_write_is_finished_by_reconcile(clocked):
    repo, provider, service, clock = clocked
    session = service.manual_on("user-a", 120, "qa-defer-fail", "manual", 40)
    service._defer_terminal_writes = lambda: True
    original = service._finalize_session
    service._finalize_session = Mock(side_effect=ConnectionError("nam5 unavailable"))
    clock[0] += timedelta(seconds=20)
    reply = service.stop("user-a", session.session_id)
    assert reply.state == "cancelled"
    _join_background("smart-charge-stop")
    assert repo.get_session("user-a", session.session_id).state == "stopping"
    service._finalize_session = original
    service.current("user-a")  # next live poll sees relay OFF
    stored = repo.get_session("user-a", session.session_id)
    assert (stored.state, stored.stop_reason) == ("cancelled", "manual")
    assert provider.off_commands == 1


def test_live_poll_racing_the_deferred_write_does_not_fail(clocked):
    repo, provider, service, clock = clocked
    session = service.manual_on("user-a", 120, "qa-defer-race", "manual", 40)
    service.stop("user-a", session.session_id)  # synchronous in-memory close
    stale = repo.get_session("user-a", session.session_id)
    stale.state = "stopping"  # a reconcile still holding the pre-close copy
    result = service._finalize_session("user-a", stale, state="cancelled", stop_reason="manual",
                                       status=provider.get_status(provider.list_devices("user-a")[0]))
    assert (result.state, result.stop_reason) == ("cancelled", "manual")


def test_verified_on_sends_a_silent_refresh_push_to_the_account(clocked):
    repo, provider, service, clock = clocked
    calls = []
    service.push_notifier = lambda uid, **kwargs: calls.append((uid, kwargs))
    session = service.manual_on("user-a", 60, "qa-push", "manual", 40)
    _join_background("smart-charge-state-push")
    assert calls == [("user-a", {"session_id": session.session_id, "vehicle_id": "manual",
                                 "state": "active", "silent": True})]


def test_silent_push_is_data_only_and_reads_the_account_tokens():
    from unittest.mock import MagicMock
    from shelly.push_notifications import send_state_push

    messaging = MagicMock()
    messaging.send_each_for_multicast.return_value = MagicMock(success_count=2, failure_count=0)
    result = send_state_push("user-a", session_id="s1", state="active", vehicle_id="v1",
                             messaging=messaging,
                             local_tokens={("user-a", "d1"): {"token": "t1"},
                                           ("user-a", "d2"): {"token": "t2"},
                                           ("user-b", "d3"): {"token": "t3"}})
    assert result == {"sent": 2, "failed": 0}
    kwargs = messaging.MulticastMessage.call_args.kwargs
    assert sorted(kwargs["tokens"]) == ["t1", "t2"]
    assert kwargs["data"]["event"] == "smart_charge" and kwargs["data"]["state"] == "active"
    assert "notification" not in kwargs  # no visible banner
