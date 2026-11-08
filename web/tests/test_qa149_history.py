"""QA 149, seen on the owner's phone while a charge ran: "Thói quen sạc" said
"1 charge in 60 days" for a vehicle with 8. The history returned this
process's cache alone (the running charge and one more) whenever the cache
was not empty, so the stored charges never came back."""
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone

from shelly.providers.fake import FakeShellyProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeService


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


def _start(service, clock, key):
    clock.now = max(clock.now - timedelta(minutes=10), datetime.now(timezone.utc))
    preview = service.create_preview("owner", {"vehicleId": "car", "currentSoc": 20,
                                               "targetSoc": 80, "historyPowerW": 440})
    return service.start("owner", preview.preview_id, key)


def _finish(service, provider, clock, key):
    session = _start(service, clock, key)
    clock.advance(seconds=300)
    provider.status.power_w = 440
    provider.status.energy_wh += session.target_energy_wh + 1
    done = service.current("owner", vehicle_id="car")
    assert done.state == "completed"
    return session


def test_history_reads_the_stored_charges_with_a_charge_in_memory(monkeypatch):
    service, repo, provider, clock = _service()
    for i in range(3):
        _finish(service, provider, clock, f"old-{i}")
    stored = [copy.deepcopy(item) for item in repo._sessions["owner"].values()]
    # A fresh process: the stored charges live only in ChargeLogs, and the
    # charge started now is the only one in memory.
    repo._sessions["owner"] = {}
    running = _start(service, clock, "now")
    repo.db = object()
    monkeypatch.setattr(repo, "_charge_log_history", lambda uid, limit=100: list(stored))
    history = repo.history("owner", limit=200)
    assert len(history) == 4
    assert history[0].session_id == running.session_id


def test_the_running_charge_keeps_its_live_copy(monkeypatch):
    service, repo, provider, clock = _service()
    running = _start(service, clock, "now")
    old_copy = copy.deepcopy(repo._sessions["owner"][running.session_id])
    old_copy.version = 0
    repo.db = object()

    def stored(uid, limit=100):
        # As the real reader does: it caches what it read, without replacing.
        repo._sessions.setdefault(uid, {}).setdefault(old_copy.session_id, old_copy)
        return [old_copy]

    monkeypatch.setattr(repo, "_charge_log_history", stored)
    history = repo.history("owner", limit=20)
    assert [item.version for item in history] == [running.version]
    assert repo._sessions["owner"][running.session_id].version == running.version
