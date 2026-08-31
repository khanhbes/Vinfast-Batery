import unittest

from shelly.providers import FakeShellyProvider
from shelly.repositories import SmartChargeRepository, _session_from_charge_log
from shelly.service import SmartChargeService


def _predict(_payload):
    return {
        "predictedDurationSeconds": 1800,
        "modelSource": "ai_model",
        "modelVersion": "history-test",
        "runtimeHealth": "loaded",
        "aiChargeEligible": True,
    }


class HistoryRetentionV4Tests(unittest.TestCase):
    def test_restored_charge_log_summary_is_readable_as_history_session(self):
        session = _session_from_charge_log({
            "sessionId": "restored-16-11",
            "ownerUid": "owner",
            "vehicleId": "vehicle-a",
            "shellyDeviceId": "plug-a",
            "source": "shelly_smart_charging",
            "startTime": "2026-08-29T16:11:00+00:00",
            "actualStopAt": "2026-08-29T20:11:00+00:00",
            "targetBatteryPercent": 80,
            "startBatteryPercent": 25,
            "predictedDurationSeconds": 14400,
            "sessionState": "terminal",
            "energyWh": 1850,
            "energyQuality": "partial",
        }, "restored-16-11", "owner")
        self.assertEqual(session.session_id, "restored-16-11")
        self.assertEqual(session.vehicle_id, "vehicle-a")
        self.assertEqual(session.state, "completed")
        self.assertEqual(session.energy_quality, "partial")
        self.assertEqual(session.energy_used_wh, 1850)

    def test_hidden_terminal_session_is_excluded_but_remains_recoverable(self):
        repo = SmartChargeRepository()
        provider = FakeShellyProvider()
        binding = provider.list_devices("owner")[0]
        binding.vehicle_id = "vehicle-a"
        repo.register_vehicle_owner("owner", "vehicle-a")
        repo.save_binding("owner", binding)
        service = SmartChargeService(repo, provider, _predict, sleeper=lambda _: None)
        preview = service.create_preview("owner", {"vehicleId": "vehicle-a", "currentSoc": 20, "targetSoc": 80})
        session = service.start("owner", preview.preview_id, "history-key")
        provider.status.relay = False
        service.current("owner", vehicle_id="vehicle-a")
        page, _ = repo.history_page("owner")
        self.assertEqual(len(page), 1)
        repo.hide_session("owner", session.session_id)
        hidden_page, _ = repo.history_page("owner")
        self.assertEqual(hidden_page, [])
        self.assertIsNotNone(repo.get_session("owner", session.session_id))


if __name__ == "__main__":
    unittest.main()
