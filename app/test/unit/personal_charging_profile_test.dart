import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/personal_charging_profile.dart';

void main() {
  test('personal profile parses owner-safe public contract', () {
    final profile = PersonalChargingProfile.fromJson({
      'vehicleId': 'VF-001',
      'consentEnabled': true,
      'validSessions': 5,
      'powerSessions': 7,
      'adapterVersion': 'personal-v5',
      'active': true,
      'validationMape': 8.2,
    });
    expect(profile.vehicleId, 'VF-001');
    expect(profile.consentEnabled, isTrue);
    expect(profile.active, isTrue);
    expect(profile.validationMape, 8.2);
  });

  test('eta candidates preserve adaptive fusion provenance', () {
    final candidate = EtaCandidate.fromJson({
      'source': 'personal',
      'durationSeconds': 14400,
      'weight': 0.4,
      'confidence': 92,
      'reason': 'personal-v5',
    });
    expect(candidate.durationSeconds, 14400);
    expect(candidate.weight, closeTo(0.4, 0.0001));
    expect(candidate.reason, 'personal-v5');
  });
}
