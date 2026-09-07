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
        assert response.status_code != 401 and response.status_code != 403, (
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
        assert response.status_code != 401 and response.status_code != 403, (
            "Vulnerability: /api/web/sync/trip-prediction is completely unauthenticated"
        )

    def test_unauthenticated_ai_dataset_access_and_export(self, client):
        """
        Audit Finding: /api/ai/dataset and /api/ai/dataset/export-csv are public,
        exposing all historical charging samples and vehicle telemetry without auth.
        """
        resp_list = client.get("/api/ai/dataset")
        assert resp_list.status_code == 200, "Dataset listing is public without authentication"
        
        resp_csv = client.get("/api/ai/dataset/export-csv")
        assert resp_csv.status_code == 200, "Dataset CSV export is public without authentication"
        assert "text/csv" in resp_csv.content_type

    def test_unauthenticated_ai_dataset_tampering_put(self, client):
        """
        Audit Finding: PUT /api/ai/dataset/records/<id> has no auth decorator,
        allowing anyone on network to edit dataset samples used for fine-tuning.
        """
        resp = client.put(
            "/api/ai/dataset/records/test_session_id_123",
            json={"actual_end_soc": 99.0, "notes": "tampered_by_attacker"}
        )
        assert resp.status_code != 401 and resp.status_code != 403, (
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
        assert response.status_code == 200
        mock_fs.collection.assert_called_with("Vehicles")
        mock_fs.collection.return_value.document.assert_called_with(target_vehicle_b_id)
        called_payload = mock_doc.set.call_args[0][0]
        assert called_payload["ownerUid"] == "dev-admin", (
            "Vulnerability WEB-H13: sync_vehicle overwrites target vehicle ownership without verifying existing owner"
        )

    def test_web_h12_owner_uid_override_in_user_add_vehicle(self, client, monkeypatch):
        """
        WEB-H12: Test whether /api/user/vehicles (POST) derives ownerUid from token
        or trusts the ownerUid passed in the request body.
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
        
        client.post(
            "/api/user/vehicles",
            json={"model": "VF-8", "ownerUid": "victim_user_b"},
            headers={"Authorization": "Bearer token_a"}
        )
        
        called_data = mock_doc.set.call_args[0][0]
        assert called_data["ownerUid"] == "user_a_real_id", (
            "Backend must derive ownerUid from verified token, not trust client input"
        )
