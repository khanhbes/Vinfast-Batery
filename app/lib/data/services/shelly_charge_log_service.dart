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

  /// Creates the canonical ChargeLog as soon as the device timer is verified.
  /// The terminal writer later merges into this exact document, so an active
  /// session never becomes a second history row.
  Future<void> saveActiveSession(SmartChargingSession session) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('ChargeLogs').doc(session.sessionId).set({
      ..._basePayload(session, uid),
      'status': 'active',
      'sessionState': session.state.wireValue,
      'endTime': null,
      'actualStopAt': null,
      'gridEnergyWh': session.energyUsedWh,
      'energyWh': session.energyUsedWh,
      'estimatedEndSoc': session.estimatedSoc,
      'smartChargingSession': session.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

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
      'status': 'terminal',
      'sessionState': session.state.wireValue,
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

  /// Reversible history action. The canonical ChargeLog remains available for
  /// recovery/privacy erase; only normal history queries hide it.
  Future<void> hideSession(String sessionId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Cần đăng nhập để ẩn phiên sạc.');
    await _firestore.collection('ChargeLogs').doc(sessionId).update({
      'hiddenByUserAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Irreversible privacy erase. A typed session id is required and the
  /// parent owner is checked before deleting the summary and telemetry.
  Future<void> privacyEraseSession(String sessionId, String confirmation) async {
    if (confirmation.trim() != sessionId) {
      throw ArgumentError('Mã xác nhận phiên không khớp.');
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Cần đăng nhập để xóa dữ liệu.');
    final parent = _firestore.collection('ChargeLogs').doc(sessionId);
    final snapshot = await parent.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['ownerUid'] != uid) {
      throw StateError('Không tìm thấy phiên sạc thuộc tài khoản này.');
    }
    final rawSession = data['smartChargingSession'];
    if (rawSession is Map &&
        !SmartChargingSession.fromJson(Map<String, dynamic>.from(rawSession))
            .state
            .isTerminal) {
      throw StateError('Hãy tắt và xác minh OFF trước khi xóa.');
    }
    final telemetry = await parent.collection('smartChargeTelemetry').get();
    final batch = _firestore.batch();
    for (final document in telemetry.docs) {
      batch.delete(document.reference);
    }
    batch.delete(parent);
    await batch.commit();
    _raw.remove(sessionId);
    _pending.remove(sessionId);
    await _removeQueuedTerminalSession(sessionId);
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
        'profileVersion': session.profileVersion,
        'adapterVersion': session.adapterVersion,
        'personalizationStage': session.personalizationStage,
        'baseAiMinutes': session.baseAiMinutes,
        'physicsMinutes': session.physicsMinutes,
        'personalMinutes': session.personalMinutes,
        'finalEtaMinutes': session.finalMinutes,
        'fusionWeights': session.fusionWeights,
        'effectiveCapacityWh': session.effectiveCapacityWh,
        'nominalCapacityWh': session.nominalCapacityWh,
        'stateOfHealth': session.stateOfHealth,
        'userStopReason': session.userStopReason.wireValue,
        'trainingEligibility': session.trainingEligible,
        'trainingExclusionReason': session.trainingReason,
        'energyQuality': session.energyQuality,
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
    await _updateLiveSummary(session, latest, point);
    if (pending.length >= 10) await flushPendingTelemetry(session.sessionId);
  }

  Future<void> _updateLiveSummary(
    SmartChargingSession session,
    SmartChargerStatus status,
    SmartChargeTelemetryPoint point,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('ChargeLogs').doc(session.sessionId).set({
      ..._basePayload(session, uid),
      'status': 'active',
      'sessionState': session.state.wireValue,
      'gridEnergyWh': session.energyUsedWh,
      'energyWh': session.energyUsedWh,
      'estimatedEndSoc': point.estimatedSoc,
      'latestPowerW': status.powerW,
      'latestVoltageV': status.voltageV,
      'latestCurrentA': status.currentA,
      'latestTemperatureC': status.shellyTemperatureC,
      'timerRemainingSeconds': status.timerRemaining?.inSeconds,
      'smartChargingSession': session.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    String? vehicleId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const SmartChargeHistoryPage(items: []);
    final cursorTime = cursor == null ? null : DateTime.tryParse(cursor);
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('ChargeLogs')
          .where('ownerUid', isEqualTo: uid)
          .where('source', isEqualTo: _source)
          .where('isDeleted', isEqualTo: false);
      if (vehicleId != null && vehicleId.isNotEmpty) {
        query = query.where('vehicleId', isEqualTo: vehicleId);
      }
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
      if (cursorTime != null) {
        query = query.startAfter([Timestamp.fromDate(cursorTime)]);
      }
      final snapshot = await query.limit(limit).get();
      return _historyPageFromDocuments(
        snapshot.docs,
        limit: limit,
        hasMore: snapshot.docs.length == limit,
      );
    } on FirebaseException catch (error) {
      // A newly-added composite index may take several minutes to become
      // available (or may not have been deployed yet). History must remain
      // usable, so fall back to the security-rule-compatible equality query
      // and perform source/strategy/order/pagination locally.
      if (error.code != 'failed-precondition') rethrow;
      return _getHistoryPageWithoutCompositeIndex(
        uid: uid,
        limit: limit,
        cursorTime: cursorTime,
        strategy: strategy,
        vehicleId: vehicleId,
      );
    }
  }

  Future<SmartChargeHistoryPage> _getHistoryPageWithoutCompositeIndex({
    required String uid,
    required int limit,
    required DateTime? cursorTime,
    required ChargingStrategy? strategy,
    required String? vehicleId,
  }) async {
    final snapshot = await _firestore
        .collection('ChargeLogs')
        .where('ownerUid', isEqualTo: uid)
        .where('isDeleted', isEqualTo: false)
        .limit(200)
        .get();
    final documents =
        snapshot.docs.where((document) {
      final data = document.data();
          if (data['source'] != _source ||
              data['hiddenByUserAt'] != null ||
              !_matchesStrategy(data, strategy)) {
            return false;
          }
          if (vehicleId != null && vehicleId.isNotEmpty && data['vehicleId'] != vehicleId) {
            return false;
          }
          final startTime = (data['startTime'] as Timestamp?)?.toDate();
          return cursorTime == null ||
              (startTime != null && startTime.isBefore(cursorTime));
        }).toList()..sort((left, right) {
          final leftTime = (left.data()['startTime'] as Timestamp?)?.toDate();
          final rightTime = (right.data()['startTime'] as Timestamp?)?.toDate();
          if (leftTime == null) return 1;
          if (rightTime == null) return -1;
          return rightTime.compareTo(leftTime);
        });
    final selected = documents.take(limit).toList();
    return _historyPageFromDocuments(
      selected,
      limit: limit,
      hasMore: documents.length > selected.length,
    );
  }

  bool _matchesStrategy(Map<String, dynamic> data, ChargingStrategy? strategy) {
    if (strategy == null) return true;
    final value = data['strategy'];
    if (strategy == ChargingStrategy.aiTarget) {
      return const {
        'ai_target',
        'target_soc',
        'deadline',
        'smart_combined',
      }.contains(value);
    }
    return value == strategy.wireValue;
  }

  SmartChargeHistoryPage _historyPageFromDocuments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents, {
    required int limit,
    required bool hasMore,
  }) {
    final sessions = <SmartChargingSession>[];
    var skipped = 0;
    for (final document in documents) {
      if (document.data()['hiddenByUserAt'] != null) {
        skipped++;
        continue;
      }
      try {
        final data = document.data();
        final raw = data['smartChargingSession'];
        final session = raw is Map
            ? SmartChargingSession.fromJson(Map<String, dynamic>.from(raw))
            : _legacySessionFromChargeLog(data, document.id);
        sessions.add(session);
      } on Object {
        skipped++;
      }
    }
    final next = !hasMore || documents.isEmpty
        ? null
        : ((documents.last.data()['startTime'] as Timestamp?)
              ?.toDate()
              .toUtc()
              .toIso8601String());
    return SmartChargeHistoryPage(
      items: sessions,
      nextCursor: next,
      skippedLegacyDocuments: skipped,
    );
  }

  /// Restored/legacy ChargeLogs may contain only the durable summary rather
  /// than the embedded snake_case runtime session. Keep those records visible
  /// in Direct mode instead of silently dropping the user's history.
  SmartChargingSession _legacySessionFromChargeLog(
    Map<String, dynamic> data,
    String documentId,
  ) {
    DateTime date(Object? value, DateTime fallback) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      final parsed = DateTime.tryParse(value?.toString() ?? '');
      return parsed ?? fallback;
    }

    final created = date(data['startTime'] ?? data['createdAt'], DateTime.now());
    final durationSeconds =
        (data['predictedDurationSeconds'] as num?)?.round() ??
        (((data['finalEtaMinutes'] ?? data['predictedMinutes']) as num?)
                ?.round() ??
            1) *
            60;
    final planned = date(
      data['plannedStopAt'],
      created.add(Duration(seconds: durationSeconds)),
    );
    final stopped = data['actualStopAt'] == null && data['endTime'] == null
        ? null
        : date(data['actualStopAt'] ?? data['endTime'], planned);
    var state = (data['sessionState'] ?? data['status'])?.toString();
    if (state == 'terminal') state = 'completed';
    if (!const {
      'arming',
      'starting',
      'active',
      'stopping',
      'completed',
      'cancelled',
      'interrupted',
      'failed',
    }.contains(state)) {
      state = stopped == null ? 'active' : 'completed';
    }
    final strategy = (data['strategy'] ?? 'ai_target').toString();
    final strategyValue = const {
      'target_soc',
      'deadline',
      'smart_combined',
      'ai_target',
      'manual_timed',
    }.contains(strategy)
        ? strategy
        : 'ai_target';
    final startSoc = (data['startBatteryPercent'] ?? data['startSoc']) as num?;
    final targetSoc =
        (data['targetBatteryPercent'] ?? data['targetSoc'] ?? startSoc) as num?;
    return SmartChargingSession.fromJson({
      'session_id': data['sessionId']?.toString() ?? documentId,
      'vehicle_id': data['vehicleId']?.toString() ?? '',
      'state': state,
      'strategy': strategyValue,
      'start_soc': startSoc?.toDouble() ?? 0,
      'target_soc': targetSoc?.toDouble() ?? 0,
      'predicted_minutes': (durationSeconds / 60).ceil(),
      'predicted_duration_seconds': durationSeconds,
      'prediction_source': data['predictionSource']?.toString() ?? 'unknown',
      'prediction_confidence': data['predictionConfidence'],
      'created_at': created.toIso8601String(),
      'updated_at': date(data['updatedAt'] ?? stopped, created).toIso8601String(),
      'started_at': created.toIso8601String(),
      'stopped_at': stopped?.toIso8601String(),
      'ai_stop_at': planned.toIso8601String(),
      'hard_deadline_at': created.add(const Duration(hours: 10)).toIso8601String(),
      'effective_stop_at': planned.toIso8601String(),
      'absolute_safety_stop_at': created.add(const Duration(hours: 10)).toIso8601String(),
      'shadow_mode': false,
      'version': (data['version'] as num?)?.round() ?? 1,
      'device_id': data['shellyDeviceId'] ?? data['deviceId'],
      'transport': data['controlTransport'] ?? data['transport'],
      'relay_verified': data['relayVerified'] == true,
      'energy_used_wh': (data['gridEnergyWh'] ?? data['energyWh'] ?? 0),
      'energy_quality': data['energyQuality']?.toString() ?? 'partial',
      'estimated_soc': data['estimatedEndSoc'],
      'model_key': data['modelKey']?.toString() ?? 'charging_time',
      'model_version': data['modelVersion']?.toString() ?? 'unknown',
      'runtime_health': data['runtimeHealth']?.toString() ?? 'unknown',
      'timer_verified': data['timerVerified'] == true,
      'user_stop_reason': data['userStopReason']?.toString() ?? 'none',
      'telemetry_coverage': data['telemetryCoverageRatio'] ?? 0,
      'owner_uid': data['ownerUid'],
      'personalization_stage': data['personalizationStage']?.toString() ?? 'base',
      'base_ai_minutes': data['baseAiMinutes'],
      'physics_minutes': data['physicsMinutes'],
      'personal_minutes': data['personalMinutes'],
      'final_minutes': data['finalEtaMinutes'],
      'fusion_weights': data['fusionWeights'] ?? const {},
      'effective_capacity_wh': data['effectiveCapacityWh'],
      'nominal_capacity_wh': data['nominalCapacityWh'],
      'state_of_health': data['stateOfHealth'],
      'average_power_w': data['averagePowerW'],
      'peak_power_w': data['peakPowerW'],
      'average_voltage_v': data['averageVoltageV'],
      'average_current_a': data['averageCurrentA'],
      'personal_ai_training_state': data['personalAiTrainingState'] ?? 'pending',
      'personal_ai_training_reason': data['personalAiTrainingReason'],
    });
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
