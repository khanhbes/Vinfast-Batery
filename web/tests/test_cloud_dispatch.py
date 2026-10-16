"""Offline scheduler state-machine/HTTP fixtures; never send a real relay command."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import threading

import pytest
import requests

from shelly.cloud_dispatch import CloudDispatchGate, CloudAdmissionError, retry_after_seconds, set_cooldown
from shelly.models import DeviceBinding
from shelly.providers import ProviderError
from shelly.providers.vault_cloud import VaultCloudControlProvider


class Store:
    def __init__(self):
        self.data = {}
        self.seconds = 0
        self.lock = threading.RLock()

    def now(self):
        return datetime(2026, 10, 9, tzinfo=timezone.utc) + timedelta(seconds=self.seconds)

    def change(self, operation):
        with self.lock:
            updated, result = operation(deepcopy(self.data), self.now())
            self.data = updated
            return result

    def sleep(self, seconds):
        self.seconds += seconds

    def gate(self, sleep=None):
        return CloudDispatchGate(self.change, sleeper=sleep or self.sleep,
            clock=lambda: self.seconds, wall_clock=self.now)


def test_completion_gap_shared_across_gate_instances():
    store = Store()
    times = []
    for _ in range(3):
        store.gate().run(lambda: times.append(store.seconds))
    assert all(b - a >= 1.1 for a, b in zip(times, times[1:]))
    assert "leaseId" not in store.data and store.data["offWaiters"] == {}


def test_off_has_priority_over_read_but_does_not_preempt_inflight():
    store = Store()
    store.data = {"dispatchVersion": 2, "leaseId": "inflight",
                  "leaseUntil": store.now() + timedelta(seconds=12)}
    calls = []
    def wait(seconds):
        assert not calls  # no request may bypass current in-flight holder
        # A read/ON arriving after the pending OFF must wait, not reserve ahead.
        with pytest.raises(CloudAdmissionError, match="cloudQueueBusy"):
            store.gate().run(lambda: calls.append("read"))
        store.data.pop("leaseId")
        store.data.pop("leaseUntil")
        store.sleep(seconds)
    store.gate(wait).run(lambda: calls.append("off"), priority_off=True)
    assert calls == ["off"]


def test_wait_is_bounded_and_cancel_does_not_remove_other_waiters():
    store = Store()
    store.data = {"nextAt": store.now() + timedelta(seconds=30),
                  "offWaiters": {"other-off": store.now() + timedelta(seconds=10)}}
    operation = Mock()
    with pytest.raises(CloudAdmissionError, match="cloudQueueBusy"):
        store.gate().run(operation, priority_off=True)
    assert store.seconds == 8
    assert set(store.data["offWaiters"]) == {"other-off"}
    operation.assert_not_called()


def test_timeout_operation_is_called_once_and_gap_is_preserved():
    store = Store()
    operation = Mock(side_effect=requests.Timeout())
    with pytest.raises(requests.Timeout):
        store.gate().run(operation)
    operation.assert_called_once()
    assert store.data["nextAt"] == store.now() + timedelta(seconds=1.1)


def test_lost_holder_cannot_release_new_holder():
    store = Store()
    def operation():
        store.data.update(leaseId="new-holder", leaseUntil=store.now() + timedelta(seconds=12))
    store.gate().run(operation)
    assert store.data["leaseId"] == "new-holder"


def test_cooldown_shared_and_not_shortened_by_release():
    store = Store()
    store.gate().run(lambda: store.change(lambda data, now: set_cooldown(data, now, 60)))
    operation = Mock()
    with pytest.raises(CloudAdmissionError):
        store.gate().run(operation, priority_off=True)
    operation.assert_not_called()
    assert store.data["cooldownUntil"] == datetime(2026, 10, 9, tzinfo=timezone.utc) + timedelta(seconds=60)


@pytest.mark.parametrize("data", [
    {"dispatchVersion": True}, {"dispatchVersion": 3}, {"nextAt": "bad"},
    {"leaseId": "missing-expiry"}, {"offWaiters": []},
    {"offWaiters": {"bad/id": datetime.now(timezone.utc)}},
    {"offWaiters": {1: datetime.now(timezone.utc)}}, ["not-an-object"],
])
def test_malformed_state_never_dispatches(data):
    store = Store()
    store.data = data
    operation = Mock()
    with pytest.raises(CloudAdmissionError, match="cloudLimiterMalformed"):
        store.gate().run(operation)
    operation.assert_not_called()


@pytest.mark.parametrize("raw,expected", [(None, 1.1), ("garbage", 1.1), ("NaN", 1.1),
                                         ("-2", 1.1), ("0", 1.1), ("60", 60), ("3600", 3600)])
def test_retry_after_seconds(raw, expected):
    assert retry_after_seconds(raw) == expected


def test_retry_after_http_date():
    now = datetime(2026, 10, 9, tzinfo=timezone.utc)
    assert retry_after_seconds("Fri, 09 Oct 2026 00:01:00 GMT", now=now) == 60


@pytest.mark.parametrize("status", [429, 500])
def test_provider_http_failure_never_retries_on(status):
    repo, http = Mock(), Mock()
    repo.run_cloud_request.side_effect = lambda _, operation, **kwargs: operation()
    http.post.return_value.status_code = status
    http.post.return_value.headers = {"Retry-After": "60"}
    provider = VaultCloudControlProvider(repo, session=http)
    provider._profile = Mock(return_value=("https://qa.shelly.cloud", "fixture-only"))
    # Task 123: the admitted slot reads the vault once and shares it.
    provider._restore_profile = Mock(return_value={})
    provider._assert_safety_context = Mock()
    binding = DeviceBinding("qa-device", "QA", "S3PL-00112EU", 3, "vault_cloud")
    with pytest.raises(ProviderError) as caught:
        provider._post(binding, "/v2/devices/api/set/switch", {"on": True}, safety_context={})
    assert caught.value.status_code == status
    http.post.assert_called_once()
    assert repo.run_cloud_request.call_args.kwargs["priority_off"] is False
    if status == 429:
        assert caught.value.retry_after_seconds == 60
        repo.defer_cloud_requests.assert_called_once()


def test_provider_off_marked_priority():
    repo, http = Mock(), Mock()
    repo.run_cloud_request.side_effect = lambda _, operation, **kwargs: operation()
    http.post.return_value.status_code = 200
    http.post.return_value.json.return_value = {}
    provider = VaultCloudControlProvider(repo, session=http)
    provider._profile = Mock(return_value=("https://qa.shelly.cloud", "fixture-only"))
    binding = DeviceBinding("qa-device", "QA", "S3PL-00112EU", 3, "vault_cloud")
    provider.turn_off(binding)
    assert repo.run_cloud_request.call_args.kwargs["priority_off"] is True
    http.post.assert_called_once()


def test_slow_live_lease_check_never_dispatches_after_wait_budget():
    store = Store()
    count = [0]
    def change(action):
        count[0] += 1
        result = store.change(action)
        if count[0] == 2:
            store.sleep(5)
        return result
    operation = Mock()
    gate = CloudDispatchGate(change, sleeper=store.sleep, clock=lambda: store.seconds)
    with pytest.raises(CloudAdmissionError, match="cloudQueueBusy"):
        gate.run(operation)
    operation.assert_not_called()
    assert not store.data.get("leaseId")


def test_datastore_failure_is_typed_without_http_fallback():
    repo, http = Mock(), Mock()
    repo.run_cloud_request.side_effect = ValueError("Injected datastore failure")
    provider = VaultCloudControlProvider(repo, session=http)
    provider._profile = Mock(return_value=("https://qa.shelly.cloud", "fixture-only"))
    binding = DeviceBinding("qa-device", "QA", "S3PL-00112EU", 3, "vault_cloud")
    with pytest.raises(ProviderError) as caught:
        provider.turn_off(binding)
    assert caught.value.code == "cloudRateLimiterUnavailable"
    assert "Injected" not in caught.value.message
    http.post.assert_not_called()


def test_admission_budget_extends_wait_only_and_is_capped():
    """Task108: the confirmed safety test may wait longer to be admitted, never bypass."""
    store = Store()
    store.data = {"dispatchVersion": 2, "nextAt": store.now() + timedelta(seconds=9)}
    operation = Mock(return_value="ok")
    with pytest.raises(CloudAdmissionError, match="cloudQueueBusy"):
        store.gate().run(operation)  # default 4s budget cannot reach the 9s slot
    operation.assert_not_called()
    store.seconds = 0
    assert store.gate().run(operation, admission_budget=12.0) == "ok"
    assert store.seconds >= 9
    operation.assert_called_once()
    store.seconds = 0
    store.data = {"dispatchVersion": 2, "nextAt": store.now() + timedelta(seconds=60)}
    late = Mock()
    with pytest.raises(CloudAdmissionError, match="cloudQueueBusy"):
        store.gate().run(late, admission_budget=999)
    assert store.seconds <= 15.25
    late.assert_not_called()
