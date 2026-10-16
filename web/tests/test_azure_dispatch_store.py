"""Task 123 — Shelly dispatch gate state in Azure Table Storage.

Local fake of the Table REST surface (ETag optimistic concurrency). No Azure,
Shelly Cloud or relay calls.
"""
from datetime import datetime, timedelta, timezone
import json
import re

import pytest

from shelly import azure_dispatch
from shelly.azure_dispatch import AzureTableDispatchStore, ManagedIdentityToken
from shelly.cloud_dispatch import CloudAdmissionError, CloudDispatchGate, set_cooldown

FP = "a" * 64


class _Response:
    def __init__(self, status, body=None, etag=None):
        self.status_code = status
        self._body = body or {}
        self.headers = {"ETag": etag} if etag else {}

    def json(self):
        return self._body


class FakeTable:
    """Minimal Azure Table: GET/POST/PUT with ETag concurrency."""

    def __init__(self):
        self.rows: dict[str, tuple[dict, str]] = {}
        self.version = 0
        self.calls = []
        self.before_write = None  # hook: simulate a concurrent writer

    def _key(self, url):
        match = re.search(r"RowKey='([^']+)'", url)
        return match.group(1) if match else None

    def _bump(self, key, entity):
        self.version += 1
        self.rows[key] = (entity, f'W/"{self.version}"')

    def get(self, url, headers=None, timeout=None, params=None):
        self.calls.append(("GET", url))
        assert headers["Authorization"] == "Bearer qa-token"
        key = self._key(url)
        if key not in self.rows:
            return _Response(404)
        entity, etag = self.rows[key]
        return _Response(200, entity, etag)

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append(("POST", url))
        if self.before_write:
            hook, self.before_write = self.before_write, None
            hook()
        key = json["RowKey"]
        if key in self.rows:
            return _Response(409)
        self._bump(key, json)
        return _Response(204)

    def put(self, url, json=None, headers=None, timeout=None):
        self.calls.append(("PUT", url))
        if self.before_write:
            hook, self.before_write = self.before_write, None
            hook()
        key = self._key(url)
        if key not in self.rows or self.rows[key][1] != headers.get("If-Match"):
            return _Response(412)
        self._bump(key, json)
        return _Response(204)


class _Token:
    def get(self):
        return "qa-token"


@pytest.fixture
def table():
    return FakeTable()


@pytest.fixture
def store(table):
    return AzureTableDispatchStore("vfmediaqa", token=_Token(), session=table)


def _stored_state(table):
    entity, _ = table.rows[FP]
    return json.loads(entity["state"])


def test_round_trips_gate_state_with_aware_datetimes(store, table):
    now = datetime(2026, 10, 14, 9, 0, tzinfo=timezone.utc)

    def set_next(data, _now):
        return {**data, "nextAt": now, "offWaiters": {"r1": now}, "dispatchVersion": 2}, "ok"

    assert store.change(FP, set_next) == "ok"
    seen = {}

    def read(data, _now):
        seen.update(data)
        return data, None

    store.change(FP, read)
    assert seen["nextAt"] == now and seen["nextAt"].tzinfo is not None
    assert seen["offWaiters"] == {"r1": now}
    # Unchanged state is never rewritten.
    assert [method for method, _ in table.calls].count("PUT") == 0


def test_lost_race_rereads_and_reapplies_the_action(store, table):
    store.change(FP, lambda data, now: ({"n": 1}, None))

    def concurrent_writer():
        entity, etag = table.rows[FP]
        table._bump(FP, {**entity, "state": json.dumps({"n": 5})})

    table.before_write = concurrent_writer
    store.change(FP, lambda data, now: ({**data, "n": data["n"] + 1}, None))
    # Applied on top of the concurrent value, never overwriting it.
    assert _stored_state(table)["n"] == 6


def test_insert_race_falls_back_to_update(store, table):
    def concurrent_insert():
        table._bump(FP, {"PartitionKey": "shellyCloud", "RowKey": FP, "state": json.dumps({"n": 3})})

    table.before_write = concurrent_insert
    store.change(FP, lambda data, now: ({**data, "n": data.get("n", 0) + 1}, None))
    assert _stored_state(table)["n"] == 4


def test_endless_contention_fails_closed(store, table):
    store.change(FP, lambda data, now: ({"n": 1}, None))
    table.put = lambda *a, **k: _Response(412)
    with pytest.raises(RuntimeError, match="cloudRateLimiterUnavailable"):
        store.change(FP, lambda data, now: ({"n": data["n"] + 1}, None))


def test_store_errors_and_bad_keys_fail_closed(store, table):
    with pytest.raises(RuntimeError, match="cloudLimiterMalformed"):
        store.change("not-a-fingerprint", lambda data, now: (data, None))
    table.get = lambda *a, **k: _Response(503)
    with pytest.raises(RuntimeError, match="cloudRateLimiterUnavailable"):
        store.change(FP, lambda data, now: (data, None))
    with pytest.raises(RuntimeError, match="dispatchStoreMisconfigured"):
        AzureTableDispatchStore("Bad_Account!", token=_Token(), session=table)


def test_gate_protocol_runs_unchanged_on_the_table(store):
    clock = [0.0]
    gate = CloudDispatchGate(lambda action: store.change(FP, action),
                             sleeper=lambda s: clock.__setitem__(0, clock[0] + s),
                             clock=lambda: clock[0])
    ran = []
    assert gate.run(lambda: ran.append("read") or "status") == "status"
    # Completion spacing is persisted: an immediate second call must wait.
    state = {}
    store.change(FP, lambda data, now: (state.update(data) or data, None))
    assert state["nextAt"] > datetime.now(timezone.utc)
    assert "leaseId" not in state
    # A 429 cooldown stored in the table blocks admission (fails closed).
    store.change(FP, lambda data, now: set_cooldown(data, now, 60))
    with pytest.raises(CloudAdmissionError):
        gate.run(lambda: ran.append("blocked"))
    assert ran == ["read"]


def test_managed_identity_token_is_cached(monkeypatch):
    calls = []

    class _Http:
        def get(self, url, params=None, headers=None, timeout=None):
            calls.append((url, params, headers))
            return _Response(200, {"access_token": "tok", "expires_on": "4102444800"})

    monkeypatch.setenv("IDENTITY_ENDPOINT", "http://localhost/msi")
    monkeypatch.setenv("IDENTITY_HEADER", "hdr")
    token = ManagedIdentityToken(client_id="cid", session=_Http(), clock=lambda: 1_000.0)
    assert token.get() == "tok" and token.get() == "tok"
    assert len(calls) == 1
    url, params, headers = calls[0]
    assert params["resource"] == "https://storage.azure.com/" and params["client_id"] == "cid"
    assert headers == {"X-IDENTITY-HEADER": "hdr"}


def test_repository_uses_the_table_only_when_configured(monkeypatch, table):
    from shelly.repositories import SmartChargeRepository

    repo = SmartChargeRepository()
    monkeypatch.setattr(azure_dispatch, "_store", None)
    monkeypatch.delenv("SHELLY_DISPATCH_TABLE_ACCOUNT", raising=False)
    assert azure_dispatch.configured_store() is None
    store = AzureTableDispatchStore("vfmediaqa", token=_Token(), session=table)
    monkeypatch.setattr(azure_dispatch, "configured_store", lambda: store)
    result = repo._cloud_dispatch_change(FP, lambda data, now: ({**data, "x": 1}, "done"))
    assert result == "done" and _stored_state(table)["x"] == 1


# --- Task 123 phase 1: worker lease + health in the table -----------------


def _worker_repo(table, scope="azure-staging-1"):
    from shelly.repositories import SmartChargeRepository

    repo = SmartChargeRepository(worker_scope=scope)
    repo._worker_table_override = AzureTableDispatchStore("vfmediaqa", token=_Token(), session=table)
    return repo


def test_worker_lease_and_health_round_trip_in_one_entity(table):
    api = _worker_repo(table)
    worker = _worker_repo(table)
    now = datetime.now(timezone.utc)
    assert worker.claim_worker_lease("worker-1", now=now) == 1
    worker.publish_worker_heartbeat("worker-1", healthy=True, now=now)
    # Another process (the API) sees it with a single entity read.
    reads_before = sum(1 for method, _ in table.calls if method == "GET")
    assert api.worker_health_ready(now + timedelta(seconds=5)) is True
    assert sum(1 for method, _ in table.calls if method == "GET") - reads_before == 1
    assert {"lease", "health"} <= set(json.loads(table.rows["azure-staging-1"][0]["state"]))


def test_worker_health_fails_closed_when_stale_lost_or_unhealthy(table):
    api = _worker_repo(table)
    worker = _worker_repo(table)
    now = datetime.now(timezone.utc)
    assert api.worker_health_ready(now) is False  # nothing published yet
    worker.claim_worker_lease("worker-1", now=now)
    worker.publish_worker_heartbeat("worker-1", healthy=False, now=now)
    assert api.worker_health_ready(now) is False
    worker.publish_worker_heartbeat("worker-1", healthy=True, now=now)
    assert api.worker_health_ready(now + timedelta(seconds=91)) is False  # stale
    # A second worker cannot take a live lease or publish under it.
    other = _worker_repo(table)
    assert other.claim_worker_lease("worker-2", now=now) is None
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        other.publish_worker_heartbeat("worker-2", healthy=True, now=now)
    # After expiry the lease moves with a new epoch; old health is rejected.
    later = now + timedelta(seconds=181)
    assert other.claim_worker_lease("worker-2", now=later) == 2
    assert api.worker_health_ready(later) is False
    with pytest.raises(RuntimeError, match="workerLeaseLost"):
        worker.renew_worker_lease("worker-1", now=later)


def test_table_switch_without_store_fails_closed(monkeypatch):
    from shelly.repositories import SmartChargeRepository

    monkeypatch.setenv("SHELLY_CONTROL_STATE", "table")
    monkeypatch.delenv("SHELLY_DISPATCH_TABLE_ACCOUNT", raising=False)
    monkeypatch.setattr(azure_dispatch, "_store", None)
    repo = SmartChargeRepository(worker_scope="azure-staging-1")
    assert repo.worker_health_ready(datetime.now(timezone.utc)) is False
    with pytest.raises(RuntimeError, match="controlStateStoreUnavailable"):
        repo.claim_worker_lease("worker-1")
