import os
import base64
import os
import unittest
from datetime import timedelta
from unittest.mock import patch
from types import SimpleNamespace
from flask import Flask

from shelly.crypto import redact_secret
from shelly.models import DeviceBinding, utcnow
from shelly.providers import FakeShellyProvider
from shelly.rate_limiter import PerDeviceRateLimiter
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeError, SmartChargeService
from shelly.routes import create_blueprint
from smart_charge_worker import reconcile_once


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
        self.repo.register_vehicle_owner("user-a", "VF-001")

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

    def test_start_preserves_canonical_preview_seconds_for_device_timer(self):
        # The UI preview carries canonical seconds while minutes are rounded
        # for display. Starting from rounded minutes used to shorten/lengthen
        # the Shelly timer relative to the approved preview.
        def precise_predictor(_payload):
            return {
                "predictedDurationSeconds": 1859,
                "predictedMinutes": 31,
                "modelSource": "ai_model",
                "modelVersion": "test-v2",
                "runtimeHealth": "loaded",
                "confidence": 88,
                "aiChargeEligible": True,
            }

        service = SmartChargeService(
            self.repo, self.provider, precise_predictor, sleeper=lambda _: None,
        )
        preview = service.create_preview("user-a", {
            "vehicleId": "VF-001", "currentSoc": 25, "targetSoc": 80,
        })
        session = service.start("user-a", preview.preview_id, "precise-key")
        self.assertEqual(session.predicted_duration_seconds, 1859)
        self.assertEqual(self.provider.status.timer_remaining, 1859)
        timer_seconds = (session.effective_stop_at - session.created_at).total_seconds()
        self.assertLessEqual(abs(timer_seconds - 1859), 1)

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

    def test_explicit_stop_resolves_requested_session_not_first_account_session(self):
        # Two devices can charge concurrently; stopping the second one must
        # not accidentally compare against the first account-wide session.
        second_provider = FakeShellyProvider()
        self.binding.vehicle_id = "VF-001"
        self.repo.save_binding("user-a", self.binding)
        second_binding = second_provider.list_devices("user-a")[0]
        second_binding.device_id = "second-plug"
        second_binding.vehicle_id = "VF-002"
        second_provider.status.device_id = "second-plug"
        self.repo.save_binding("user-a", second_binding)
        self.repo.register_vehicle_owner("user-a", "VF-002")
        first = self.service.start("user-a", self.preview().preview_id, "first-device")
        second_service = SmartChargeService(
            self.repo, second_provider, predictor, sleeper=lambda _: None,
        )
        second_preview = second_service.create_preview("user-a", {
            "vehicleId": "VF-002", "currentSoc": 25, "targetSoc": 80,
        })
        second = second_service.start("user-a", second_preview.preview_id, "second-device")
        stopped = second_service.stop("user-a", second.session_id)
        self.assertEqual(stopped.session_id, second.session_id)
        self.assertEqual(self.repo.get_session("user-a", first.session_id).state, "active")

    def test_provider_without_device_timer_is_blocked(self):
        self.provider.supports_device_timer = False
        preview = self.preview()
        with self.assertRaises(SmartChargeError) as caught:
            self.service.start("user-a", preview.preview_id, "blocked")
        self.assertEqual(caught.exception.code, "providerTimerUnsupported")

    def test_binding_is_owned_by_uid(self):
        self.assertIsNotNone(self.service.binding("user-a"))
        self.assertIsNone(self.service.binding("user-b"))

    def test_legacy_single_binding_is_migrated_only_when_vehicle_is_unambiguous(self):
        # The fixture has exactly one active vehicle and one unscoped device.
        migrated = self.service.binding("user-a", "VF-001")
        self.assertIsNotNone(migrated)
        self.assertEqual(migrated.vehicle_id, "VF-001")

        self.repo.register_vehicle_owner("user-a", "VF-002")
        other_repo = SmartChargeRepository()
        other_repo.register_vehicle_owner("user-a", "VF-001")
        other_repo.register_vehicle_owner("user-a", "VF-002")
        other_repo.save_binding("user-a", FakeShellyProvider().list_devices("user-a")[0])
        other_service = SmartChargeService(other_repo, FakeShellyProvider(), predictor, sleeper=lambda _: None)
        self.assertIsNone(other_service.binding("user-a", "VF-002"))

    def test_vehicle_bound_charger_never_falls_through_to_another_vehicle(self):
        self.repo.register_vehicle_owner("user-a", "VF-002")
        self.binding.vehicle_id = "VF-001"
        self.repo.save_binding("user-a", self.binding)
        self.assertIsNotNone(self.service.binding("user-a", "VF-001"))
        self.assertIsNone(self.service.binding("user-a", "VF-002"))

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

    def test_environment_cannot_raise_hard_ten_hour_limit(self):
        with patch.dict(os.environ, {"SMART_CHARGE_MAX_MINUTES": "9999"}):
            service = SmartChargeService(
                self.repo, self.provider, predictor, sleeper=lambda _: None,
            )
        self.assertEqual(service.max_minutes, 600)

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

    def test_personal_profile_is_scoped_by_owner_and_fuses_eta(self):
        profile = self.service.update_personal_consent("user-a", "VF-001", True)
        profile.valid_sessions = 5
        profile.active = True
        profile.eta_bias_ratio = 0.10
        profile.validation_mape = 8
        profile.adapter_version = "personal-v5"
        profile.median_power_w = 500
        self.repo.save_personal_profile(profile)
        preview = self.service.create_preview("user-a", {
            "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
            "estimatedCapacityWh": 3000, "capacityConfidence": 90,
        })
        sources = {item.source for item in preview.eta_candidates}
        self.assertEqual(sources, {"global_ai", "physics", "personal"})
        self.assertAlmostEqual(sum(item.weight for item in preview.eta_candidates), 1.0)
        self.assertIsNone(self.repo.get_personal_profile("user-b", "VF-001"))

    def test_personal_data_delete_does_not_cross_owner(self):
        self.service.update_personal_consent("user-a", "VF-001", True)
        self.repo.register_vehicle_owner("user-b", "VF-B")
        self.service.update_personal_consent("user-b", "VF-B", True)
        self.service.delete_personal_profile("user-a", "VF-001")
        self.assertIsNone(self.repo.get_personal_profile("user-a", "VF-001"))
        self.assertIsNotNone(self.repo.get_personal_profile("user-b", "VF-B"))

    def test_same_vehicle_id_cannot_cross_accounts(self):
        with self.assertRaises(SmartChargeError) as caught:
            self.service.create_preview("user-b", {
                "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
            })
        self.assertEqual(caught.exception.code, "vehicleForbidden")

    def test_archived_vehicle_cannot_create_preview_or_train(self):
        self.repo.set_vehicle_archived("user-a", "VF-001")
        with self.assertRaisesRegex(SmartChargeError, "không thuộc"):
            self.service.create_preview("user-a", {
                "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
            })

    def test_safety_cutoff_requires_two_consecutive_samples(self):
        active = self.service.start("user-a", self.preview().preview_id, "safety")
        self.provider.status.power_w = 2460
        self.service.status("user-a")
        self.assertTrue(self.provider.status.relay)
        self.service.status("user-a")
        self.assertFalse(self.provider.status.relay)
        terminal = next(item for item in self.repo.history("user-a") if item.session_id == active.session_id)
        self.assertEqual(terminal.stop_reason, "safety_cutoff")

    def test_privacy_erase_requires_confirmation_and_only_erases_terminal(self):
        active = self.service.start("user-a", self.preview().preview_id, "erase")
        with self.assertRaisesRegex(SmartChargeError, "đang sạc"):
            self.service.privacy_erase_session("user-a", active.session_id, active.session_id)
        self.service.stop("user-a", active.session_id)
        with self.assertRaisesRegex(SmartChargeError, "xác nhận"):
            self.service.privacy_erase_session("user-a", active.session_id, "wrong")
        self.service.privacy_erase_session("user-a", active.session_id, active.session_id)
        self.assertIsNone(self.repo.get_session("user-a", active.session_id))

    def test_hide_session_keeps_record_but_excludes_it_from_history(self):
        active = self.service.start("user-a", self.preview().preview_id, "hide")
        self.service.stop("user-a", active.session_id)
        hidden = self.service.hide_session("user-a", active.session_id)
        self.assertIsNotNone(hidden.hidden_at)
        self.assertEqual(self.repo.history("user-a"), [])
        self.assertIsNotNone(self.repo.get_session("user-a", active.session_id))


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

    def test_nested_switch_component_is_parsed(self):
        from shelly.providers.legacy_cloud import LegacyCloudControlProvider

        class Response:
            status_code = 200
            def json(self):
                return {"result": {"device": {"status": {
                    "switch:0": {"output": True, "apower": 812.5,
                                  "voltage": 231.0, "current": 3.6,
                                  "timer_remaining": 42}
                }}}}

        class Session:
            def post(self, *args, **kwargs):
                return Response()

        provider = LegacyCloudControlProvider(
            host="https://shelly-test-eu.shelly.cloud", auth_key="test-only",
            session=Session(), limiter=PerDeviceRateLimiter(interval_seconds=0),
        )
        status = provider.get_status(DeviceBinding("plug-id", "Plug", "S3PL-00112EU", 3, "legacy"))
        self.assertTrue(status.relay)
        self.assertEqual(status.timer_remaining, 42)
        self.assertEqual(status.power_w, 812.5)


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
        self.repo.register_vehicle_owner("owner", "VF-001")
        app = Flask(__name__)
        app.register_blueprint(create_blueprint(self.service, self.repo, lambda: ("owner", "owner@test", "user")))
        self.client = app.test_client()

    def test_easy_connect_fake_binds_owned_device(self):
        response = self.client.post("/api/shelly/consent/start")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()["data"]["completed"])
        self.assertIsNotNone(self.repo.get_binding("owner"))

    def test_encrypted_direct_profile_restore_is_owner_scoped(self):
        key = base64.urlsafe_b64encode(b"a" * 32).decode().rstrip("=")
        with patch.dict(os.environ, {"SHELLY_PROFILE_MASTER_KEY": key}):
            repo = SmartChargeRepository()
            repo.register_vehicle_owner("owner", "VF-001")
            service = SmartChargeService(repo, FakeShellyProvider(), predictor, sleeper=lambda _: None)
            app = Flask(__name__)
            app.register_blueprint(create_blueprint(service, repo, lambda: ("owner", "owner@test", "user")))
            client = app.test_client()
            saved = client.put("/api/shelly/profiles/plug-1", json={
                "vehicleId": "VF-001", "cloudHost": "https://shelly-eu.shelly.cloud",
                "cloudAuthKey": "secret-key", "lanAddress": "192.168.1.4",
                "verification": {"cloudVerified": True, "powerMeterVerified": True,
                                 "safeBootVerified": True, "noLoadTestVerified": True},
            })
            self.assertEqual(saved.status_code, 200)
            listed = client.get("/api/shelly/profiles?vehicleId=VF-001").get_json()["data"]["items"]
            self.assertNotIn("cloudAuthKey", listed[0])
            restored = client.post("/api/shelly/profiles/plug-1/restore")
            self.assertEqual(restored.status_code, 200)
            self.assertEqual(restored.get_json()["data"]["cloudAuthKey"], "secret-key")
            self.assertEqual(restored.headers["Cache-Control"], "no-store, private")

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

    def test_vehicle_scoped_off_cannot_stop_another_vehicle_session(self):
        self.client.post("/api/shelly/consent/start")
        started = self.client.post(
            "/api/smart-charging/on",
            json={"durationSeconds": 1800, "vehicleId": "VF-001", "currentSoc": 25},
            headers={"Idempotency-Key": "vehicle-off-scope"},
        )
        self.assertEqual(started.status_code, 200)
        wrong_vehicle = self.client.post(
            "/api/smart-charging/off",
            json={"vehicleId": "VF-NOT-OWNED"},
        )
        self.assertEqual(wrong_vehicle.status_code, 404)
        self.assertTrue(self.provider.status.relay)

    def test_capabilities_are_explicit(self):
        self.client.post("/api/shelly/consent/start")
        response = self.client.get("/api/shelly/capabilities")
        self.assertTrue(response.get_json()["data"]["readyForControl"])

    def test_capabilities_are_scoped_to_requested_vehicle(self):
        self.client.post("/api/shelly/consent/start")
        self.repo.register_vehicle_owner("owner", "VF-002")
        binding = self.repo.get_binding("owner")
        binding.vehicle_id = "VF-001"
        self.repo.save_binding("owner", binding)

        selected = self.client.get("/api/shelly/capabilities?vehicleId=VF-001")
        other = self.client.get("/api/shelly/capabilities?vehicleId=VF-002")
        self.assertTrue(selected.get_json()["data"]["readyForControl"])
        self.assertFalse(other.get_json()["data"]["readyForControl"])

    def test_device_selection_rejects_vehicle_owned_by_another_account(self):
        self.client.post("/api/shelly/consent/start")
        device_id = self.repo.list_bindings("owner")[0].device_id
        self.repo.register_vehicle_owner("someone-else", "VF-OTHER")
        response = self.client.post(
            f"/api/shelly/devices/{device_id}/select",
            json={"vehicleId": "VF-OTHER"},
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.get_json()["error"]["code"], "vehicleForbidden")

    def test_personal_profile_consent_contract(self):
        response = self.client.put(
            "/api/smart-charging/personal-profile/VF-001",
            json={"consentEnabled": True},
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.get_json()["data"]["consentEnabled"])
        other_repo = self.repo.get_personal_profile("someone-else", "VF-001")
        self.assertIsNone(other_repo)

    def test_training_data_edit_requires_server_developer_role(self):
        denied = self.client.get("/api/smart-charging/developer/training-access")
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(denied.get_json()["error"]["code"], "developerRequired")

        app = Flask(__name__)
        app.register_blueprint(
            create_blueprint(
                self.service,
                self.repo,
                lambda: ("owner", "owner@test", "admin"),
            )
        )
        allowed = app.test_client().get("/api/smart-charging/developer/training-access")
        self.assertEqual(allowed.status_code, 200)
        self.assertTrue(allowed.get_json()["data"]["canEditTrainingData"])

    def test_privacy_erase_route_returns_safe_errors_and_erases_terminal(self):
        self.client.post("/api/shelly/consent/start")
        preview = self.client.post("/api/smart-charging/preview", json={
            "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
        }).get_json()["data"]
        started = self.client.post(
            "/api/smart-charging/sessions",
            json={"previewId": preview["previewId"]},
            headers={"Idempotency-Key": "erase-route"},
        ).get_json()["data"]
        session_id = started["session_id"]
        active = self.client.delete(
            f"/api/smart-charging/sessions/{session_id}/privacy-erase",
            json={"confirmation": session_id},
        )
        self.assertEqual(active.status_code, 409)
        self.client.post(f"/api/smart-charging/session/{session_id}/stop")
        wrong = self.client.delete(
            f"/api/smart-charging/sessions/{session_id}/privacy-erase",
            json={"confirmation": "nope"},
        )
        self.assertEqual(wrong.status_code, 400)
        erased = self.client.delete(
            f"/api/smart-charging/sessions/{session_id}/privacy-erase",
            json={"confirmation": session_id},
        )
        self.assertEqual(erased.status_code, 200)
        self.assertIsNone(self.repo.get_session("owner", session_id))

    def test_hide_route_rejects_active_and_hides_terminal(self):
        self.client.post("/api/shelly/consent/start")
        preview = self.client.post("/api/smart-charging/preview", json={
            "vehicleId": "VF-001", "currentSoc": 20, "targetSoc": 80,
        }).get_json()["data"]
        started = self.client.post(
            "/api/smart-charging/sessions",
            json={"previewId": preview["previewId"]},
            headers={"Idempotency-Key": "hide-route"},
        ).get_json()["data"]
        session_id = started["session_id"]
        active = self.client.post(f"/api/smart-charging/sessions/{session_id}/hide")
        self.assertEqual(active.status_code, 409)
        self.client.post(f"/api/smart-charging/session/{session_id}/stop")
        hidden = self.client.post(f"/api/smart-charging/sessions/{session_id}/hide")
        self.assertEqual(hidden.status_code, 200)
        page = self.client.get("/api/smart-charging/history")
        self.assertEqual(page.status_code, 200)
        self.assertEqual(page.get_json()["data"]["items"], [])


class SecurityTests(unittest.TestCase):
    def test_redaction_never_returns_secret(self):
        secret = "very-sensitive-auth-key"
        self.assertNotIn(secret, redact_secret(secret))

    def test_no_secret_defaults_are_committed(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(os.environ.get("SHELLY_LEGACY_AUTH_KEY", ""), "")


class WorkerMultiVehicleTests(unittest.TestCase):
    def test_reconcile_checks_every_active_vehicle_session_binding(self):
        first = SimpleNamespace(vehicle_id="VF-A", session_id="s-a")
        second = SimpleNamespace(vehicle_id="VF-B", session_id="s-b")
        repository = SimpleNamespace(active_sessions=lambda uid: [first, second])
        provider = SimpleNamespace(
            get_status=lambda binding: SimpleNamespace(relay=True, timer_remaining=120),
        )
        requested = []
        service = SimpleNamespace(
            repository=repository,
            provider=provider,
            binding=lambda uid, vehicle_id: requested.append(vehicle_id) or object(),
        )
        result = reconcile_once(service, "owner")
        self.assertIs(result, first)
        self.assertEqual(requested, ["VF-A", "VF-B"])


if __name__ == "__main__":
    unittest.main()
