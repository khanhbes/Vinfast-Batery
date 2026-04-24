import 'package:cloud_firestore/cloud_firestore.dart';

/// Charge sample data for model fine-tuning
/// Collected implicitly during app charging sessions
class ChargeSampleModel {
  final String? sampleId;
  final String? sessionId;
  final String? ownerUid;
  final String? vehicleId;
  
  // Prediction inputs
  final int? startBatteryPercent;
  final int? targetBatteryPercent;
  final double? ambientTempC;
  
  // Prediction metadata
  final DateTime? predictedStopAt;
  final double? predictedDurationSec;
  final String? modelVersion;
  final String? modelSource;
  
  // Actual results (filled when session ends)
  final int? actualEndBatteryPercent;
  final DateTime? actualEndTime;
  final double? actualDurationSec;
  
  // Location (if available)
  final double? latitude;
  final double? longitude;
  
  // Flags
  final bool? eligibleForTraining;
  final DateTime? createdAt;

  ChargeSampleModel({
    this.sampleId,
    this.sessionId,
    this.ownerUid,
    this.vehicleId,
    this.startBatteryPercent,
    this.targetBatteryPercent,
    this.ambientTempC,
    this.predictedStopAt,
    this.predictedDurationSec,
    this.modelVersion,
    this.modelSource,
    this.actualEndBatteryPercent,
    this.actualEndTime,
    this.actualDurationSec,
    this.latitude,
    this.longitude,
    this.eligibleForTraining,
    this.createdAt,
  });

  factory ChargeSampleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      return ChargeSampleModel(sampleId: doc.id);
    }
    return ChargeSampleModel(
      sampleId: doc.id,
      sessionId: data['sessionId'],
      ownerUid: data['ownerUid'],
      vehicleId: data['vehicleId'],
      startBatteryPercent: data['startBatteryPercent'],
      targetBatteryPercent: data['targetBatteryPercent'],
      ambientTempC: data['ambientTempC']?.toDouble(),
      predictedStopAt: data['predictedStopAt'] != null
          ? (data['predictedStopAt'] as Timestamp).toDate()
          : null,
      predictedDurationSec: data['predictedDurationSec']?.toDouble(),
      modelVersion: data['modelVersion'],
      modelSource: data['modelSource'],
      actualEndBatteryPercent: data['actualEndBatteryPercent'],
      actualEndTime: data['actualEndTime'] != null
          ? (data['actualEndTime'] as Timestamp).toDate()
          : null,
      actualDurationSec: data['actualDurationSec']?.toDouble(),
      latitude: data['latitude']?.toDouble(),
      longitude: data['longitude']?.toDouble(),
      eligibleForTraining: data['eligibleForTraining'],
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (sessionId != null) 'sessionId': sessionId,
      if (ownerUid != null) 'ownerUid': ownerUid,
      if (vehicleId != null) 'vehicleId': vehicleId,
      if (startBatteryPercent != null) 'startBatteryPercent': startBatteryPercent,
      if (targetBatteryPercent != null) 'targetBatteryPercent': targetBatteryPercent,
      if (ambientTempC != null) 'ambientTempC': ambientTempC,
      if (predictedStopAt != null) 'predictedStopAt': Timestamp.fromDate(predictedStopAt!),
      if (predictedDurationSec != null) 'predictedDurationSec': predictedDurationSec,
      if (modelVersion != null) 'modelVersion': modelVersion,
      if (modelSource != null) 'modelSource': modelSource,
      if (actualEndBatteryPercent != null) 'actualEndBatteryPercent': actualEndBatteryPercent,
      if (actualEndTime != null) 'actualEndTime': Timestamp.fromDate(actualEndTime!),
      if (actualDurationSec != null) 'actualDurationSec': actualDurationSec,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (eligibleForTraining != null) 'eligibleForTraining': eligibleForTraining,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  /// Create from a charging session start
  factory ChargeSampleModel.fromSessionStart({
    required String sessionId,
    required String ownerUid,
    required String vehicleId,
    required int startBatteryPercent,
    required int targetBatteryPercent,
    required DateTime predictedStopAt,
    required double predictedDurationSec,
    required String modelVersion,
    required String modelSource,
    double? ambientTempC,
    double? latitude,
    double? longitude,
  }) {
    return ChargeSampleModel(
      sessionId: sessionId,
      ownerUid: ownerUid,
      vehicleId: vehicleId,
      startBatteryPercent: startBatteryPercent,
      targetBatteryPercent: targetBatteryPercent,
      ambientTempC: ambientTempC ?? 25.0, // Default 25°C
      predictedStopAt: predictedStopAt,
      predictedDurationSec: predictedDurationSec,
      modelVersion: modelVersion,
      modelSource: modelSource,
      latitude: latitude,
      longitude: longitude,
      eligibleForTraining: false, // Will be determined when session ends
      createdAt: DateTime.now(),
    );
  }

  /// Update with actual results when session ends
  ChargeSampleModel copyWithActualResults({
    required int actualEndBatteryPercent,
    required DateTime actualEndTime,
  }) {
    final duration = actualEndTime.difference(createdAt ?? actualEndTime).inSeconds.toDouble();
    
    // Determine eligibility for training
    final eligible = actualEndBatteryPercent > (startBatteryPercent ?? 0) &&
                    duration > 60 && // > 1 minute
                    (targetBatteryPercent != null && 
                     actualEndBatteryPercent >= targetBatteryPercent! - 5);

    return ChargeSampleModel(
      sampleId: sampleId,
      sessionId: sessionId,
      ownerUid: ownerUid,
      vehicleId: vehicleId,
      startBatteryPercent: startBatteryPercent,
      targetBatteryPercent: targetBatteryPercent,
      ambientTempC: ambientTempC,
      predictedStopAt: predictedStopAt,
      predictedDurationSec: predictedDurationSec,
      modelVersion: modelVersion,
      modelSource: modelSource,
      actualEndBatteryPercent: actualEndBatteryPercent,
      actualEndTime: actualEndTime,
      actualDurationSec: duration,
      latitude: latitude,
      longitude: longitude,
      eligibleForTraining: eligible,
      createdAt: createdAt,
    );
  }
}
