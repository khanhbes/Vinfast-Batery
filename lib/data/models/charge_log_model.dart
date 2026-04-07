import 'package:cloud_firestore/cloud_firestore.dart';

class ChargeLogModel {
  final String? logId;
  final String vehicleId;
  final DateTime startTime;
  final DateTime endTime;
  final int startBatteryPercent;
  final int endBatteryPercent;
  final int odoAtCharge;
  final int? targetBatteryPercent;
  final DateTime? estimatedCompleteAt;

  ChargeLogModel({
    this.logId,
    required this.vehicleId,
    required this.startTime,
    required this.endTime,
    required this.startBatteryPercent,
    required this.endBatteryPercent,
    required this.odoAtCharge,
    this.targetBatteryPercent,
    this.estimatedCompleteAt,
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
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      startBatteryPercent: data['startBatteryPercent'] ?? 0,
      endBatteryPercent: data['endBatteryPercent'] ?? 0,
      odoAtCharge: data['odoAtCharge'] ?? 0,
      targetBatteryPercent: data['targetBatteryPercent'],
      estimatedCompleteAt: data['estimatedCompleteAt'] != null
          ? (data['estimatedCompleteAt'] as Timestamp).toDate()
          : null,
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
    );
  }

  /// Convert model to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'startBatteryPercent': startBatteryPercent,
      'endBatteryPercent': endBatteryPercent,
      'odoAtCharge': odoAtCharge,
      'targetBatteryPercent': targetBatteryPercent,
      'estimatedCompleteAt': estimatedCompleteAt != null
          ? Timestamp.fromDate(estimatedCompleteAt!)
          : null,
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
      'estimatedCompleteAt': estimatedCompleteAt?.toIso8601String(),
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
    );
  }
}
