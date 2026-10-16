"""Task 124 — Gemini relay (Japan East) and the API client's relay mode."""
import json
import threading
from http.server import ThreadingHTTPServer
from unittest.mock import MagicMock

import pytest
import requests

from assistant.gemini import GeminiClient
from gemini_relay import relay


@pytest.fixture
def server(monkeypatch):
    monkeypatch.setenv("RELAY_TOKEN", "relay-secret-token")
    monkeypatch.setenv("GEMINI_API_KEY", "fixture-key")
    monkeypatch.setenv("RELAY_ALLOWED_MODELS", "gemini-3.5-flash-lite")
    upstream = MagicMock()
    upstream.post.return_value = MagicMock(status_code=200, content=b'{"candidates":[]}',
                                           headers={"Content-Type": "application/json"})
    monkeypatch.setattr(relay.Handler, "session", upstream)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), relay.Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{httpd.server_address[1]}", upstream
    httpd.shutdown()


def test_relay_forwards_only_with_the_shared_token(server):
    base, upstream = server
    body = {"contents": [{"parts": [{"text": "hi"}]}]}
    assert requests.post(f"{base}/v1/generate/gemini-3.5-flash-lite", json=body, timeout=5).status_code == 401
    assert requests.post(f"{base}/v1/generate/gemini-3.5-flash-lite", json=body, timeout=5,
                         headers={"X-Relay-Token": "wrong"}).status_code == 401
    upstream.post.assert_not_called()
    ok = requests.post(f"{base}/v1/generate/gemini-3.5-flash-lite", json=body, timeout=5,
                       headers={"X-Relay-Token": "relay-secret-token"})
    assert ok.status_code == 200
    assert upstream.post.call_args.args[0].endswith("/models/gemini-3.5-flash-lite:generateContent")
    assert upstream.post.call_args.kwargs["headers"]["x-goog-api-key"] == "fixture-key"
    assert json.loads(upstream.post.call_args.kwargs["data"]) == body


def test_relay_rejects_other_models_paths_and_bad_bodies(server):
    base, upstream = server
    headers = {"X-Relay-Token": "relay-secret-token"}
    assert requests.post(f"{base}/v1/generate/gemini-ultra", json={}, headers=headers, timeout=5).status_code == 400
    assert requests.post(f"{base}/v1/other", json={}, headers=headers, timeout=5).status_code == 404
    assert requests.post(f"{base}/v1/generate/gemini-3.5-flash-lite", data=b"not json",
                         headers=headers, timeout=5).status_code == 400
    upstream.post.assert_not_called()
    assert requests.get(f"{base}/healthz", timeout=5).json() == {"ok": True}


def test_client_uses_relay_without_sending_the_gemini_key(monkeypatch):
    monkeypatch.setenv("GEMINI_RELAY_URL", "https://relay.example/")
    monkeypatch.setenv("GEMINI_RELAY_TOKEN", "relay-secret-token")
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    http = MagicMock()
    http.post.return_value = MagicMock(status_code=200, json=lambda: {
        "candidates": [{"content": {"parts": [{"text": "ok"}]}}]})
    client = GeminiClient(model="gemini-3.5-flash-lite", session=http)
    assert client.configured
    assert client.generate(system="s", contents=[]) == [{"text": "ok"}]
    args, kwargs = http.post.call_args
    assert args[0] == "https://relay.example/v1/generate/gemini-3.5-flash-lite"
    assert kwargs["headers"] == {"X-Relay-Token": "relay-secret-token"}


def test_relay_mode_needs_its_token(monkeypatch):
    monkeypatch.setenv("GEMINI_RELAY_URL", "https://relay.example")
    monkeypatch.delenv("GEMINI_RELAY_TOKEN", raising=False)
    assert GeminiClient(api_key="direct", model="m").configured is False
