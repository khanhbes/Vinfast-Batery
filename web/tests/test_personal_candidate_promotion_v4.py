import unittest
from dataclasses import replace

from shelly.models import PersonalChargingProfile
from shelly.personal_model_registry import PersonalModelRegistry, validate_candidate


class PersonalCandidatePromotionV4Tests(unittest.TestCase):
    def setUp(self):
        self.profile = PersonalChargingProfile(
            owner_uid="owner-a", vehicle_id="vehicle-a", consent_enabled=True,
            valid_sessions=5, profile_version=3, base_model_version="charging-v2",
        )
        self.rows = [
            {"sessionId": f"s{i}", "predictedMinutes": 60, "durationSeconds": 3900}
            for i in range(5)
        ]

    def test_candidate_promotes_and_is_owner_vehicle_scoped(self):
        registry = PersonalModelRegistry()
        candidate_profile, candidate = registry.build_candidate(
            self.profile, "owner-a", "vehicle-a", self.rows, "charging-v2"
        )
        decision = registry.promote_or_reject(
            candidate_profile, candidate,
            validate_candidate(candidate_profile, self.rows),
        )
        self.assertEqual(decision.status, "promoted")
        self.assertEqual(registry.promoted("owner-a", "vehicle-a").vehicle_id, "vehicle-a")
        self.assertIsNone(registry.promoted("owner-b", "vehicle-a"))

    def test_regressing_candidate_is_rejected_without_replacing_promoted(self):
        registry = PersonalModelRegistry()
        candidate_profile, candidate = registry.build_candidate(
            self.profile, "owner-a", "vehicle-a", self.rows, "charging-v2"
        )
        first = registry.promote_or_reject(candidate_profile, candidate)
        self.assertEqual(first.status, "promoted")
        worse_rows = [
            {"sessionId": f"w{i}", "predictedMinutes": 60, "durationSeconds": 5400}
            for i in range(5)
        ]
        candidate_profile, candidate = registry.build_candidate(
            self.profile, "owner-a", "vehicle-a", worse_rows, "charging-v2"
        )
        decision = registry.promote_or_reject(
            candidate_profile, candidate, validate_candidate(candidate_profile, worse_rows)
        )
        self.assertEqual(decision.status, "rejected")
        self.assertEqual(registry.promoted("owner-a", "vehicle-a").profile_version, first.candidate.profile_version)

    def test_promotion_preserves_superseded_version_for_rollback(self):
        registry = PersonalModelRegistry()
        candidate_profile, candidate = registry.build_candidate(
            self.profile, "owner-a", "vehicle-a", self.rows, "charging-v2"
        )
        # Seed a promoted version with a non-zero baseline metric.
        first = registry.promote_or_reject(
            candidate_profile,
            replace(candidate, validation_mape=10.0),
        )
        self.assertEqual(first.status, "promoted")

        newer_profile = replace(self.profile, profile_version=4)
        newer_profile, newer = registry.build_candidate(
            newer_profile, "owner-a", "vehicle-a", self.rows, "charging-v2"
        )
        decision = registry.promote_or_reject(
            newer_profile, replace(newer, validation_mape=1.0)
        )
        self.assertEqual(decision.status, "promoted")
        restored = registry.rollback("owner-a", "vehicle-a")
        self.assertIsNotNone(restored)
        self.assertEqual(restored.profile_version, first.candidate.profile_version)


if __name__ == "__main__":
    unittest.main()
