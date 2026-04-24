import 'package:cloud_firestore/cloud_firestore.dart';
import 'vehicle_model.dart';

/// Model trạng thái pin đồng bộ với web dashboard
/// Tương ứng BatteryState trong app tham khảo
class BatteryStateModel {
  final String vehicleId;
  final double percentage; // % pin hiện tại
  final double soh; // State of Health 0-100%
  final double estimatedRange; // km ước tính
  final double temp; // Nhiệt độ Celsius
  final DateTime timestamp;
  final String? source; // 'app', 'web', 'api'

  const BatteryStateModel({
    required this.vehicleId,
    required this.percentage,
    required this.soh,
    required this.estimatedRange,
    required this.temp,
    required this.timestamp,
    this.source,
  });

  /// Tạo từ Firestore document
  factory BatteryStateModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BatteryStateModel(
      vehicleId: doc.id,
      percentage: (data['percentage'] ?? 0).toDouble(),
      soh: (data['soh'] ?? 0).toDouble(),
      estimatedRange: (data['estimatedRange'] ?? 0).toDouble(),
      temp: (data['temp'] ?? 0).toDouble(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      source: data['source'],
    );
  }

  /// Chuyển thành Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'percentage': percentage,
      'soh': soh,
      'estimatedRange': estimatedRange,
      'temp': temp,
      'timestamp': Timestamp.fromDate(timestamp),
      'source': source,
    };
  }

  /// Tạo từ VehicleModel
  factory BatteryStateModel.fromVehicleModel(VehicleModel vehicle, {double? temp}) {
    return BatteryStateModel(
      vehicleId: vehicle.vehicleId,
      percentage: vehicle.currentBattery.toDouble(),
      soh: vehicle.stateOfHealth,
      estimatedRange: vehicle.currentBattery * vehicle.defaultEfficiency,
      temp: temp ?? 25.0, // Default temperature
      timestamp: DateTime.now(),
      source: 'app',
    );
  }

  /// Copy with updated values
  BatteryStateModel copyWith({
    double? percentage,
    double? soh,
    double? estimatedRange,
    double? temp,
    DateTime? timestamp,
    String? source,
  }) {
    return BatteryStateModel(
      vehicleId: vehicleId,
      percentage: percentage ?? this.percentage,
      soh: soh ?? this.soh,
      estimatedRange: estimatedRange ?? this.estimatedRange,
      temp: temp ?? this.temp,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
    );
  }

  /// Check if battery needs charging
  bool get needsCharging => percentage < 20;

  /// Check if battery health is critical
  bool get healthCritical => soh < 80;

  /// Get battery status text
  String get statusText {
    if (percentage < 10) return 'Critical';
    if (percentage < 20) return 'Low';
    if (percentage < 50) return 'Medium';
    return 'Good';
  }

  /// Get battery color
  String get statusColor {
    if (percentage < 10) return '#EF4444'; // red
    if (percentage < 20) return '#F59E0B'; // amber
    if (percentage < 50) return '#3B82F6'; // blue
    return '#10B981'; // green
  }

  @override
  String toString() {
    return 'BatteryStateModel(vehicleId: $vehicleId, percentage: $percentage%, soh: $soh, range: ${estimatedRange}km, temp: $temp°C)';
  }
}
