import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/smart_charging_session.dart';

class ShellyChargeLogService {
  ShellyChargeLogService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<void> saveTerminalSession(SmartChargingSession session) async {
    if (!session.state.isTerminal) return;
    await _firestore.collection('ChargeLogs').doc(session.sessionId).set({
      'sessionId': session.sessionId,
      'vehicleId': session.vehicleId,
      if (_auth.currentUser != null) 'ownerUid': _auth.currentUser!.uid,
      'startTime': Timestamp.fromDate(session.startedAt ?? session.createdAt),
      'endTime': Timestamp.fromDate(session.stoppedAt ?? session.updatedAt),
      'startBatteryPercent': session.startSoc.round(),
      'endBatteryPercent': (session.estimatedSoc ?? session.targetSoc).round(),
      'targetBatteryPercent': session.targetSoc.round(),
      'source': 'shelly_smart_charging',
      'shellyDeviceId': session.deviceId,
      'controlTransport': session.transport,
      'plannedStopAt': Timestamp.fromDate(session.effectiveStopAt),
      'actualStopAt': Timestamp.fromDate(
        session.stoppedAt ?? session.updatedAt,
      ),
      'stopReason': session.stopReason?.wireValue,
      'energyWh': session.energyUsedWh,
      'predictionSource': session.predictionSource,
      'predictionConfidence': session.predictionConfidence,
      'socEstimated': true,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
