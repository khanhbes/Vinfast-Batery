"""QA 140 (item 11): the public privacy policy and the owner's consent."""
from __future__ import annotations

from types import SimpleNamespace

from flask import Flask

from support import privacy
from support.routes import create_support_blueprint


def _client(uid="owner"):
    app = Flask(__name__)
    caller = {"uid": uid}
    app.register_blueprint(create_support_blueprint(
        service=SimpleNamespace(db=None),
        auth_resolver=lambda: (caller["uid"], "o@example.com", "user"),
        require_admin=lambda f: f,
    ))
    return app.test_client(), caller


def test_the_policy_page_is_public_and_names_controller_contact_and_third_parties():
    client, caller = _client(uid=None)
    page = client.get("/chinh-sach-bao-mat")
    assert page.status_code == 200 and "text/html" in page.content_type
    text = page.get_data(as_text=True)
    for must in (privacy.CONTROLLER, privacy.CONTACT_EMAIL, privacy.VERSION, "Firebase", "Gemini",
                 "Shelly Cloud", "Hoa Kỳ", "Xóa tài khoản"):
        assert must in text, must
    assert client.get("/privacy-policy").status_code == 200


def test_consent_needs_sign_in_and_the_current_version():
    client, caller = _client()
    assert client.get("/api/account/privacy-consent").get_json()["data"]["accepted"] is False
    stale = client.post("/api/account/privacy-consent", json={"version": "2020-01-01"})
    assert stale.status_code == 409
    done = client.post("/api/account/privacy-consent", json={"version": privacy.VERSION, "source": "register"})
    assert done.status_code == 200 and done.get_json()["data"]["accepted"] is True
    caller["uid"] = None
    assert client.get("/api/account/privacy-consent").status_code == 401
    assert client.post("/api/account/privacy-consent", json={"version": privacy.VERSION}).status_code == 401
