import 'package:cloud_firestore/cloud_firestore.dart';

/// Model xe VinFast với thông tin mở rộng
/// Bao gồm SoH, currentBattery, defaultEfficiency cho tính toán chai pin
class VehicleModel {
  final String vehicleId;
  final String vehicleName;
  final String? ownerUid;
  final int currentOdo;
  final int currentBattery; // % pin hiện tại (realtime)
  final double stateOfHealth; // SoH 0-100%
  final double defaultEfficiency; // km / 1% khi mới (VD: 1.2)
  final double batteryCapacityWh;
  final int totalCharges;
  final int totalTrips;
  final int lastBatteryPercent;
  final String? avatarColor;
  // ── VinFast Model Link fields ──
  final String? vinfastModelId;
  final String? vinfastModelName;
  final int? specVersion;
  final DateTime? specLinkedAt;
  final bool isArchived;
  final DateTime? archivedAt;
  // Provenance flags distinguish real persisted telemetry/spec values from
  // constructor defaults used by legacy callers and demo objects.
  final bool hasBatteryData;
  final bool hasSohData;
  final bool hasEfficiencyData;
  final bool hasOdoData;

  VehicleModel({
    required this.vehicleId,
    this.vehicleName = '',
    this.ownerUid,
    required this.currentOdo,
    this.currentBattery = 100,
    this.stateOfHealth = 100.0,
    this.defaultEfficiency = 1.2, // VinFast Feliz Neo: ~1.2 km/1%
    this.batteryCapacityWh = 0,
    this.totalCharges = 0,
    this.totalTrips = 0,
    this.lastBatteryPercent = 100,
    this.avatarColor,
    this.vinfastModelId,
    this.vinfastModelName,
    this.specVersion,
    this.specLinkedAt,
    this.isArchived = false,
    this.archivedAt,
    this.hasBatteryData = true,
    this.hasSohData = true,
    this.hasEfficiencyData = true,
    this.hasOdoData = true,
  });

  /// Convert Firestore document to model
  /// Whether this vehicle has been linked to a VinFast model spec
  bool get hasModelLink => vinfastModelId != null && vinfastModelId!.isNotEmpty;

  /// Parse số nguyên an toàn — chấp nhận `int`, `double`, `num`, `String`,
  /// hoặc `null`. Tránh crash `'double' is not a subtype of int` khi Firestore
  /// trả về `0.0` cho field đang khai báo là int.
  static int _asInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value) ?? double.tryParse(value)?.round();
      return parsed ?? fallback;
    }
    return fallback;
  }

  /// Parse số thực an toàn.
  static double _asDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  factory VehicleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VehicleModel(
      vehicleId: doc.id,
      vehicleName: data['vehicleName'] ?? '',
      ownerUid: data['ownerUid'],
      currentOdo: _asInt(data['currentOdo']),
      currentBattery: _asInt(
        data['currentBattery'] ?? data['lastBatteryPercent'],
        100,
      ),
      stateOfHealth: _asDouble(data['stateOfHealth'], 100.0),
      defaultEfficiency: _asDouble(data['defaultEfficiency'], 1.2),
      batteryCapacityWh: _asDouble(
        data['batteryCapacityWh'] ?? data['batteryCapacity'],
      ),
      totalCharges: _asInt(data['totalCharges']),
      totalTrips: _asInt(data['totalTrips']),
      lastBatteryPercent: _asInt(data['lastBatteryPercent'], 100),
      hasBatteryData: data['hasBatteryData'] is bool
          ? data['hasBatteryData'] as bool
          : data.containsKey('currentBattery') ||
                data.containsKey('lastBatteryPercent'),
      hasSohData: data['hasSohData'] is bool
          ? data['hasSohData'] as bool
          : data.containsKey('stateOfHealth'),
      hasEfficiencyData: data['hasEfficiencyData'] is bool
          ? data['hasEfficiencyData'] as bool
          : data.containsKey('defaultEfficiency'),
      hasOdoData: data['hasOdoData'] is bool
          ? data['hasOdoData'] as bool
          : data.containsKey('currentOdo'),
      avatarColor: data['avatarColor'],
      vinfastModelId: data['vinfastModelId'],
      vinfastModelName: data['vinfastModelName'],
      specVersion: data['specVersion'] == null
          ? null
          : _asInt(data['specVersion']),
      specLinkedAt: data['specLinkedAt'] != null
          ? (data['specLinkedAt'] as Timestamp).toDate()
          : null,
      isArchived: data['isDeleted'] == true || data['archivedAt'] != null,
      archivedAt: data['archivedAt'] is Timestamp
          ? (data['archivedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Convert from in-memory map (demo mode)
  factory VehicleModel.fromMap(Map<String, dynamic> data) {
    return VehicleModel(
      vehicleId: data['vehicleId'] ?? '',
      vehicleName: data['vehicleName'] ?? '',
      currentOdo: _asInt(data['currentOdo']),
      currentBattery: _asInt(data['currentBattery'], 100),
      stateOfHealth: _asDouble(data['stateOfHealth'], 100.0),
      defaultEfficiency: _asDouble(data['defaultEfficiency'], 1.2),
      batteryCapacityWh: _asDouble(
        data['batteryCapacityWh'] ?? data['batteryCapacity'],
      ),
      totalCharges: _asInt(data['totalCharges']),
      totalTrips: _asInt(data['totalTrips']),
      lastBatteryPercent: _asInt(data['lastBatteryPercent'], 100),
      hasBatteryData: data['hasBatteryData'] is bool
          ? data['hasBatteryData'] as bool
          : data.containsKey('currentBattery') ||
                data.containsKey('lastBatteryPercent'),
      hasSohData: data['hasSohData'] is bool
          ? data['hasSohData'] as bool
          : data.containsKey('stateOfHealth'),
      hasEfficiencyData: data['hasEfficiencyData'] is bool
          ? data['hasEfficiencyData'] as bool
          : data.containsKey('defaultEfficiency'),
      hasOdoData: data['hasOdoData'] is bool
          ? data['hasOdoData'] as bool
          : data.containsKey('currentOdo'),
      avatarColor: data['avatarColor'],
      vinfastModelId: data['vinfastModelId'],
      vinfastModelName: data['vinfastModelName'],
      specVersion: data['specVersion'] == null
          ? null
          : _asInt(data['specVersion']),
      specLinkedAt: data['specLinkedAt'] is DateTime
          ? data['specLinkedAt']
          : data['specLinkedAt'] != null
          ? DateTime.tryParse(data['specLinkedAt'].toString())
          : null,
      isArchived: data['isDeleted'] == true || data['archivedAt'] != null,
      archivedAt: data['archivedAt'] is DateTime ? data['archivedAt'] : null,
    );
  }

  /// Convert model to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      'vehicleName': vehicleName,
      if (ownerUid != null) 'ownerUid': ownerUid,
      'currentOdo': currentOdo,
      'currentBattery': currentBattery,
      'stateOfHealth': stateOfHealth,
      'defaultEfficiency': defaultEfficiency,
      if (batteryCapacityWh > 0) 'batteryCapacity': batteryCapacityWh,
      'totalCharges': totalCharges,
      'totalTrips': totalTrips,
      'lastBatteryPercent': lastBatteryPercent,
      'hasBatteryData': hasBatteryData,
      'hasSohData': hasSohData,
      'hasEfficiencyData': hasEfficiencyData,
      'hasOdoData': hasOdoData,
      'avatarColor': avatarColor,
      'vinfastModelId': vinfastModelId,
      'vinfastModelName': vinfastModelName,
      'specVersion': specVersion,
      'specLinkedAt': specLinkedAt != null
          ? Timestamp.fromDate(specLinkedAt!)
          : null,
      'isDeleted': isArchived,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  VehicleModel copyWith({
    String? vehicleId,
    String? vehicleName,
    String? ownerUid,
    int? currentOdo,
    int? currentBattery,
    double? stateOfHealth,
    double? defaultEfficiency,
    double? batteryCapacityWh,
    int? totalCharges,
    int? totalTrips,
    int? lastBatteryPercent,
    String? avatarColor,
    String? vinfastModelId,
    String? vinfastModelName,
    int? specVersion,
    DateTime? specLinkedAt,
    bool? isArchived,
    DateTime? archivedAt,
    bool? hasBatteryData,
    bool? hasSohData,
    bool? hasEfficiencyData,
    bool? hasOdoData,
  }) {
    return VehicleModel(
      vehicleId: vehicleId ?? this.vehicleId,
      vehicleName: vehicleName ?? this.vehicleName,
      ownerUid: ownerUid ?? this.ownerUid,
      currentOdo: currentOdo ?? this.currentOdo,
      currentBattery: currentBattery ?? this.currentBattery,
      stateOfHealth: stateOfHealth ?? this.stateOfHealth,
      defaultEfficiency: defaultEfficiency ?? this.defaultEfficiency,
      batteryCapacityWh: batteryCapacityWh ?? this.batteryCapacityWh,
      totalCharges: totalCharges ?? this.totalCharges,
      totalTrips: totalTrips ?? this.totalTrips,
      lastBatteryPercent: lastBatteryPercent ?? this.lastBatteryPercent,
      avatarColor: avatarColor ?? this.avatarColor,
      vinfastModelId: vinfastModelId ?? this.vinfastModelId,
      vinfastModelName: vinfastModelName ?? this.vinfastModelName,
      specVersion: specVersion ?? this.specVersion,
      specLinkedAt: specLinkedAt ?? this.specLinkedAt,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      hasBatteryData: hasBatteryData ?? this.hasBatteryData,
      hasSohData: hasSohData ?? this.hasSohData,
      hasEfficiencyData: hasEfficiencyData ?? this.hasEfficiencyData,
      hasOdoData: hasOdoData ?? this.hasOdoData,
    );
  }
}
