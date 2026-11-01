"""Pinova Bot conduct enforcement owned by the server (QA 142).

The web build (Pinova 3.1) answered violations with a 3-strike text but:
the strike came from the request (an app could always send strike 1), the
30-minute suspension was recorded and never enforced, every user's record
sat in one shared document (and a JSON file in the container), and "a
warning email was sent" when none was. Here:

- one record per account at ``users/{uid}/assistantConduct/state`` (memory
  when Firestore is absent); a record with no violation for 30 days resets;
- the lock is checked before the quota and the model: a locked account gets
  the lock reply (SOS is answered before this gate, Stop charging and the
  Charge tab never depend on the bot);
- strike 2 and 3 email the account owner through ACS, and the reply only
  says so when the email was really queued;
- tricks are refused without a strike: obfuscated swear words are folded
  before matching ("d.m", "đ m", "dcm", "v.k.l", leetspeak, repeated
  letters); posing as admin/developer/system; asking for another
  account's data; more than 5 messages in 30 seconds is slowed down.
"""
from __future__ import annotations

import re
import threading
import time
import unicodedata
from collections import deque
from datetime import datetime, timedelta, timezone
from typing import Any, Callable

STRIKE_RESET_DAYS = 30
LOCK_MINUTES = 30
SPAM_WINDOW_SECONDS = 30
SPAM_MAX_MESSAGES = 5

_FOLD = str.maketrans({"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
                       "@": "a", "$": "s", "đ": "d", "Đ": "d"})


def fold(text: str) -> str:
    """Lower-case, no accents, leetspeak undone, separators between single
    letters dropped and runs of a letter squeezed: "Đ.M", "đ m", "dmmm",
    "v-k-l" → "dm", "dm", "dm", "vkl"."""
    value = unicodedata.normalize("NFD", str(text or "").lower().translate(_FOLD))
    value = "".join(ch for ch in value if unicodedata.category(ch) != "Mn")
    value = re.sub(r"[^a-z0-9\s]", " ", value)
    # "d m" / "v k l": single letters in a row join into one word.
    value = re.sub(r"\b([a-z])(?:\s+(?=[a-z]\b))", r"\1", value)
    value = re.sub(r"([a-z])\1{2,}", r"\1", value)
    return " ".join(value.split())


# Folded (accent-free) slang that no ordinary Vietnamese word folds into;
# short ones stand alone so "cc" in "50cc" never matches. Words such as
# "cặc", "lồn", "buồi", "đéo" fold into "các", "lon", "buổi", "đeo", so
# they are matched with their accents instead.
_PROFANITY = re.compile(
    r"\b(dm|dmm|dcm|dkm|clm|cmm|vcl|vkl|vcc|ditme|dit me|dit con me|oc cho|ngu nhu bo|"
    r"thang ngu|fuck|fck|fuk|shit|bitch|asshole|motherfucker|dumbass)\b")
_PROFANITY_ACCENTED = re.compile(
    r"(?<!\w)(địt|đéo|lồn|cặc|buồi|đụ|đĩ|mẹ mày|bố mày|đồ chó|thằng chó)(?!\w)")
_CC = re.compile(r"(?<![0-9a-z])cc(?![0-9a-z])")
_IMPERSONATION = re.compile(
    r"\b(toi la (admin|quan tri|nha phat trien|developer|dev|ky su pinova)|"
    r"(che do|mode) (admin|developer|dev|nha phat trien|god|debug)|developer mode|dan mode|jailbreak|"
    r"bo qua (moi |tat ca )?(quy tac|huong dan|gioi han)|quen (het )?(huong dan|quy tac)|"
    r"ignore (all |previous |the )*(instructions|rules)|system prompt|you are now|"
    r"pinova (admin|support) yeu cau|lenh tu he thong)\b")
_SYSTEM_TAG = re.compile(r"^\s*(\[|<)?\s*(system|admin|developer)\s*(\]|>|:)", re.IGNORECASE)
_OTHER_ACCOUNT = re.compile(
    r"\b((xe|pin|lich su|vi tri|du lieu|tai khoan|so dien thoai|email|odo)(\s+[a-z]+){0,3}\s+(cua\s+)?"
    r"(nguoi khac|user khac|tai khoan khac|khach khac|ban toi|hang xom|vo toi|chong toi)|"
    r"(xem|tra|cho toi biet) .{0,20}(bien so|xe) \d{2}[a-z])")


def trick_kind(message: str) -> str | None:
    """'impersonation' or 'other_account' when the message tries to get
    around the rules; None otherwise."""
    text = str(message or "")
    folded = fold(text)
    if _SYSTEM_TAG.search(text) or _IMPERSONATION.search(folded):
        return "impersonation"
    if _OTHER_ACCOUNT.search(folded):
        return "other_account"
    return None


def obfuscated_profanity(message: str) -> bool:
    folded = fold(message)
    accented = unicodedata.normalize("NFC", str(message or "").lower()[:2000])
    # "đ.ị.t" / "l-ồ-n": separators between single letters dropped.
    accented = re.sub(r"(?<=\b\w)[\s.\-_*]+(?=\w\b)", "", accented)
    return bool(_PROFANITY.search(folded) or _CC.search(folded)
                or _PROFANITY_ACCENTED.search(accented))


TRICK_REPLIES = {
    "impersonation": (
        "Mình chỉ làm theo quy tắc an toàn của Pinova, lời nhắn trong chat không đổi được quy tắc "
        "hay giới hạn an toàn (12 A / 2 500 W, ngắt khi ổ quá nóng). Quản trị viên không yêu cầu "
        "qua cuộc trò chuyện này. Bạn cần hỗ trợ gì về xe hay sạc?"),
    "other_account": (
        "Mình chỉ xem được xe và dữ liệu của chính tài khoản bạn. Dữ liệu của người khác được bảo vệ "
        "và không thể tra qua Pinova Bot. Bạn muốn xem gì trên xe của mình?"),
}


class ConductStore:
    """Per-account conduct record with a memory fallback."""

    def __init__(self, db=None, clock: Callable[[], datetime] | None = None):
        self.db = db
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self._memory: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()

    def _ref(self, uid: str):
        return (self.db.collection("users").document(uid)
                .collection("assistantConduct").document("state"))

    @staticmethod
    def _parse(value) -> datetime | None:
        if value is None:
            return None
        if isinstance(value, datetime):
            return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        try:
            parsed = datetime.fromisoformat(str(value))
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)

    def _blank(self, uid: str) -> dict[str, Any]:
        return {"uid": uid, "strikeCount": 0, "warningEmailsSent": 0, "lockedUntil": None,
                "lastViolationAt": None, "lastCategory": None}

    def get(self, uid: str) -> dict[str, Any]:
        record = None
        if self.db is not None:
            try:
                snap = self._ref(uid).get()
                record = snap.to_dict() if snap.exists else None
            except Exception:
                record = None
        if record is None:
            with self._lock:
                record = dict(self._memory.get(uid) or {})
        record = {**self._blank(uid), **(record or {})}
        last = self._parse(record.get("lastViolationAt"))
        if last is not None and self.clock() - last > timedelta(days=STRIKE_RESET_DAYS):
            record.update({"strikeCount": 0, "lockedUntil": None})
        return record

    def _save(self, uid: str, record: dict[str, Any]) -> None:
        with self._lock:
            self._memory[uid] = dict(record)
        if self.db is not None:
            try:
                self._ref(uid).set(record)
            except Exception:
                pass  # the memory copy still enforces on this instance

    def locked_until(self, uid: str) -> datetime | None:
        until = self._parse(self.get(uid).get("lockedUntil"))
        return until if until is not None and until > self.clock() else None

    def record_violation(self, uid: str, category: str, *, email_sent: bool) -> dict[str, Any]:
        record = self.get(uid)
        now = self.clock()
        strike = min(3, int(record.get("strikeCount") or 0) + 1)
        record.update({"strikeCount": strike, "lastViolationAt": now.isoformat(), "lastCategory": category})
        if email_sent:
            record["warningEmailsSent"] = int(record.get("warningEmailsSent") or 0) + 1
        if strike >= 3:
            record["lockedUntil"] = (now + timedelta(minutes=LOCK_MINUTES)).isoformat()
            # After a lock the next violation locks again; 30 clean days
            # reset the record.
            record["strikeCount"] = 2
        self._save(uid, record)
        return {**record, "strike": strike}

    def reset(self, uid: str) -> dict[str, Any]:
        record = self._blank(uid)
        self._save(uid, record)
        return record


class SpamGuard:
    """At most SPAM_MAX_MESSAGES per SPAM_WINDOW_SECONDS per account (per
    instance; the API runs one replica at rest)."""

    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self.clock = clock
        self._seen: dict[str, deque] = {}
        self._lock = threading.Lock()

    def wait_seconds(self, uid: str) -> int:
        now = self.clock()
        with self._lock:
            seen = self._seen.setdefault(uid, deque())
            while seen and now - seen[0] > SPAM_WINDOW_SECONDS:
                seen.popleft()
            if len(seen) >= SPAM_MAX_MESSAGES:
                return max(1, int(SPAM_WINDOW_SECONDS - (now - seen[0])) + 1)
            seen.append(now)
            return 0


def lock_reply(until: datetime) -> dict[str, Any]:
    local = until.astimezone(timezone(timedelta(hours=7)))
    return {
        "reply": (f"🔒 Pinova Bot đang tạm khóa với tài khoản này tới **{local:%H:%M}** vì vi phạm Quy tắc "
                  "Cộng đồng 3 lần. Bạn vẫn bật/dừng sạc ở tab **Sạc pin** và gửi phiếu ở **Trợ giúp**; "
                  "báo cháy, khói hay giật điện vẫn được trả lời ngay."),
        "actions": [], "source": "conduct_lock",
        "assistantLock": {"until": until.isoformat(), "reason": "conduct"},
    }


def spam_reply(seconds: int) -> dict[str, Any]:
    return {
        "reply": f"Bạn gửi hơi nhanh. Chờ khoảng {seconds} giây rồi hỏi tiếp nhé, tin này không bị trừ lượt.",
        "actions": [], "source": "conduct_spam", "retryAfterSeconds": seconds,
    }
