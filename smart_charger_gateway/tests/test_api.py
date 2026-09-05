from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi.testclient import TestClient

import main
from models import ChargerCommandResponse, ChargerStatus
from session_store import SessionStore
from shelly import ShellyUnavailableError
from smart_charging import SmartChargingConfig, SmartChargingController
from smart_session_store import SmartSessionStore


class FakeShelly:
    def __init__(self) -> None:
        self.relay = False
        self.set_calls: list[bool] = []

    def get_status(self) -> ChargerStatus:
        return ChargerStatus(
            online=True,
            relay=self.relay,
            power_w=12,
            voltage_v=229.4,
            current_a=0.052,
            frequency_hz=49.9,
            temperature_c=41.2,
            energy_wh=18,
        )

    def set_relay(
        self, on: bool, auto_off_delay_seconds: int | None = None
    ) -> ChargerCommandResponse:
        self.set_calls.append(on)
        previous = self.relay
        self.relay = on
        return ChargerCommandResponse(
            success=True,
            relay=on,
            previous_state=previous,
        )



class UnavailableShelly(FakeShelly):
    def get_status(self) -> ChargerStatus:
        raise ShellyUnavailableError("timeout")


def configure(monkeypatch, tmp_path: Path, shelly=None) -> TestClient:
    fake = shelly or FakeShelly()
    monkeypatch.setenv("SMART_CHARGER_API_TOKEN", "test-token")
    monkeypatch.setattr(main, "shelly_client", fake)
    monkeypatch.setattr(
        main,
        "session_store",
        SessionStore(tmp_path / "current_session.json"),
    )
    monkeypatch.setattr(
        main,
        "smart_controller",
        SmartChargingController(
            SmartSessionStore(tmp_path / "smart.sqlite3"),
            fake,
            SmartChargingConfig(max_session_minutes=240),
        ),
    )
    return TestClient(main.app)


AUTH = {"Authorization": "Bearer test-token"}


def valid_session() -> dict[str, object]:
    return {
        "vehicle_id": "VF-001",
        "start_soc": 20,
        "target_soc": 80,
        "predicted_minutes": 160,
        "started_at": "2026-08-27T18:30:00+07:00",
        "predicted_full_at": "2026-08-27T21:10:00+07:00",
        "charging_mode": "standard",
        "prediction_source": "ai_model",
        "prediction_confidence": 82,
    }


def valid_automatic_session() -> dict[str, object]:
    now = datetime.now(timezone.utc)
    return {
        "vehicle_id": "VF-001",
        "start_soc": 20,
        "target_soc": 80,
        "predicted_minutes": 60,
        "strategy": "smart_combined",
        "hard_deadline_at": (now + timedelta(hours=2)).isoformat(),
        "predicted_full_at": (now + timedelta(hours=1)).isoformat(),
        "charging_mode": "standard",
        "prediction_source": "ai_model",
        "prediction_confidence": 82,
        "estimated_capacity_wh": 2400,
        "acknowledge_estimated_soc": True,
    }


def test_status_is_normalized(monkeypatch, tmp_path):
    response = configure(monkeypatch, tmp_path).get("/api/charger/status", headers=AUTH)
    assert response.status_code == 200
    assert response.json()["power_w"] == 12.0
    assert response.json()["relay"] is False


def test_on_and_off_commands(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    turned_on = client.post("/api/charger/on", headers=AUTH)
    assert turned_on.json() == {
        "success": True,
        "relay": True,
        "previous_state": False,
    }
    turned_off = client.post("/api/charger/off", headers=AUTH)
    assert turned_off.json()["relay"] is False


def test_shelly_timeout_returns_503(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path, UnavailableShelly())
    assert client.get("/api/charger/status", headers=AUTH).status_code == 503


def test_session_is_monitor_only_and_persisted(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    response = client.post("/api/charging/session", json=valid_session(), headers=AUTH)
    assert response.status_code == 200
    assert response.json()["mode"] == "monitor_only"

    current = client.get("/api/charging/session/current", headers=AUTH).json()
    assert current["active"] is True
    assert current["session"]["vehicle_id"] == "VF-001"
    assert current["session"]["mode"] == "monitor_only"


def test_session_does_not_contact_shelly(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path, UnavailableShelly())
    response = client.post("/api/charging/session", json=valid_session(), headers=AUTH)
    assert response.status_code == 200
    assert response.json()["mode"] == "monitor_only"


def test_session_rejects_invalid_soc(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    payload = valid_session()
    payload["start_soc"] = -1
    assert client.post("/api/charging/session", json=payload, headers=AUTH).status_code == 422


def test_session_rejects_target_not_greater(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    payload = valid_session()
    payload["target_soc"] = 20
    assert client.post("/api/charging/session", json=payload, headers=AUTH).status_code == 422


def test_session_rejects_invalid_time_order(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    payload = valid_session()
    payload["predicted_full_at"] = payload["started_at"]
    assert client.post("/api/charging/session", json=payload, headers=AUTH).status_code == 422


def test_gateway_requires_bearer_token(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    response = client.get("/api/charger/status")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_automatic_session_endpoint_lifecycle(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    headers = {**AUTH, "Idempotency-Key": "start-one"}
    started = client.post(
        "/api/charging/session/start",
        json=valid_automatic_session(),
        headers=headers,
    )
    assert started.status_code == 200
    session = started.json()
    assert session["state"] == "active"

    current = client.get("/api/charging/session/current", headers=AUTH).json()
    assert current["session"]["session_id"] == session["session_id"]
    fetched = client.get(
        f"/api/charging/session/{session['session_id']}", headers=AUTH
    )
    assert fetched.status_code == 200

    stopped = client.post(
        f"/api/charging/session/{session['session_id']}/stop",
        json={"expected_version": session["version"]},
        headers=AUTH,
    )
    assert stopped.status_code == 200
    assert stopped.json()["state"] == "cancelled"

    history = client.get("/api/charging/sessions?limit=1", headers=AUTH).json()
    assert history["sessions"][0]["session_id"] == session["session_id"]


def test_start_endpoint_is_idempotent(monkeypatch, tmp_path):
    shelly = FakeShelly()
    client = configure(monkeypatch, tmp_path, shelly)
    headers = {**AUTH, "Idempotency-Key": "same-key"}
    first = client.post(
        "/api/charging/session/start",
        json=valid_automatic_session(),
        headers=headers,
    )
    second = client.post(
        "/api/charging/session/start",
        json=valid_automatic_session(),
        headers=headers,
    )
    assert second.json()["session_id"] == first.json()["session_id"]
    assert shelly.set_calls == [True]


def test_start_requires_idempotency_key(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    response = client.post(
        "/api/charging/session/start",
        json=valid_automatic_session(),
        headers=AUTH,
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "IDEMPOTENCY_KEY_REQUIRED"


def test_patch_endpoint_rejects_stale_version(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    started = client.post(
        "/api/charging/session/start",
        json=valid_automatic_session(),
        headers={**AUTH, "Idempotency-Key": "patch-one"},
    ).json()
    response = client.patch(
        f"/api/charging/session/{started['session_id']}",
        json={"expected_version": 1, "target_soc": 90},
        headers=AUTH,
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "VERSION_CONFLICT"
