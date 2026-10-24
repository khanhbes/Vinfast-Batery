"""HTTP surface for the dashboard image reader (QA 135)."""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from assistant.gemini import GeminiUnavailable

from .reader import ScanError, decode_image


def create_scan_blueprint(*, reader, quota, auth_resolver):
    bp = Blueprint("scan", __name__)

    def fail(status, code, message, retryable=False):
        return jsonify({"success": False, "code": code, "userMessage": message, "retryable": retryable,
                        "error": {"code": code, "message": message, "userMessage": message}}), status

    @bp.post("/api/scan/dashboard")
    def read_dashboard():
        uid, _email, _role = auth_resolver()
        if not uid:
            return fail(401, "unauthorized", "Cần đăng nhập")
        if not reader.configured:
            return fail(503, "scanAiUnavailable", "Chưa bật đọc ảnh bằng AI.")
        body = request.get_json(silent=True) or {}
        try:
            image, mime = decode_image(body.get("image"), body.get("mimeType"))
        except ScanError as error:
            return fail(error.status, error.code, error.message)
        last = body.get("lastOdoKm")
        try:
            last = float(last) if last not in (None, "") else None
        except (TypeError, ValueError):
            last = None
        allowed, remaining = quota.take(uid)
        if not allowed:
            return fail(429, "scanAiQuota", "Đã dùng hết lượt đọc ảnh bằng AI hôm nay.")
        try:
            result = reader.read(image, mime, last)
        except GeminiUnavailable:
            quota.refund(uid)
            return fail(503, "scanAiUnavailable", "Đọc ảnh bằng AI tạm thời không phản hồi.", retryable=True)
        except Exception:
            quota.refund(uid)
            return fail(503, "scanAiUnavailable", "Đọc ảnh bằng AI tạm thời không phản hồi.", retryable=True)
        # Nothing about the image is kept; only the count for the daily limit.
        return jsonify({"success": True, "data": {**result, "remainingToday": remaining}})

    return bp
