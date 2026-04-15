import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ========================================================================
/// AI Insights Repository — Đọc AiVehicleInsights từ Firestore cache
/// Dữ liệu do Web Admin quản lý (train + refresh insight)
/// App chỉ READ, không bao giờ WRITE
/// ========================================================================

class AiVehicleInsight {
  final String vehicleId;
  final String ownerUid;
  final bool hasTrained;
  final String? trainedAt;
  final String? profileVersion;
  final int dataPoints;
  final double healthAdjustment;
  final double healthScore;
  final String healthStatus;
  final double? estimatedLifeMonths;
  final double confidence;
  final int? peakChargingHour;
  final String? peakChargingDay;
  final double? chargeFrequencyPerWeek;
  final double? avgSessionDuration;
  final List<String> recommendations;
  final double? equivalentCycles;
  final double? remainingCycles;
  final double? avgDoD;
  final double? avgChargeRate;
  final List<dynamic> patterns;
  final String? lastInferenceAt;
  final String lastInferenceStatus; // 'ok' | 'error'
  final String? lastInferenceError;
  final String? updatedAt;
  final String schemaVersion;

  AiVehicleInsight({
    required this.vehicleId,
    required this.ownerUid,
    required this.hasTrained,
    this.trainedAt,
    this.profileVersion,
    this.dataPoints = 0,
    this.healthAdjustment = 0,
    this.healthScore = 100,
    this.healthStatus = 'Chưa có dữ liệu',
    this.estimatedLifeMonths,
    this.confidence = 0,
    this.peakChargingHour,
    this.peakChargingDay,
    this.chargeFrequencyPerWeek,
    this.avgSessionDuration,
    this.recommendations = const [],
    this.equivalentCycles,
    this.remainingCycles,
    this.avgDoD,
    this.avgChargeRate,
    this.patterns = const [],
    this.lastInferenceAt,
    this.lastInferenceStatus = 'unknown',
    this.lastInferenceError,
    this.updatedAt,
    this.schemaVersion = 'insight-v1',
  });

  factory AiVehicleInsight.fromMap(Map<String, dynamic> map) {
    return AiVehicleInsight(
      vehicleId: map['vehicleId'] ?? '',
      ownerUid: map['ownerUid'] ?? '',
      hasTrained: map['hasTrained'] ?? false,
      trainedAt: map['trainedAt']?.toString(),
      profileVersion: map['profileVersion']?.toString(),
      dataPoints: (map['dataPoints'] as num?)?.toInt() ?? 0,
      healthAdjustment: (map['healthAdjustment'] as num?)?.toDouble() ?? 0,
      healthScore: (map['healthScore'] as num?)?.toDouble() ?? 100,
      healthStatus: map['healthStatus'] ?? 'Chưa có dữ liệu',
      estimatedLifeMonths: (map['estimatedLifeMonths'] as num?)?.toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      peakChargingHour: (map['peakChargingHour'] as num?)?.toInt(),
      peakChargingDay: map['peakChargingDay']?.toString(),
      chargeFrequencyPerWeek: (map['chargeFrequencyPerWeek'] as num?)?.toDouble(),
      avgSessionDuration: (map['avgSessionDuration'] as num?)?.toDouble(),
      recommendations: (map['recommendations'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      equivalentCycles: (map['equivalentCycles'] as num?)?.toDouble(),
      remainingCycles: (map['remainingCycles'] as num?)?.toDouble(),
      avgDoD: (map['avgDoD'] as num?)?.toDouble(),
      avgChargeRate: (map['avgChargeRate'] as num?)?.toDouble(),
      patterns: (map['patterns'] as List?) ?? [],
      lastInferenceAt: map['lastInferenceAt']?.toString(),
      lastInferenceStatus: map['lastInferenceStatus'] ?? 'unknown',
      lastInferenceError: map['lastInferenceError']?.toString(),
      updatedAt: map['updatedAt']?.toString(),
      schemaVersion: map['schemaVersion'] ?? 'insight-v1',
    );
  }

  /// Insight có stale không (updatedAt quá 24 giờ)
  bool get isStale {
    if (updatedAt == null) return true;
    try {
      final dt = DateTime.parse(updatedAt!);
      return DateTime.now().toUtc().difference(dt).inHours > 24;
    } catch (_) {
      return true;
    }
  }

  /// Trạng thái hiển thị: available / stale / missing
  String get displayStatus {
    if (!hasTrained) return 'missing';
    if (isStale) return 'stale';
    return 'available';
  }
}

/// Repository đọc AiVehicleInsights từ Firestore
class AiInsightsRepository {
  final FirebaseFirestore _firestore;

  AiInsightsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Lấy insight theo vehicleId (1 doc)
  Future<AiVehicleInsight?> getInsight(String vehicleId) async {
    if (vehicleId.isEmpty) return null;
    try {
      final doc = await _firestore
          .collection('AiVehicleInsights')
          .doc(vehicleId)
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return AiVehicleInsight.fromMap(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Stream realtime insight cho vehicleId
  Stream<AiVehicleInsight?> watchInsight(String vehicleId) {
    if (vehicleId.isEmpty) return Stream.value(null);
    return _firestore
        .collection('AiVehicleInsights')
        .doc(vehicleId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return AiVehicleInsight.fromMap(snap.data()!);
    });
  }
}

/// Providers
final aiInsightsRepositoryProvider = Provider<AiInsightsRepository>((ref) {
  return AiInsightsRepository();
});

/// Stream provider cho insight theo vehicleId
final aiInsightProvider =
    StreamProvider.family<AiVehicleInsight?, String>((ref, vehicleId) {
  return ref.watch(aiInsightsRepositoryProvider).watchInsight(vehicleId);
});
