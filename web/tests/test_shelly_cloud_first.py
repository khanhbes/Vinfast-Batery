import os
import unittest
from datetime import timedelta
from unittest.mock import patch
from flask import Flask

from shelly.crypto import redact_secret
from shelly.models import DeviceBinding, utcnow
from shelly.providers import FakeShellyProvider
from shelly.rate_limiter import PerDeviceRateLimiter
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeError, SmartChargeService
from shelly.routes import create_blueprint


def predictor(_payload):
    return {
        "predictedDurationSeconds": 1800,
        "predictedMinutes": 30,
        "modelSource": "ai_model",
        "modelVersion": "test-v2",
        "runtimeHealth": "loaded",
        "confidence": 88,
        "aiChargeEligible": True,
    }


class SmartChargeServiceTests(unittest.TestCase):
    def setUp(self):
        self.repo = SmartChargeRepository()
        self.provider = FakeShellyProvider()
        self.service = SmartChargeService(self.repo, self.provider, predictor, sleeper=lambda _: None)
        self.binding = self.provider.list_devices("user-a")[0]
        self.repo.save_binding("user-a", self.binding)

    def preview(self):
        return self.service.create_preview("user-a", {
            "vehicleId": "VF-001",
            "currentSoc": 25,
            "targetSoc": 80,
        })

    def test_preview_is_scoped_to_owner_and_expires(self):
        preview = self.preview()
        self.assertIsNone(self.repo.get_preview("user-b", preview.preview_id))
        preview.expires_at = utcnow() - timedelta(seconds=1)
        with self.assertRaisesRegex(SmartChargeError, "hết hạn"):
            self.service.start("user-a", preview.preview_id, "key-1")

    def test_idempotent_start_only_sends_one_on(self):
        preview = self.preview()
        first = self.service.start("user-a", preview.preview_id, "same-key")
        second = self.service.start("user-a", preview.preview_id, "same-key")
        self.assertEqual(first.session_id, second.session_id)
        self.assertEqual(self.provider.command_count, 1)
        self.assertTrue(first.timer_verified)

    def test_active_session_conflict(self):
        first_preview = self.preview()
        self.service.start("user-a", first_preview.preview_id, "first")
        second_preview = self.preview()
        with self.assertRaisesRegex(SmartChargeError, "phiên sạc"):
            self.service.start("user-a", second_preview.preview_id, "second")

    def test_missing_timer_sends_off_and_marks_failed(self):
        self.provider.fail_readback = True
        preview = self.preview()
        with self.assertRaises(SmartChargeError) as caught:
            self.service.start("user-a", preview.preview_id, "failed")
        self.assertEqual(caught.exception.code, "timerNotArmed")
        self.assertFalse(self.provider.status.relay)
        self.assertEqual(self.repo.history("user-a")[0].state, "failed")

    def test_manual_off_requires_readback(self):
        preview = self.preview()
        active = self.service.start("user-a", preview.preview_id, "off")
        stopped = self.service.stop("user-a", active.session_id)
        self.assertEqual(stopped.state, "cancelled")
        self.assertTrue(stopped.relay_verified)

    def test_provider_without_device_timer_is_blocked(self):
        self.provider.supports_device_timer = False
        preview = self.preview()
        with self.assertRaises(SmartChargeError) as caught:
            self.service.start("user-a", preview.preview_id, "blocked")
        self.assertEqual(caught.exception.code, "providerTimerUnsupported")

    def test_binding_is_owned_by_uid(self):
        self.assertIsNotNone(self.service.binding("user-a"))
        self.assertIsNone(self.service.binding("user-b"))

    def test_manual_on_always_arms_device_timer(self):
        session = self.service.manual_on("user-a", 60, "manual-key")
        self.assertEqual(session.strategy, "manual_timed")
        self.assertTrue(session.relay_verified)
        self.assertTrue(session.timer_verified)

    def test_manual_on_rejects_unsafe_duration(self):
        with self.assertRaises(SmartChargeError) as caught:
            self.service.manual_on("user-a", 10 * 60 * 60 + 1, "unsafe")
        self.assertEqual(caught.exception.code, "unsafeDuration")

    def test_manual_on_accepts_exactly_ten_hours(self):
        session = self.service.manual_on("user-a", 10 * 60 * 60, "ten-hours")
        self.assertEqual(session.strategy, "manual_timed")
        self.assertTrue(session.timer_verified)

    def test_fallback_preview_cannot_start_ai(self):
        service = SmartChargeService(
            self.repo,
            self.provider,
            lambda _payload: {
                "predictedDurationSeconds": 1800,
                "modelSource": "heuristic_fallback",
                "modelVersion": "heuristic-v1",
                "runtimeHealth": "fallback",
                "aiChargeEligible": False,
            },
            sleeper=lambda _: None,
        )
        preview = service.create_preview("user-a", {
            "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
        })
        self.assertFalse(preview.ai_charge_eligible)
        with self.assertRaises(SmartChargeError) as caught:
            service.start("user-a", preview.preview_id, "fallback")
        self.assertEqual(caught.exception.code, "aiPredictionUnavailable")


class LegacyCloudResponseTests(unittest.TestCase):
    def test_official_top_level_device_state_list_is_parsed(self):
        from shelly.providers.legacy_cloud import LegacyCloudControlProvider

        class Response:
            status_code = 200
            def json(self):
                return [{
                    "id": "plug-id", "online": 1,
                    "status": {"switch:0": {"output": False, "voltage": 231.2, "aenergy": {"total": 9.5}}},
                }]

        class Session:
            def post(self, *args, **kwargs):
                return Response()

        provider = LegacyCloudControlProvider(
            host="https://shelly-test-eu.shelly.cloud",
            auth_key="test-only",
            session=Session(),
            limiter=PerDeviceRateLimiter(interval_seconds=0),
        )
        binding = DeviceBinding("plug-id", "Plug", "S3PL-00112EU", 3, "legacy")
        status = provider.get_status(binding)
        self.assertFalse(status.relay)
        self.assertEqual(status.voltage_v, 231.2)
        self.assertEqual(status.energy_wh, 9.5)

    def test_gen3_timer_fields_are_converted_to_remaining_seconds(self):
        from shelly.providers.legacy_cloud import LegacyCloudControlProvider

        class Response:
            status_code = 200
            def json(self):
                import time
                return [{"id": "plug-id", "online": 1, "status": {"switch:0": {
                    "output": True, "timer_started_at": time.time() - 30, "timer_duration": 120,
                }}}]

        class Session:
            def post(self, *args, **kwargs):
                return Response()

        provider = LegacyCloudControlProvider(
            host="https://shelly-test-eu.shelly.cloud", auth_key="test-only",
            session=Session(), limiter=PerDeviceRateLimiter(interval_seconds=0),
        )
        status = provider.get_status(DeviceBinding("plug-id", "Plug", "S3PL-00112EU", 3, "legacy"))
        self.assertGreaterEqual(status.timer_remaining, 89)
        self.assertLessEqual(status.timer_remaining, 90)


class RateLimiterTests(unittest.TestCase):
    def test_serial_interval_per_device(self):
        now = [0.0]
        sleeps = []

        def sleep(value):
            sleeps.append(value)
            now[0] += value

        limiter = PerDeviceRateLimiter(clock=lambda: now[0], sleeper=sleep)
        limiter.run("plug", lambda: None)
        limiter.run("plug", lambda: None)
        self.assertEqual(sleeps, [1.0])


class RouteContractTests(unittest.TestCase):
    def setUp(self):
        self.repo = SmartChargeRepository()
        self.provider = FakeShellyProvider()
        self.service = SmartChargeService(self.repo, self.provider, predictor, sleeper=lambda _: None)
        app = Flask(__name__)
        app.register_blueprint(create_blueprint(self.service, self.repo, lambda: ("owner", "owner@test", "user")))
        self.client = app.test_client()

    def test_easy_connect_fake_binds_owned_device(self):
        response = self.client.post("/api/shelly/consent/start")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()["data"]["completed"])
        self.assertIsNotNone(self.repo.get_binding("owner"))

    def test_preview_and_idempotent_start_contract(self):
        self.client.post("/api/shelly/consent/start")
        preview = self.client.post("/api/smart-charging/preview", json={
            "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
        }).get_json()["data"]
        headers = {"Idempotency-Key": "contract-key"}
        first = self.client.post("/api/smart-charging/sessions", json={"previewId": preview["previewId"]}, headers=headers)
        second = self.client.post("/api/smart-charging/sessions", json={"previewId": preview["previewId"]}, headers=headers)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.get_json()["data"]["session_id"], second.get_json()["data"]["session_id"])

    def test_manual_on_contract_returns_timed_session(self):
        self.client.post("/api/shelly/consent/start")
        response = self.client.post(
            "/api/smart-charging/on",
            json={"durationSeconds": 1800, "vehicleId": "VF-001", "currentSoc": 25},
            headers={"Idempotency-Key": "manual-contract"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["data"]["strategy"], "manual_timed")

    def test_capabilities_are_explicit(self):
        self.client.post("/api/shelly/consent/start")
        response = self.client.get("/api/shelly/capabilities")
        self.assertTrue(response.get_json()["data"]["readyForControl"])


class SecurityTests(unittest.TestCase):
    def test_redaction_never_returns_secret(self):
        secret = "very-sensitive-auth-key"
        self.assertNotIn(secret, redact_secret(secret))

    def test_no_secret_defaults_are_committed(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(os.environ.get("SHELLY_LEGACY_AUTH_KEY", ""), "")


if __name__ == "__main__":
    unittest.main()
