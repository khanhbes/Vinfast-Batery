import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/trip_prediction_model.dart';
import '../models/vehicle_model.dart';
import '../../core/constants/app_constants.dart';

/// Service xử lý dự đoán chuyến đi đồng bộ với web dashboard
/// Sử dụng AI model từ server hoặc fallback heuristic
class TripPredictionService {
  static String get _baseUrl => AppConstants.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 30);

  /// Dự đoán tiêu hao pin cho chuyến đi
  static Future<TripPredictionModel> predictTrip({
    required String vehicleId,
    required String from,
    required String to,
    required double distance,
    required VehicleModel vehicle,
    required double weather,
    required double temperature,
    required double riderWeight,
  }) async {
    try {
      // Thử gọi API server trước
      final prediction = await _callPredictionAPI(
        vehicleId: vehicleId,
        from: from,
        to: to,
        distance: distance,
        currentBattery: vehicle.currentBattery.toDouble(),
        temperature: temperature,
        riderWeight: riderWeight,
        weather: _getWeatherString(weather),
      );

      // Lưu vào Firestore
      await _savePredictionToFirestore(prediction);

      return prediction;
    } catch (e) {
      print('API prediction failed, using fallback: $e');
      
      // Fallback về local calculation
      final prediction = TripPredictionModel.create(
        vehicleId: vehicleId,
        from: from,
        to: to,
        distance: distance,
        startBattery: vehicle.currentBattery.toDouble(),
        weather: weather,
        temperature: temperature,
        riderWeight: riderWeight,
      );

      // Lưu vào Firestore
      await _savePredictionToFirestore(prediction);

      return prediction;
    }
  }

  /// Gọi API prediction từ server
  static Future<TripPredictionModel> _callPredictionAPI({
    required String vehicleId,
    required String from,
    required String to,
    required double distance,
    required double currentBattery,
    required double temperature,
    required double riderWeight,
    required String weather,
  }) async {
    final url = Uri.parse('$_baseUrl/api/trip/predict');
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'vehicleId': vehicleId,
        'from': from,
        'to': to,
        'distance': distance,
        'currentBattery': currentBattery,
        'temperature': temperature,
        'riderWeight': riderWeight,
        'weather': weather,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('API call failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    
    if (!data['success']) {
      throw Exception('API returned error: ${data['error']}');
    }

    final result = data['data'];
    
    return TripPredictionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      vehicleId: vehicleId,
      from: from,
      to: to,
      distance: distance,
      duration: result['estimatedDuration'] ?? ((distance / 30) * 60).round(),
      consumption: result['predictedConsumption']?.toDouble() ?? 0.0,
      reasoning: result['reasoningScore']?.toDouble() ?? 0.8,
      reasoningText: result['reasoningText'] ?? 'AI prediction',
      confidence: result['confidence']?.toDouble() ?? 0.85,
      startBattery: currentBattery,
      endBattery: result['predictedEndBattery']?.toDouble() ?? (currentBattery - (result['predictedConsumption'] ?? 0)).clamp(0.0, 100.0),
      isSafe: result['isSafe'] ?? true,
      weather: weather,
      temperature: temperature,
      riderWeight: riderWeight,
      timestamp: DateTime.now(),
      status: 'planned',
    );
  }

  /// Lưu prediction vào Firestore
  static Future<void> _savePredictionToFirestore(TripPredictionModel prediction) async {
    try {
      await FirebaseFirestore.instance
          .collection('trip_predictions')
          .doc(prediction.id)
          .set(prediction.toFirestore());
      
      print('Trip prediction saved to Firestore: ${prediction.id}');
    } catch (e) {
      print('Failed to save prediction to Firestore: $e');
    }
  }

  /// Lấy lịch sử dự đoán chuyến đi
  static Future<List<TripPredictionModel>> getPredictionHistory({
    required String vehicleId,
    int limit = 10,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('trip_predictions')
          .where('vehicleId', isEqualTo: vehicleId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => TripPredictionModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Failed to get prediction history: $e');
      return [];
    }
  }

  /// Cập nhật trạng thái chuyến đi
  static Future<void> updateTripStatus(String predictionId, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('trip_predictions')
          .doc(predictionId)
          .update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('Trip status updated: $predictionId -> $status');
    } catch (e) {
      print('Failed to update trip status: $e');
    }
  }

  /// Xóa dự đoán chuyến đi
  static Future<void> deletePrediction(String predictionId) async {
    try {
      await FirebaseFirestore.instance
          .collection('trip_predictions')
          .doc(predictionId)
          .delete();
      
      print('Trip prediction deleted: $predictionId');
    } catch (e) {
      print('Failed to delete prediction: $e');
    }
  }

  /// Lấy thống kê dự đoán
  static Future<Map<String, dynamic>> getPredictionStats(String vehicleId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('trip_predictions')
          .where('vehicleId', isEqualTo: vehicleId)
          .get();

      final predictions = snapshot.docs
          .map((doc) => TripPredictionModel.fromFirestore(doc))
          .toList();

      final totalPredictions = predictions.length;
      final completedTrips = predictions.where((p) => p.status == 'completed').length;
      final totalDistance = predictions.fold<double>(0, (sum, p) => sum + p.distance);
      final avgConsumption = predictions.isEmpty ? 0.0 : 
          predictions.fold<double>(0, (sum, p) => sum + p.consumption) / predictions.length;

      return {
        'totalPredictions': totalPredictions,
        'completedTrips': completedTrips,
        'totalDistance': totalDistance,
        'avgConsumption': avgConsumption,
        'completionRate': totalPredictions > 0 ? (completedTrips / totalPredictions) * 100 : 0.0,
      };
    } catch (e) {
      print('Failed to get prediction stats: $e');
      return {};
    }
  }

  /// Đồng bộ dữ liệu với web dashboard
  static Future<void> syncWithWebDashboard(String vehicleId) async {
    try {
      // Lấy predictions từ local
      final localPredictions = await getPredictionHistory(vehicleId: vehicleId);
      
      // Gửi đến web dashboard API
      for (final prediction in localPredictions) {
        await _syncPredictionToWeb(prediction);
      }
      
      print('Synced ${localPredictions.length} predictions to web dashboard');
    } catch (e) {
      print('Failed to sync with web dashboard: $e');
    }
  }

  /// Sync prediction đến web dashboard
  static Future<void> _syncPredictionToWeb(TripPredictionModel prediction) async {
    try {
      final url = Uri.parse('$_baseUrl/api/web/sync/trip-prediction');
      
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(prediction.toFirestore()),
      ).timeout(_timeout);
    } catch (e) {
      print('Failed to sync prediction to web: $e');
    }
  }

  /// Convert weather code to string
  static String _getWeatherString(double weatherCode) {
    if (weatherCode < 0.3) return 'rain';
    if (weatherCode < 0.7) return 'cloudy';
    return 'sunny';
  }

  /// Test API connection
  static Future<bool> testAPIConnection() async {
    try {
      final url = Uri.parse('$_baseUrl/api/health');
      final response = await http.get(url).timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      print('API connection test failed: $e');
      return false;
    }
  }
}
