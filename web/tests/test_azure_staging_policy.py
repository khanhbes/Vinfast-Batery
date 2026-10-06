"""Exercise HTTP denial before any provider/enrollment handler executes."""
from unittest.mock import Mock

import pytest
from flask import Flask

from deployment_policy import staging_hardware_guard


@pytest.mark.parametrize("path", [
    "/api/smart-charging/on", "/api/smart-charging/sessions",
    "/api/smart-charging/rearm", "/api/shelly/devices/fake/safety-test",
    "/api/shelly/devices/fake/authorize", "/api/shelly/redeem-code",
    "/api/chat/action/confirm",
])
def test_staging_cannot_call_hardware_or_enrollment(monkeypatch, path):
    monkeypatch.setenv("AZURE_STAGING_HARDWARE_DISABLED", "1")
    app = Flask(__name__)
    app.before_request(staging_hardware_guard)
    provider = Mock(return_value="unsafe")
    app.add_url_rule(path, endpoint="fake_provider", view_func=lambda: provider(), methods=["POST"])
    response = app.test_client().post(path, json={"operationId": "qa-only"})
    assert response.status_code == 503
    assert response.json["code"] == "STAGING_HARDWARE_DISABLED"
    provider.assert_not_called()


@pytest.mark.parametrize("path,method", [
    ("/api/shelly/status", "GET"), ("/api/shelly/profiles/resolve", "POST"),
    ("/api/smart-charging/preview", "POST"), ("/api/smart-charging/off", "POST"),
    ("/api/smart-charging/session/fake/stop", "POST"),
    ("/api/mobile/onboarding/commit", "POST"), ("/api/chat/send", "POST"),
])
def test_staging_preserves_reads_auth_chat_and_safe_recovery(monkeypatch, path, method):
    monkeypatch.setenv("AZURE_STAGING_HARDWARE_DISABLED", "1")
    app = Flask(__name__)
    app.before_request(staging_hardware_guard)
    app.add_url_rule(path, view_func=lambda: "fake handler", methods=[method])
    assert app.test_client().open(path, method=method).status_code == 200


def test_local_policy_unchanged_without_opt_in(monkeypatch):
    monkeypatch.delenv("AZURE_STAGING_HARDWARE_DISABLED", raising=False)
    app = Flask(__name__)
    app.before_request(staging_hardware_guard)
    app.add_url_rule("/api/smart-charging/on", view_func=lambda: "fake only", methods=["POST"])
    assert app.test_client().post("/api/smart-charging/on").status_code == 200
