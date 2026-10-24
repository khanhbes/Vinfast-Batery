"""QA 135 — help for every plan: tickets, diagnostics, admin email, replies."""
import base64
import hashlib
import hmac
import json

import pytest
from flask import Flask

from assistant.quota import DailyQuota
from support.mailer import SupportMailer, parse_connection_string, signed_headers
from support.routes import create_support_blueprint
from support.tickets import SupportError, SupportService, clean_diagnostics

KEY = base64.b64encode(b"secret-key-bytes").decode()
CONNECTION = f"endpoint=https://pinova-acs.communication.azure.com/;accesskey={KEY}"


class FakeHttp:
    def __init__(self, status=202):
        self.status = status
        self.calls = []

    def post(self, url, data, headers, timeout):
        self.calls.append({"url": url, "body": json.loads(data), "headers": headers})
        return type("R", (), {"status_code": self.status})()


def mailer(http=None, **kwargs):
    return SupportMailer(CONNECTION, sender="DoNotReply@x.azurecomm.net",
                         recipients=kwargs.get("recipients", "admin@pinova.vn"),
                         session=http or FakeHttp(), background=False)


def test_connection_string_and_hmac_signature():
    endpoint, key = parse_connection_string(CONNECTION)
    assert endpoint == "https://pinova-acs.communication.azure.com" and key == b"secret-key-bytes"
    assert parse_connection_string("endpoint=http://x;accesskey=abc") is None
    assert parse_connection_string("") is None
    body = b'{"a":1}'
    headers = signed_headers(endpoint, key, "/emails:send?api-version=2023-03-31", body,
                             "Sun, 25 Oct 2026 03:00:00 GMT")
    digest = base64.b64encode(hashlib.sha256(body).digest()).decode()
    expected = base64.b64encode(hmac.new(
        key, f"POST\n/emails:send?api-version=2023-03-31\nSun, 25 Oct 2026 03:00:00 GMT;"
             f"pinova-acs.communication.azure.com;{digest}".encode(), hashlib.sha256).digest()).decode()
    assert headers["x-ms-content-sha256"] == digest
    assert headers["Authorization"].endswith(f"Signature={expected}")


def test_mailer_needs_full_configuration():
    assert mailer().configured
    assert not SupportMailer("", sender="a@b.c", recipients="x@y.z", background=False).configured
    assert not SupportMailer(CONNECTION, sender="", recipients="x@y.z", background=False).configured
    assert not SupportMailer(CONNECTION, sender="a@b.c", recipients="", background=False).configured
    assert SupportMailer("", sender="", recipients="", background=False).send("s", "t") is False


def test_diagnostics_drop_secrets_and_cap_size():
    raw = {"appVersion": "1.3.0+197", "idToken": "eyJabc", "shelly": {"online": True, "authKey": "k"},
           "note": "Bearer abc.def", "x" * 80: "y" * 500, "perms": ["camera", "notifications"],
           "n": 3, "ok": False}
    clean = clean_diagnostics(raw)
    assert clean["appVersion"] == "1.3.0+197"
    assert "idToken" not in clean and "note" not in clean
    assert clean["shelly"] == {"online": True}
    assert len(next(v for k, v in clean.items() if k.startswith("x"))) == 200
    assert clean["perms"] == ["camera", "notifications"] and clean["n"] == 3 and clean["ok"] is False
    assert clean_diagnostics("nope") == {}


def service(**kwargs):
    notes = []
    svc = SupportService(mailer=kwargs.get("mailer", mailer(kwargs.get("http"))),
                         notifier=lambda *args: notes.append(args),
                         quota=kwargs.get("quota", DailyQuota(limit=5, partition="supportQuota")),
                         portal_url="https://portal.pinova.vn/")
    return svc, notes


def test_ticket_flow_user_admin_reply_and_unread():
    http = FakeHttp()
    svc, notes = service(http=http)
    ticket = svc.create("u1", "u1@x.vn", {"subject": "Không bật được sạc", "category": "shelly",
                                         "message": "Bấm vuốt để sạc nhưng ổ không bật.",
                                         "diagnostics": {"appVersion": "1.3.0", "token": "t"}}, tier="pro")
    assert ticket["status"] == "open" and ticket["categoryLabel"] == "Ổ sạc Shelly"
    mail = http.calls[0]["body"]
    assert mail["content"]["subject"] == "[Pinova hỗ trợ] Không bật được sạc"
    assert "u1@x.vn" in mail["content"]["plainText"] and "appVersion: 1.3.0" in mail["content"]["plainText"]
    assert "token" not in mail["content"]["plainText"]
    assert "https://portal.pinova.vn/support" in mail["content"]["plainText"]
    assert svc.unread_count() == 1
    admin = svc.admin_get(ticket["id"])
    assert admin["tier"] == "pro" and admin["emailSent"] is True and svc.unread_count() == 0
    answered = svc.admin_reply(ticket["id"], "Bạn kiểm tra ổ đã cấp nguồn chưa nhé.", actor="admin")
    assert answered["status"] == "answered" and answered["replies"][-1]["by"] == "admin"
    assert notes and notes[0][0] == "u1" and notes[0][1] == ticket["id"]
    mine = svc.mine("u1")
    assert mine[0]["unread"] is True and svc.mine("u2") == []
    assert svc.get_mine("u1", ticket["id"])["unread"] is False
    again = svc.user_reply("u1", ticket["id"], "Đã cấp nguồn, vẫn không bật.")
    assert again["status"] == "open" and len(http.calls) == 2 and svc.unread_count() == 1
    closed = svc.admin_reply(ticket["id"], "", status="closed")
    assert closed["status"] == "closed"
    with pytest.raises(SupportError):
        svc.get_mine("u2", ticket["id"])  # not the owner
    assert [t["id"] for t in svc.admin_list("closed")] == [ticket["id"]]
    assert svc.admin_list("open") == []


def test_ticket_validation_and_daily_limit():
    svc, _ = service()
    for bad in ({"subject": "", "message": "đủ dài để gửi đi"}, {"subject": "Lỗi", "message": "ngắn"},
                {"subject": "x" * 121, "message": "đủ dài để gửi đi"}):
        with pytest.raises(SupportError):
            svc.create("u1", None, bad)
    for _ in range(5):
        svc.create("u1", None, {"subject": "Hỏi", "message": "Câu hỏi đủ dài nhé"})
    with pytest.raises(SupportError) as error:
        svc.create("u1", None, {"subject": "Hỏi", "message": "Câu hỏi đủ dài nhé"})
    assert error.value.code == "supportQuota" and error.value.status == 429


def test_ticket_is_kept_when_email_fails_or_is_not_configured():
    svc, _ = service(http=FakeHttp(status=500))
    ticket = svc.create("u1", None, {"subject": "Hỏi", "message": "Câu hỏi đủ dài nhé"})
    assert svc.admin_get(ticket["id"])["emailSent"] is False
    bare = SupportService()
    assert bare.create("u1", None, {"subject": "Hỏi", "message": "Câu hỏi đủ dài nhé"})["status"] == "open"


def test_routes_user_and_admin():
    app = Flask(__name__)
    svc, notes = service()
    app.register_blueprint(create_support_blueprint(
        service=svc, auth_resolver=lambda: ("u1", "u1@x.vn", "user"), require_admin=lambda f: f,
        tier_of=lambda uid: "ultra"))
    http = app.test_client()
    created = http.post("/api/support/tickets", json={"subject": "Quét sai", "category": "scan",
                                                      "message": "Đồng hồ 68% nhưng app đọc 8%."})
    assert created.status_code == 200
    ticket_id = created.get_json()["data"]["id"]
    assert http.get("/api/support/tickets").get_json()["data"]["items"][0]["id"] == ticket_id
    listing = http.get("/api/admin/support").get_json()["data"]
    assert listing["unread"] == 1 and listing["items"][0]["tier"] == "ultra" and listing["emailConfigured"]
    replied = http.post(f"/api/admin/support/{ticket_id}/reply", json={"text": "Đã ghi nhận, cảm ơn bạn."})
    assert replied.get_json()["data"]["status"] == "answered" and notes
    assert http.post(f"/api/support/tickets/{ticket_id}/replies", json={"text": "OK"}).status_code == 200
    bad = http.post("/api/support/tickets", json={"subject": "x"})
    assert bad.status_code == 400 and bad.get_json()["userMessage"]
    assert http.get("/api/support/tickets/nope").status_code == 404
