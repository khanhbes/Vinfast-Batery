"""
QA Master Audit Test Suite — IDOR, Multi-Tenancy & Data Integrity
Covers:
- WEB-H3: Public telemetry cross-user leak
- WEB-H4: Public charge logs exposure
- WEB-H12: Backend trusting client-supplied ownerUid
- WEB-H13: Vehicle IDOR / Account takeover via sync_vehicle & sync_full
- WEB-H14: Soft-deleted records exposed via public queries
- Unauthenticated endpoints leaking or allowing tampering of training datasets
"""
import pytest
import server
from unittest.mock import MagicMock

class TestIdorAndDataIntegrity:
    def test_unauthenticated_battery_state_sync_is_permitted(self, client):
        """
        Audit Finding: /api/web/sync/battery-state lacks any auth decorator,
        allowing unauthenticated callers to write arbitrary battery records.
        """
        response = client.post(
            "/api/web/sync/battery-state",
            json={"batteryLevel": 85, "voltage": 400.0, "current": 10.0}
        )
        assert response.status_code == 401, (
            "Vulnerability: /api/web/sync/battery-state is completely unauthenticated"
        )

    def test_unauthenticated_trip_prediction_sync_is_permitted(self, client):
        """
        Audit Finding: /api/web/sync/trip-prediction lacks any auth decorator,
        allowing unauthenticated callers to write trip prediction records.
        """
        response = client.post(
            "/api/web/sync/trip-prediction",
            json={"distance": 25.5, "predictedSoc": 60}
        )
        assert response.status_code == 401, (
            "Vulnerability: /api/web/sync/trip-prediction is completely unauthenticated"
        )

    def test_unauthenticated_ai_dataset_access_and_export(self, client):
        """
        Audit Finding: /api/ai/dataset and /api/ai/dataset/export-csv are public,
        exposing all historical charging samples and vehicle telemetry without auth.
        """
        resp_list = client.get("/api/ai/dataset")
        assert resp_list.status_code == 401
        
        resp_csv = client.get("/api/ai/dataset/export-csv")
        assert resp_csv.status_code == 401

    def test_unauthenticated_ai_dataset_tampering_put(self, client):
        """
        Audit Finding: PUT /api/ai/dataset/records/<id> has no auth decorator,
        allowing anyone on network to edit dataset samples used for fine-tuning.
        """
        resp = client.put(
            "/api/ai/dataset/records/test_session_id_123",
            json={"actual_end_soc": 99.0, "notes": "tampered_by_attacker"}
        )
        assert resp.status_code == 401, (
            "Vulnerability: dataset record update lacks authentication"
        )

    def test_web_h13_vehicle_idor_takeover_in_sync_vehicle(self, client, monkeypatch):
        """
        WEB-H13: In /api/web/sync/vehicle, verify if User A can overwrite a vehicle
        belonging to User B by providing vehicleId in the request body.
        """
        mock_fs = MagicMock()
        mock_doc = MagicMock()
        mock_fs.collection.return_value.document.return_value = mock_doc
        monkeypatch.setattr(server, "_firestore_db", mock_fs)
        monkeypatch.setattr(server, '_verify_token', lambda: ('user-a', 'a@test.invalid', 'user'))
        from sync_writes import commit_owned_writes
        mock_doc.get.return_value.exists = True
        mock_doc.get.return_value.to_dict.return_value = {'ownerUid': 'user-b'}
        monkeypatch.setattr(server, 'commit_owned_writes', lambda db, writes, uid: commit_owned_writes(db, writes, uid, runner=lambda fn: fn(MagicMock())))
        
        secret_key = "test-secret-dev-admin-key-32-bytes"
        monkeypatch.setattr(server, "_DEV_ADMIN_KEY", secret_key)
        
        headers = {"X-Admin-Key": secret_key}
        target_vehicle_b_id = "vehicle_owned_by_user_b"
        
        response = client.post(
            "/api/web/sync/vehicle",
            json={
                "vehicleId": target_vehicle_b_id,
                "model": "VF-e34",
                "batteryCapacityWh": 42000
            },
            headers=headers
        )
        assert response.status_code == 403
        mock_doc.set.assert_not_called()

    def test_web_h12_owner_uid_override_in_user_add_vehicle(self, client, monkeypatch):
        """
        WEB-H12: Legacy/custom vehicle payloads are rejected. Creation requires
        a published catalogId and ownership is always derived from the token.
        """
        mock_fs = MagicMock()
        mock_doc = MagicMock()
        mock_fs.collection.return_value.document.return_value = mock_doc
        monkeypatch.setattr(server, "_firestore_db", mock_fs)
        
        class MockFirebaseAuth:
            def verify_id_token(self, token):
                return {"uid": "user_a_real_id", "email": "usera@test.com", "admin": False}
        monkeypatch.setattr(server, "_firebase_available", True)
        monkeypatch.setattr(server, "_firebase_auth", MockFirebaseAuth())
        
        response = client.post(
            "/api/user/vehicles",
            json={"model": "VF-8", "ownerUid": "victim_user_b"},
            headers={"Authorization": "Bearer token_a"}
        )

        assert response.status_code == 400
        assert response.get_json()["error"] == "catalogId is required"
        mock_doc.set.assert_not_called()
