"""QA 143: fixes from the full-flow test with a brand-new account.

- Fire, smoke, explosion and shock in plain words reach the emergency reply,
  also while Pinova Bot is locked (3 strikes).
- The onboarding commit keeps the name and phone written at registration.
- The initial ODO is at most 999 999 km.
"""
from __future__ import annotations

from datetime import datetime, timezone

import pytest
from flask import Flask

import server
from assistant.conduct import ConductStore
from assistant.config_store import PinovaConfigStore
from assistant.engine import AssistantEngine
from assistant.guardrails import check_emergency_sos
from assistant.knowledge import KnowledgeBase
from assistant.memory import AssistantMemory
from assistant.quota import DailyQuota
from assistant.routes import create_assistant_blueprint
from tests.test_onboarding_and_preferences import FakeFirestore


@pytest.mark.parametrize("message", [
    "Xe bị cháy, có khói",
    "xe boc chay roi",
    "khói bốc ra từ cốp xe",
    "nghe tiếng nổ ở pin",
    "ổ cắm có tia lửa",
    "bị điện giật khi rút sạc",
    "pin bị phồng rồi",
    "có mùi khét ở ổ cắm",
    "Fire! smoke everywhere",
])
def test_plain_emergency_words_get_the_sos_reply(message):
    sos = check_emergency_sos(message)
    assert sos and sos["emergencyBypass"] is True
    assert any(action["name"] == "stop_charging" for action in sos["actions"])


@pytest.mark.parametrize("message", [
    "xe đang chạy 40 km/h",
    "xe dang chay binh thuong",
    "mình muốn ra khỏi app",
    "sạc qua đêm có sợ cháy không?",
    "làm sao để phòng cháy khi sạc",
    "nút này nổi bật quá",
    "ODO bao nhiêu",
])
def test_ordinary_or_prevention_questions_are_not_emergencies(message):
    assert check_emergency_sos(message) is None


class _NoGemini:
    def generate(self, *args, **kwargs):  # pragma: no cover - never reached
        raise AssertionError("the model must not be called")


def test_sos_is_answered_while_the_bot_is_locked(tmp_path):
    engine = AssistantEngine(
        gemini=_NoGemini(), knowledge=KnowledgeBase(None), memory=AssistantMemory(None),
        config_store=PinovaConfigStore(db=None, json_path=tmp_path / "state.json"),
        conduct_store=ConductStore(None, clock=lambda: datetime(2026, 11, 2, 2, 0, tzinfo=timezone.utc)),
        mailer=None)
    for _ in range(3):
        engine.conduct_gate("u1", "đm con bot ngu như bò")
    assert engine.conduct_gate("u1", "pin bao nhiêu?")["source"] == "conduct_lock"
    app = Flask(__name__)
    memory = AssistantMemory(None)
    app.register_blueprint(create_assistant_blueprint(
        engine=engine, memory=memory, quota=DailyQuota(limit=50), knowledge=KnowledgeBase(None),
        auth_resolver=lambda: ("u1", "a@b.vn", "user"), require_admin=lambda f: f,
        db=None, audit=lambda *args: None))
    data = app.test_client().post("/api/assistant/chat", json={"message": "Xe bị cháy, có khói"}).get_json()["data"]
    assert data["emergencyBypass"] is True and "114" in data["reply"]


@pytest.fixture
def fake_fs(monkeypatch):
    fake = FakeFirestore()
    monkeypatch.setattr(server, "_fs", lambda: fake)
    fake.collection("VehicleCatalog").document("feliz_2025").set({
        "catalogId": "feliz_2025", "status": "published", "selectable": True,
        "revision": 1, "brandName": "VinFast", "model": "Feliz", "variant": "2025",
        "modelYear": 2025, "vehicleType": "scooter",
        "appDefaults": {"calculationCapacityWh": 2400, "defaultEfficiencyKmPerPercent": 1.34},
        "battery": {"chemistry": "LFP"},
        "localized": {"vi": {"displayName": "VinFast Feliz 2025"}}, "media": {},
    })
    return fake


def _commit(uid, profile, odo=0):
    server.app.config["TESTING"] = True
    return server.app.test_client().post(
        "/api/mobile/onboarding/commit",
        json={"schemaVersion": 1, "operationId": f"op-{uid}-{odo}", "profile": profile,
              "vehicle": {"catalogId": "feliz_2025", "initialOdo": odo}, "shellyStatus": "skipped"},
        headers={"Idempotency-Key": f"op-{uid}-{odo}"})


def test_survey_placeholder_name_and_empty_phone_keep_the_registered_ones(fake_fs, monkeypatch):
    uid = "qa143-new"
    monkeypatch.setattr(server, "_verify_token", lambda: (uid, "qa@example.com", "user"))
    fake_fs.collection("users").document(uid).set({"name": "Pinova QA", "displayName": "Pinova QA",
                                                   "phone": "0900000000"})
    response = _commit(uid, {"name": "Bạn", "phone": ""})
    assert response.status_code == 200, response.json
    saved = fake_fs.collection("users").document(uid).get().to_dict()
    assert saved["name"] == "Pinova QA" and saved["displayName"] == "Pinova QA"
    assert saved["phone"] == "0900000000"


def test_a_name_the_user_typed_in_the_survey_still_wins(fake_fs, monkeypatch):
    uid = "qa143-rename"
    monkeypatch.setattr(server, "_verify_token", lambda: (uid, "qa@example.com", "user"))
    fake_fs.collection("users").document(uid).set({"name": "Pinova QA", "phone": "0900000000"})
    assert _commit(uid, {"name": "Nguyễn An", "phone": "0911111111"}).status_code == 200
    saved = fake_fs.collection("users").document(uid).get().to_dict()
    assert saved["name"] == "Nguyễn An" and saved["phone"] == "0911111111"


@pytest.mark.parametrize("odo,status", [(999_999, 200), (1_000_000, 400), (1_234_567, 400)])
def test_initial_odo_is_at_most_six_digits(fake_fs, monkeypatch, odo, status):
    uid = f"qa143-odo-{odo}"
    monkeypatch.setattr(server, "_verify_token", lambda: (uid, "qa@example.com", "user"))
    response = _commit(uid, {"name": "Pinova QA"}, odo=odo)
    assert response.status_code == status
    if status == 400:
        assert response.json["code"] == "invalidOdo" and "999 999" in response.json["userMessage"]


def test_the_third_strike_keeps_the_chat_open(tmp_path):
    """The lock reply is read in the chat; no action jumps to Trợ giúp."""
    engine = AssistantEngine(
        gemini=_NoGemini(), knowledge=KnowledgeBase(None), memory=AssistantMemory(None),
        config_store=PinovaConfigStore(db=None, json_path=tmp_path / "state.json"),
        conduct_store=ConductStore(None, clock=lambda: datetime(2026, 11, 2, 2, 0, tzinfo=timezone.utc)),
        mailer=None)
    replies = [engine.conduct_gate("u3", "đm con bot ngu như bò") for _ in range(3)]
    assert replies[2]["assistantLock"] and replies[2]["actions"] == []
    assert "Trợ giúp" in replies[2]["reply"] or "Hỗ trợ" in replies[2]["reply"]


def _catalog_script():
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
    # An ops script, not in the API image the Linux gate tests.
    return pytest.importorskip("qa143_catalog_specs")


def test_catalog_fields_at_the_old_figures_move_to_vinfast_figures():
    fix = _catalog_script()
    data = {"battery": {"grossCapacityWh": 1872, "calculationCapacityWh": 1872.0, "capacityAh": 39,
                        "chemistry": "LFP"},
            "appDefaults": {"calculationCapacityWh": 1872, "defaultEfficiencyKmPerPercent": 1.2},
            "performance": {"rangeKm": 203, "topSpeedKmh": 70}}
    assert fix.catalog_changes("evo200", data) == {
        "battery.grossCapacityWh": 3500, "battery.calculationCapacityWh": 3500,
        "appDefaults.calculationCapacityWh": 3500, "battery.capacityAh": 73,
        "appDefaults.defaultEfficiencyKmPerPercent": 2.03,
    }


def test_a_value_the_owner_or_admin_changed_is_left_alone():
    fix = _catalog_script()
    assert fix.vehicle_changes("evo200", {"nominalCapacityWh": 2000, "defaultEfficiency": 1.25}) == {}
    assert fix.vehicle_changes("tempest", {"batteryType": "NMC"}) == {}


def test_a_vehicle_on_the_catalog_defaults_gets_every_copy_fixed():
    fix = _catalog_script()
    data = {"batteryCapacity": 2880, "batteryType": "LFP", "defaultEfficiency": 0.9,
            "catalogSnapshot": {"calculationCapacityWh": 2880, "defaultEfficiencyKmPerPercent": 0.9,
                                "batteryChemistry": "LFP"}}
    assert fix.vehicle_changes("tempest", data) == {
        "batteryCapacity": 1260, "catalogSnapshot.calculationCapacityWh": 1260,
        "batteryType": "Lead-acid", "catalogSnapshot.batteryChemistry": "Lead-acid",
        "defaultEfficiency": 0.8, "catalogSnapshot.defaultEfficiencyKmPerPercent": 0.8,
    }


def test_the_script_and_the_bundled_catalog_agree():
    import json
    from pathlib import Path
    fix = _catalog_script()
    bundled = {m["modelId"]: m for m in json.loads(
        (Path(__file__).resolve().parents[1] / "assets" / "vinfast_specs_fallback.json").read_text("utf-8"))}
    for model_id, fields in fix.SPECS.items():
        for key, (_old, new) in fields.items():
            assert bundled[model_id].get(key, "LFP") == new, (model_id, key)
        spec = bundled[model_id]
        assert spec["defaultEfficiencyKmPerPercent"] == round(spec["rangeKm"] / 100, 2)
