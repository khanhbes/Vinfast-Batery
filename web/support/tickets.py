"""Support tickets (QA 135): every plan can ask the Pinova team for help.

Firestore ``supportTickets/{id}`` (server only; no client rule). The app
attaches a diagnostics snapshot it gathered itself (version, permissions,
connection, Shelly state); only known, short, non-secret fields are kept.
A new ticket and each user reply email the support admin; an admin reply
lands in the user's Notification Center and as a push.
"""
from __future__ import annotations

import re
import secrets
import threading
from datetime import datetime, timezone

COLLECTION = "supportTickets"
CATEGORIES = ("charging", "shelly", "scan", "battery", "billing", "account", "app", "other")
CATEGORY_LABELS = {
    "charging": "Sạc pin", "shelly": "Ổ sạc Shelly", "scan": "Quét đồng hồ", "battery": "Pin & quãng đường",
    "billing": "Gói Premium", "account": "Tài khoản", "app": "Lỗi ứng dụng", "other": "Khác",
}
STATUSES = ("open", "answered", "closed")
MAX_REPLIES = 40
_SECRET_KEY = re.compile(r"(token|secret|password|passwd|auth|key|cookie|credential)", re.IGNORECASE)
_SECRET_VALUE = re.compile(r"(bearer\s|eyJ[a-zA-Z0-9_-]{10,}|AIza[0-9A-Za-z_-]{20,})", re.IGNORECASE)


class SupportError(RuntimeError):
    def __init__(self, code: str, message: str, status: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def _now():
    return datetime.now(timezone.utc)


def _iso(value):
    if isinstance(value, datetime):
        value = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        return value.isoformat().replace("+00:00", "Z")
    return value


def clean_diagnostics(raw, depth: int = 0) -> dict:
    """Keep a small, flat-ish snapshot: no secrets, short strings, ≤ 60 keys."""
    if not isinstance(raw, dict) or depth > 2:
        return {}
    out = {}
    for key, value in list(raw.items())[:60]:
        name = str(key)[:40]
        if _SECRET_KEY.search(name):
            continue
        if isinstance(value, bool) or value is None or isinstance(value, (int, float)):
            out[name] = value
        elif isinstance(value, str):
            if not _SECRET_VALUE.search(value):
                out[name] = value[:200]
        elif isinstance(value, dict):
            nested = clean_diagnostics(value, depth + 1)
            if nested:
                out[name] = nested
        elif isinstance(value, list):
            out[name] = [str(v)[:120] for v in value[:10] if not _SECRET_VALUE.search(str(v))]
    return out


class SupportService:
    def __init__(self, db=None, mailer=None, notifier=None, quota=None, clock=None, portal_url: str = ""):
        self.db = db
        self.mailer = mailer
        # notifier(uid, ticket_id, title, message): inbox item + push.
        self.notifier = notifier
        self.quota = quota  # DailyQuota-like: take(uid) -> (allowed, left)
        self.clock = clock or _now
        self.portal_url = portal_url.rstrip("/")
        self._local: dict[str, dict] = {}
        self._lock = threading.Lock()

    # -- storage ----------------------------------------------------------
    def _get(self, ticket_id: str) -> dict | None:
        if self.db is None:
            with self._lock:
                item = self._local.get(ticket_id)
                return dict(item) if item else None
        snapshot = self.db.collection(COLLECTION).document(ticket_id).get()
        return (snapshot.to_dict() or {}) if snapshot.exists else None

    def _put(self, ticket_id: str, data: dict) -> None:
        if self.db is None:
            with self._lock:
                self._local[ticket_id] = dict(data)
        else:
            self.db.collection(COLLECTION).document(ticket_id).set(data)

    def _rows(self, uid: str | None = None, limit: int = 100) -> list[dict]:
        if self.db is None:
            with self._lock:
                rows = [dict(v) for v in self._local.values() if uid is None or v.get("uid") == uid]
        else:
            query = self.db.collection(COLLECTION)
            if uid is not None:
                # Single-field equality: no composite index needed.
                query = query.where("uid", "==", uid)
            rows = [s.to_dict() or {} for s in query.limit(limit).stream()]
        rows.sort(key=lambda r: str(_iso(r.get("updatedAt")) or ""), reverse=True)
        return rows

    # -- views ------------------------------------------------------------
    @staticmethod
    def public(data: dict, admin: bool = False) -> dict:
        value = {
            "id": data.get("id"), "subject": data.get("subject"), "category": data.get("category"),
            "categoryLabel": CATEGORY_LABELS.get(data.get("category"), "Khác"),
            "message": data.get("message"), "status": data.get("status"),
            "createdAt": _iso(data.get("createdAt")), "updatedAt": _iso(data.get("updatedAt")),
            "replies": [{"at": _iso(r.get("at")), "by": r.get("by"), "text": r.get("text")}
                        for r in data.get("replies") or []],
            "unread": bool(data.get("unreadForAdmin" if admin else "unreadForUser")),
        }
        if admin:
            value.update({"uid": data.get("uid"), "email": data.get("email"), "tier": data.get("tier"),
                          "diagnostics": data.get("diagnostics") or {}, "emailSent": data.get("emailSent")})
        return value

    # -- user ---------------------------------------------------------------
    def create(self, uid: str, email: str | None, body: dict, tier: str = "free") -> dict:
        subject = re.sub(r"\s+", " ", str(body.get("subject") or "")).strip()
        message = str(body.get("message") or "").strip()
        category = str(body.get("category") or "other").lower()
        if category not in CATEGORIES:
            category = "other"
        if len(subject) < 3:
            raise SupportError("invalidTicket", "Hãy nhập tiêu đề (ít nhất 3 ký tự).")
        if len(message) < 10:
            raise SupportError("invalidTicket", "Hãy mô tả vấn đề (ít nhất 10 ký tự).")
        if len(subject) > 120 or len(message) > 4000:
            raise SupportError("invalidTicket", "Tiêu đề tối đa 120 ký tự, nội dung tối đa 4000 ký tự.")
        if self.quota is not None:
            allowed, _left = self.quota.take(uid)
            if not allowed:
                raise SupportError("supportQuota", "Bạn đã gửi 5 yêu cầu hôm nay. Đội hỗ trợ sẽ trả lời các yêu cầu đã gửi.", 429)
        now = self.clock()
        ticket_id = now.strftime("%Y%m%d") + "-" + secrets.token_hex(4)
        data = {
            "id": ticket_id, "uid": uid, "email": (email or "")[:200], "tier": tier,
            "subject": subject, "message": message, "category": category,
            "diagnostics": clean_diagnostics(body.get("diagnostics")),
            "status": "open", "replies": [], "createdAt": now, "updatedAt": now,
            "unreadForAdmin": True, "unreadForUser": False, "emailSent": False,
        }
        data["emailSent"] = self._email_admin(data, f"[Pinova hỗ trợ] {subject}", message)
        self._put(ticket_id, data)
        return self.public(data)

    def mine(self, uid: str) -> list[dict]:
        return [self.public(r) for r in self._rows(uid=uid, limit=50)]

    def get_mine(self, uid: str, ticket_id: str) -> dict:
        data = self._get(ticket_id)
        if not data or data.get("uid") != uid:
            raise SupportError("ticketNotFound", "Không tìm thấy yêu cầu hỗ trợ.", 404)
        if data.get("unreadForUser"):
            data["unreadForUser"] = False
            self._put(ticket_id, data)
        return self.public(data)

    def user_reply(self, uid: str, ticket_id: str, text: str) -> dict:
        data = self._get(ticket_id)
        if not data or data.get("uid") != uid:
            raise SupportError("ticketNotFound", "Không tìm thấy yêu cầu hỗ trợ.", 404)
        text = str(text or "").strip()
        if not 1 <= len(text) <= 4000:
            raise SupportError("invalidReply", "Nội dung trả lời từ 1 đến 4000 ký tự.")
        if len(data.get("replies") or []) >= MAX_REPLIES:
            raise SupportError("ticketFull", "Yêu cầu này đã dài; hãy tạo yêu cầu mới.", 409)
        now = self.clock()
        data["replies"] = list(data.get("replies") or []) + [{"at": now, "by": "user", "text": text}]
        data.update({"status": "open", "updatedAt": now, "unreadForAdmin": True})
        self._email_admin(data, f"[Pinova hỗ trợ] Trả lời: {data.get('subject')}", text)
        self._put(ticket_id, data)
        return self.public(data)

    # -- admin ------------------------------------------------------------
    def admin_list(self, status: str | None = None) -> list[dict]:
        rows = self._rows(limit=200)
        if status in STATUSES:
            rows = [r for r in rows if r.get("status") == status]
        return [self.public(r, admin=True) for r in rows]

    def admin_get(self, ticket_id: str) -> dict:
        data = self._get(ticket_id)
        if not data:
            raise SupportError("ticketNotFound", "Không tìm thấy yêu cầu.", 404)
        if data.get("unreadForAdmin"):
            data["unreadForAdmin"] = False
            self._put(ticket_id, data)
        return self.public(data, admin=True)

    def admin_reply(self, ticket_id: str, text: str, status: str | None = None, actor: str = "") -> dict:
        data = self._get(ticket_id)
        if not data:
            raise SupportError("ticketNotFound", "Không tìm thấy yêu cầu.", 404)
        text = str(text or "").strip()
        now = self.clock()
        if text:
            if len(text) > 4000:
                raise SupportError("invalidReply", "Nội dung trả lời tối đa 4000 ký tự.")
            data["replies"] = list(data.get("replies") or []) + [
                {"at": now, "by": "admin", "text": text, "actor": actor[:128]}]
            data.update({"status": "answered", "unreadForUser": True})
        if status in STATUSES:
            data["status"] = status
        elif not text:
            raise SupportError("invalidReply", "Cần nội dung trả lời hoặc trạng thái.")
        data.update({"updatedAt": now, "unreadForAdmin": False})
        self._put(ticket_id, data)
        if text and self.notifier is not None:
            try:
                self.notifier(data["uid"], ticket_id, "Pinova đã trả lời yêu cầu hỗ trợ",
                              f"{data.get('subject')}: {text[:140]}")
            except Exception:
                pass  # the reply is saved; the app shows it on next open
        return self.public(data, admin=True)

    def unread_count(self) -> int:
        return sum(1 for r in self._rows(limit=200) if r.get("unreadForAdmin"))

    # -- email --------------------------------------------------------------
    def _email_admin(self, data: dict, subject: str, text: str) -> bool:
        if self.mailer is None or not self.mailer.configured:
            return False
        diagnostics = data.get("diagnostics") or {}
        lines = [
            f"Tài khoản: {data.get('email') or '(không có email)'} · UID {data.get('uid')}",
            f"Gói: {data.get('tier')} · Mục: {CATEGORY_LABELS.get(data.get('category'), 'Khác')}",
            f"Mã yêu cầu: {data.get('id')}",
            "",
            text,
            "",
            "— Chẩn đoán tự động —",
        ] + [f"{k}: {v}" for k, v in list(diagnostics.items())[:40]]
        if self.portal_url:
            lines += ["", f"Trả lời trên portal: {self.portal_url}/support"]
        try:
            return bool(self.mailer.send(subject, "\n".join(lines)))
        except Exception:
            return False
