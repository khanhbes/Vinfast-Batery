"""QA 138 — the owner deletes their own account in the app (Google Play and
App Store rule): recent sign-in, confirmation phrase, never during a Smart
Charge session, same purge as the admin portal (now also night plans and
support tickets), and a public page explaining it."""
from __future__ import annotations

import time
import uuid
from datetime import datetime, timedelta, timezone

import pytest

import server


class _Snap:
    def __init__(self, db, path):
        self.reference = _Ref(db, path)
        self.id = path.rsplit("/", 1)[-1]
        self._data = db.docs.get(path)

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return dict(self._data) if self._data is not None else None


class _Ref:
    def __init__(self, db, path):
        self.db, self.path = db, path

    def collections(self):
        prefix = self.path + "/"
        names = {p[len(prefix):].split("/")[0] for p in self.db.docs if p.startswith(prefix)}
        return [_Query(self.db, f"{self.path}/{name}") for name in sorted(names)]

    def delete(self):
        self.db.docs.pop(self.path, None)

    def get(self, **_):
        return _Snap(self.db, self.path)

    def set(self, data, merge=False):
        self.db.docs[self.path] = {**(self.db.docs.get(self.path) or {}), **data} if merge else dict(data)


class _Query:
    def __init__(self, db, path, filters=()):
        self.db, self.path, self.filters = db, path, tuple(filters)

    def document(self, doc_id=None):
        return _Ref(self.db, f"{self.path}/{doc_id or uuid.uuid4().hex}")

    def where(self, field, op, value):
        assert op == "=="
        return _Query(self.db, self.path, self.filters + ((field, value),))

    def limit(self, _n):
        return self

    def add(self, data):
        self.document().set(data)

    def stream(self):
        depth = self.path.count("/") + 1
        for path in sorted(self.db.docs):
            if not path.startswith(self.path + "/") or path.count("/") != depth:
                continue
            data = self.db.docs[path]
            if all(data.get(f) == v for f, v in self.filters):
                yield _Snap(self.db, path)


class _FakeFirestore:
    def __init__(self, docs):
        self.docs = dict(docs)

    def collection(self, name):
        return _Query(self, name)


class _FakeAuth:
    def __init__(self, uid="owner-1", email="owner@example.com", auth_time=None):
        self.uid, self.email = uid, email
        self.auth_time = time.time() if auth_time is None else auth_time
        self.calls = []

    def verify_id_token(self, token, check_revoked=False):
        return {"uid": self.uid, "email": self.email, "auth_time": self.auth_time}

    def update_user(self, uid, **fields):
        self.calls.append(("update_user", uid, fields))

    def revoke_refresh_tokens(self, uid):
        self.calls.append(("revoke", uid))

    def delete_user(self, uid):
        self.calls.append(("delete_user", uid))


def _owner_data(extra=None):
    docs = {
        "users/owner-1": {"email": "owner@example.com"},
        "users/owner-1/smartChargingSessions/s1": {"state": "completed"},
        "users/owner-1/entitlements/current": {"tier": "free"},
        "Vehicles/car-1": {"ownerUid": "owner-1"},
        "ChargeLogs/log-1": {"ownerUid": "owner-1"},
        "nightPlans/owner-1__car-1": {"uid": "owner-1", "state": "armed"},
        "supportTickets/20261026-ab12": {"uid": "owner-1", "message": "xin chào"},
        "Vehicles/car-2": {"ownerUid": "someone-else"},
        "users/someone-else": {"email": "other@example.com"},
    }
    docs.update(extra or {})
    return docs


@pytest.fixture
def owner(monkeypatch):
    def setup(auth_time=None, email="owner@example.com", extra=None):
        db = _FakeFirestore(_owner_data(extra))
        auth = _FakeAuth(email=email, auth_time=auth_time)
        monkeypatch.setattr(server, "_firestore_db", db)
        monkeypatch.setattr(server, "_firebase_available", True)
        monkeypatch.setattr(server, "_firebase_auth", auth)
        monkeypatch.setattr(server, "ADMIN_EMAILS", ["admin@vinfast.vn"])
        return db, auth
    return setup


def _delete(client, confirm="XOA TAI KHOAN"):
    return client.delete("/api/account", json={"confirm": confirm},
                         headers={"Authorization": "Bearer fresh-token"})


def test_the_owner_deletes_the_account_and_every_piece_of_their_data(client, owner):
    db, auth = owner()
    response = _delete(client)
    assert response.status_code == 200, response.get_json()
    left = sorted(db.docs)
    assert not [p for p in left if "owner-1" in p], left
    assert "Vehicles/car-2" in db.docs and "users/someone-else" in db.docs
    assert ("update_user", "owner-1", {"disabled": True}) in auth.calls
    assert ("revoke", "owner-1") in auth.calls and ("delete_user", "owner-1") in auth.calls
    audits = [d for p, d in db.docs.items() if p.startswith("AuditLogs/")]
    assert audits and audits[0]["action"] == "account_self_delete"
    assert audits[0]["actorEmail"] == ""  # no email kept after deletion


def test_an_old_sign_in_must_enter_the_password_again(client, owner):
    db, auth = owner(auth_time=time.time() - 3600)
    response = _delete(client)
    assert response.status_code == 401
    assert response.get_json()["code"] == "recentLoginRequired"
    assert "users/owner-1" in db.docs and not auth.calls


def test_the_confirmation_phrase_is_required(client, owner):
    db, auth = owner()
    response = _delete(client, confirm="xoa")
    assert response.status_code == 400 and response.get_json()["code"] == "confirmationRequired"
    assert "Vehicles/car-1" in db.docs and not auth.calls


def test_never_while_a_smart_charge_session_holds_the_outlet(client, owner):
    lock = {"shellyDeviceLocks/plug-1": {"ownerUid": "owner-1",
                                         "expiresAt": datetime.now(timezone.utc) + timedelta(minutes=30)}}
    db, auth = owner(extra=lock)
    response = _delete(client)
    assert response.status_code == 409
    body = response.get_json()
    assert body["code"] == "activeSmartCharge" and "dừng sạc" in body["userMessage"]
    assert "users/owner-1" in db.docs and not auth.calls


def test_an_admin_account_is_not_deleted_from_the_app(client, owner):
    db, auth = owner(email="admin@vinfast.vn")
    response = _delete(client)
    assert response.status_code == 403 and response.get_json()["code"] == "protectedAccount"
    assert "users/owner-1" in db.docs and not auth.calls


def test_the_public_deletion_page(client, monkeypatch):
    monkeypatch.delenv("ACCOUNT_DELETION_CONTACT", raising=False)
    page = client.get("/xoa-tai-khoan")
    assert page.status_code == 200 and page.mimetype == "text/html"
    text = page.get_data(as_text=True)
    assert "Xóa tài khoản Pinova" in text and "Hồ sơ" in text and "email tới" not in text
    monkeypatch.setenv("ACCOUNT_DELETION_CONTACT", "hotro@pinova.example<script>")
    text = client.get("/account-deletion").get_data(as_text=True)
    assert "hotro@pinova.example&lt;script&gt;" in text and "<script>" not in text
