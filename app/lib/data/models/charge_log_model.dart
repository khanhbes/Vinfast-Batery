import 'package:cloud_firestore/cloud_firestore.dart';

/// AI Prediction metadata for charging sessions
class AiPredictionData {
  final DateTime? requestedAt;
  final int? startBatteryPercent;
  final int? targetBatteryPercent;
  final double? predictedDurationSec;
  final DateTime? predictedStopAt;
  final String? modelSource;
  final String? modelVersion;
  final bool? isBeta;
  final int? actualStopBatteryPercent;
  final double? actualDurationSec;
  final double? predictionErrorSec;
  final bool? eligibleForTraining;

  AiPredictionData({
    this.requestedAt,
    this.startBatteryPercent,
    this.targetBatteryPercent,
    this.predictedDurationSec,
    this.predictedStopAt,
    this.modelSource,
    this.modelVersion,
    this.isBeta,
    this.actualStopBatteryPercent,
    this.actualDurationSec,
    this.predictionErrorSec,
    this.eligibleForTraining,
  });

  factory AiPredictionData.fromMap(Map<String, dynamic>? data) {
    if (data == null) return AiPredictionData();
    return AiPredictionData(
      requestedAt: data['requestedAt'] != null
          ? (data['requestedAt'] as Timestamp).toDate()
          : null,
      startBatteryPercent: data['startBatteryPercent'],
      targetBatteryPercent: data['targetBatteryPercent'],
      predictedDurationSec: data['predictedDurationSec']?.toDouble(),
      predictedStopAt: data['predictedStopAt'] != null
          ? (data['predictedStopAt'] as Timestamp).toDate()
          : null,
      modelSource: data['modelSource'],
      modelVersion: data['modelVersion'],
      isBeta: data['isBeta'],
      actualStopBatteryPercent: data['actualStopBatteryPercent'],
      actualDurationSec: data['actualDurationSec']?.toDouble(),
      predictionErrorSec: data['predictionErrorSec']?.toDouble(),
      eligibleForTraining: data['eligibleForTraining'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (requestedAt != null) 'requestedAt': Timestamp.fromDate(requestedAt!),
      if (startBatteryPercent != null) 'startBatteryPercent': startBatteryPercent,
      if (targetBatteryPercent != null) 'targetBatteryPercent': targetBatteryPercent,
      if (predictedDurationSec != null) 'predictedDurationSec': predictedDurationSec,
      if (predictedStopAt != null) 'predictedStopAt': Timestamp.fromDate(predictedStopAt!),
      if (modelSource != null) 'modelSource': modelSource,
      if (modelVersion != null) 'modelVersion': modelVersion,
      if (isBeta != null) 'isBeta': isBeta,
      if (actualStopBatteryPercent != null) 'actualStopBatteryPercent': actualStopBatteryPercent,
      if (actualDurationSec != null) 'actualDurationSec': actualDurationSec,
      if (predictionErrorSec != null) 'predictionErrorSec': predictionErrorSec,
      if (eligibleForTraining != null) 'eligibleForTraining': eligibleForTraining,
    };
  }

  /// Convert to JSON map (for SharedPreferences storage)
  Map<String, dynamic> toJson() => toMap();

  /// Create from JSON map (from SharedPreferences)
  factory AiPredictionData.fromJson(Map<String, dynamic> json) => AiPredictionData.fromMap(json);

  /// Format duration as hours/minutes string
  String get formattedDuration {
    final seconds = predictedDurationSec ?? 0;
    final hours = (seconds / 3600).floor();
    final mins = ((seconds % 3600) / 60).floor();
    if (hours > 0) {
      return '${hours} giờ ${mins} phút';
    }
    return '${mins} phút';
  }

  /// Calculate prediction error after session ends
  AiPredictionData copyWithActual(int actualBattery, DateTime actualEndTime) {
    final actualDuration = actualEndTime.difference(requestedAt ?? actualEndTime).inSeconds.toDouble();
    final predictedDuration = predictedDurationSec ?? 0;
    final error = actualDuration - predictedDuration;
    
    // Determine if eligible for training
    final eligible = actualBattery > (startBatteryPercent ?? 0) && // Pin phải tăng
                    actualDuration > 60 && // Thời gian > 1 phút
                    (targetBatteryPercent != null && actualBattery >= targetBatteryPercent! - 5); // Gần đạt target

    return AiPredictionData(
      requestedAt: requestedAt,
      startBatteryPercent: startBatteryPercent,
      targetBatteryPercent: targetBatteryPercent,
      predictedDurationSec: predictedDurationSec,
      predictedStopAt: predictedStopAt,
      modelSource: modelSource,
      modelVersion: modelVersion,
      isBeta: isBeta,
      actualStopBatteryPercent: actualBattery,
      actualDurationSec: actualDuration,
      predictionErrorSec: error,
      eligibleForTraining: eligible,
    );
  }
}

class ChargeLogModel {
  final String? logId;
  final String vehicleId;
  final String? ownerUid;
  final DateTime startTime;
  final DateTime endTime;
  final int startBatteryPercent;
  final int endBatteryPercent;
  final int odoAtCharge;
  final int? targetBatteryPercent;
  final DateTime? estimatedCompleteAt;
  final AiPredictionData? aiPrediction;

  ChargeLogModel({
    this.logId,
    required this.vehicleId,
    this.ownerUid,
    required this.startTime,
    required this.endTime,
    required this.startBatteryPercent,
    required this.endBatteryPercent,
    required this.odoAtCharge,
    this.targetBatteryPercent,
    this.estimatedCompleteAt,
    this.aiPrediction,
  });

  /// Lượng pin sạc được (%)
  int get chargeGain => endBatteryPercent - startBatteryPercent;

  /// Thời gian sạc
  Duration get chargeDuration => endTime.difference(startTime);

  /// Thời gian sạc dạng text "2h 30m"
  String get durationText {
    final d = chargeDuration;
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m';
  }

  /// Convert Firestore document to model
  factory ChargeLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChargeLogModel(
      logId: doc.id,
      vehicleId: data['vehicleId'] ?? '',
      ownerUid: data['ownerUid'],
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      startBatteryPercent: data['startBatteryPercent'] ?? 0,
      endBatteryPercent: data['endBatteryPercent'] ?? 0,
      odoAtCharge: data['odoAtCharge'] ?? 0,
      targetBatteryPercent: data['targetBatteryPercent'],
      estimatedCompleteAt: data['estimatedCompleteAt'] != null
          ? (data['estimatedCompleteAt'] as Timestamp).toDate()
          : null,
      aiPrediction: AiPredictionData.fromMap(data['aiPrediction']),
    );
  }

  /// Convert from in-memory map (demo mode)
  factory ChargeLogModel.fromMap(Map<String, dynamic> data) {
    return ChargeLogModel(
      logId: data['logId'],
      vehicleId: data['vehicleId'] ?? '',
      startTime: data['startTime'] is DateTime
          ? data['startTime']
          : DateTime.parse(data['startTime']),
      endTime: data['endTime'] is DateTime
          ? data['endTime']
          : DateTime.parse(data['endTime']),
      startBatteryPercent: data['startBatteryPercent'] ?? 0,
      endBatteryPercent: data['endBatteryPercent'] ?? 0,
      odoAtCharge: data['odoAtCharge'] ?? 0,
      targetBatteryPercent: data['targetBatteryPercent'],
      estimatedCompleteAt: data['estimatedCompleteAt'] is DateTime
          ? data['estimatedCompleteAt']
          : data['estimatedCompleteAt'] != null
              ? DateTime.parse(data['estimatedCompleteAt'])
              : null,
      aiPrediction: AiPredictionData.fromMap(data['aiPrediction']),
    );
  }

  /// Convert model to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      if (ownerUid != null) 'ownerUid': ownerUid,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'startBatteryPercent': startBatteryPercent,
      'endBatteryPercent': endBatteryPercent,
      'odoAtCharge': odoAtCharge,
      'targetBatteryPercent': targetBatteryPercent,
      'estimatedCompleteAt': estimatedCompleteAt != null
          ? Timestamp.fromDate(estimatedCompleteAt!)
          : null,
      'aiPrediction': aiPrediction?.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Convert to plain map
  Map<String, dynamic> toMap() {
    return {
      'logId': logId,
      'vehicleId': vehicleId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'startBatteryPercent': startBatteryPercent,
      'endBatteryPercent': endBatteryPercent,
      'odoAtCharge': odoAtCharge,
      'targetBatteryPercent': targetBatteryPercent,
      if (estimatedCompleteAt != null)
        'estimatedCompleteAt': estimatedCompleteAt!.toIso8601String(),
      if (aiPrediction != null) 'aiPrediction': aiPrediction?.toMap(),
    };
  }

  ChargeLogModel copyWith({
    String? logId,
    String? vehicleId,
    DateTime? startTime,
    DateTime? endTime,
    int? startBatteryPercent,
    int? endBatteryPercent,
    int? odoAtCharge,
    int? targetBatteryPercent,
    DateTime? estimatedCompleteAt,
    AiPredictionData? aiPrediction,
  }) {
    return ChargeLogModel(
      logId: logId ?? this.logId,
      vehicleId: vehicleId ?? this.vehicleId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startBatteryPercent: startBatteryPercent ?? this.startBatteryPercent,
      endBatteryPercent: endBatteryPercent ?? this.endBatteryPercent,
      odoAtCharge: odoAtCharge ?? this.odoAtCharge,
      targetBatteryPercent: targetBatteryPercent ?? this.targetBatteryPercent,
      estimatedCompleteAt: estimatedCompleteAt ?? this.estimatedCompleteAt,
      aiPrediction: aiPrediction ?? this.aiPrediction,
    );
  }
}
