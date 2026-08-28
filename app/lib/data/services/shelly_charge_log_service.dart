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
      'modelKey': session.modelKey,
      'modelVersion': session.modelVersion,
      'runtimeHealth': session.runtimeHealth,
      'predictionWarnings': session.predictionWarnings,
      'fallbackReason': session.fallbackReason,
      'predictionAnalyzedAt': session.predictionAnalyzedAt == null
          ? null
          : Timestamp.fromDate(session.predictionAnalyzedAt!),
      'strategy': session.strategy.wireValue,
      'timerVerified': session.timerVerified,
      'smartChargingSession': session.toJson(),
      'socEstimated': true,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<SmartChargingSession>> loadTerminalSessions({
    int limit = 20,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    final snapshot = await _firestore
        .collection('ChargeLogs')
        .where('ownerUid', isEqualTo: uid)
        .limit(100)
        .get();
    final sessions = <SmartChargingSession>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      if (data['source'] != 'shelly_smart_charging' ||
          data['smartChargingSession'] is! Map) {
        continue;
      }
      try {
        sessions.add(
          SmartChargingSession.fromJson(
            Map<String, dynamic>.from(data['smartChargingSession'] as Map),
          ),
        );
      } on FormatException {
        // Ignore legacy/incomplete logs; they remain visible in ChargeLogs UI.
      }
    }
    sessions.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return sessions.take(limit).toList(growable: false);
  }
}
