"""Minimal Gemini REST client (generateContent + function calling).

Plain ``requests`` keeps the API image free of the google-genai SDK. The key
travels only in the ``x-goog-api-key`` header (never in a URL or a log).
"""
from __future__ import annotations

import os
import time

import requests

_ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class GeminiUnavailable(RuntimeError):
    """Not configured, quota, network or a malformed answer: use the fallback."""


class GeminiClient:
    def __init__(self, api_key: str | None = None, model: str | None = None, *, session=None,
                 timeout: float = 25.0):
        self.api_key = (api_key if api_key is not None else
                        os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or "").strip()
        self.model = (model or os.environ.get("GEMINI_CHAT_MODEL") or "gemini-3.5-flash-lite").strip()
        self.http = session or requests.Session()
        self.timeout = timeout
        # Gemini refuses Azure East Asia (Hong Kong); production calls go
        # through the Japan East relay (web/gemini_relay), which holds the
        # key and accepts only the shared relay token (Task 124).
        self.relay_url = (os.environ.get("GEMINI_RELAY_URL") or "").strip().rstrip("/")
        self.relay_token = (os.environ.get("GEMINI_RELAY_TOKEN") or "").strip()

    @property
    def configured(self) -> bool:
        if self.relay_url:
            return bool(self.relay_token and self.model)
        return bool(self.api_key and self.model)

    def _request(self, body: dict, timeout: float):
        if self.relay_url:
            return self.http.post(f"{self.relay_url}/v1/generate/{self.model}",
                                  headers={"X-Relay-Token": self.relay_token}, json=body,
                                  timeout=timeout)
        return self.http.post(_ENDPOINT.format(model=self.model),
                              headers={"x-goog-api-key": self.api_key}, json=body,
                              timeout=timeout)

    def generate(self, *, system: str, contents: list[dict], tools: list[dict] | None = None,
                 temperature: float = 0.4, max_tokens: int = 1024, tool_mode: str = "AUTO",
                 timeout: float | None = None, response_mime_type: str | None = None) -> list[dict]:
        """Return the first candidate's parts ({"text"} / {"functionCall"}).

        ``timeout`` is what is left of the chat turn's overall budget;
        ``tool_mode="NONE"`` forces a text answer (last round)."""
        if not self.configured:
            raise GeminiUnavailable("notConfigured")
        budget = self.timeout if timeout is None else max(1.0, min(self.timeout, timeout))
        started = time.monotonic()
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": contents,
            "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens},
        }
        if response_mime_type:
            # QA 135: the dashboard reader asks for a JSON answer.
            body["generationConfig"]["responseMimeType"] = response_mime_type
        if tools:
            body["tools"] = [{"functionDeclarations": tools}]
            body["toolConfig"] = {"functionCallingConfig": {"mode": tool_mode}}
        response = None
        for attempt in range(2):
            left = budget - (time.monotonic() - started)
            if left < 1.0:
                if response is None:
                    raise GeminiUnavailable("timeout")
                break
            try:
                response = self._request(body, left)
            except requests.RequestException as error:
                if attempt:
                    raise GeminiUnavailable("network") from error
                continue
            # A model call has no side effects: one retry on a busy backend.
            if response.status_code not in (500, 503) or attempt:
                break
            time.sleep(0.8)
        if response.status_code == 429:
            raise GeminiUnavailable("rateLimited")
        if response.status_code != 200:
            raise GeminiUnavailable(f"http{response.status_code}")
        try:
            data = response.json()
            candidate = (data.get("candidates") or [])[0]
            parts = (candidate.get("content") or {}).get("parts") or []
        except (ValueError, IndexError, AttributeError) as error:
            raise GeminiUnavailable("malformed") from error
        if not isinstance(parts, list):
            raise GeminiUnavailable("malformed")
        return [part for part in parts if isinstance(part, dict)]
