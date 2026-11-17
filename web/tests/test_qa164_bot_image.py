"""QA 164 (owner's choice): a photo for Pinova Bot, Pro and Ultra only.

The photo goes with that one question to the model (inlineData), uses one of
the day's AI photos (shared with the dashboard scan), is never stored, and a
refused or broken photo never costs a message.
"""
import base64

from flask import Flask

from assistant.engine import AssistantEngine
from assistant.knowledge import KnowledgeBase
from assistant.memory import AssistantMemory
from assistant.quota import DailyQuota
from assistant.routes import IMAGE_MAX_BYTES, clean_image, create_assistant_blueprint
from billing.entitlements import EntitlementService

JPEG = base64.b64encode(b"\xff\xd8\xff\xe0" + b"0" * 2000).decode()
CONTEXT = {"vehicleId": "v1", "vehicle": {"name": "Feliz"}, "vehicles": [{"name": "Feliz"}]}


class Gemini:
    configured = True
    model = "fake"

    def __init__(self):
        self.calls = []

    def generate(self, *, system, contents, **_):
        self.calls.append(contents)
        return [{"text": "Đèn này báo pin yếu."}]


def _app(tier="pro", photos=2, messages=5):
    billing = EntitlementService(enforced=True)
    if tier != "free":
        billing.grant("u1", tier, period="month")
    gemini = Gemini()
    memory = AssistantMemory()
    eng = AssistantEngine(gemini=gemini, knowledge=KnowledgeBase(), memory=memory, entitlements=billing)
    quota = DailyQuota(limit=messages)
    image_quota = DailyQuota(limit=photos, partition="scanAiQuota")
    app = Flask(__name__)
    app.register_blueprint(create_assistant_blueprint(
        engine=eng, memory=memory, quota=quota, knowledge=eng.knowledge,
        auth_resolver=lambda: ("u1", None, "user"), require_admin=lambda f: f, db=None,
        image_quota=image_quota))
    return app.test_client(), gemini, quota, image_quota


def test_photo_goes_with_that_question_only():
    client, gemini, quota, photos = _app()
    response = client.post("/api/assistant/chat", json={
        "message": "đèn này là gì", "context": CONTEXT,
        "image": {"mimeType": "image/jpeg", "data": JPEG}})
    assert response.status_code == 200
    parts = gemini.calls[0][-1]["parts"]
    assert parts[0] == {"inlineData": {"mimeType": "image/jpeg", "data": JPEG}}
    assert parts[1] == {"text": "đèn này là gì"}
    assert quota.used_today("u1") == 1 and photos.used_today("u1") == 1
    # The next question carries no photo.
    client.post("/api/assistant/chat", json={"message": "cảm ơn", "context": CONTEXT})
    assert all("inlineData" not in part for turn in gemini.calls[1] for part in turn["parts"])


def test_a_photo_without_words_gets_a_question():
    client, gemini, _, _ = _app()
    client.post("/api/assistant/chat", json={"message": "", "context": CONTEXT,
                                             "image": {"mimeType": "image/jpeg", "data": JPEG}})
    assert gemini.calls[0][-1]["parts"][1] == {"text": "Bạn xem giúp mình ảnh này."}


def test_free_plan_gets_premium_required_and_spends_nothing():
    client, gemini, quota, photos = _app(tier="free")
    response = client.post("/api/assistant/chat", json={
        "message": "đèn này là gì", "image": {"mimeType": "image/jpeg", "data": JPEG}})
    assert response.status_code == 403
    assert response.get_json()["error"]["code"] == "PREMIUM_REQUIRED"
    assert not gemini.calls and quota.used_today("u1") == 0 and photos.used_today("u1") == 0


def test_the_days_photos_run_out_before_the_messages():
    client, _, quota, _ = _app(photos=1)
    image = {"mimeType": "image/jpeg", "data": JPEG}
    assert client.post("/api/assistant/chat", json={"message": "a", "image": image}).status_code == 200
    over = client.post("/api/assistant/chat", json={"message": "b", "image": image})
    assert over.status_code == 429 and over.get_json()["error"]["code"] == "IMAGE_QUOTA"
    assert quota.used_today("u1") == 1


def test_broken_or_big_or_disguised_photos_are_refused():
    assert clean_image({"mimeType": "image/gif", "data": JPEG}) is None
    assert clean_image({"mimeType": "image/jpeg", "data": "not base64!"}) is None
    assert clean_image({"mimeType": "image/png", "data": JPEG}) is None  # not a PNG
    big = base64.b64encode(b"\xff\xd8" + b"0" * (IMAGE_MAX_BYTES + 10)).decode()
    assert clean_image({"mimeType": "image/jpeg", "data": big}) is None
    client, gemini, quota, _ = _app()
    response = client.post("/api/assistant/chat", json={
        "message": "x", "image": {"mimeType": "image/jpeg", "data": "%%%"}})
    assert response.status_code == 400 and not gemini.calls and quota.used_today("u1") == 0


def test_a_failed_turn_gives_back_the_photo_too():
    client, gemini, quota, photos = _app()

    def broken(**_):
        raise RuntimeError("boom")

    gemini.generate = broken
    response = client.post("/api/assistant/chat", json={
        "message": "x", "image": {"mimeType": "image/jpeg", "data": JPEG}})
    assert response.status_code == 503
    assert quota.used_today("u1") == 0 and photos.used_today("u1") == 0
