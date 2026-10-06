"""Static-contract regressions: fake identities/models, no external requests."""
import json
import os
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

os.environ.setdefault("APP_ENV", "testing")


def test_model_load_route_is_registered_once_and_preserves_smoke_result(monkeypatch, tmp_path):
    from ai_server import model_store

    # The module may initialize model directories on import; keep those in tmp.
    monkeypatch.setenv("AI_SERVER_MODELS_DIR", str(tmp_path))
    monkeypatch.setattr(model_store.ModelStore, "seed_from_legacy", lambda *_args: None)
    from ai_server import main

    routes = [route for route in main.app.routes
              if getattr(route, "path", None) == "/v1/models/{type_key}/load-active"
              and "POST" in getattr(route, "methods", set())]
    assert len(routes) == 1
    runtime = SimpleNamespace(is_loaded=False, active_version=None,
                              load_persisted=Mock(return_value={"ok": True}))
    store = model_store.ModelStore(str(tmp_path / "store"))
    monkeypatch.setattr(store, "active_version", lambda: "v-test")
    monkeypatch.setattr(main, "_get_store", lambda _key: store)
    monkeypatch.setattr(main, "_get_runtime", lambda _key: runtime)
    monkeypatch.setattr(main, "_check_token", lambda _token: None)
    payload = json.loads(bytes(main.load_active_model("soc", None).body))
    assert payload["data"]["smokeTest"] == {"ok": True}
    assert payload["data"]["status"] == "loaded"
    runtime.is_loaded, runtime.active_version = True, "v-test"
    assert json.loads(bytes(main.load_active_model("soc", None).body))["data"]["status"] == "already_loaded"
    assert runtime.load_persisted.call_count == 1


def test_model_training_registration_preserves_source_and_metadata(tmp_path):
    from ai_server.model_store import ModelStore

    source = tmp_path / "trained.joblib"
    source.write_bytes(b"fake-model-artifact")
    store = ModelStore(str(tmp_path / "store"))
    metadata = {"mape": 3.5, "hyperparameters": {"maxDepth": 3}}
    store.save_version("v-training", str(source), metadata)
    metadata["hyperparameters"]["maxDepth"] = 99
    assert source.read_bytes() == b"fake-model-artifact"
    assert store.list_versions()[0]["metadata"]["hyperparameters"]["maxDepth"] == 3
    assert store.active_version() is None
    with pytest.raises(ValueError):
        store.save_version("v-training", str(source))
    assert source.exists()
    assert len(store.list_versions()) == 1
    assert not list((tmp_path / "store").glob("tmp*.joblib"))


def test_chat_confirmation_missing_session_is_rejected_without_execution():
    from ai_server.chat_engine import ChatEngine

    engine = ChatEngine()
    result = engine.confirm_action("missing", "start_smart_charging", {}, session_id=None)
    assert result["success"] is False
    assert result["code"] == "actionInvalid"


def test_shadow_status_uses_authenticated_account_repository(monkeypatch):
    import server

    repository = SimpleNamespace(history=Mock(return_value=[]))
    monkeypatch.setitem(server.app.extensions, "smart_charge_service", SimpleNamespace(repository=repository))
    monkeypatch.setattr(server, "_require_user_or_admin", lambda: ("qa-account", None))
    with server.app.test_client() as client:
        response = client.get("/api/smart-charge/shadow-status?vehicleId=qa-vehicle")
    assert response.status_code == 200
    payload = response.get_json()
    assert isinstance(payload, dict)
    assert payload["success"] is True
    repository.history.assert_called_once_with("qa-account", 50)


def test_vehicle_training_rejects_other_account_vehicle(monkeypatch):
    import server

    repository = SimpleNamespace(vehicle_for_owner=Mock(return_value=None), history=Mock())
    monkeypatch.setitem(server.app.extensions, "smart_charge_service", SimpleNamespace(repository=repository))
    monkeypatch.setattr(server, "_require_user_or_admin", lambda: ("qa-account", None))
    with server.app.test_client() as client:
        response = client.post("/api/ai/models/charging_time/fine-tune/vehicle",
                               json={"vehicleId": "other-account-vehicle", "sessions": [{"fake": True}]})
    assert response.status_code == 403
    repository.vehicle_for_owner.assert_called_once_with("qa-account", "other-account-vehicle")
    repository.history.assert_not_called()


def test_authenticated_request_context_does_not_grant_default_identity():
    from auth_context import AuthenticatedRequest

    request = AuthenticatedRequest.from_values()
    assert not hasattr(request, "_uid")
    assert not hasattr(request, "_role")
