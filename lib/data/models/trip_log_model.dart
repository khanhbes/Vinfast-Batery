import 'package:cloud_firestore/cloud_firestore.dart';

/// Loại tải trọng khi di chuyển
enum PayloadType {
  onePerson('1_person', '1 người', 1.0),
  twoPerson('2_person', '2 người / Chở nặng', 1.3);

  final String value;
  final String label;
  final double factor; // Hệ số tiêu hao pin

  const PayloadType(this.value, this.label, this.factor);

  static PayloadType fromString(String v) {
    return PayloadType.values.firstWhere(
      (e) => e.value == v,
      orElse: () => PayloadType.onePerson,
    );
  }
}

/// Chế độ nhập dữ liệu
enum TripEntryMode {
  live('live', 'Theo dõi GPS'),
  manual('manual', 'Nhập tay');

  final String value;
  final String label;
  const TripEntryMode(this.value, this.label);

  static TripEntryMode fromString(String v) {
    return TripEntryMode.values.firstWhere(
      (e) => e.value == v,
      orElse: () => TripEntryMode.live,
    );
  }
}

/// Nguồn tính khoảng cách
enum DistanceSource {
  gps('gps', 'GPS'),
  odometer('odometer', 'ODO');

  final String value;
  final String label;
  const DistanceSource(this.value, this.label);

  static DistanceSource fromString(String v) {
    return DistanceSource.values.firstWhere(
      (e) => e.value == v,
      orElse: () => DistanceSource.gps,
    );
  }
}

/// Model cho mỗi chuyến đi
class TripLogModel {
  final String? tripId;
  final String vehicleId;
  final DateTime startTime;
  final DateTime endTime;
  final double distance; // km
  final PayloadType payloadType;
  final int startBattery; // %
  final int endBattery; // %
  final int batteryConsumed; // % tiêu thụ
  final double efficiency; // km / 1%
  final int startOdo;
  final int endOdo;
  final TripEntryMode entryMode;
  final DistanceSource distanceSource;

  TripLogModel({
    this.tripId,
    required this.vehicleId,
    required this.startTime,
    required this.endTime,
    required this.distance,
    required this.payloadType,
    required this.startBattery,
    required this.endBattery,
    required this.batteryConsumed,
    required this.efficiency,
    required this.startOdo,
    required this.endOdo,
    this.entryMode = TripEntryMode.live,
    this.distanceSource = DistanceSource.gps,
  });

  /// Thời gian di chuyển
  Duration get duration => endTime.difference(startTime);

  String get durationText {
    final d = duration;
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  /// Tốc độ trung bình (km/h)
  double get avgSpeed {
    final hours = duration.inSeconds / 3600.0;
    return hours > 0 ? distance / hours : 0;
  }

  factory TripLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TripLogModel(
      tripId: doc.id,
      vehicleId: data['vehicleId'] ?? '',
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      distance: (data['distance'] ?? 0).toDouble(),
      payloadType: PayloadType.fromString(data['payloadType'] ?? '1_person'),
      startBattery: data['startBattery'] ?? 0,
      endBattery: data['endBattery'] ?? 0,
      batteryConsumed: data['batteryConsumed'] ?? 0,
      efficiency: (data['efficiency'] ?? 0).toDouble(),
      startOdo: data['startOdo'] ?? 0,
      endOdo: data['endOdo'] ?? 0,
      entryMode: TripEntryMode.fromString(data['entryMode'] ?? 'live'),
      distanceSource: DistanceSource.fromString(data['distanceSource'] ?? 'gps'),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'distance': distance,
      'payloadType': payloadType.value,
      'startBattery': startBattery,
      'endBattery': endBattery,
      'batteryConsumed': batteryConsumed,
      'efficiency': efficiency,
      'startOdo': startOdo,
      'endOdo': endOdo,
      'entryMode': entryMode.value,
      'distanceSource': distanceSource.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
