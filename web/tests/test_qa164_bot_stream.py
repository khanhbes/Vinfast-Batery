"""QA 164 (owner's choice): Pinova Bot streams its answer.

The model's text reaches the app as it is written (server-sent events), what
Pinova Bot is reading shows as a status, the "GỢI Ý:" line never shows, and
the final checked answer still decides. A relay without the stream operation
falls back to the whole answer at once.
"""
import json
from unittest.mock import MagicMock

from flask import Flask

from assistant.engine import AssistantEngine, VisibleText
from assistant.gemini import GeminiClient, GeminiUnavailable
from assistant.knowledge import KnowledgeBase
from assistant.memory import AssistantMemory
from assistant.quota import DailyQuota
from assistant.routes import create_assistant_blueprint

CONTEXT = {"vehicleId": "v1", "vehicle": {"name": "Feliz", "batteryPercent": 40},
           "vehicles": [{"name": "Feliz"}], "screen": "overview"}


def _sse_lines(chunks):
    return [f"data: {json.dumps(c)}" for c in chunks] + [""]


def _response(status=200, lines=()):
    response = MagicMock(status_code=status)
    response.iter_lines.return_value = iter(lines)
    return response


def _client_with(session):
    client = GeminiClient(api_key="k", model="m", session=session)
    return client


def test_stream_yields_text_as_written_and_keeps_function_calls_verbatim():
    session = MagicMock()
    session.post.return_value = _response(lines=_sse_lines([
        {"candidates": [{"content": {"parts": [{"text": "Pin ", "thoughtSignature": "sig1"}]}}]},
        {"candidates": [{"content": {"parts": [{"text": "còn 40%."}]}}]},
        {"candidates": [{"content": {"parts": [{"functionCall": {"name": "navigate", "args": {}},
                                               "thoughtSignature": "sig2"}]}}]},
    ]))
    events = list(_client_with(session).stream(system="s", contents=[]))
    assert events[:2] == [("text", "Pin "), ("text", "còn 40%.")]
    kind, parts = events[-1]
    assert kind == "parts"
    assert parts[0] == {"text": "Pin còn 40%.", "thoughtSignature": "sig1"}
    assert parts[1]["functionCall"]["name"] == "navigate" and parts[1]["thoughtSignature"] == "sig2"
    url = session.post.call_args.args[0]
    assert url.endswith(":streamGenerateContent?alt=sse")
    assert session.post.call_args.kwargs["stream"] is True


def test_relay_without_the_stream_operation_falls_back_and_remembers(monkeypatch):
    monkeypatch.setenv("GEMINI_RELAY_URL", "https://relay.example/gemini")
    monkeypatch.setenv("GEMINI_RELAY_TOKEN", "t")
    session = MagicMock()
    whole = MagicMock(status_code=200)
    whole.json.return_value = {"candidates": [{"content": {"parts": [{"text": "Chào bạn"}]}}]}
    session.post.side_effect = [_response(status=404), whole, whole]
    client = _client_with(session)
    assert list(client.stream(system="s", contents=[])) == [
        ("text", "Chào bạn"), ("parts", [{"text": "Chào bạn"}])]
    assert session.post.call_args_list[0].args[0].endswith("/v1/stream/m")
    assert session.post.call_args_list[1].args[0].endswith("/v1/generate/m")
    # Next turn: straight to generate, no second 404.
    list(client.stream(system="s", contents=[]))
    assert session.post.call_args_list[2].args[0].endswith("/v1/generate/m")


def test_visible_text_hides_the_follow_up_line_and_markers():
    shown = []
    visible = VisibleText(lambda kind, data: shown.append((kind, data)))
    for piece in ["Sạc lên 80% mất khoảng ", "1 giờ 40 phút.\n", "GỢI Ý: Khi nào ", "đầy? | Tốn bao nhiêu?"]:
        visible.feed(piece)
    text = "".join(data for kind, data in shown if kind == "delta")
    assert text.startswith("Sạc lên 80% mất khoảng 1 giờ 40 phút.")
    assert "GỢI" not in text and "Khi nào" not in text
    marker = []
    hidden = VisibleText(lambda kind, data: marker.append(data))
    hidden.feed("Mình chưa rõ câu này. [UNSCRIPTED_ESCALATE]")
    assert "[" not in "".join(m for m in marker if m)


class StreamingGemini:
    configured = True
    model = "fake"

    def __init__(self, rounds):
        self.rounds = list(rounds)

    def generate(self, **_):
        raise AssertionError("the stream is used")

    def stream(self, **_):
        step = self.rounds.pop(0)
        if isinstance(step, Exception):
            raise step
        for kind, data in step:
            yield kind, data


def _app(gemini, limit=5):
    app = Flask(__name__)
    memory = AssistantMemory()
    eng = AssistantEngine(gemini=gemini, knowledge=KnowledgeBase(), memory=memory)
    quota = DailyQuota(limit=limit)
    app.register_blueprint(create_assistant_blueprint(
        engine=eng, memory=memory, quota=quota, knowledge=eng.knowledge,
        auth_resolver=lambda: ("u1", None, "user"), require_admin=lambda f: f, db=None))
    return app.test_client(), quota


def _events(response):
    body = response.get_data(as_text=True)
    out = []
    for block in body.strip().split("\n\n"):
        lines = block.split("\n")
        event = lines[0].removeprefix("event: ")
        data = json.loads(lines[1].removeprefix("data: "))
        out.append((event, data))
    return out


def test_stream_route_sends_status_text_then_the_checked_answer():
    reply = "Pin còn 40%, đủ đi khoảng 34 km.\nGỢI Ý: Sạc lên 80% mất bao lâu? | Đi 30 km được không?"
    gemini = StreamingGemini([
        [("parts", [{"functionCall": {"name": "get_charger_status", "args": {}}}])],
        [("text", reply[:20]), ("text", reply[20:]), ("parts", [{"text": reply}])],
    ])
    client, quota = _app(gemini)
    response = client.post("/api/assistant/chat",
                           json={"message": "pin còn bao nhiêu", "context": CONTEXT, "stream": True})
    assert response.status_code == 200
    assert response.mimetype == "text/event-stream"
    events = _events(response)
    kinds = [k for k, _ in events]
    assert kinds[0] == "start" and kinds[-1] == "done"
    assert ("status", {"text": "Đang xem ổ Shelly…"}) in events
    streamed = "".join(d["text"] for k, d in events if k == "delta")
    assert streamed and "GỢI Ý" not in streamed
    done = events[-1][1]
    assert done["reply"] == "Pin còn 40%, đủ đi khoảng 34 km."
    assert done["followUps"] == ["Sạc lên 80% mất bao lâu?", "Đi 30 km được không?"]
    assert done["remainingToday"] == 4
    assert quota.used_today("u1") == 1


def test_stream_route_error_refunds_the_message():
    client, quota = _app(StreamingGemini([GeminiUnavailable("network")]))
    response = client.post("/api/assistant/chat",
                           json={"message": "chào", "context": CONTEXT, "stream": True})
    events = _events(response)
    assert events[-1][0] == "error"
    assert events[-1][1]["code"] == "ASSISTANT_UNAVAILABLE"
    assert quota.used_today("u1") == 0


def test_without_stream_flag_the_route_still_answers_json():
    gemini = StreamingGemini([[("text", "Chào bạn"), ("parts", [{"text": "Chào bạn"}])]])
    gemini.generate = lambda **_: [{"text": "Chào bạn"}]
    client, _ = _app(gemini)
    response = client.post("/api/assistant/chat", json={"message": "chào", "context": CONTEXT})
    assert response.get_json()["data"]["reply"] == "Chào bạn"


def test_driving_mode_is_not_streamed():
    gemini = StreamingGemini([])
    gemini.generate = lambda **_: [{"text": "Câu một. Câu hai. Câu ba."}]
    client, _ = _app(gemini)
    response = client.post("/api/assistant/chat", json={
        "message": "pin", "context": {**CONTEXT, "drivingMode": True}, "stream": True})
    events = _events(response)
    assert not [k for k, _ in events if k == "delta"]
    assert events[-1][0] == "done"


def test_health_brief_puts_the_start_first_and_drops_the_charge_list():
    from assistant.engine import health_brief
    brief = health_brief({
        "nominalCapacityWh": 2400,
        "estimate": {"sohPct": 98.8, "samples": 8},
        "spread": {"uncertaintyPct": 2.2, "totalPct": 4.0},
        "tracking": {"status": "ready", "relativePct": 99.4, "uncertaintyPct": 2.8,
                     "since": "2026-09-12T17:00:00+00:00"},
        "charges": [{"at": "x"}] * 20,
        "trend": [{"sohPct": 99}] * 40,
    })
    assert brief == {"nominalCapacityWh": 2400, "relativePct": 99.4, "relativeErrorPct": 2.8,
                     "since": "2026-09", "capacityPct": 98.8, "capacityErrorPct": 4.0,
                     "charges": 8, "stale": False}
    building = health_brief({"estimate": {"sohPct": 99}, "tracking": {"status": "building", "needCharges": 2}})
    assert building["referenceBuilding"] is True and building["needCharges"] == 2


def test_unscripted_flag_never_shows_and_does_not_stop_the_stream():
    shown = []
    visible = VisibleText(lambda kind, data: shown.append(data))
    for piece in ["[UNSCRIPTED_", "ESCALATE]Đây là thông tin chung: không nên ", "lấy điện từ cổng sạc cho thiết bị khác vì dễ hỏng pin."]:
        visible.feed(piece)
    text = "".join(s for s in shown if s)
    assert text.startswith("Đây là thông tin chung")
    assert "[" not in text and "UNSCRIPTED" not in text
