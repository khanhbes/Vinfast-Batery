import 'package:flutter/foundation.dart';
// Legacy AI diagnostics remain visible to the local support console.
// ignore_for_file: avoid_print, avoid_types_as_parameter_names

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/battery_state_model.dart';
import '../models/vehicle_model.dart';
import 'range_estimator.dart';
import '../../core/constants/app_constants.dart';

/// Service xử lý trạng thái pin đồng bộ với web dashboard
/// Tích hợp với SOC AI model và real-time monitoring
class BatteryStateService {
  static String get _baseUrl => AppConstants.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 30);

  /// Lấy trạng thái pin hiện tại từ vehicle
  static Future<BatteryStateModel> getCurrentBatteryState(
    String vehicleId,
  ) async {
    try {
      // Lấy vehicle information
      final vehicleDoc = await FirebaseFirestore.instance
          .collection('Vehicles')
          .doc(vehicleId)
          .get();

      if (!vehicleDoc.exists) {
        throw Exception('Vehicle not found: $vehicleId');
      }

      final vehicle = VehicleModel.fromFirestore(vehicleDoc);

      // Lấy nhiệt độ gần nhất từ trip logs hoặc sensors
      final temperature = await _getLatestTemperature(vehicleId);

      // Tạo battery state
      final batteryState = BatteryStateModel.fromVehicleModel(
        vehicle,
        temp: temperature,
      );

      // Lưu vào Firestore
      await _saveBatteryStateToFirestore(batteryState);

      return batteryState;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get current battery state: $e');
      rethrow;
    }
  }

  /// Lấy lịch sử trạng thái pin
  static Future<List<BatteryStateModel>> getBatteryHistory({
    required String vehicleId,
    int limit = 24,
    Duration? timeRange,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      Query query = FirebaseFirestore.instance
          .collection('battery_states')
          .where('vehicleId', isEqualTo: vehicleId);
      if (uid != null) {
        query = query.where('ownerUid', isEqualTo: uid);
      }
      query = query.orderBy('timestamp', descending: true);

      if (timeRange != null) {
        final startTime = DateTime.now().subtract(timeRange);
        query = query.where('timestamp', isGreaterThanOrEqualTo: startTime);
      }

      final snapshot = await query.limit(limit).get();

      return snapshot.docs
          .map((doc) => BatteryStateModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get battery history: $e');
      return [];
    }
  }

  /// Cập nhật trạng thái pin real-time
  static Future<void> updateBatteryState({
    required String vehicleId,
    required double percentage,
    double? temperature,
    double? voltage,
    double? current,
  }) async {
    try {
      final batteryState = BatteryStateModel(
        vehicleId: vehicleId,
        percentage: percentage,
        soh: await _calculateSOH(vehicleId),
        estimatedRange: await _calculateEstimatedRange(vehicleId, percentage),
        temp: temperature ?? 25.0,
        timestamp: DateTime.now(),
        source: 'app',
      );

      await _saveBatteryStateToFirestore(batteryState);

      // Cập nhật vehicle model
      await FirebaseFirestore.instance
          .collection('Vehicles')
          .doc(vehicleId)
          .update({
            'currentBattery': percentage.round(),
            'lastBatteryPercent': percentage.round(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      if (kDebugMode) {
        debugPrint('Battery state updated for vehicle: $vehicleId');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to update battery state: $e');
    }
  }

  /// Lấy thống kê pin
  static Future<Map<String, dynamic>> getBatteryStats(String vehicleId) async {
    try {
      final history = await getBatteryHistory(vehicleId: vehicleId, limit: 100);

      if (history.isEmpty) {
        return {};
      }

      final currentSOC = history.first.percentage;
      final avgSOC =
          history.fold<double>(0, (sum, state) => sum + state.percentage) /
          history.length;
      final minSOC = history
          .map((s) => s.percentage)
          .reduce((a, b) => a < b ? a : b);
      final maxSOC = history
          .map((s) => s.percentage)
          .reduce((a, b) => a > b ? a : b);
      final avgTemp =
          history.fold<double>(0, (sum, state) => sum + state.temp) /
          history.length;
      final avgSOH =
          history.fold<double>(0, (sum, state) => sum + state.soh) /
          history.length;

      // Tính xu hướng tiêu hao
      final consumptionTrend = _calculateConsumptionTrend(history);

      return {
        'currentSOC': currentSOC,
        'avgSOC': avgSOC,
        'minSOC': minSOC,
        'maxSOC': maxSOC,
        'avgTemp': avgTemp,
        'avgSOH': avgSOH,
        'consumptionTrend': consumptionTrend,
        'dataPoints': history.length,
        'lastUpdated': history.first.timestamp.toIso8601String(),
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get battery stats: $e');
      return {};
    }
  }

  /// Đồng bộ dữ liệu với web dashboard
  static Future<void> syncWithWebDashboard(String vehicleId) async {
    try {
      final batteryState = await getCurrentBatteryState(vehicleId);

      final url = Uri.parse('$_baseUrl/api/web/sync/battery-state');

      await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(batteryState.toFirestore()),
          )
          .timeout(_timeout);

      if (kDebugMode) {
        debugPrint('Battery state synced to web dashboard: $vehicleId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to sync battery state to web dashboard: $e');
      }
    }
  }

  /// Lưu battery state vào Firestore
  static Future<void> _saveBatteryStateToFirestore(
    BatteryStateModel batteryState,
  ) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (kDebugMode) {
          debugPrint('Skip battery state save: not authenticated');
        }
        return;
      }
      final payload = <String, dynamic>{
        ...batteryState.toFirestore(),
        'ownerUid': uid,
      };
      await FirebaseFirestore.instance
          .collection('battery_states')
          .doc(
            '${batteryState.vehicleId}_${batteryState.timestamp.millisecondsSinceEpoch}',
          )
          .set(payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to save battery state to Firestore: $e');
      }
    }
  }

  /// Lấy nhiệt độ gần nhất
  static Future<double> _getLatestTemperature(String vehicleId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('trip_logs')
          .where('vehicleId', isEqualTo: vehicleId)
          .orderBy('startTime', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        return (data['avgTemperature'] ?? 25.0).toDouble();
      }

      return 25.0; // Default temperature
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to get latest temperature: $e');
      return 25.0;
    }
  }

  /// Tính State of Health
  static Future<double> _calculateSOH(String vehicleId) async {
    try {
      final vehicleDoc = await FirebaseFirestore.instance
          .collection('Vehicles')
          .doc(vehicleId)
          .get();

      if (!vehicleDoc.exists) return 100.0;

      final vehicle = VehicleModel.fromFirestore(vehicleDoc);
      return vehicle.stateOfHealth;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to calculate SOH: $e');
      return 100.0;
    }
  }

  /// Tính estimated range
  static Future<double> _calculateEstimatedRange(
    String vehicleId,
    double currentBattery,
  ) async {
    try {
      final vehicleDoc = await FirebaseFirestore.instance
          .collection('Vehicles')
          .doc(vehicleId)
          .get();

      if (!vehicleDoc.exists) return 0;

      final vehicle = VehicleModel.fromFirestore(vehicleDoc);
      return estimateRangeKm(vehicle, socOverride: currentBattery) ?? 0;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to calculate estimated range: $e');
      return 0;
    }
  }

  /// Tính xu hướng tiêu hao
  static Map<String, dynamic> _calculateConsumptionTrend(
    List<BatteryStateModel> history,
  ) {
    if (history.length < 2) {
      return {'trend': 'stable', 'rate': 0.0};
    }

    final recent = history.take(6).toList(); // Last 6 data points
    final older = history.skip(6).take(6).toList(); // Previous 6 data points

    if (older.isEmpty) {
      return {'trend': 'stable', 'rate': 0.0};
    }

    final recentAvg =
        recent.fold<double>(0, (sum, state) => sum + state.percentage) /
        recent.length;
    final olderAvg =
        older.fold<double>(0, (sum, state) => sum + state.percentage) /
        older.length;

    final rate = recentAvg - olderAvg;

    String trend;
    if (rate > 2) {
      trend = 'increasing';
    } else if (rate < -2) {
      trend = 'decreasing';
    } else {
      trend = 'stable';
    }

    return {'trend': trend, 'rate': rate};
  }

  /// Test API connection
  static Future<bool> testAPIConnection() async {
    try {
      final url = Uri.parse('$_baseUrl/api/soc/status');
      final response = await http.get(url).timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('SOC API connection test failed: $e');
      return false;
    }
  }

  /// Submit charge feedback for ML training
  static Future<Map<String, dynamic>> submitChargeFeedback({
    required String vehicleId,
    required String predictionId,
    required int predictedDurationMinutes,
    required double actualSOC,
    required double targetSOC,
    required String chargingMode,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/ai/charge-feedback');
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Cần đăng nhập trước khi gửi phản hồi sạc');
      }
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'vehicleId': vehicleId,
              'predictionId': predictionId,
              'predictedDurationMinutes': predictedDurationMinutes,
              'actualSOC': actualSOC,
              'targetSOC': targetSOC,
              'chargingMode': chargingMode,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to submit feedback: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error submitting charge feedback: $e');
      rethrow;
    }
  }

  /// Get charging model status
  static Future<Map<String, dynamic>> getChargingModelStatus() async {
    try {
      final url = Uri.parse('$_baseUrl/api/ai/charging-model-status');
      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get model status: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting charging model status: $e');
      return {
        'status': 'error',
        'message': e.toString(),
        'version': 'unknown',
        'samples': 0,
      };
    }
  }
}
