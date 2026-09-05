import unittest

from telemetry_schema import TelemetryValidationError, normalize_telemetry


class TelemetrySchemaTests(unittest.TestCase):
    def test_legacy_mobile_payload_is_preserved_and_normalized(self):
        item = normalize_telemetry({
            "vehicleId": "VF-001", "percentage": 68.5, "soh": 94,
            "timestamp": "2026-09-04T10:30:00Z", "source": "flutter_app",
        })
        self.assertEqual(item["schemaVersion"], "battery-telemetry/v1")
        self.assertEqual(item["percentage"], 68.5)
        self.assertEqual(item["measurements"]["soc"]["value"], 68.5)
        self.assertEqual(item["measurements"]["soc"]["source"], "manual_entry")
        self.assertEqual(item["measurements"]["soh"]["unit"], "%")

    def test_legacy_kw_and_kwh_convert_to_default_w_and_wh(self):
        item = normalize_telemetry({
            "vehicleId": "VF-001", "chargerId": "shelly-1", "source": "shelly",
            "powerKw": 2.3, "energyKwh": 1.25, "measuredAt": "2026-09-04T10:30:00+07:00",
        })
        self.assertEqual(item["measurements"]["power"]["value"], 2300.0)
        self.assertEqual(item["measurements"]["energy"]["value"], 1250.0)
        self.assertEqual(item["measurements"]["power"]["unit"], "W")
        self.assertEqual(item["measurements"]["energy"]["unit"], "Wh")
        self.assertEqual(item["measurements"]["power"]["source"], "shelly_meter")
        self.assertEqual(item["recordedAt"], "2026-09-04T03:30:00Z")

    def test_ai_measurement_tracks_confidence_and_model_version(self):
        item = normalize_telemetry({
            "vehicleId": "VF-001", "measurements": {"soc": {
                "value": 68.5, "source": "ai_estimate", "confidence": 0.82,
                "modelVersion": "soc-v3", "measuredAt": "2026-09-04T10:30:00Z",
            }},
        })
        self.assertEqual(item["measurements"]["soc"]["modelVersion"], "soc-v3")
        self.assertEqual(item["measurements"]["soc"]["confidence"], 0.82)

    def test_vehicle_id_and_measurement_are_required(self):
        with self.assertRaises(TelemetryValidationError):
            normalize_telemetry({"soc": 60})
        with self.assertRaises(TelemetryValidationError):
            normalize_telemetry({"vehicleId": "VF-001"})


if __name__ == "__main__":
    unittest.main()
