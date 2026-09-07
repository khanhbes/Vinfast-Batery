/// Firebase Emulator and Mock Data Fixtures for VinFast Battery App QA Audit.
/// Includes User A/B isolation trees and malformed Firestore fixtures.

class QaUserFixture {
  const QaUserFixture({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.primaryVehicleId,
  });

  final String uid;
  final String email;
  final String displayName;
  final String primaryVehicleId;
}

class FirebaseEmulatorFixtures {
  // User A (Alice - Primary Owner)
  static const userA = QaUserFixture(
    uid: 'qa_user_alice_001',
    email: 'alice@vinfast-qa.local',
    displayName: 'Alice Nguyen',
    primaryVehicleId: 'VF_FELIZ_ALICE',
  );

  // User B (Bob - Secondary Isolated Owner)
  static const userB = QaUserFixture(
    uid: 'qa_user_bob_002',
    email: 'bob@vinfast-qa.local',
    displayName: 'Bob Tran',
    primaryVehicleId: 'VF_KLARA_BOB',
  );

  // User A Vehicle Document
  static Map<String, dynamic> vehicleAlice() => {
    'id': userA.primaryVehicleId,
    'ownerUid': userA.uid,
    'name': 'VinFast Feliz S (Alice)',
    'modelCode': 'VF_FELIZ_2025',
    'batteryCapacityKwh': 3.5,
    'currentSoc': 42.0,
    'soh': 98.5,
    'odometerKm': 4250.0,
    'isDeleted': false,
    'isArchived': false,
    'archivedAt': null,
    'createdAt': '2026-01-15T08:00:00Z',
    'updatedAt': '2026-09-07T12:00:00Z',
  };

  // User B Vehicle Document
  static Map<String, dynamic> vehicleBob() => {
    'id': userB.primaryVehicleId,
    'ownerUid': userB.uid,
    'name': 'VinFast Klara S (Bob)',
    'modelCode': 'VF_KLARA_S',
    'batteryCapacityKwh': 3.5,
    'currentSoc': 85.0,
    'soh': 94.0,
    'odometerKm': 12800.0,
    'isDeleted': false,
    'isArchived': false,
    'archivedAt': null,
    'createdAt': '2026-02-10T09:00:00Z',
    'updatedAt': '2026-09-07T14:30:00Z',
  };

  // User A ChargeLog Document
  static Map<String, dynamic> chargeLogAlice({String logId = 'charge_alice_101'}) => {
    'id': logId,
    'ownerUid': userA.uid,
    'vehicleId': userA.primaryVehicleId,
    'startSoc': 25.0,
    'targetSoc': 100.0,
    'actualEndSoc': 95.0,
    'energyWh': 2650.0,
    'durationSeconds': 9600,
    'sessionState': 'completed',
    'isDeleted': false,
    'createdAt': '2026-09-06T18:00:00Z',
    'completedAt': '2026-09-06T20:40:00Z',
  };

  // User B ChargeLog Document
  static Map<String, dynamic> chargeLogBob({String logId = 'charge_bob_201'}) => {
    'id': logId,
    'ownerUid': userB.uid,
    'vehicleId': userB.primaryVehicleId,
    'startSoc': 40.0,
    'targetSoc': 80.0,
    'actualEndSoc': 80.0,
    'energyWh': 1480.0,
    'durationSeconds': 5400,
    'sessionState': 'completed',
    'isDeleted': false,
    'createdAt': '2026-09-07T07:00:00Z',
    'completedAt': '2026-09-07T08:30:00Z',
  };

  // --- MALFORMED FIRESTORE FIXTURES FOR RESILIENCE TESTING ---

  /// Missing mandatory fields (null vehicleId, missing batteryCapacity)
  static Map<String, dynamic> malformedVehicleMissingFields() => {
    'name': 'Corrupted Vehicle (No ID/Capacity)',
    'isDeleted': false,
  };

  /// Wrong types (String instead of double/int, int instead of bool)
  static Map<String, dynamic> malformedVehicleWrongTypes() => {
    'id': 'VF_CORRUPT_001',
    'ownerUid': userA.uid,
    'name': 'Type Mismatched Vehicle',
    'batteryCapacityKwh': 'three_point_five', // String instead of num
    'currentSoc': 'seventy_percent',          // String instead of num
    'isDeleted': 'false_string',               // String instead of bool
  };

  /// Corrupted ChargeLog with boundary violations (SOC > 100, negative duration, negative energy)
  static Map<String, dynamic> malformedChargeLogBoundaryViolations() => {
    'id': 'corrupt_charge_999',
    'ownerUid': userA.uid,
    'vehicleId': userA.primaryVehicleId,
    'startSoc': -15.0,        // Negative SOC violation
    'targetSoc': 150.0,       // SOC > 100 violation
    'actualEndSoc': 105.0,    // SOC > 100 violation
    'energyWh': -2500.0,      // Negative energy violation
    'durationSeconds': -3600, // Negative duration violation
    'sessionState': 'unknown_corrupted_state',
    'isDeleted': false,
  };

  /// Corrupted TripLog with invalid out-of-order GPS points and negative distance
  static Map<String, dynamic> malformedTripOutOfOrder() => {
    'id': 'corrupt_trip_001',
    'ownerUid': userA.uid,
    'vehicleId': userA.primaryVehicleId,
    'distanceKm': -12.4, // Negative distance
    'startSoc': 40.0,
    'endSoc': 65.0,      // Consumed negative battery (battery went UP during driving)
    'routePoints': [
      {'lat': 21.0285, 'lng': 105.8542, 'timestamp': '2026-09-07T10:00:00Z'},
      {'lat': 21.0350, 'lng': 105.8600, 'timestamp': '2026-09-07T09:45:00Z'}, // Out of order!
      {'lat': 999.0, 'lng': -999.0, 'timestamp': 'invalid-date-string'},      // Impossible GPS & invalid date
    ],
  };

  /// Corrupted Timestamp format
  static Map<String, dynamic> malformedTimestampDoc() => {
    'id': 'doc_bad_timestamp',
    'createdAt': 'not-a-valid-iso-date-string',
    'updatedAt': 1234567890123456789, // Oversized integer
  };
}
