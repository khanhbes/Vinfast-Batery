"""Task 125 — security fixes from the full app review (Đợt 0)."""
from types import SimpleNamespace

import pytest

RETIRED = [
    ("post", "/api/ai/predict-consumption"),
    ("get", "/api/soc/history?limit=100000"),
    ("post", "/api/trip/predict"),
    ("get", "/api/trip/history?vehicleId=someone-else"),
    ("get", "/api/ai/models/charging_time/adapters"),
    ("get", "/api/ai/models/charging_time/adapters/VF-1"),
    ("post", "/api/ai/models/charging_time/predict"),
    ("get", "/api/ai/models/charging_time/training-readiness/VF-1"),
]


@pytest.mark.parametrize("method,path", RETIRED)
def test_retired_unauthenticated_routes_never_execute(method, path, monkeypatch):
    import server

    def no_firestore():
        raise AssertionError("retired route touched Firestore")

    monkeypatch.setattr(server, "_fs", no_firestore)
    with server.app.test_client() as client:
        response = getattr(client, method)(path, json={})
    assert response.status_code == 410
    assert response.get_json()["code"] == "endpointRetired"


@pytest.mark.parametrize("path", ["/api/ai/predict-range", "/api/ai/predict-charging-time"])
def test_prediction_routes_require_a_signed_in_user(path, monkeypatch):
    import server

    monkeypatch.setattr(server, "_verify_token", lambda: (None, None, None))
    with server.app.test_client() as client:
        response = client.post(path, json={"currentBattery": 50})
    assert response.status_code == 401


class _Doc:
    def __init__(self, writes):
        self.writes = writes

    def set(self, data, merge=False):
        self.writes.append((data, merge))


def test_sync_user_writes_only_profile_fields(monkeypatch):
    import server

    writes = []
    database = SimpleNamespace(collection=lambda name: SimpleNamespace(document=lambda doc_id: _Doc(writes)))
    monkeypatch.setattr(server, "_fs", lambda: database)
    monkeypatch.setattr(server, "_require_user_or_admin", lambda: ("u1", "u1@test"))
    with server.app.test_client() as client:
        response = client.post("/api/web/sync/user", json={
            "name": "An", "role": "admin", "accountStatus": "active", "quota": 999,
            "onboardingCompleted": True, "email": "forged@test",
        })
    assert response.status_code == 200
    data, merge = writes[0]
    assert merge is True
    assert data["name"] == "An" and data["ownerUid"] == "u1" and data["email"] == "u1@test"
    for forbidden in ("role", "accountStatus", "quota", "onboardingCompleted"):
        assert forbidden not in data


def test_sync_user_rejects_a_non_object_profile(monkeypatch):
    import server

    monkeypatch.setattr(server, "_fs", lambda: object())
    monkeypatch.setattr(server, "_require_user_or_admin", lambda: ("u1", "u1@test"))
    with server.app.test_client() as client:
        response = client.post("/api/web/sync/user", json={"profile": ["role", "admin"]})
    assert response.status_code == 400


def test_code_expiry_is_clamped_and_never_crashes():
    from shelly.routes import _code_expiry_hours

    assert _code_expiry_hours({}) == 24
    assert _code_expiry_hours({"expiresHours": "abc"}) == 24
    assert _code_expiry_hours({"expiresHours": 720}) == 168
    assert _code_expiry_hours({"expiresHours": -5}) == 1


def test_redeem_guard_blocks_guessing_per_account():
    from shelly.routes import _RedeemGuard

    now = [0.0]
    guard = _RedeemGuard(limit=3, window=600, clock=lambda: now[0])
    for _ in range(3):
        assert not guard.blocked("u1")
        guard.fail("u1")
    assert guard.blocked("u1") and not guard.blocked("u2")
    now[0] = 601
    assert not guard.blocked("u1")


def test_redeem_route_answers_429_after_repeated_wrong_codes():
    from flask import Flask
    from shelly.routes import _RedeemGuard, create_blueprint

    repository = SimpleNamespace(db=None)
    app = Flask(__name__)
    app.register_blueprint(create_blueprint(SimpleNamespace(), repository, lambda: ("u1", "u@test", "user"),
                                            redeem_guard=_RedeemGuard(limit=2)))
    client = app.test_client()
    assert client.post("/api/shelly/redeem-code", json={"code": "??"}).status_code == 400
    assert client.post("/api/shelly/redeem-code", json={"code": "!!"}).status_code == 400
    blocked = client.post("/api/shelly/redeem-code", json={"code": "ABC123"})
    assert blocked.status_code == 429
    assert blocked.get_json()["error"]["code"] == "tooManyAttempts"
