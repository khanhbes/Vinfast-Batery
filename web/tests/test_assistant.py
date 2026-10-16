"""Task 124 — BatteryBot v2 engine, memory, quota and routes (fake Gemini)."""
from types import SimpleNamespace
from datetime import datetime, timezone

import pytest
from flask import Flask

from assistant.engine import AssistantEngine, habits_from, summarize_session, validate_action
from assistant.gemini import GeminiUnavailable
from assistant.knowledge import KnowledgeBase, fold
from assistant.memory import AssistantMemory
from assistant.quota import DailyQuota
from assistant.routes import create_assistant_blueprint


class FakeGemini:
    configured = True
    model = "fake"

    def __init__(self, script):
        self.script = list(script)
        self.calls = []

    def generate(self, *, system, contents, tools=None, **_):
        self.calls.append({"system": system, "contents": contents, "tools": [t["name"] for t in tools or []]})
        if not self.script:
            return [{"text": "ok"}]
        step = self.script.pop(0)
        if isinstance(step, Exception):
            raise step
        return step


def engine(script, **kwargs):
    memory = kwargs.pop("memory", AssistantMemory())
    return AssistantEngine(gemini=FakeGemini(script), knowledge=KnowledgeBase(), memory=memory, **kwargs), memory


CONTEXT = {"vehicleId": "v1", "vehicle": {"name": "Feliz", "batteryPercent": 40},
           "vehicles": [{"name": "Feliz"}, {"name": "Evo Grand"}], "screen": "overview"}


def test_plain_answer_uses_knowledge_and_context_in_prompt():
    eng, _ = engine([[{"text": "Bạn mở tab **Lịch sử** nhé."}]])
    result = eng.chat("u1", "Xem lịch sử sạc ở đâu?", [], CONTEXT)
    timings = result.pop("timingsMs")
    assert {"profile", "model1", "total"} <= set(timings)
    assert result == {"reply": "Bạn mở tab **Lịch sử** nhé.", "actions": [], "source": "gemini",
                      "memoryChanged": False}
    system = eng.gemini.calls[0]["system"]
    assert "Lịch sử sạc" in system and '"batteryPercent": 40' in system


def test_client_action_is_validated_and_returned_not_executed():
    eng, _ = engine([[{"text": "Mình chuẩn bị bật sạc 45 phút."},
                      {"functionCall": {"name": "start_timed_charging", "args": {"minutes": 45}}}]])
    result = eng.chat("u1", "sạc giúp 45 phút", [], CONTEXT)
    assert result["actions"] == [{"name": "start_timed_charging", "args": {"minutes": 45}}]
    assert len(eng.gemini.calls) == 1  # no follow-up turn after a client action


@pytest.mark.parametrize("name,args", [
    ("start_timed_charging", {"minutes": 0}), ("start_timed_charging", {"minutes": 9999}),
    ("update_battery_level", {"percent": 140}), ("set_target_soc", {"percent": 20}),
    ("select_vehicle", {"vehicle_name": "Xe hàng xóm"}), ("navigate", {"screen": "admin_panel"}),
    ("create_reminder", {"kind": "maintenance", "date": "2020-01-01"}),
    ("set_electricity_price", {"vnd_per_kwh": 99}), ("rm_rf", {}),
    ("set_app_setting", {"setting": "language", "value": "en"}),
    ("set_app_setting", {"setting": "theme", "value": "dark"}),
])
def test_invalid_model_arguments_are_dropped(name, args):
    assert validate_action(name, args, CONTEXT) is None


def test_app_settings_accept_only_known_values():
    assert validate_action("set_app_setting", {"setting": "push_notifications", "value": "OFF"}, CONTEXT) == {"setting": "push_notifications", "value": "off"}
    assert validate_action("set_app_setting", {"setting": "push_notifications", "value": "maybe"}, CONTEXT) is None


def test_setting_action_alone_gets_a_specific_sentence():
    eng, _ = engine([[{"functionCall": {"name": "set_app_setting",
                                        "args": {"setting": "push_notifications", "value": "off"}}}]])
    result = eng.chat("u1", "tắt thông báo", [], CONTEXT)
    assert result["actions"] == [{"name": "set_app_setting", "args": {"setting": "push_notifications", "value": "off"}}]
    assert "tắt thông báo đẩy" in result["reply"]


def test_vehicle_name_matches_only_the_users_vehicles():
    assert validate_action("select_vehicle", {"vehicle_name": "evo"}, CONTEXT) == {"vehicle_name": "Evo Grand"}


def test_server_tools_run_then_model_answers():
    live = {"status": {"online": True, "relay": True, "power_w": 410, "timer_remaining": 600},
            "session": {"state": "active", "estimated_soc": 55}}
    eng, _ = engine([[{"functionCall": {"name": "get_charger_status", "args": {}}}],
                     [{"text": "Đang sạc **410 W**."}]],
                    live_reader=lambda uid, vid: live)
    result = eng.chat("u1", "đang sạc không", [], CONTEXT)
    assert result["reply"] == "Đang sạc **410 W**."
    response = eng.gemini.calls[1]["contents"][-1]["parts"][0]["functionResponse"]
    assert response["name"] == "get_charger_status" and response["response"]["powerW"] == 410


def test_remember_and_forget_change_memory_and_respect_opt_out():
    eng, memory = engine([[{"functionCall": {"name": "remember",
                                             "args": {"fact": "Đi làm 15 km mỗi ngày", "category": "habit"}}}],
                          [{"text": "Mình nhớ rồi."}]])
    result = eng.chat("u1", "tôi đi làm 15 km mỗi ngày", [], CONTEXT)
    assert result["memoryChanged"] is True
    assert [f["text"] for f in memory.facts("u1")] == ["Đi làm 15 km mỗi ngày"]
    # Facts are injected into the next prompt.
    eng.gemini.script = [[{"text": "ok"}]]
    eng.chat("u1", "nên sạc bao nhiêu", [], CONTEXT)
    assert "Đi làm 15 km mỗi ngày" in eng.gemini.calls[-1]["system"]
    # Opt-out: no remember tool offered, no facts in the prompt.
    memory.set_learning("u1", False)
    eng.gemini.script = [[{"text": "ok"}]]
    eng.chat("u1", "nên sạc bao nhiêu", [], CONTEXT)
    assert "remember" not in eng.gemini.calls[-1]["tools"]
    assert "Đi làm 15 km" not in eng.gemini.calls[-1]["system"]


def test_memory_never_stores_secrets():
    memory = AssistantMemory()
    for text in ["mật khẩu là 123456", "email a@b.com", "số tài khoản 0123456789", "ab"]:
        assert memory.remember("u1", text) is None
    assert memory.facts("u1") == []


def test_sensitive_message_never_reaches_the_model():
    eng, _ = engine([])
    result = eng.chat("u1", "auth_key của tôi là abcdefabcdefabcdefabcdefabcdefabcd", [], CONTEXT)
    assert eng.gemini.calls == [] and "mật khẩu" in result["reply"]


def test_habits_from_history():
    raw = [{"session_id": f"s{i}", "created_at": f"2026-10-1{i}T13:00:00+00:00",
            "stopped_at": f"2026-10-1{i}T14:00:00+00:00", "state": "completed", "target_soc": 80,
            "energy_used_wh": 500, "strategy": "manual_timed"} for i in range(3)]
    sessions = [summarize_session(item) for item in raw]
    habits = habits_from(sessions)
    assert habits["sessions"] == 3 and habits["usualStartHour"] == 20  # 13:00Z = 20:00 VN
    assert habits["medianMinutes"] == 60 and habits["usualTargetSoc"] == 80


def test_knowledge_search_folds_accents():
    kb = KnowledgeBase()
    assert kb.search("lam sao ket noi shelly")[0]["id"] == "shelly-connect"
    assert fold("Đặt giá điện") == "dat gia dien"


def test_quota_limits_and_refunds():
    quota = DailyQuota(limit=2)
    assert quota.take("u1") == (True, 1)
    assert quota.take("u1") == (True, 0)
    assert quota.take("u1") == (False, 0)
    quota.refund("u1")
    assert quota.take("u1")[0] is True
    assert quota.take("u2") == (True, 1)  # per account


def _client(script, limit=50):
    app = Flask(__name__)
    eng, memory = engine(script)
    quota = DailyQuota(limit=limit)
    app.register_blueprint(create_assistant_blueprint(
        engine=eng, memory=memory, quota=quota, knowledge=eng.knowledge,
        auth_resolver=lambda: ("u1", None, "user"), require_admin=lambda f: f, db=None))
    return app.test_client(), memory, quota


def test_chat_route_quota_and_fallback_codes():
    client, _, _ = _client([[{"text": "Chào bạn"}], GeminiUnavailable("http500")], limit=2)
    ok = client.post("/api/assistant/chat", json={"message": "chào", "context": CONTEXT})
    assert ok.status_code == 200 and ok.get_json()["data"]["reply"] == "Chào bạn"
    down = client.post("/api/assistant/chat", json={"message": "chào"})
    assert down.status_code == 503 and down.get_json()["error"]["code"] == "ASSISTANT_UNAVAILABLE"
    # The failed turn was refunded: one more allowed, then the quota answers 429.
    assert client.post("/api/assistant/chat", json={"message": "x"}).status_code == 200
    over = client.post("/api/assistant/chat", json={"message": "x"})
    assert over.status_code == 429 and over.get_json()["error"]["code"] == "ASSISTANT_QUOTA"


def test_memory_routes_list_delete_and_toggle():
    client, memory, _ = _client([])
    fact = memory.remember("u1", "Thích sạc buổi tối", "preference")
    data = client.get("/api/assistant/memory").get_json()["data"]
    assert data["settings"] == {"learningEnabled": True} and data["facts"][0]["text"] == "Thích sạc buổi tối"
    assert client.delete(f"/api/assistant/memory/{fact['id']}").get_json()["data"]["deleted"] is True
    assert client.put("/api/assistant/settings", json={"learningEnabled": False}).get_json()["data"] == \
        {"learningEnabled": False}
    assert memory.remember("u1", "Không được lưu") is None


def test_answer_and_remember_in_one_turn_skips_the_second_model_call():
    eng, memory = engine([[{"text": "Nên sạc tới 80%."},
                           {"functionCall": {"name": "remember",
                                             "args": {"fact": "Đi làm 12 km mỗi ngày", "category": "habit"}}}]])
    result = eng.chat("u1", "đi làm 12 km, sạc bao nhiêu", [], CONTEXT)
    assert result["reply"] == "Nên sạc tới 80%." and result["memoryChanged"] is True
    assert len(eng.gemini.calls) == 1
    assert [f["text"] for f in memory.facts("u1")] == ["Đi làm 12 km mỗi ngày"]


def test_history_turn_with_a_secret_never_reaches_the_model():
    eng, _ = engine([[{"text": "ok"}]])
    eng.chat("u1", "tiếp tục", [{"role": "user", "text": "api key của tôi là abcdefabcdefabcdefabcdefabcdefabcd"},
                                {"role": "assistant", "text": "Đừng gửi"}], CONTEXT)
    sent = " ".join(p.get("text", "") for c in eng.gemini.calls[0]["contents"] for p in c["parts"])
    assert "abcdefabcdef" not in sent and "Đừng gửi" in sent


def test_empty_and_secret_messages_do_not_spend_quota():
    client, _, quota = _client([], limit=1)
    for message in ("", "mật khẩu là 123456"):
        response = client.post("/api/assistant/chat", json={"message": message})
        assert response.status_code == 200
    assert quota.used_today("u1") == 0


def test_unexpected_engine_error_refunds_the_message(monkeypatch):
    client, _, quota = _client([], limit=1)
    app_engine = client.application.blueprints  # noqa: F841 - keep app alive
    import assistant.engine as engine_module
    monkeypatch.setattr(engine_module.AssistantEngine, "chat",
                        lambda *a, **k: (_ for _ in ()).throw(ValueError("bug")))
    response = client.post("/api/assistant/chat", json={"message": "chào"})
    assert response.status_code == 503 and quota.used_today("u1") == 0


def test_last_round_forces_a_text_answer():
    calls = [[{"functionCall": {"name": "get_charging_history", "args": {}}}]] * 2 + [[{"text": "Xong"}]]
    eng, _ = engine(calls, history_reader=lambda uid, vid, n: [])
    modes = []
    original = eng.gemini.generate

    def spy(**kwargs):
        modes.append(kwargs.get("tool_mode"))
        return original(**kwargs)

    eng.gemini.generate = spy
    assert eng.chat("u1", "lịch sử sạc", [], CONTEXT)["reply"] == "Xong"
    assert modes == ["AUTO", "AUTO", "NONE"]


def test_forget_removes_only_the_fact_meant_and_ignores_accents():
    memory = AssistantMemory()
    memory.remember("u1", "Thích sạc buổi tối", "preference")
    memory.remember("u1", "Hay sạc ở nhà", "habit")
    memory.remember("u1", "Đi làm khoảng 12 km mỗi ngày", "habit")
    assert memory.forget_matching("u1", "sạc") == 0  # two facts: ambiguous
    assert memory.forget_matching("u1", "di lam 12 km") == 1  # no accents
    assert memory.forget_matching("u1", "sac buoi toi") == 1
    assert [f["text"] for f in memory.facts("u1")] == ["Hay sạc ở nhà"]


def test_knowledge_edit_is_validated_and_audited():
    writes, audits = [], []
    doc = SimpleNamespace(set=lambda data: writes.append(data), delete=lambda: writes.append("deleted"))
    db = SimpleNamespace(collection=lambda name: SimpleNamespace(document=lambda doc_id: doc))
    app = Flask(__name__)
    eng, memory = engine([])
    app.register_blueprint(create_assistant_blueprint(
        engine=eng, memory=memory, quota=DailyQuota(), knowledge=eng.knowledge,
        auth_resolver=lambda: ("admin", None, "admin"), require_admin=lambda f: f, db=db,
        audit=lambda *args: audits.append(args)))
    client = app.test_client()
    url = "/api/admin/assistant/knowledge/bao-hanh"
    assert client.put(url, json={"title": "T" * 121, "body": "x"}).status_code == 400
    assert client.put(url, json={"title": "Bảo hành", "body": "x", "keywords": "bảo hành"}).status_code == 400
    assert writes == [] and audits == []
    ok = client.put(url, json={"title": "Bảo hành", "body": "Pin bảo hành 3 năm", "keywords": ["bảo hành"]})
    assert ok.status_code == 200 and writes[0]["keywords"] == ["bảo hành"]
    assert audits[0][0] == "assistant_knowledge_update" and audits[0][2] == "bao-hanh"
    assert client.delete(url).status_code == 200 and audits[-1][0] == "assistant_knowledge_delete"
