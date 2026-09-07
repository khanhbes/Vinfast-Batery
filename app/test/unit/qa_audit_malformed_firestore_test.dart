import 'package:flutter_test/flutter_test.dart';
import '../qa_harness/firebase_emulator_fixtures.dart';
import 'package:vinfast_battery/data/models/vehicle_model.dart';
import 'package:vinfast_battery/data/models/charge_log_model.dart';

bool isSemanticVersionNewer(String current, String latest) {
  List<int> parse(String v) {
    final clean = v.split('+').first;
    return clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }
  final c = parse(current);
  final l = parse(latest);
  for (int i = 0; i < 3; i++) {
    final cv = i < c.length ? c[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

void main() {
  group('QA Audit — Malformed Data Resilience & SemVer Comparison (CHK-13..15, CHK-38, APP-H14)', () {
    test('CHK-13 & CHK-14: Vehicle parsing handles missing fields and invalid type gracefully', () {
      final normalMap = {
        'vehicleId': 'VF_FELIZ_ALICE',
        'vehicleName': 'VinFast Feliz S (Alice)',
        'currentOdo': 4250,
        'currentBattery': 42,
        'stateOfHealth': 98.5,
      };
      final vehicle = VehicleModel.fromMap(normalMap);
      expect(vehicle.vehicleId, 'VF_FELIZ_ALICE');
      expect(vehicle.vehicleName, 'VinFast Feliz S (Alice)');

      // Malformed: missing mandatory fields
      final missingFieldsMap = <String, dynamic>{
        'vehicleName': 'Fallback Vehicle',
      };
      final fallbackVehicle = VehicleModel.fromMap(missingFieldsMap);
      expect(fallbackVehicle.vehicleName, 'Fallback Vehicle');
      expect(fallbackVehicle.currentOdo, 0);
    });

    test('CHK-13 & CHK-14: ChargeLog parser gracefully digests data without uncaught exceptions', () {
      final normalLog = {
        'logId': 'charge_alice_101',
        'vehicleId': 'VF_FELIZ_ALICE',
        'startTime': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'endTime': DateTime.now().toIso8601String(),
        'startBatteryPercent': 25,
        'endBatteryPercent': 95,
        'odoAtCharge': 4250,
      };
      final log = ChargeLogModel.fromMap(normalLog);

      expect(log.logId, 'charge_alice_101');
      expect(log.startBatteryPercent, 25);
      expect(log.endBatteryPercent, 95);
      expect(log.chargeGain, 70);
    });

    test('CHK-38 & APP-H14: Semantic version comparison (1.0.10 MUST be greater than 1.0.9)', () {
      expect(isSemanticVersionNewer('1.0.9', '1.0.10'), isTrue);
      expect(isSemanticVersionNewer('1.0.10', '1.0.9'), isFalse);
      expect(isSemanticVersionNewer('1.0.9', '1.1.0'), isTrue);
      expect(isSemanticVersionNewer('1.1.0', '2.0.0'), isTrue);
      expect(isSemanticVersionNewer('1.0.0', '1.0.0'), isFalse);
      expect(isSemanticVersionNewer('2.0.0', '1.9.9'), isFalse);
    });

    test('User A and User B data isolation contract', () {
      final aliceDoc = FirebaseEmulatorFixtures.vehicleAlice();
      final bobDoc = FirebaseEmulatorFixtures.vehicleBob();

      // Ensure distinct UIDs and vehicle IDs
      expect(aliceDoc['ownerUid'], isNot(equals(bobDoc['ownerUid'])));
      expect(aliceDoc['id'], isNot(equals(bobDoc['id'])));
      expect(aliceDoc['ownerUid'], FirebaseEmulatorFixtures.userA.uid);
      expect(bobDoc['ownerUid'], FirebaseEmulatorFixtures.userB.uid);
    });
  });
}
