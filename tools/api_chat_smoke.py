"""API-only QA: no hardware calls, real-account login or credential output.

Run inside API container. --preflight reads only charging metadata before
restart. Default checks API health/auth and API-container -> AI connectivity;
it does not bypass public Firebase auth or claim mobile end-to-end coverage.
"""
import json
import logging
import os
import sys
import time
import uuid
import warnings

import requests

logging.disable(logging.CRITICAL)
warnings.filterwarnings("ignore", category=UserWarning)
sys.path.insert(0, "/app")


def main():
    report = {"scope": "read-only preflight" if "--preflight" in sys.argv else "API runtime and internal AI link",
              "hardwareCommands": 0, "checks": []}
    try:
        if "--preflight" in sys.argv:
            import firebase_admin
            from firebase_admin import credentials, firestore
            from shelly.models import NONTERMINAL_SESSION_STATES
            config = json.loads(os.environ["FIREBASE_CREDENTIALS_JSON"])
            firebase_admin.initialize_app(credentials.Certificate(config))
            db = firestore.client()
            # No where-filter: missing production collection-group indexes must
            # not be interpreted as "no active sessions". Fail closed if this
            # bounded projection cannot exhaust the collection or has bad state.
            snapshots = list(db.collection_group("smartChargingSessions")
                .select(["state"]).limit(201).stream(timeout=15))
            states = [(snapshot.to_dict() or {}).get("state") for snapshot in snapshots]
            terminal = {"completed", "cancelled", "interrupted", "failed"}
            nonterminal = any(state in NONTERMINAL_SESSION_STATES for state in states)
            uncertain = any(state not in terminal and state not in NONTERMINAL_SESSION_STATES for state in states)
            truncated = len(snapshots) > 200
            locks = list(db.collection("shellyDeviceLocks").select(["sessionId"]).limit(1).stream(timeout=15))
            report["checks"].append({"id": "charging-metadata", "nonterminalSessionPresent": nonterminal,
                "unknownSchemaPresent": uncertain, "scanTruncated": truncated, "documentsScanned": len(snapshots),
                "deviceLeasePresent": bool(locks), "pass": not nonterminal and not uncertain and not truncated and not locks})
        else:
            api_url = "http://127.0.0.1:5000"
            ai_url = os.environ.get("AI_SERVER_URL", "").rstrip("/")
            token = os.environ.get("AI_SERVER_INTERNAL_TOKEN", "")
            if not ai_url or not token:
                raise ValueError("configurationMissing")
            headers = {"X-Internal-Token": token}
            with requests.Session() as http:
                deadline = time.monotonic() + 45
                while True:
                    try:
                        ai_health = http.get(ai_url + "/healthz", timeout=3)
                        if ai_health.status_code == 200:
                            break
                    except requests.RequestException:
                        pass
                    if time.monotonic() >= deadline:
                        raise TimeoutError("aiStartupTimeout")
                    time.sleep(1)
                for path in ("/api/health", "/api/ready"):
                    response = http.get(api_url + path, timeout=20)
                    report["checks"].append({"id": path, "httpStatus": response.status_code,
                                              "pass": response.status_code == 200,
                                              "requestIdPresent": bool(response.headers.get("X-Request-Id"))})
                for path in ("/api/chat/send", "/api/chat/feedback", "/api/chat/action/confirm"):
                    response = http.post(api_url + path, json={"message": "QA", "userId": "spoofed-qa"}, timeout=15)
                    report["checks"].append({"id": "auth-required:" + path, "httpStatus": response.status_code,
                                              "pass": response.status_code == 401})
                session_id = "qa-api-link-" + uuid.uuid4().hex
                owner = "qa-api-link"
                # This is the same internal service URL/header the proxy uses,
                # but not a Firebase-authenticated request to the public route.
                response = http.post(ai_url + "/v1/chat/send", headers=headers,
                    json={"message": "Chào BatteryBot. Trả lời một câu ngắn bằng tiếng Việt; không gọi công cụ.",
                          "sessionId": session_id, "userId": owner}, timeout=70)
                check = {"id": "api-container-to-ai-sse", "httpStatus": response.status_code, "pass": False}
                report["checks"].append(check)
                if response.status_code == 200:
                    for frame in response.text.replace("\r\n", "\n").split("\n\n"):
                        if "event: message_end\n" not in frame:
                            continue
                        data = "\n".join(line[5:].lstrip() for line in frame.splitlines() if line.startswith("data:"))
                        usage = json.loads(data).get("usage", {})
                        check["source"] = usage.get("source")
                        check["providerStatus"] = usage.get("providerStatus")
                        check["providerErrorCode"] = usage.get("providerErrorCode")
                        check["pass"] = usage.get("source") == "gemini" and usage.get("providerStatus") == "succeeded"
                deleted = http.delete(ai_url + "/v1/chat/sessions/" + session_id, headers=headers,
                    params={"userId": owner}, timeout=10)
                report["checks"].append({"id": "qa-session-cleanup", "httpStatus": deleted.status_code,
                                          "pass": deleted.status_code == 200})
    except Exception as error:
        report["failure"] = {"type": type(error).__name__}
    report["pass"] = bool(report["checks"]) and "failure" not in report and all(
        check.get("pass") is True for check in report["checks"])
    print(json.dumps(report, ensure_ascii=True))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
