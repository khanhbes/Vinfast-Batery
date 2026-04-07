import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/charge_log_model.dart';

// =============================================================================
// AI PREDICTION SERVICE — Gọi Flask API dự đoán chai pin
// =============================================================================

class AiPredictionService {
  /// URL của Flask AI API (đổi IP khi deploy)
  static const String _baseUrl = 'http://10.0.2.2:5001'; // Android emulator → localhost

  /// Dự đoán mức độ chai pin
  Future<Map<String, dynamic>?> predictDegradation({
    required String vehicleId,
    required List<ChargeLogModel> chargeLogs,
  }) async {
    if (chargeLogs.length < 3) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/predict-degradation'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'vehicleId': vehicleId,
              'chargeLogs': chargeLogs.map((l) => l.toMap()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return null;
    } catch (e) {
      // API không available → trả null, app vẫn hoạt động bình thường
      return null;
    }
  }

  /// Phân tích thói quen sạc
  Future<Map<String, dynamic>?> analyzePatterns({
    required String vehicleId,
    required List<ChargeLogModel> chargeLogs,
  }) async {
    if (chargeLogs.length < 3) return null;

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/analyze-patterns'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'vehicleId': vehicleId,
              'chargeLogs': chargeLogs.map((l) => l.toMap()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['data'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Kiểm tra AI API có hoạt động không
  Future<bool> isAvailable() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

/// Riverpod provider
final aiPredictionServiceProvider = Provider<AiPredictionService>((ref) {
  return AiPredictionService();
});
