import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/smart_charge_history.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';

class ShellyChargeLogService {
  ShellyChargeLogService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Future<SharedPreferences> Function()? preferences,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const _source = 'shelly_smart_charging';
  static const _pendingIndexKey = 'smart_charge_pending_telemetry_sessions_v1';
  static const _pendingPrefix = 'smart_charge_pending_telemetry_v1_';
  static const telemetryRetention = Duration(days: 365);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Future<SharedPreferences> Function() _preferences;
  final Map<String, List<SmartChargeRawStatusSample>> _raw = {};
  final Map<String, List<SmartChargeTelemetryPoint>> _pending = {};

  Future<void> saveTerminalSession(SmartChargingSession session) async {
    if (!session.state.isTerminal) return;
    // Queue first so an auth/network failure can never lose a terminal session.
    await _queueTerminalSession(session);
    await flushPendingTelemetry(session.sessionId);
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      await _queueTerminalSession(session);
      return;
    }
    final points = await getTelemetry(session.sessionId);
    final summary = SmartChargeEnergySummary.calculate(
      session: session,
      points: points,
    );
    await _firestore.collection('ChargeLogs').doc(session.sessionId).set({
      ..._basePayload(session, uid),
      'endTime': Timestamp.fromDate(session.stoppedAt ?? session.updatedAt),
      'actualStopAt': Timestamp.fromDate(
        session.stoppedAt ?? session.updatedAt,
      ),
      'endBatteryPercent':
          (summary.estimatedEndSoc ?? session.estimatedSoc ?? session.targetSoc)
              .round(),
      'stopReason': session.stopReason?.wireValue,
      'gridEnergyWh': summary.gridEnergyWh,
      'energyWh': summary.gridEnergyWh,
      'estimatedStoredWh': summary.estimatedStoredWh,
      'estimatedRemainingWh': summary.estimatedRemainingWh,
      'estimatedEndSoc': summary.estimatedEndSoc,
      'averagePowerW': summary.averagePowerW,
      'peakPowerW': summary.peakPowerW,
      'averageVoltageV': summary.averageVoltageV,
      'averageCurrentA': summary.averageCurrentA,
      'maximumTemperatureC': summary.maximumTemperatureC,
      'telemetrySampleCount': summary.sampleCount,
      'telemetryCoverageRatio': summary.coverageRatio,
      'energyQuality': summary.energyQuality,
      'smartChargingSession': session.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _removeQueuedTerminalSession(session.sessionId);
  }

  Map<String, Object?> _basePayload(SmartChargingSession session, String uid) =>
      {
        'sessionId': session.sessionId,
        'vehicleId': session.vehicleId,
        'ownerUid': uid,
        'startTime': Timestamp.fromDate(session.startedAt ?? session.createdAt),
        'startBatteryPercent': session.startSoc.round(),
        'targetBatteryPercent': session.targetSoc.round(),
        'source': _source,
        'shellyDeviceId': session.deviceId,
        'controlTransport': session.transport,
        'plannedStopAt': Timestamp.fromDate(session.effectiveStopAt),
        'predictionSource': session.predictionSource,
        'predictionConfidence': session.predictionConfidence,
        'modelKey': session.modelKey,
        'modelVersion': session.modelVersion,
        'runtimeHealth': session.runtimeHealth,
        'predictionWarnings': session.predictionWarnings,
        'fallbackReason': session.fallbackReason,
        'strategy': session.strategy.wireValue,
        'timerVerified': session.timerVerified,
        'relayVerified': session.relayVerified,
        'estimatedCapacityWh': session.estimatedCapacityWh,
        'socEstimated': true,
        'isDeleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      };

  Future<void> recordStatusSample(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) async {
    if (session.state != ChargingSessionState.active) return;
    final now = DateTime.now();
    final raw = _raw.putIfAbsent(session.sessionId, () => []);
    raw.add(SmartChargeRawStatusSample(now, status));
    if (raw.length < 2 || now.difference(raw.first.timestamp).inSeconds < 30) {
      return;
    }
    final powers = raw.map((sample) => sample.status.powerW).toList();
    double average(double Function(SmartChargerStatus status) read) =>
        raw.map((sample) => read(sample.status)).reduce((a, b) => a + b) /
        raw.length;
    final temperatures = raw
        .map((sample) => sample.status.temperatureC)
        .whereType<double>()
        .toList();
    final latest = raw.last.status;
    final point = SmartChargeTelemetryPoint(
      timestamp: now,
      elapsedSeconds: now
          .difference(session.startedAt ?? session.createdAt)
          .inSeconds,
      powerAverageW: average((value) => value.powerW),
      powerMinimumW: powers.reduce((a, b) => a < b ? a : b),
      powerMaximumW: powers.reduce((a, b) => a > b ? a : b),
      voltageV: average((value) => value.voltageV),
      currentA: average((value) => value.currentA),
      temperatureC: temperatures.isEmpty
          ? null
          : temperatures.reduce((a, b) => a > b ? a : b),
      energyWh: latest.energyWh,
      estimatedSoc: _estimatedSoc(session, latest.energyWh),
      relay: latest.relay,
      timerRemainingSeconds: latest.timerRemaining?.inSeconds,
      transport: latest.transport?.name,
    );
    raw.clear();
    final pending = _pending.putIfAbsent(session.sessionId, () => []);
    pending.add(point);
    await _persistPending(session.sessionId, pending);
    if (pending.length >= 10) await flushPendingTelemetry(session.sessionId);
  }

  double? _estimatedSoc(SmartChargingSession session, double energyWh) {
    final capacity = session.estimatedCapacityWh ?? 0;
    final baseline = session.baselineEnergyWh;
    if (capacity <= 0 || baseline == null) return null;
    return (session.startSoc +
            (energyWh - baseline).clamp(0, double.infinity) *
                0.90 /
                capacity *
                100)
        .clamp(0, 100)
        .toDouble();
  }

  Future<void> flushPendingTelemetry(String sessionId) async {
    final points = await _loadPending(sessionId);
    if (points.isEmpty) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final parent = _firestore.collection('ChargeLogs').doc(sessionId);
    final first = points.first.timestamp;
    await parent.set({
      'sessionId': sessionId,
      'ownerUid': uid,
      'source': _source,
      'isDeleted': false,
      'startTime': Timestamp.fromDate(first),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final chunkId = first.microsecondsSinceEpoch.toString();
    await parent.collection('smartChargeTelemetry').doc(chunkId).set({
      'ownerUid': uid,
      'sessionId': sessionId,
      'startedAt': Timestamp.fromDate(first),
      'points': points.map((point) => point.toJson()).toList(),
      'expireAt': Timestamp.fromDate(DateTime.now().add(telemetryRetention)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _pending[sessionId] = [];
    await _persistPending(sessionId, const []);
  }

  Future<List<SmartChargeTelemetryPoint>> getTelemetry(String sessionId) async {
    final snapshot = await _firestore
        .collection('ChargeLogs')
        .doc(sessionId)
        .collection('smartChargeTelemetry')
        .orderBy('startedAt')
        .get();
    final points = <SmartChargeTelemetryPoint>[];
    for (final document in snapshot.docs) {
      for (final value in (document.data()['points'] as List?) ?? const []) {
        try {
          points.add(
            SmartChargeTelemetryPoint.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          );
        } on Object {
          // Preserve the rest of a partially corrupted chunk.
        }
      }
    }
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const SmartChargeHistoryPage(items: []);
    Query<Map<String, dynamic>> query = _firestore
        .collection('ChargeLogs')
        .where('ownerUid', isEqualTo: uid)
        .where('source', isEqualTo: _source)
        .where('isDeleted', isEqualTo: false);
    if (strategy == ChargingStrategy.aiTarget) {
      query = query.where(
        'strategy',
        whereIn: const [
          'ai_target',
          'target_soc',
          'deadline',
          'smart_combined',
        ],
      );
    } else if (strategy != null) {
      query = query.where('strategy', isEqualTo: strategy.wireValue);
    }
    query = query.orderBy('startTime', descending: true);
    final cursorTime = cursor == null ? null : DateTime.tryParse(cursor);
    if (cursorTime != null) {
      query = query.startAfter([Timestamp.fromDate(cursorTime)]);
    }
    final snapshot = await query.limit(limit).get();
    final sessions = <SmartChargingSession>[];
    var skipped = 0;
    for (final document in snapshot.docs) {
      final raw = document.data()['smartChargingSession'];
      if (raw is! Map) {
        skipped++;
        continue;
      }
      try {
        sessions.add(
          SmartChargingSession.fromJson(Map<String, dynamic>.from(raw)),
        );
      } on Object {
        skipped++;
      }
    }
    final next = snapshot.docs.length < limit || snapshot.docs.isEmpty
        ? null
        : ((snapshot.docs.last.data()['startTime'] as Timestamp?)
              ?.toDate()
              .toUtc()
              .toIso8601String());
    return SmartChargeHistoryPage(
      items: sessions,
      nextCursor: next,
      skippedLegacyDocuments: skipped,
    );
  }

  Future<List<SmartChargingSession>> loadTerminalSessions({
    int limit = 20,
  }) async => (await getHistoryPage(limit: limit)).items;

  Future<SmartChargeEnergySummary> confirmActualEndSoc(
    SmartChargingSession session,
    double soc,
  ) async {
    if (soc <= session.startSoc || soc > 100) {
      throw ArgumentError.value(soc, 'soc', 'SOC cuối phải lớn hơn SOC đầu.');
    }
    final points = await getTelemetry(session.sessionId);
    final summary = SmartChargeEnergySummary.calculate(
      session: session,
      points: points,
      confirmedEndSoc: soc,
    );
    await _firestore.collection('ChargeLogs').doc(session.sessionId).update({
      'confirmedEndSoc': soc,
      'estimatedUsableCapacityWh': summary.estimatedUsableCapacityWh,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return summary;
  }

  Future<List<SmartChargeTelemetryPoint>> _loadPending(String sessionId) async {
    final memory = _pending[sessionId];
    if (memory != null && memory.isNotEmpty) return [...memory];
    final raw = (await _preferences()).getString('$_pendingPrefix$sessionId');
    if (raw == null) return const [];
    try {
      final points = (jsonDecode(raw) as List)
          .map(
            (value) => SmartChargeTelemetryPoint.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
      _pending[sessionId] = points;
      return [...points];
    } on Object {
      return const [];
    }
  }

  Future<void> _persistPending(
    String sessionId,
    List<SmartChargeTelemetryPoint> points,
  ) async {
    final preferences = await _preferences();
    final index = preferences.getStringList(_pendingIndexKey)?.toSet() ?? {};
    if (points.isEmpty) {
      await preferences.remove('$_pendingPrefix$sessionId');
      index.remove(sessionId);
    } else {
      await preferences.setString(
        '$_pendingPrefix$sessionId',
        jsonEncode(points.map((point) => point.toJson()).toList()),
      );
      index.add(sessionId);
    }
    await preferences.setStringList(_pendingIndexKey, index.toList());
  }

  Future<void> flushAllPending() async {
    final ids =
        (await _preferences()).getStringList(_pendingIndexKey) ?? const [];
    for (final id in ids) {
      try {
        await flushPendingTelemetry(id);
      } on Object {
        // Keep the durable queue for the next foreground/login sync.
      }
    }
    await _flushQueuedTerminalSessions();
  }

  Future<void> _queueTerminalSession(SmartChargingSession session) async {
    final preferences = await _preferences();
    await preferences.setString(
      'smart_charge_terminal_${session.sessionId}',
      jsonEncode(session.toJson()),
    );
    final ids =
        preferences
            .getStringList('smart_charge_pending_terminal_sessions_v1')
            ?.toSet() ??
        {};
    ids.add(session.sessionId);
    await preferences.setStringList(
      'smart_charge_pending_terminal_sessions_v1',
      ids.toList(),
    );
  }

  Future<void> _flushQueuedTerminalSessions() async {
    if (_auth.currentUser == null) return;
    final preferences = await _preferences();
    final ids =
        preferences.getStringList(
          'smart_charge_pending_terminal_sessions_v1',
        ) ??
        const [];
    for (final id in ids) {
      final raw = preferences.getString('smart_charge_terminal_$id');
      if (raw == null) continue;
      try {
        await saveTerminalSession(
          SmartChargingSession.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        );
      } on Object {
        // Retry on the next sync.
      }
    }
  }

  Future<void> _removeQueuedTerminalSession(String sessionId) async {
    final preferences = await _preferences();
    await preferences.remove('smart_charge_terminal_$sessionId');
    final ids =
        preferences
            .getStringList('smart_charge_pending_terminal_sessions_v1')
            ?.toSet() ??
        {};
    ids.remove(sessionId);
    await preferences.setStringList(
      'smart_charge_pending_terminal_sessions_v1',
      ids.toList(),
    );
  }
}
