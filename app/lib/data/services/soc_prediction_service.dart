import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ========================================================================
/// Legacy SOC API retained for compatibility. No verified mobile SOC artifact
/// exists: inference reports unavailable, never simulates or uploads predictions.

class SOCPredictionInput {
  final double currentBattery; // % hiện tại
  final double temperature; // Nhiệt độ (°C)
  final double voltage; // Điện áp (V)
  final double current; // Dòng điện (A)
  final double odometer; // Odometer (km)
  final int timeOfDay; // Giờ trong ngày (0-23)
  final int dayOfWeek; // Ngày trong tuần (0-6)
  final double avgSpeed; // Tốc độ trung bình (km/h)
  final double elevationGain; // Độ cao tăng (m)
  final String weatherCondition; // Điều kiện thời tiết

  SOCPredictionInput({
    required this.currentBattery,
    required this.temperature,
    required this.voltage,
    required this.current,
    required this.odometer,
    required this.timeOfDay,
    required this.dayOfWeek,
    required this.avgSpeed,
    required this.elevationGain,
    required this.weatherCondition,
  });

  Map<String, dynamic> toJson() {
    return {
      'currentBattery': currentBattery,
      'temperature': temperature,
      'voltage': voltage,
      'current': current,
      'odometer': odometer,
      'timeOfDay': timeOfDay,
      'dayOfWeek': dayOfWeek,
      'avgSpeed': avgSpeed,
      'elevationGain': elevationGain,
      'weatherCondition': weatherCondition,
    };
  }
}

class SOCPredictionResult {
  final double predictedSOC; // SOC dự đoán (%)
  final double confidence; // Độ tin cậy (%)
  final List<double> timeSeries; // Chuỗi thời gian SOC (24h)
  final double batteryHealth; // Sức khỏe pin (%)
  final List<String> recommendations; // Đề xuất
  final DateTime timestamp; // Thời gian dự đoán
  final String modelVersion; // Phiên bản mô hình

  SOCPredictionResult({
    required this.predictedSOC,
    required this.confidence,
    required this.timeSeries,
    required this.batteryHealth,
    required this.recommendations,
    required this.timestamp,
    required this.modelVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'predictedSOC': predictedSOC,
      'confidence': confidence,
      'timeSeries': timeSeries,
      'batteryHealth': batteryHealth,
      'recommendations': recommendations,
      'timestamp': timestamp.toIso8601String(),
      'modelVersion': modelVersion,
    };
  }

  factory SOCPredictionResult.fromJson(Map<String, dynamic> json) {
    return SOCPredictionResult(
      predictedSOC: (json['predictedSOC'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      timeSeries: (json['timeSeries'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      batteryHealth: (json['batteryHealth'] as num).toDouble(),
      recommendations: List<String>.from(json['recommendations']),
      timestamp: DateTime.parse(json['timestamp']),
      modelVersion: json['modelVersion'],
    );
  }
}

class SOCPredictionService {
  /// The bundled pickle is not an Android inference runtime.
  Future<void> loadModel() async => throw const SOCModelUnavailableException();
  Future<SOCPredictionResult> predictSOC(SOCPredictionInput input) async =>
      throw const SOCModelUnavailableException();
  Future<List<SOCPredictionResult>> getPredictionHistory(
    String vehicleId, {
    int limit = 10,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('soc_predictions')
        .where('input.vehicleId', isEqualTo: vehicleId)
        .where('ownerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    if (FirebaseAuth.instance.currentUser?.uid != uid) return [];
    return snapshot.docs
        .map((doc) => SOCPredictionResult.fromJson(doc['result']))
        .toList();
  }

  Map<String, dynamic> getModelStatus() => {
    'isLoaded': false,
    'available': false,
    'code': 'LOCAL_MODEL_UNAVAILABLE',
    'modelVersion': null,
  };
}

class SOCModelUnavailableException implements Exception {
  const SOCModelUnavailableException();
  @override
  String toString() => 'Chưa có model SOC tương thích trên điện thoại.';
}

/// Provider cho SOCPredictionService
final socPredictionServiceProvider = Provider<SOCPredictionService>((ref) {
  return SOCPredictionService();
});

/// Provider cho model status
final socModelStatusProvider = Provider<Map<String, dynamic>>((ref) {
  final service = ref.watch(socPredictionServiceProvider);
  return service.getModelStatus();
});
