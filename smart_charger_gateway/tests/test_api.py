from pathlib import Path

from fastapi.testclient import TestClient

import main
from models import ChargerCommandResponse, ChargerStatus
from session_store import SessionStore
from shelly import ShellyUnavailableError


class FakeShelly:
    def __init__(self) -> None:
        self.relay = False

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

    def set_relay(self, on: bool) -> ChargerCommandResponse:
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
    monkeypatch.setattr(main, "shelly_client", shelly or FakeShelly())
    monkeypatch.setattr(
        main,
        "session_store",
        SessionStore(tmp_path / "current_session.json"),
    )
    return TestClient(main.app)


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


def test_status_is_normalized(monkeypatch, tmp_path):
    response = configure(monkeypatch, tmp_path).get("/api/charger/status")
    assert response.status_code == 200
    assert response.json()["power_w"] == 12.0
    assert response.json()["relay"] is False


def test_on_and_off_commands(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    turned_on = client.post("/api/charger/on")
    assert turned_on.json() == {
        "success": True,
        "relay": True,
        "previous_state": False,
    }
    turned_off = client.post("/api/charger/off")
    assert turned_off.json()["relay"] is False


def test_shelly_timeout_returns_503(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path, UnavailableShelly())
    assert client.get("/api/charger/status").status_code == 503


def test_session_is_monitor_only_and_persisted(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    response = client.post("/api/charging/session", json=valid_session())
    assert response.status_code == 200
    assert response.json()["mode"] == "monitor_only"

    current = client.get("/api/charging/session/current").json()
    assert current["active"] is True
    assert current["session"]["vehicle_id"] == "VF-001"
    assert current["session"]["mode"] == "monitor_only"


def test_session_does_not_contact_shelly(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path, UnavailableShelly())
    response = client.post("/api/charging/session", json=valid_session())
    assert response.status_code == 200
    assert response.json()["mode"] == "monitor_only"


def test_session_rejects_invalid_soc(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    payload = valid_session()
    payload["start_soc"] = -1
    assert client.post("/api/charging/session", json=payload).status_code == 422


def test_session_rejects_target_not_greater(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    payload = valid_session()
    payload["target_soc"] = 20
    assert client.post("/api/charging/session", json=payload).status_code == 422


def test_session_rejects_invalid_time_order(monkeypatch, tmp_path):
    client = configure(monkeypatch, tmp_path)
    payload = valid_session()
    payload["predicted_full_at"] = payload["started_at"]
    assert client.post("/api/charging/session", json=payload).status_code == 422
