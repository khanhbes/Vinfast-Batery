import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ========================================================================
/// SOC PREDICTION SERVICE - Tích hợp mô hình AI ev_soc_pipeline.pkl
/// ========================================================================
/// 
/// Service này chịu trách nhiệm:
/// 1. Load mô hình AI từ assets
/// 2. Dự đoán State of Charge (SOC) dựa trên dữ liệu xe
/// 3. Lưu kết quả vào Firestore cho web dashboard
/// 4. Cung cấp API cho mobile app

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
      timeSeries: (json['timeSeries'] as List).map((e) => (e as num).toDouble()).toList(),
      batteryHealth: (json['batteryHealth'] as num).toDouble(),
      recommendations: List<String>.from(json['recommendations']),
      timestamp: DateTime.parse(json['timestamp']),
      modelVersion: json['modelVersion'],
    );
  }
}

class SOCPredictionService {
  static const String _modelPath = 'assets/models/ev_soc_pipeline.pkl';
  static const String _modelVersion = '1.0.0';
  bool _isModelLoaded = false;
  File? _modelFile;

  /// Load mô hình AI từ assets
  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      // Copy model từ assets đến thư mục temporary
      final byteData = await rootBundle.load(_modelPath);
      final buffer = byteData.buffer;
      
      final directory = await getTemporaryDirectory();
      _modelFile = File('${directory.path}/ev_soc_pipeline.pkl');
      
      await _modelFile?.writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes)
      );

      _isModelLoaded = true;
      print('✅ SOC Prediction Model loaded successfully');
    } catch (e) {
      print('❌ Error loading SOC model: $e');
      throw Exception('Failed to load SOC prediction model: $e');
    }
  }

  /// Dự đoán SOC dựa trên input data
  Future<SOCPredictionResult> predictSOC(SOCPredictionInput input) async {
    if (!_isModelLoaded) {
      await loadModel();
    }

    try {
      // TODO: Implement actual model inference
      // Hiện tại đang simulate kết quả
      // Trong thực tế sẽ gọi Python model qua FFI hoặc HTTP endpoint
      
      final result = await _simulateModelInference(input);
      
      // Lưu kết quả vào Firestore
      await _savePredictionResult(input, result);
      
      return result;
    } catch (e) {
      print('❌ Error predicting SOC: $e');
      throw Exception('Failed to predict SOC: $e');
    }
  }

  /// Simulate model inference (placeholder cho Python model)
  Future<SOCPredictionResult> _simulateModelInference(SOCPredictionInput input) async {
    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 500));

    // Generate time series prediction (24 hours)
    final List<double> timeSeries = [];
    double currentSOC = input.currentBattery;
    
    for (int i = 0; i < 24; i++) {
      // Simulate SOC degradation/consumption
      double consumption = 0.5 + (input.avgSpeed / 100) + (input.temperature / 100);
      currentSOC = (currentSOC - consumption).clamp(0.0, 100.0);
      timeSeries.add(currentSOC);
    }

    // Calculate battery health based on various factors
    double batteryHealth = 100.0;
    batteryHealth -= (input.odometer / 1000); // Age factor
    batteryHealth -= (input.temperature > 35 ? 10 : 0); // Temperature stress
    batteryHealth -= (input.current > 50 ? 5 : 0); // High current stress
    batteryHealth = batteryHealth.clamp(0.0, 100.0);

    // Generate recommendations
    final List<String> recommendations = [];
    if (input.temperature > 35) {
      recommendations.add('Nhiệt độ pin cao, nên đỗ xe trong bóng mát');
    }
    if (input.currentBattery < 20) {
      recommendations.add('Pin yếu, nên sạc sớm');
    }
    if (batteryHealth < 80) {
      recommendations.add('Sức khỏe pin giảm, cân nhắc bảo dưỡng');
    }
    if (input.avgSpeed > 60) {
      recommendations.add('Tốc độ cao, tiêu thụ pin tăng');
    }

    return SOCPredictionResult(
      predictedSOC: timeSeries.last,
      confidence: 85.0 + (batteryHealth / 20), // Higher confidence with better health
      timeSeries: timeSeries,
      batteryHealth: batteryHealth,
      recommendations: recommendations,
      timestamp: DateTime.now(),
      modelVersion: _modelVersion,
    );
  }

  /// Lưu kết quả dự đoán vào Firestore
  Future<void> _savePredictionResult(SOCPredictionInput input, SOCPredictionResult result) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Lưu vào collection soc_predictions
      await firestore.collection('soc_predictions').add({
        'input': input.toJson(),
        'result': result.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ SOC prediction saved to Firestore');
    } catch (e) {
      print('❌ Error saving prediction to Firestore: $e');
      // Không throw exception để không ảnh hưởng đến main flow
    }
  }

  /// Lấy lịch sử dự đoán SOC
  Future<List<SOCPredictionResult>> getPredictionHistory(String vehicleId, {int limit = 10}) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('soc_predictions')
          .where('input.vehicleId', isEqualTo: vehicleId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => SOCPredictionResult.fromJson(doc['result']))
          .toList();
    } catch (e) {
      print('❌ Error getting prediction history: $e');
      return [];
    }
  }

  /// Get model status
  Map<String, dynamic> getModelStatus() {
    return {
      'isLoaded': _isModelLoaded,
      'modelPath': _modelPath,
      'modelVersion': _modelVersion,
      'modelFile': _modelFile?.path,
    };
  }
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
