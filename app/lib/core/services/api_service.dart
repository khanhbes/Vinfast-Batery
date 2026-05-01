import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';

/// API Service for backend communication
/// Handles authentication and provides typed API methods
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String get _baseUrl => AppConstants.apiBaseUrl;

  /// Public getter for baseUrl
  String get baseUrl => _baseUrl;

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
    };
  }

  /// GET request helper
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final headers = await getHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}: ${response.body}'};
    } on TimeoutException {
      return {'success': false, 'error': 'Request timeout'};
    } catch (e) {
      return {'success': false, 'error': 'Network error: $e'};
    }
  }

  /// POST request helper
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    return _post(endpoint, body);
  }

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
    return get('/api/ai/charging-model-status');
  }

  /// Lấy catalog AI models cho app (user-facing, chỉ deployed)
  Future<Map<String, dynamic>> getUserAiModels() async {
    return get('/api/user/ai/models/deployed');
  }

  /// Predict qua server khi local model không khả dụng
  Future<Map<String, dynamic>> predictWithServer(
    String typeKey,
    Map<String, dynamic> input,
  ) async {
    return _post('/api/user/ai/models/$typeKey/predict', input);
  }

  /// Lấy sync overview (bootstrap khi login)
  Future<Map<String, dynamic>> getSyncOverview() async {
    return get('/api/user/sync/overview');
  }

  /// Full sync snapshot lên server
  Future<Map<String, dynamic>> syncFull(Map<String, dynamic> payload) async {
    return _post('/api/web/sync/full', payload);
  }

  /// Download URL cho model .tflite
  String modelDownloadUrl(String typeKey) =>
      '$_baseUrl/api/user/ai/models/$typeKey/download';
}
