import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/charge_log_model.dart';

// =============================================================================
// AI PREDICTION SERVICE — Gọi Flask API dự đoán chai pin
// =============================================================================

/// Key lưu URL AI trong SharedPreferences
const kAiBaseUrlKey = 'ai_base_url';

/// URL mặc định (Android emulator → localhost)
const kAiBaseUrlDefault = 'http://10.0.2.2:5001';

class AiPredictionService {
  String _baseUrl = kAiBaseUrlDefault;
  String get baseUrl => _baseUrl;

  /// Load URL từ SharedPreferences (gọi 1 lần khi init)
  Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(kAiBaseUrlKey) ?? kAiBaseUrlDefault;
  }

  /// Cập nhật URL mới và lưu SharedPreferences
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAiBaseUrlKey, _baseUrl);
  }

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

/// Riverpod provider (singleton, URL loaded lazily)
final aiPredictionServiceProvider = Provider<AiPredictionService>((ref) {
  final service = AiPredictionService();
  // Load URL từ SharedPreferences (fire-and-forget, non-blocking)
  service.loadBaseUrl();
  return service;
});
