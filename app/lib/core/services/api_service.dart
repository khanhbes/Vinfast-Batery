import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// API Service for backend communication
/// Handles authentication and provides typed API methods
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Backend URL - update for production
  static const String _baseUrl = 'https://your-backend-url.com';
  static const String _apiKey = 'your-api-key'; // For dev testing

  /// Public getter for baseUrl
  String get baseUrl => _baseUrl;

  /// Public getter for API key
  String get apiKey => _apiKey;

  /// Get auth headers with Firebase token (public for repository use)
  Future<Map<String, String>> getHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    String? token;
    if (user != null) {
      token = await user.getIdToken();
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      'X-API-Key': _apiKey,
    };
  }

  /// POST request helper
  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      final headers = await getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Request timeout',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  /// Predict charging time using AI Center model
  /// 
  /// Response format per PLAN1.md:
  /// {
  ///   'predictedDurationSec': double,
  ///   'predictedDurationMin': double,
  ///   'formattedDuration': string,
  ///   'modelSource': string,
  ///   'modelVersion': string,
  ///   'isBeta': bool,
  ///   'confidence': double,
  ///   'warnings': List<String>,
  ///   // Backward compat
  ///   'estimatedMinutes': double,
  ///   'formattedTime': string,
  /// }
  Future<Map<String, dynamic>> predictChargingTime({
    required String vehicleId,
    required int currentBattery,
    required int targetBattery,
    double? ambientTempC,
  }) async {
    return _post('/api/ai/predict-charging-time', {
      'vehicleId': vehicleId,
      'currentBattery': currentBattery,
      'targetBattery': targetBattery,
      'ambientTempC': ambientTempC ?? 25.0, // Default 25°C
    });
  }

  /// Get AI Center charging_time model status
  Future<Map<String, dynamic>> getChargingModelStatus() async {
    try {
      final headers = await getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/api/ai/charging-model-status'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'active': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'active': false, 'error': '$e'};
    }
  }
}
