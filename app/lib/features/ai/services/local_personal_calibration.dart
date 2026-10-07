import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/services/account_secure_storage.dart';

class CalibrationSample {
  const CalibrationSample({
    required this.sessionId,
    required this.recordedAt,
    required this.baseSeconds,
    required this.actualSeconds,
    required this.verified,
  });
  final String sessionId;
  final DateTime recordedAt;
  final double baseSeconds, actualSeconds;
  final bool verified;
  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'recordedAt': recordedAt.toIso8601String(),
    'baseSeconds': baseSeconds,
    'actualSeconds': actualSeconds,
    'verified': verified,
  };
  factory CalibrationSample.fromJson(Map<String, dynamic> j) =>
      CalibrationSample(
        sessionId: j['sessionId'] as String,
        recordedAt: DateTime.parse(j['recordedAt'] as String),
        baseSeconds: (j['baseSeconds'] as num).toDouble(),
        actualSeconds: (j['actualSeconds'] as num).toDouble(),
        verified: j['verified'] == true,
      );
  bool get eligible =>
      verified &&
      sessionId.isNotEmpty &&
      baseSeconds.isFinite &&
      actualSeconds.isFinite &&
      baseSeconds >= 60 &&
      actualSeconds >= 60 &&
      baseSeconds <= 36000 &&
      actualSeconds <= 36000;
}

class CalibrationCandidate {
  const CalibrationCandidate({
    required this.scale,
    required this.biasSeconds,
    required this.promoted,
    required this.reason,
    required this.testCount,
  });
  final double scale, biasSeconds;
  final bool promoted;
  final String reason;
  final int testCount;
  double predict(double baseSeconds) =>
      (scale * baseSeconds + biasSeconds).clamp(60, 36000);
  Map<String, dynamic> toJson() => {
    'scale': scale,
    'biasSeconds': biasSeconds,
    'promoted': promoted,
    'reason': reason,
    'testCount': testCount,
    'schemaVersion': 1,
  };
}

/// A small ridge adapter, not neural-network or LLM weight fine-tuning.
class LocalPersonalCalibration {
  static CalibrationCandidate train(List<CalibrationSample> input) {
    CalibrationCandidate reject(String reason, [int count = 0]) =>
        CalibrationCandidate(
          scale: 1,
          biasSeconds: 0,
          promoted: false,
          reason: reason,
          testCount: count,
        );
    // Reject duplicated session IDs entirely, rather than selecting a label.
    final counts = <String, int>{};
    for (final s in input) {
      counts[s.sessionId] = (counts[s.sessionId] ?? 0) + 1;
    }
    final data =
        input.where((s) => s.eligible && counts[s.sessionId] == 1).toList()
          ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    if (data.length < 60) {
      return reject('insufficientSeparateTrainValidationTest');
    }
    if (data.last.recordedAt.difference(data.first.recordedAt) <
        const Duration(days: 14)) {
      return reject('insufficientHistory');
    }
    final training = data.sublist(0, data.length - 30);
    final validation = data.sublist(data.length - 30, data.length - 20);
    final test = data.sublist(data.length - 20);
    // Timestamp ties cannot cross partitions and leak an observation window.
    if (!training.last.recordedAt.isBefore(validation.first.recordedAt) ||
        !validation.last.recordedAt.isBefore(test.first.recordedAt)) {
      return reject('overlappingTimePartitions');
    }
    final n = training.length;
    final meanX = training.fold(0.0, (p, s) => p + s.baseSeconds / 3600) / n;
    final meanY = training.fold(0.0, (p, s) => p + s.actualSeconds / 3600) / n;
    var covariance = 0.0, variance = 0.0;
    for (final s in training) {
      final x = s.baseSeconds / 3600 - meanX;
      covariance += x * (s.actualSeconds / 3600 - meanY);
      variance += x * x;
    }
    if (variance < 1e-6) return reject('insufficientFeatureVariation');
    // Ridge prior slope=1, lambda=1. No test-derived parameter selection.
    final scale = ((covariance + 1) / (variance + 1)).clamp(0.5, 1.5);
    final bias = ((meanY - scale * meanX) * 3600).clamp(-1800.0, 1800.0);
    double corrected(CalibrationSample s) =>
        (s.baseSeconds * scale + bias).clamp(60, 36000);
    List<double> metrics(List<CalibrationSample> rows, bool candidate) {
      final errors = rows
          .map(
            (s) => (candidate ? corrected(s) : s.baseSeconds) - s.actualSeconds,
          )
          .toList();
      return [
        errors.fold(0.0, (p, e) => p + e.abs()) / rows.length,
        math.sqrt(errors.fold(0.0, (p, e) => p + e * e) / rows.length),
        (errors.fold(0.0, (p, e) => p + e) / rows.length).abs(),
      ];
    }

    bool improves(List<CalibrationSample> rows) {
      final base = metrics(rows, false), next = metrics(rows, true);
      return base[0] > 0 &&
          next[0] <= base[0] * 0.98 &&
          next[1] <= base[1] * 1.03 &&
          next[2] <= base[2];
    }

    final approved = improves(validation) && improves(test);
    return CalibrationCandidate(
      scale: scale,
      biasSeconds: bias,
      promoted: approved,
      reason: approved ? 'qualityGatePassed' : 'qualityGateRejected',
      testCount: test.length,
    );
  }
}

/// Secure UID/vehicle storage. Nothing uploads to Azure or Firestore.
class LocalCalibrationStore {
  LocalCalibrationStore(this.uidResolver, {FlutterSecureStorage? storage})
    : storage = storage ?? accountSecureStorage;
  final String? Function() uidResolver;
  final FlutterSecureStorage storage;
  String _key(String uid, String vehicle) =>
      'personal_calibration_v1.${Uri.encodeComponent(uid)}.${Uri.encodeComponent(vehicle)}';
  Future<Map<String, dynamic>> read(String vehicle) async {
    final uid = uidResolver();
    if (uid == null) return {};
    final raw = await storage.read(key: _key(uid, vehicle));
    if (uidResolver() != uid) throw StateError('accountChanged');
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> setConsent(String vehicle, bool enabled) async {
    final uid = uidResolver();
    if (uid == null) throw StateError('authenticationRequired');
    final state = await read(vehicle);
    if (uidResolver() != uid) throw StateError('accountChanged');
    await storage.write(
      key: _key(uid, vehicle),
      value: jsonEncode({...state, 'consent': enabled}),
    );
  }

  Future<void> reset(String vehicle) async {
    final uid = uidResolver();
    if (uid != null) await storage.delete(key: _key(uid, vehicle));
  }
}
