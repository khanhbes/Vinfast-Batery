"""Explicitly authorized live QA, fake data only, run inside the AI container.

At most three ordinary chat requests. No confirmation or hardware endpoint.
Print safe summaries only; never print keys, tokens, URLs or raw exceptions.
"""
import json
import logging
import os
import sys
import time
import uuid

import requests

logging.disable(logging.CRITICAL)
sys.path.insert(0, "/app")


def safe_text(value):
    from ai_server.chat_guardrails import chat_guardrails
    text, _ = chat_guardrails.sanitize_pii(str(value or ""))
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "AI_SERVER_INTERNAL_TOKEN"):
        secret = os.environ.get(name, "")
        if secret:
            text = text.replace(secret, "[redacted]")
    return text[:1600]


def events(body):
    result = []
    for frame in body.replace("\r\n", "\n").split("\n\n"):
        name, data = "message", []
        for line in frame.splitlines():
            if line.startswith("event:"):
                name = line[6:].strip()
            elif line.startswith("data:"):
                data.append(line[5:].lstrip())
        if data:
            result.append((name, json.loads("\n".join(data))))
    return result


def main():
    summary = {"scope": "Gemini SDK and internal AI HTTP; not Flutter/public API/hardware",
               "hardwareCommands": 0, "checks": []}
    try:
        from google import genai
        from google.genai import types
        from ai_server.chat_engine import DEFAULT_MODEL
        key = (os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or "").strip()
        token = os.environ.get("AI_SERVER_INTERNAL_TOKEN", "")
        summary["keyConfigured"] = bool(key)
        summary["modelConfigured"] = bool(DEFAULT_MODEL)
        summary["internalAuthConfigured"] = bool(token)
        if not key or not DEFAULT_MODEL or not token:
            raise ValueError("configurationMissing")
        client = genai.Client(api_key=key, http_options=types.HttpOptions(timeout=20000))
        started = time.monotonic()
        try:
            # No tools supplied: this request can only return text.
            reply = client.models.generate_content(model=DEFAULT_MODEL,
                contents="Trả lời bằng tiếng Việt, tối đa hai câu: Khi chưa có số đo pin, trợ lý nên nói gì? Không bịa số liệu.",
                config=types.GenerateContentConfig(max_output_tokens=1024, temperature=0.2))
            text = reply.text or ""
            check = {"id": "provider-sdk", "pass": bool(text.strip()),
                     "elapsedSeconds": round(time.monotonic() - started, 2),
                     "reply": safe_text(text)}
            summary["checks"].append(check)
            if not check["pass"]:
                raise ValueError("providerEmptyResponse")
        finally:
            client.close()

        headers = {"X-Internal-Token": token}
        with requests.Session() as http:
            health = http.get("http://127.0.0.1:8001/healthz", timeout=10)
            summary["checks"].append({"id": "ai-health", "httpStatus": health.status_code,
                                      "pass": health.status_code == 200 and health.json().get("ok") is True})
            rejected = http.post("http://127.0.0.1:8001/v1/chat/send",
                json={"message": "QA", "userId": "qa-smoke"}, timeout=10)
            summary["checks"].append({"id": "internal-auth-required", "httpStatus": rejected.status_code,
                                      "pass": rejected.status_code == 401})

            session_id = "qa-gemini-" + uuid.uuid4().hex
            owner = "qa-provider-smoke"
            prompts = [
                "Hãy giới thiệu bạn là BatteryBot trong tối đa hai câu ngắn bằng tiếng Việt, không emoji. Không gọi công cụ hoặc điều khiển thiết bị.",
                "Trong câu trả lời vừa rồi bạn tên là gì? Chỉ trả lời tên, không gọi công cụ.",
            ]
            for number, prompt in enumerate(prompts, 1):
                started = time.monotonic()
                response = http.post("http://127.0.0.1:8001/v1/chat/send", headers=headers,
                    json={"message": prompt, "sessionId": session_id, "userId": owner}, timeout=70)
                check = {"id": "ai-http-turn-" + str(number), "httpStatus": response.status_code,
                         "elapsedSeconds": round(time.monotonic() - started, 2)}
                summary["checks"].append(check)
                if response.status_code != 200:
                    check["pass"] = False
                    break
                frames = events(response.text)
                texts = [item.get("delta", "") for name, item in frames if name == "text_delta"]
                ends = [item for name, item in frames if name == "message_end"]
                check["eventTypes"] = [name for name, _ in frames]
                check["reply"] = safe_text("".join(texts))
                usage = ends[-1].get("usage", {}) if ends else {}
                check["source"] = usage.get("source")
                check["providerStatus"] = usage.get("providerStatus")
                check["providerErrorCode"] = usage.get("providerErrorCode")
                check["pass"] = bool(ends and check["reply"].strip()) and not any(
                    name in ("error", "function_call") for name, _ in frames) and (
                    usage.get("source") == "gemini" and usage.get("providerStatus") == "succeeded")
                check["providerOriginVerified"] = check["pass"]
                if not check["pass"]:
                    break
            # Remove only the fake session created by this script, not real data.
            deleted = http.delete("http://127.0.0.1:8001/v1/chat/sessions/" + session_id,
                headers=headers, params={"userId": owner}, timeout=10)
            summary["checks"].append({"id": "qa-session-cleanup", "httpStatus": deleted.status_code,
                                      "pass": deleted.status_code == 200})
    except Exception as error:
        code = getattr(error, "code", None)
        status = getattr(error, "status", None)
        allowed_statuses = {"INVALID_ARGUMENT", "UNAUTHENTICATED", "PERMISSION_DENIED",
                            "NOT_FOUND", "RESOURCE_EXHAUSTED", "UNAVAILABLE", "INTERNAL"}
        summary["failure"] = {"type": type(error).__name__,
                              "httpStatus": code if isinstance(code, int) else None,
                              "providerStatus": status if status in allowed_statuses else None}
    summary["pass"] = bool(summary["checks"]) and "failure" not in summary and all(
        check.get("pass") is True for check in summary["checks"])
    print(json.dumps(summary, ensure_ascii=True))
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
