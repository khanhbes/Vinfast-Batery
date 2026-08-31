import unittest

from shelly.providers import FakeShellyProvider
from shelly.repositories import SmartChargeRepository
from shelly.service import SmartChargeError, SmartChargeService


def _predict(_payload):
    return {
        "predictedDurationSeconds": 1800,
        "modelSource": "ai_model",
        "modelVersion": "v4-test",
        "runtimeHealth": "loaded",
        "aiChargeEligible": True,
        "confidence": 90,
    }


class MultiVehicleSmartChargeV4Tests(unittest.TestCase):
    def test_two_vehicles_use_separate_devices_concurrently(self):
        repo = SmartChargeRepository()
        first_provider = FakeShellyProvider()
        second_provider = FakeShellyProvider()
        first = first_provider.list_devices("owner")[0]
        second = second_provider.list_devices("owner")[0]
        second.device_id = "plug-b"
        second.vehicle_id = "vehicle-b"
        first.vehicle_id = "vehicle-a"
        repo.register_vehicle_owner("owner", "vehicle-a")
        repo.register_vehicle_owner("owner", "vehicle-b")
        repo.save_binding("owner", first)
        repo.save_binding("owner", second)

        service_a = SmartChargeService(repo, first_provider, _predict, sleeper=lambda _: None)
        service_b = SmartChargeService(repo, second_provider, _predict, sleeper=lambda _: None)
        preview_a = service_a.create_preview("owner", {"vehicleId": "vehicle-a", "currentSoc": 20, "targetSoc": 80})
        preview_b = service_b.create_preview("owner", {"vehicleId": "vehicle-b", "currentSoc": 30, "targetSoc": 80})
        session_a = service_a.start("owner", preview_a.preview_id, "key-a")
        session_b = service_b.start("owner", preview_b.preview_id, "key-b")

        self.assertNotEqual(session_a.device_id, session_b.device_id)
        self.assertEqual(repo.current_session("owner", vehicle_id="vehicle-a").session_id, session_a.session_id)
        self.assertEqual(repo.current_session("owner", vehicle_id="vehicle-b").session_id, session_b.session_id)

    def test_same_physical_device_cannot_charge_two_vehicles(self):
        repo = SmartChargeRepository()
        provider = FakeShellyProvider()
        binding = provider.list_devices("owner")[0]
        binding.vehicle_id = "vehicle-a"
        repo.register_vehicle_owner("owner", "vehicle-a")
        repo.register_vehicle_owner("owner", "vehicle-b")
        repo.save_binding("owner", binding)
        shared = type(binding)(binding.device_id, binding.display_name, binding.model, binding.generation, binding.provider)
        shared.vehicle_id = "vehicle-b"
        shared.shared = True
        repo.save_binding("owner", shared)
        service = SmartChargeService(repo, provider, _predict, sleeper=lambda _: None)
        preview = service.create_preview("owner", {"vehicleId": "vehicle-a", "currentSoc": 20, "targetSoc": 80})
        service.start("owner", preview.preview_id, "first")
        other = service.create_preview("owner", {"vehicleId": "vehicle-b", "currentSoc": 20, "targetSoc": 80})
        with self.assertRaises(SmartChargeError) as caught:
            service.start("owner", other.preview_id, "second")
        self.assertEqual(caught.exception.code, "activeSessionConflict")

    def test_telemetry_targets_requested_session_when_two_devices_are_active(self):
        repo = SmartChargeRepository()
        provider_a = FakeShellyProvider()
        provider_b = FakeShellyProvider()
        binding_a = provider_a.list_devices("owner")[0]
        binding_b = provider_b.list_devices("owner")[0]
        binding_a.device_id, binding_a.vehicle_id = "plug-a", "vehicle-a"
        binding_b.device_id, binding_b.vehicle_id = "plug-b", "vehicle-b"
        repo.register_vehicle_owner("owner", "vehicle-a")
        repo.register_vehicle_owner("owner", "vehicle-b")
        repo.save_binding("owner", binding_a)
        repo.save_binding("owner", binding_b)
        service_a = SmartChargeService(repo, provider_a, _predict, sleeper=lambda _: None)
        service_b = SmartChargeService(repo, provider_b, _predict, sleeper=lambda _: None)
        preview_a = service_a.create_preview("owner", {"vehicleId": "vehicle-a", "currentSoc": 20, "targetSoc": 80})
        preview_b = service_b.create_preview("owner", {"vehicleId": "vehicle-b", "currentSoc": 30, "targetSoc": 80})
        session_a = service_a.start("owner", preview_a.preview_id, "telemetry-a")
        session_b = service_b.start("owner", preview_b.preview_id, "telemetry-b")

        result = service_b.record_telemetry("owner", session_b.session_id, {
            "powerW": 1200, "voltageV": 230, "currentA": 5.2,
            "energyWh": 12, "relay": True, "timerRemainingSeconds": 1700,
        })
        self.assertTrue(result["recorded"])
        self.assertEqual(repo.telemetry("owner", session_b.session_id)[0]["sessionId"], session_b.session_id)
        self.assertEqual(repo.telemetry("owner", session_a.session_id), [])

    def test_shared_device_lease_blocks_a_second_account(self):
        repo = SmartChargeRepository()
        provider = FakeShellyProvider()
        binding_a = provider.list_devices("owner-a")[0]
        binding_a.device_id, binding_a.vehicle_id = "shared-plug", "vehicle-a"
        binding_b = type(binding_a)(binding_a.device_id, binding_a.display_name,
                                    binding_a.model, binding_a.generation,
                                    binding_a.provider)
        binding_b.vehicle_id = "vehicle-b"
        repo.register_vehicle_owner("owner-a", "vehicle-a")
        repo.register_vehicle_owner("owner-b", "vehicle-b")
        repo.save_binding("owner-a", binding_a)
        repo.save_binding("owner-b", binding_b)
        first = SmartChargeService(repo, provider, _predict, sleeper=lambda _: None)
        second = SmartChargeService(repo, provider, _predict, sleeper=lambda _: None)
        first_preview = first.create_preview("owner-a", {"vehicleId": "vehicle-a", "currentSoc": 20, "targetSoc": 80})
        second_preview = second.create_preview("owner-b", {"vehicleId": "vehicle-b", "currentSoc": 20, "targetSoc": 80})
        first.start("owner-a", first_preview.preview_id, "shared-a")
        with self.assertRaises(SmartChargeError) as caught:
            second.start("owner-b", second_preview.preview_id, "shared-b")
        self.assertEqual(caught.exception.code, "activeSessionConflict")


if __name__ == "__main__":
    unittest.main()
