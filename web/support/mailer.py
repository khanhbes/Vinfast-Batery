"""Email to the support admin via Azure Communication Services (QA 135).

REST ``/emails:send`` with the connection string's HMAC key, so the API image
needs no extra SDK. Configuration (all optional; without it tickets are
still stored and shown on the portal, only the email is skipped):

- ``ACS_CONNECTION_STRING``  ``endpoint=https://<res>.communication.azure.com/;accesskey=<base64>``
- ``SUPPORT_SENDER_EMAIL``   a verified sender, e.g. ``DoNotReply@<id>.azurecomm.net``
- ``SUPPORT_ADMIN_EMAIL``    where new tickets go (comma-separated allowed)

Sending runs in a background thread: a slow or failing mail service never
delays or fails the user's request.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import threading
from email.utils import formatdate
from urllib.parse import urlparse

import requests

API_VERSION = "2023-03-31"
log = logging.getLogger(__name__)


def parse_connection_string(value: str) -> tuple[str, bytes] | None:
    parts = {}
    for item in str(value or "").split(";"):
        if "=" in item:
            key, _, val = item.partition("=")
            parts[key.strip().lower()] = val.strip()
    endpoint, key = parts.get("endpoint", ""), parts.get("accesskey", "")
    if not endpoint.startswith("https://") or not key:
        return None
    try:
        return endpoint.rstrip("/"), base64.b64decode(key)
    except (ValueError, TypeError):
        return None


def signed_headers(endpoint: str, key: bytes, path_and_query: str, body: bytes, date: str) -> dict:
    """ACS HMAC-SHA256 request signature."""
    host = urlparse(endpoint).netloc
    content_hash = base64.b64encode(hashlib.sha256(body).digest()).decode()
    to_sign = f"POST\n{path_and_query}\n{date};{host};{content_hash}"
    signature = base64.b64encode(hmac.new(key, to_sign.encode("utf-8"), hashlib.sha256).digest()).decode()
    return {
        "x-ms-date": date,
        "x-ms-content-sha256": content_hash,
        "host": host,
        "Authorization": f"HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature={signature}",
        "Content-Type": "application/json",
    }


class SupportMailer:
    def __init__(self, connection_string: str | None = None, sender: str | None = None,
                 recipients: str | None = None, session=None, background: bool = True):
        parsed = parse_connection_string(
            connection_string if connection_string is not None else os.environ.get("ACS_CONNECTION_STRING", ""))
        self.endpoint, self._key = parsed if parsed else (None, None)
        self.sender = (sender if sender is not None else os.environ.get("SUPPORT_SENDER_EMAIL", "")).strip()
        raw = recipients if recipients is not None else os.environ.get("SUPPORT_ADMIN_EMAIL", "")
        self.recipients = [r.strip() for r in str(raw).split(",") if "@" in r][:5]
        self.session = session or requests
        self.background = background
        self.sent: list[dict] = []  # tests / diagnostics

    @property
    def configured(self) -> bool:
        return bool(self.endpoint and self._key and self.sender and self.recipients)

    def send(self, subject: str, text: str) -> bool:
        if not self.configured:
            return False
        message = {
            "senderAddress": self.sender,
            "recipients": {"to": [{"address": r} for r in self.recipients]},
            "content": {"subject": subject[:200], "plainText": text[:20000]},
        }
        if self.background:
            threading.Thread(target=self._post, args=(message,), daemon=True).start()
            return True
        return self._post(message)

    def _post(self, message: dict) -> bool:
        path = f"/emails:send?api-version={API_VERSION}"
        body = json.dumps(message, ensure_ascii=False).encode("utf-8")
        headers = signed_headers(self.endpoint, self._key, path, body, formatdate(usegmt=True))
        try:
            response = self.session.post(self.endpoint + path, data=body, headers=headers, timeout=15)
            ok = response.status_code in (200, 202)
        except Exception as error:  # never surfaces to the user
            log.warning("support email failed: %s", type(error).__name__)
            return False
        if not ok:
            log.warning("support email rejected: HTTP %s", response.status_code)
        else:
            self.sent.append(message)
        return ok
