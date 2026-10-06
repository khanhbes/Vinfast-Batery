"""Opt-in staging policy: a scale-to-zero QA API must never energize hardware."""
import os

from flask import jsonify, request


def staging_hardware_guard():
    if os.environ.get("AZURE_STAGING_HARDWARE_DISABLED", "0") != "1":
        return None
    if request.method in {"GET", "HEAD", "OPTIONS"}:
        return None
    path = request.path.rstrip("/")
    # Read-only POSTs and OFF/recovery remain available. All other Shelly
    # mutations are denied, including enrollment/control permits and safety tests.
    allowed = {
        "/api/shelly/profiles/resolve", "/api/smart-charging/preview",
        "/api/smart-charging/off",
    }
    recovery = path.startswith("/api/smart-charging/session/") and path.endswith("/stop")
    restore = path.startswith("/api/shelly/profiles/") and path.endswith("/restore")
    protected = path.startswith(("/api/shelly/", "/api/smart-charging/", "/api/smart-charge/"))
    if path == "/api/chat/action/confirm" or (protected and path not in allowed and not recovery and not restore):
        return jsonify({
            "success": False, "code": "STAGING_HARDWARE_DISABLED",
            "userMessage": "Bản thử nghiệm này chưa hỗ trợ bật sạc. Hãy dùng hệ thống đang hoạt động.",
            "error": "Hardware control is disabled in Azure staging",
            "retryable": False, "statusCode": 503,
        }), 503
    return None
