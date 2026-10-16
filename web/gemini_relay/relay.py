"""Gemini relay (Task 124): forwards generateContent from the VinFast API.

The Gemini API refuses calls from Azure East Asia (Hong Kong: "User location
is not supported"). This tiny service runs in Azure Japan East (allowed by
the Student region policy), holds the Gemini key and accepts only requests
carrying the shared relay token. It never logs bodies, keys or tokens.
Standard library + requests only.
"""
from __future__ import annotations

import hmac
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import requests

GEMINI = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
MAX_BODY = 512 * 1024
_MODEL = re.compile(r"^[a-z0-9][a-z0-9.\-]{2,63}$")
_PATH = re.compile(r"^/v1/generate/([^/?#]+)$")


def _config():
    return {
        "token": os.environ.get("RELAY_TOKEN", "").strip(),
        "key": os.environ.get("GEMINI_API_KEY", "").strip(),
        "models": {m.strip() for m in os.environ.get("RELAY_ALLOWED_MODELS", "").split(",") if m.strip()},
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "gemini-relay"
    session = requests.Session()

    def log_message(self, fmt, *args):  # status line only, never bodies
        print(f"[relay] {self.command} {self.path.split('?')[0][:60]} -> {args[1] if len(args) > 1 else ''}",
              flush=True)

    def _send(self, status: int, body: bytes, content_type: str = "application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, code: str):
        self._send(status, json.dumps({"error": {"code": status, "status": code}}).encode())

    def do_GET(self):
        if self.path == "/healthz":
            cfg = _config()
            ok = bool(cfg["token"] and cfg["key"])
            return self._send(200 if ok else 503, json.dumps({"ok": ok}).encode())
        return self._error(404, "NOT_FOUND")

    def do_POST(self):
        cfg = _config()
        match = _PATH.match(self.path)
        if not match:
            return self._error(404, "NOT_FOUND")
        supplied = self.headers.get("X-Relay-Token", "")
        if not cfg["token"] or not hmac.compare_digest(supplied.encode(), cfg["token"].encode()):
            return self._error(401, "UNAUTHENTICATED")
        model = match.group(1)
        if not _MODEL.match(model) or (cfg["models"] and model not in cfg["models"]):
            return self._error(400, "MODEL_NOT_ALLOWED")
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = -1
        if length <= 0 or length > MAX_BODY:
            return self._error(413, "BODY_SIZE")
        body = self.rfile.read(length)
        try:
            json.loads(body)
        except ValueError:
            return self._error(400, "INVALID_JSON")
        if not cfg["key"]:
            return self._error(503, "NOT_CONFIGURED")
        try:
            upstream = self.session.post(GEMINI.format(model=model), data=body, timeout=25,
                                         headers={"x-goog-api-key": cfg["key"],
                                                  "Content-Type": "application/json"})
        except requests.RequestException:
            return self._error(502, "UPSTREAM_UNREACHABLE")
        self._send(upstream.status_code, upstream.content,
                   upstream.headers.get("Content-Type", "application/json"))


def main():
    port = int(os.environ.get("PORT", "8080"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
