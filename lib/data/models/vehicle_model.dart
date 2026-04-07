import 'package:cloud_firestore/cloud_firestore.dart';

/// Model xe VinFast với thông tin mở rộng
/// Bao gồm SoH, currentBattery, defaultEfficiency cho tính toán chai pin
class VehicleModel {
  final String vehicleId;
  final String vehicleName;
  final int currentOdo;
  final int currentBattery; // % pin hiện tại (realtime)
  final double stateOfHealth; // SoH 0-100%
  final double defaultEfficiency; // km / 1% khi mới (VD: 1.2)
  final int totalCharges;
  final int totalTrips;
  final int lastBatteryPercent;
  final String? avatarColor;
  // ── VinFast Model Link fields ──
  final String? vinfastModelId;
  final String? vinfastModelName;
  final int? specVersion;
  final DateTime? specLinkedAt;

  VehicleModel({
    required this.vehicleId,
    this.vehicleName = '',
    required this.currentOdo,
    this.currentBattery = 100,
    this.stateOfHealth = 100.0,
    this.defaultEfficiency = 1.2, // VinFast Feliz Neo: ~1.2 km/1%
    this.totalCharges = 0,
    this.totalTrips = 0,
    this.lastBatteryPercent = 100,
    this.avatarColor,
    this.vinfastModelId,
    this.vinfastModelName,
    this.specVersion,
    this.specLinkedAt,
  });

  /// Convert Firestore document to model
  /// Whether this vehicle has been linked to a VinFast model spec
  bool get hasModelLink => vinfastModelId != null && vinfastModelId!.isNotEmpty;

  factory VehicleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VehicleModel(
      vehicleId: doc.id,
      vehicleName: data['vehicleName'] ?? '',
      currentOdo: data['currentOdo'] ?? 0,
      currentBattery: data['currentBattery'] ?? data['lastBatteryPercent'] ?? 100,
      stateOfHealth: (data['stateOfHealth'] ?? 100.0).toDouble(),
      defaultEfficiency: (data['defaultEfficiency'] ?? 1.2).toDouble(),
      totalCharges: data['totalCharges'] ?? 0,
      totalTrips: data['totalTrips'] ?? 0,
      lastBatteryPercent: data['lastBatteryPercent'] ?? 100,
      avatarColor: data['avatarColor'],
      vinfastModelId: data['vinfastModelId'],
      vinfastModelName: data['vinfastModelName'],
      specVersion: data['specVersion'],
      specLinkedAt: data['specLinkedAt'] != null
          ? (data['specLinkedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Convert from in-memory map (demo mode)
  factory VehicleModel.fromMap(Map<String, dynamic> data) {
    return VehicleModel(
      vehicleId: data['vehicleId'] ?? '',
      vehicleName: data['vehicleName'] ?? '',
      currentOdo: data['currentOdo'] ?? 0,
      currentBattery: data['currentBattery'] ?? 100,
      stateOfHealth: (data['stateOfHealth'] ?? 100.0).toDouble(),
      defaultEfficiency: (data['defaultEfficiency'] ?? 1.2).toDouble(),
      totalCharges: data['totalCharges'] ?? 0,
      totalTrips: data['totalTrips'] ?? 0,
      lastBatteryPercent: data['lastBatteryPercent'] ?? 100,
      avatarColor: data['avatarColor'],
      vinfastModelId: data['vinfastModelId'],
      vinfastModelName: data['vinfastModelName'],
      specVersion: data['specVersion'],
      specLinkedAt: data['specLinkedAt'] is DateTime
          ? data['specLinkedAt']
          : data['specLinkedAt'] != null
              ? DateTime.tryParse(data['specLinkedAt'].toString())
              : null,
    );
  }

  /// Convert model to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
      'currentOdo': currentOdo,
      'currentBattery': currentBattery,
      'stateOfHealth': stateOfHealth,
      'defaultEfficiency': defaultEfficiency,
      'totalCharges': totalCharges,
      'totalTrips': totalTrips,
      'lastBatteryPercent': lastBatteryPercent,
      'avatarColor': avatarColor,
      'vinfastModelId': vinfastModelId,
      'vinfastModelName': vinfastModelName,
      'specVersion': specVersion,
      'specLinkedAt': specLinkedAt != null
          ? Timestamp.fromDate(specLinkedAt!)
          : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  VehicleModel copyWith({
    String? vehicleId,
    String? vehicleName,
    int? currentOdo,
    int? currentBattery,
    double? stateOfHealth,
    double? defaultEfficiency,
    int? totalCharges,
    int? totalTrips,
    int? lastBatteryPercent,
    String? avatarColor,
    String? vinfastModelId,
    String? vinfastModelName,
    int? specVersion,
    DateTime? specLinkedAt,
  }) {
    return VehicleModel(
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      currentOdo: currentOdo ?? this.currentOdo,
      currentBattery: currentBattery ?? this.currentBattery,
      stateOfHealth: stateOfHealth ?? this.stateOfHealth,
      defaultEfficiency: defaultEfficiency ?? this.defaultEfficiency,
      totalCharges: totalCharges ?? this.totalCharges,
      totalTrips: totalTrips ?? this.totalTrips,
      lastBatteryPercent: lastBatteryPercent ?? this.lastBatteryPercent,
      avatarColor: avatarColor ?? this.avatarColor,
      vinfastModelId: vinfastModelId ?? this.vinfastModelId,
      vinfastModelName: vinfastModelName ?? this.vinfastModelName,
      specVersion: specVersion ?? this.specVersion,
      specLinkedAt: specLinkedAt ?? this.specLinkedAt,
    );
  }
}
