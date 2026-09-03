import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_constants.dart';
import 'app_error_reporter.dart';

/// Exception thrown or logged during API requests.
class ApiException implements Exception {
  ApiException({
    required this.endpoint,
    this.statusCode,
    this.message,
    this.responseBody,
    this.debugCode,
    this.debugDetail,
  });

  final String endpoint;
  final int? statusCode;
  final String? message;
  final String? responseBody;
  final String? debugCode;
  final String? debugDetail;

  @override
  String toString() {
    final sb = StringBuffer('ApiException');
    if (statusCode != null) sb.write(' (HTTP $statusCode)');
    sb.write(
      ' on $endpoint: ${message ?? responseBody ?? "Unknown API error"}',
    );
    if (debugCode != null) sb.write(' [$debugCode]');
    return sb.toString();
  }
}

/// API Service for backend communication
/// Handles authentication, error reporting, and provides typed API methods
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String get _baseUrl => AppConstants.apiBaseUrl;

  /// Public getter for baseUrl
  String get baseUrl => _baseUrl;

  /// Get auth headers with Firebase token (public for repository use)
  Future<Map<String, String>> getHeaders() async {
    try {
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
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        source: 'FirebaseAuth',
        debugCode: 'AUTH_TOKEN_ERROR',
      );
      return {'Content-Type': 'application/json', 'Accept': 'application/json'};
    }
  }

  /// GET request helper
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final headers = await getHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl$endpoint'), headers: headers)
          .timeout(const Duration(seconds: 30));

      return _handleResponse(endpoint, response);
    } on TimeoutException catch (e, stack) {
      final err = ApiException(
        endpoint: endpoint,
        message: 'Yêu cầu hết thời gian chờ (Timeout).',
        debugCode: 'GET_TIMEOUT',
      );
      AppErrorReporter.report(
        err,
        stack,
        source: 'ApiService',
        endpoint: endpoint,
        debugCode: 'GET_TIMEOUT',
      );
      return {
        'success': false,
        'error': 'Yêu cầu hết thời gian chờ (Timeout).',
      };
    } on SocketException catch (e, stack) {
      final err = ApiException(
        endpoint: endpoint,
        message: 'Không thể kết nối tới máy chủ (${e.message}).',
        debugCode: 'SOCKET_EXCEPTION',
      );
      AppErrorReporter.report(
        err,
        stack,
        source: 'ApiService',
        endpoint: endpoint,
        debugCode: 'SOCKET_EXCEPTION',
      );
      return {'success': false, 'error': 'Không thể kết nối tới máy chủ.'};
    } catch (e, stack) {
      final err = ApiException(
        endpoint: endpoint,
        message: e.toString(),
        debugCode: 'GET_ERROR',
      );
      AppErrorReporter.report(
        err,
        stack,
        source: 'ApiService',
        endpoint: endpoint,
        debugCode: 'GET_ERROR',
      );
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
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
      final response = await http
          .post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      return _handleResponse(endpoint, response);
    } on TimeoutException catch (e, stack) {
      final err = ApiException(
        endpoint: endpoint,
        message: 'Yêu cầu hết thời gian chờ (Timeout).',
        debugCode: 'POST_TIMEOUT',
      );
      AppErrorReporter.report(
        err,
        stack,
        source: 'ApiService',
        endpoint: endpoint,
        debugCode: 'POST_TIMEOUT',
      );
      return {
        'success': false,
        'error': 'Yêu cầu hết thời gian chờ (Timeout).',
      };
    } on SocketException catch (e, stack) {
      final err = ApiException(
        endpoint: endpoint,
        message: 'Không thể kết nối tới máy chủ (${e.message}).',
        debugCode: 'SOCKET_EXCEPTION',
      );
      AppErrorReporter.report(
        err,
        stack,
        source: 'ApiService',
        endpoint: endpoint,
        debugCode: 'SOCKET_EXCEPTION',
      );
      return {'success': false, 'error': 'Không thể kết nối tới máy chủ.'};
    } catch (e, stack) {
      final err = ApiException(
        endpoint: endpoint,
        message: e.toString(),
        debugCode: 'POST_ERROR',
      );
      AppErrorReporter.report(
        err,
        stack,
        source: 'ApiService',
        endpoint: endpoint,
        debugCode: 'POST_ERROR',
      );
      return {'success': false, 'error': 'Lỗi kết nối: $e'};
    }
  }

  Map<String, dynamic> _handleResponse(
    String endpoint,
    http.Response response,
  ) {
    Map<String, dynamic>? parsedJson;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        parsedJson = decoded;
      }
    } catch (e, stack) {
      if (response.statusCode != 200) {
        final err = ApiException(
          endpoint: endpoint,
          statusCode: response.statusCode,
          message: 'HTTP ${response.statusCode}: ${response.body}',
          responseBody: response.body,
          debugCode: 'HTTP_PARSE_ERROR',
        );
        AppErrorReporter.report(
          err,
          stack,
          source: 'ApiService',
          endpoint: endpoint,
          statusCode: response.statusCode,
          debugCode: 'HTTP_PARSE_ERROR',
        );
        return {
          'success': false,
          'statusCode': response.statusCode,
          'error': 'HTTP ${response.statusCode}: ${response.body}',
        };
      }
    }

    if (response.statusCode == 200) {
      return parsedJson ?? <String, dynamic>{'success': true};
    }

    final errorMessage =
        parsedJson?['error']?.toString() ??
        'HTTP ${response.statusCode}: ${response.body}';
    final debugCode =
        parsedJson?['debugCode']?.toString() ?? 'HTTP_${response.statusCode}';
    final debugDetail = parsedJson?['debugDetail']?.toString();

    final apiError = ApiException(
      endpoint: endpoint,
      statusCode: response.statusCode,
      message: errorMessage,
      responseBody: response.body,
      debugCode: debugCode,
      debugDetail: debugDetail,
    );

    AppErrorReporter.report(
      apiError,
      StackTrace.current,
      source: 'ApiService',
      endpoint: endpoint,
      statusCode: response.statusCode,
      debugCode: debugCode,
      debugDetail: debugDetail,
    );

    return {
      'success': false,
      'statusCode': response.statusCode,
      'error': errorMessage,
      'debugCode': debugCode,
      if (debugDetail != null) 'debugDetail': debugDetail,
    };
  }

  /// Predict charging time using AI Center model
  ///
  /// Response format for the synchronized backend API:
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
    bool strictAi = false,
  }) async {
    return _post('/api/ai/predict-charging-time', {
      'vehicleId': vehicleId,
      'currentBattery': currentBattery,
      'targetBattery': targetBattery,
      'ambientTempC': ambientTempC ?? 25.0, // Default 25°C
      'strictAi': strictAi,
    });
  }

  /// Canonical Smart Charge preview contract. The server owns model
  /// selection, personal-profile fusion and safety validation; the app never
  /// runs a charging-time model locally.
  Future<Map<String, dynamic>> previewSmartCharge({
    required String vehicleId,
    required int currentBattery,
    required int targetBattery,
    double? ambientTempC,
    bool strictAi = true,
  }) async {
    return _post('/api/smart-charging/preview', {
      'vehicleId': vehicleId,
      'currentSoc': currentBattery,
      'targetSoc': targetBattery,
      'ambientTempC': ambientTempC ?? 25.0,
      'strictAi': strictAi,
    });
  }

  /// Get AI Center charging_time model status
  Future<Map<String, dynamic>> getChargingModelStatus() async {
    return get('/api/ai/charging-model-status');
  }

  Future<Map<String, dynamic>> predictRemainingRange({
    required int batteryPercent,
    required double stateOfHealth,
    required double baseEfficiencyKmPerPercent,
    double temperatureC = 30,
    double averageSpeedKmh = 35,
    double payloadKg = 75,
  }) async {
    return _post('/api/ai/predict-range', {
      'batteryPercent': batteryPercent,
      'stateOfHealth': stateOfHealth,
      'baseEfficiencyKmPerPercent': baseEfficiencyKmPerPercent,
      'temperatureC': temperatureC,
      'averageSpeedKmh': averageSpeedKmh,
      'payloadKg': payloadKg,
      'reservePercent': 5,
    });
  }

  /// Lấy catalog AI models cho app (canonical — tất cả models + flat status schema)
  Future<Map<String, dynamic>> getUserAiModels() async {
    return get('/api/user/ai/models');
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
