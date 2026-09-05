import unittest

from ai_server.lifecycle import dataset_manifest, detect_drift, personal_ai_eligibility, promotion_gate, split_by_vehicle_and_time


class AiLifecycleTests(unittest.TestCase):
    def test_split_is_chronological_per_vehicle(self):
        rows = [{"vehicleId": "A", "measuredAt": f"2026-01-0{i}T00:00:00Z"} for i in range(1, 6)]
        split = split_by_vehicle_and_time(rows)
        self.assertEqual(len(split["train"]), 3)
        self.assertLess(split["train"][-1]["measuredAt"], split["validation"][0]["measuredAt"])
        self.assertLess(split["validation"][-1]["measuredAt"], split["test"][0]["measuredAt"])

    def test_manifest_is_versioned_and_promotion_requires_improvement(self):
        manifest = dataset_manifest("charging_time", [{"vehicleId": "A", "measuredAt": "2026-01-01T00:00:00Z"}])
        decision = promotion_gate({"mae": 8, "rmse": 10, "bias": 0.1, "sampleCount": 25}, {"mae": 10, "rmse": 11, "bias": 0.1, "sampleCount": 25}, task="charging_time")
        self.assertTrue(manifest["datasetVersion"].startswith("charging_time-ds-"))
        self.assertTrue(decision["approved"])
        self.assertEqual(decision["mode"], "canary")

    def test_personal_ai_threshold_and_drift(self):
        rows = [{"actual_end_soc": 80, "measuredAt": f"2026-01-{(i % 20) + 1:02d}T00:00:00Z"} for i in range(30)]
        self.assertTrue(personal_ai_eligibility(rows)["eligible"])
        self.assertEqual(detect_drift([10] * 20, [14] * 20)["status"], "drift_detected")


if __name__ == "__main__":
    unittest.main()
