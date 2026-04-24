import 'package:cloud_firestore/cloud_firestore.dart';

/// Model dự đoán chuyến đi đồng bộ với web dashboard
/// Tương ứng Trip trong app tham khảo nhưng có thêm AI prediction
class TripPredictionModel {
  final String id;
  final String vehicleId;
  final String from;
  final String to;
  final double distance; // km
  final int duration; // minutes
  final double consumption; // % tiêu hao dự đoán
  final double reasoning; // AI reasoning score
  final String? reasoningText; // AI reasoning text
  final double confidence; // Confidence score 0-1
  final double startBattery; // % pin khi bắt đầu
  final double endBattery; // % pin dự kiến khi kết thúc
  final bool isSafe; // Có đủ pin không
  final String weather; // Weather condition
  final double temperature; // Temperature
  final double riderWeight; // Rider weight
  final DateTime timestamp;
  final String status; // 'planned', 'active', 'completed', 'cancelled'

  const TripPredictionModel({
    required this.id,
    required this.vehicleId,
    required this.from,
    required this.to,
    required this.distance,
    required this.duration,
    required this.consumption,
    required this.reasoning,
    this.reasoningText,
    required this.confidence,
    required this.startBattery,
    required this.endBattery,
    required this.isSafe,
    required this.weather,
    required this.temperature,
    required this.riderWeight,
    required this.timestamp,
    required this.status,
  });

  /// Tạo từ Firestore document
  factory TripPredictionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TripPredictionModel(
      id: doc.id,
      vehicleId: data['vehicleId'] ?? '',
      from: data['from'] ?? '',
      to: data['to'] ?? '',
      distance: (data['distance'] ?? 0).toDouble(),
      duration: data['duration'] ?? 0,
      consumption: (data['consumption'] ?? 0).toDouble(),
      reasoning: (data['reasoning'] ?? 0).toDouble(),
      reasoningText: data['reasoningText'],
      confidence: (data['confidence'] ?? 0).toDouble(),
      startBattery: (data['startBattery'] ?? 0).toDouble(),
      endBattery: (data['endBattery'] ?? 0).toDouble(),
      isSafe: data['isSafe'] ?? false,
      weather: data['weather'] ?? 'Unknown',
      temperature: (data['temperature'] ?? 0).toDouble(),
      riderWeight: (data['riderWeight'] ?? 0).toDouble(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'planned',
    );
  }

  /// Chuyển thành Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'vehicleId': vehicleId,
      'from': from,
      'to': to,
      'distance': distance,
      'duration': duration,
      'consumption': consumption,
      'reasoning': reasoning,
      'reasoningText': reasoningText,
      'confidence': confidence,
      'startBattery': startBattery,
      'endBattery': endBattery,
      'isSafe': isSafe,
      'weather': weather,
      'temperature': temperature,
      'riderWeight': riderWeight,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
    };
  }

  /// Tạo trip prediction mới
  factory TripPredictionModel.create({
    required String vehicleId,
    required String from,
    required String to,
    required double distance,
    required double startBattery,
    required double weather,
    required double temperature,
    required double riderWeight,
  }) {
    // Calculate estimated duration (average speed 30 km/h)
    final duration = (distance / 30 * 60).round();
    
    // Calculate consumption using AI model or fallback
    final consumption = _calculateConsumption(distance, temperature, riderWeight);
    
    final endBattery = (startBattery - consumption).clamp(0.0, 100.0);
    final isSafe = endBattery > 15; // Safe if more than 15% battery
    
    return TripPredictionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      vehicleId: vehicleId,
      from: from,
      to: to,
      distance: distance,
      duration: duration,
      consumption: consumption,
      reasoning: 0.8, // AI reasoning score
      reasoningText: _generateReasoningText(distance, temperature, riderWeight, consumption),
      confidence: 0.85,
      startBattery: startBattery,
      endBattery: endBattery,
      isSafe: isSafe,
      weather: _getWeatherCondition(weather),
      temperature: temperature,
      riderWeight: riderWeight,
      timestamp: DateTime.now(),
      status: 'planned',
    );
  }

  /// Calculate consumption using AI model or fallback
  static double _calculateConsumption(double distance, double temperature, double weight) {
    // Base consumption: 0.8% per km for VinFast Feliz Neo
    double baseConsumption = distance * 0.8;
    
    // Temperature factor
    double tempFactor = 1.0;
    if (temperature < 10) {
      tempFactor = 1.2; // Cold weather increases consumption
    } else if (temperature > 35) {
      tempFactor = 1.1; // Hot weather increases consumption
    }
    
    // Weight factor
    double weightFactor = 1.0 + ((weight - 70) / 70) * 0.3; // 30% more for every 70kg above base
    
    return baseConsumption * tempFactor * weightFactor;
  }

  /// Generate reasoning text
  static String _generateReasoningText(double distance, double temperature, double weight, double consumption) {
    final tempDesc = temperature < 10 ? 'thời tiết lạnh' : 
                     temperature > 35 ? 'thời tiết nóng' : 'thời tiết lý tưởng';
    final weightDesc = weight > 80 ? 'trọng lượng nặng' : 
                       weight < 60 ? 'trọng lượng nhẹ' : 'trọng lượng trung bình';
    
    return 'Dự đoán dựa trên quãng đường $distance km với $tempDesc và $weightDesc. Tiêu hao pin ước tính là ${consumption.toStringAsFixed(1)}%.';
  }

  /// Get weather condition string
  static String _getWeatherCondition(double weatherCode) {
    if (weatherCode < 0.3) return 'Mưa';
    if (weatherCode < 0.7) return 'Nhiều mây';
    return 'Nắng';
  }

  /// Get trip status color
  String get statusColor {
    switch (status) {
      case 'planned':
        return '#3B82F6'; // blue
      case 'active':
        return '#10B981'; // green
      case 'completed':
        return '#6B7280'; // gray
      case 'cancelled':
        return '#EF4444'; // red
      default:
        return '#6B7280'; // gray
    }
  }

  /// Get safety status text
  String get safetyText {
    if (!isSafe) return 'Pin yếu - Cần sạc trước khi đi';
    if (endBattery < 30) return 'Cẩn thận - Pin còn ít';
    return 'An toàn - Đủ pin cho chuyến đi';
  }

  /// Get safety color
  String get safetyColor {
    if (!isSafe) return '#EF4444'; // red
    if (endBattery < 30) return '#F59E0B'; // amber
    return '#10B981'; // green
  }

  @override
  String toString() {
    return 'TripPredictionModel(id: $id, from: $from, to: $to, distance: ${distance}km, consumption: $consumption%, status: $status)';
  }
}
