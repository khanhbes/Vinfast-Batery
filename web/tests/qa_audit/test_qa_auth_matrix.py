"""
QA Master Audit Test Suite — Authentication & Admin Authorization
Covers:
- WEB-H1: DEV_ADMIN_KEY bypass in production/testing
- WEB-H2: ADMIN_EMAILS=* wildcards promoting regular users to admin
- WEB-H5: Regular users accessing privileged admin routes
- WEB-H22: Firebase Auth service unavailable / fail-closed verification
"""
import pytest
import server

class TestAuthMatrix:
    def test_web_h1_dev_admin_key_bypasses_firebase_auth(self, client, monkeypatch):
        """
        WEB-H1: Verify if supplying X-Admin-Key allows full bypass of Firebase auth
        and executes admin actions as 'dev-admin'.
        """
        secret_key = "test-secret-dev-admin-key-32-bytes"
        monkeypatch.setattr(server, "_DEV_ADMIN_KEY", secret_key)
        
        # Sending request to admin-only endpoint with X-Admin-Key
        response = client.get(
            "/api/admin/ai/status",
            headers={"X-Admin-Key": secret_key}
        )
        # Auth succeeds because X-Admin-Key matches _DEV_ADMIN_KEY (status is 200 or 502 upstream)
        assert response.status_code in (200, 502), (
            f"Expected auth bypass with valid X-Admin-Key, got {response.status_code}"
        )

    def test_web_h1_wrong_admin_key_is_rejected(self, client, monkeypatch):
        """Verify that an invalid X-Admin-Key does not grant admin access."""
        monkeypatch.setattr(server, "_DEV_ADMIN_KEY", "real-admin-key")
        response = client.get(
            "/api/admin/ai/status",
            headers={"X-Admin-Key": "invalid-wrong-key"}
        )
        assert response.status_code == 401

    def test_web_h2_admin_emails_wildcard_vulnerability(self, monkeypatch):
        """
        WEB-H2: Test if ADMIN_EMAILS='*' turns every authenticated user into admin.
        """
        monkeypatch.setattr(server, "ADMIN_EMAILS", ["*"])
        
        class MockFirebaseAuth:
            def verify_id_token(self, token):
                return {"uid": "attacker_user_123", "email": "untrusted@evil.com", "admin": False}
        
        monkeypatch.setattr(server, "_firebase_available", True)
        monkeypatch.setattr(server, "_firebase_auth", MockFirebaseAuth())
        
        with server.app.test_request_context(headers={"Authorization": "Bearer mock-token"}):
            uid, email, role = server._verify_token()
            assert role == "admin", "Vulnerability WEB-H2: Wildcard * in ADMIN_EMAILS elevates regular users to admin"

    def test_web_h5_regular_user_cannot_access_admin_endpoints(self, client, monkeypatch):
        """
        WEB-H5: Verify whether a standard regular user is blocked from admin routes.
        """
        class MockFirebaseAuth:
            def verify_id_token(self, token):
                return {"uid": "regular_user_456", "email": "user@vinfast.vn", "admin": False}
        
        monkeypatch.setattr(server, "_firebase_available", True)
        monkeypatch.setattr(server, "_firebase_auth", MockFirebaseAuth())
        monkeypatch.setattr(server, "ADMIN_EMAILS", ["admin@vinfast.vn"])
        
        response = client.get(
            "/api/admin/ai/status",
            headers={"Authorization": "Bearer regular-token"}
        )
        assert response.status_code == 403, "Regular user should be rejected with 403 Forbidden"

    def test_web_h22_firebase_down_fails_closed_on_admin(self, client, monkeypatch):
        """
        WEB-H22: If Firebase Auth is down or unavailable, verify if admin routes fail-closed (401/403).
        """
        monkeypatch.setattr(server, "_firebase_available", False)
        monkeypatch.setattr(server, "_firebase_auth", None)
        monkeypatch.setattr(server, "_DEV_ADMIN_KEY", "")
        
        response = client.get(
            "/api/admin/ai/status",
            headers={"Authorization": "Bearer some-token"}
        )
        assert response.status_code == 401, "Should fail-closed with 401 Unauthorized"
