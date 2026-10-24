"""QA 135 — dashboard photo reading with an image model (fake Gemini)."""
import base64

import pytest
from flask import Flask

from assistant.gemini import GeminiUnavailable
from assistant.quota import DailyQuota
from scan.reader import DashboardImageReader, ScanError, decode_image, parse_answer
from scan.routes import create_scan_blueprint

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


class FakeGemini:
    configured = True

    def __init__(self, answers):
        self.answers = list(answers)
        self.calls = []

    def generate(self, **kwargs):
        self.calls.append(kwargs)
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return [{"text": answer}]


def test_answers_are_validated():
    assert parse_answer('{"soc": 68, "odoKm": 4818, "confidence": 0.9}') == \
        {"soc": 68, "odoKm": 4818.0, "confidence": 0.9}
    assert parse_answer('```json\n{"soc": "68%", "odoKm": "48 18 km"}\n```') == \
        {"soc": 68, "odoKm": 4818.0, "confidence": 0.5}
    assert parse_answer('{"soc": 140, "odoKm": -3}')["soc"] is None
    assert parse_answer('{"soc": 68.5, "odoKm": 2000000}') == {"soc": None, "odoKm": None, "confidence": 0.5}
    assert parse_answer('{"soc": true}')["soc"] is None
    assert parse_answer("không đọc được") == {"soc": None, "odoKm": None, "confidence": 0.0}
    # The odometer never goes back.
    assert parse_answer('{"odoKm": 4700}', last_odo_km=4804)["odoKm"] is None
    assert parse_answer('{"odoKm": 4818}', last_odo_km=4804)["odoKm"] == 4818.0
    assert parse_answer('{"soc": 5, "odoKm": "123.456"}')["odoKm"] == 123456.0


def test_images_are_checked_before_the_model():
    data, mime = decode_image(base64.b64encode(PNG).decode(), "image/png")
    assert data == PNG and mime == "image/png"
    for raw, mime in ((base64.b64encode(b"GIF89a").decode(), "image/png"),
                      ("not-base64!!", "image/png"),
                      ("", "image/png"),
                      (base64.b64encode(PNG).decode(), "image/gif")):
        with pytest.raises(ScanError):
            decode_image(raw, mime)
    with pytest.raises(ScanError) as error:
        decode_image(base64.b64encode(b"\x89PNG" + b"0" * (400 * 1024)).decode(), "image/png")
    assert error.value.status == 413


def test_reader_sends_one_image_and_asks_for_json():
    gemini = FakeGemini(['{"soc": 68, "odoKm": 4818, "confidence": 0.8}'])
    result = DashboardImageReader(gemini).read(PNG, "image/png", 4804)
    assert result["soc"] == 68 and result["odoKm"] == 4818
    call = gemini.calls[0]
    assert call["response_mime_type"] == "application/json"
    parts = call["contents"][0]["parts"]
    assert parts[0]["inlineData"]["mimeType"] == "image/png"
    assert base64.b64decode(parts[0]["inlineData"]["data"]) == PNG
    assert "4804" in parts[1]["text"]


def _client(answers, limit=2):
    app = Flask(__name__)
    gemini = FakeGemini(answers)
    quota = DailyQuota(limit=limit, partition="scanAiQuota")
    app.register_blueprint(create_scan_blueprint(
        reader=DashboardImageReader(gemini), quota=quota,
        auth_resolver=lambda: ("u1", None, "user")))
    return app.test_client(), quota


def test_route_quota_refund_and_errors():
    http, quota = _client([GeminiUnavailable("http500"), '{"soc": 68, "odoKm": 4818}',
                           '{"soc": 8, "odoKm": null}'])
    body = {"image": base64.b64encode(PNG).decode(), "mimeType": "image/png", "lastOdoKm": 4804}
    down = http.post("/api/scan/dashboard", json=body)
    assert down.status_code == 503 and down.get_json()["retryable"] is True
    assert quota.used_today("u1") == 0  # refunded
    ok = http.post("/api/scan/dashboard", json=body).get_json()["data"]
    assert ok["soc"] == 68 and ok["odoKm"] == 4818 and ok["remainingToday"] == 1
    assert http.post("/api/scan/dashboard", json=body).status_code == 200
    over = http.post("/api/scan/dashboard", json=body)
    assert over.status_code == 429 and over.get_json()["code"] == "scanAiQuota"
    bad = http.post("/api/scan/dashboard", json={"image": "x", "mimeType": "image/png"})
    assert bad.status_code == 400


def test_route_needs_login_and_configuration():
    app = Flask(__name__)

    class Off:
        configured = False

    app.register_blueprint(create_scan_blueprint(
        reader=DashboardImageReader(Off()), quota=DailyQuota(limit=5),
        auth_resolver=lambda: (None, None, None)))
    assert app.test_client().post("/api/scan/dashboard", json={}).status_code == 401
    app2 = Flask(__name__)
    app2.register_blueprint(create_scan_blueprint(
        reader=DashboardImageReader(Off()), quota=DailyQuota(limit=5),
        auth_resolver=lambda: ("u1", None, "user")))
    assert app2.test_client().post("/api/scan/dashboard", json={}).status_code == 503
