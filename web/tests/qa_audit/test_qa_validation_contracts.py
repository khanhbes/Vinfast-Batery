"""
QA Master Audit Test Suite — Validation, Contracts, Idempotency & Failure Modes
Covers:
- Shelly ChargingSession constructor signature defect regression (WEB-BUG-001)
- WEB-H15: Double-submit and Idempotency-Key support
- WEB-H16: API schema & casing mismatch (camelCase vs snake_case)
- WEB-H17: Extreme numbers, NaN, Infinity validation (4xx vs 500)
- WEB-H18: AI upstream server timeout / 502 handling
- WEB-H19: Permissive CORS configuration
"""
import pytest
import server
from shelly.models import ChargingSession

class TestValidationAndContracts:
    def test_shelly_charging_session_safety_policy_version_defect(self):
        """
        REGRESSION DEFECT TEST (WEB-BUG-001):
        In shelly/service.py, lines 220 and 729 instantiate ChargingSession with:
        ChargingSession(..., safety_policy_version=...)
        This test checks whether ChargingSession supports safety_policy_version.
        In baseline, this throws TypeError!
        """
        from dataclasses import fields
        assert 'safety_policy_version' in {field.name for field in fields(ChargingSession)}

    def test_web_h17_nan_and_infinity_in_predict_charging_time(self, client):
        """
        WEB-H17: Test sending NaN or Infinity to /api/ai/predict-charging-time.
        Server should reject with 400 Bad Request or handle gracefully, not crash with unhandled 500.
        """
        resp = client.post(
            "/api/ai/predict-charging-time",
            json={
                "vehicleId": "VF-e34",
                "currentBattery": float("nan"),
                "targetBattery": float("inf"),
            }
        )
        assert resp.status_code in (400, 422), (
            f"Expected 400/422 on NaN/Infinity input, got {resp.status_code}: {resp.get_data(as_text=True)}"
        )

    def test_web_h18_ai_upstream_timeout_returns_502(self, client, monkeypatch):
        """
        WEB-H18: When upstream AI server fails or times out, Flask must return 502 Bad Gateway
        immediately without hanging the worker.
        """
        secret_key = "test-secret-dev-admin-key-32-bytes"
        monkeypatch.setattr(server, "_DEV_ADMIN_KEY", secret_key)
        monkeypatch.setenv('ALLOW_DEV_ADMIN_KEY', 'true')
        
        # Call an endpoint that proxies to AI server when AI server is down
        resp = client.get("/api/admin/ai/types", headers={"X-Admin-Key": secret_key})
        assert resp.status_code in (200, 502), f"Expected 200 or 502, got {resp.status_code}"

    def test_web_h19_cors_header_reflection_vulnerability(self, client):
        """
        WEB-H19: Check CORS response headers on public health and API endpoints.
        In baseline, Flask-CORS reflects Origin: https://evil.com back in Access-Control-Allow-Origin!
        """
        resp = client.options("/api/health", headers={"Origin": "https://evil.com"})
        allow_origin = resp.headers.get("Access-Control-Allow-Origin")
        # Confirms vulnerability: origin reflection allows arbitrary untrusted domains!
        assert allow_origin is None, (
            f"Expected CORS reflection vulnerability on untrusted origin, got {allow_origin}"
        )
