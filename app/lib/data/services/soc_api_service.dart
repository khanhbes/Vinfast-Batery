import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'soc_prediction_service.dart';

/// ========================================================================
/// SOC API SERVICE - HTTP server cho web dashboard gọi AI model
/// ========================================================================
/// 
/// Cung cấp REST API endpoints:
/// - POST /api/soc/predict - Dự đoán SOC
/// - GET /api/soc/status - Trạng thái model
/// - GET /api/soc/history/{vehicleId} - Lịch sử dự đoán

class SOCApiService {
  final SOCPredictionService _socService;
  HttpServer? _server;
  static const int _defaultPort = 8080;

  SOCApiService(this._socService);

  /// Start HTTP server
  Future<void> startServer({int port = _defaultPort}) async {
    if (_server != null) {
      print('⚠️ Server already running on port ${_server!.port}');
      return;
    }

    try {
      _server = await HttpServer.bind('localhost', port);
      print('🚀 SOC API Server started on http://localhost:$port');

      await for (HttpRequest request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      print('❌ Failed to start SOC API server: $e');
      throw Exception('Failed to start server: $e');
    }
  }

  /// Stop HTTP server
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      print('🛑 SOC API Server stopped');
    }
  }

  /// Handle incoming requests
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

      // Handle CORS preflight
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }

      final path = request.uri.path;
      final method = request.method;

      print('📡 $method $path');

      switch ('$method $path') {
        case 'POST /api/soc/predict':
          await _handlePredict(request, response);
          break;
        case 'GET /api/soc/status':
          await _handleStatus(request, response);
          break;
        case 'GET /api/soc/history':
          await _handleHistory(request, response);
          break;
        default:
          _sendError(response, HttpStatus.notFound, 'Endpoint not found: $method $path');
      }
    } catch (e) {
      print('❌ Error handling request: $e');
      _sendError(request.response, HttpStatus.internalServerError, 'Internal server error: $e');
    }
  }

  /// Handle SOC prediction request
  Future<void> _handlePredict(HttpRequest request, HttpResponse response) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = json.decode(body) as Map<String, dynamic>;

      // Validate input
      if (!_validatePredictInput(data)) {
        _sendError(response, HttpStatus.badRequest, 'Invalid input data');
        return;
      }

      // Create prediction input
      final input = SOCPredictionInput(
        currentBattery: (data['currentBattery'] as num).toDouble(),
        temperature: (data['temperature'] as num).toDouble(),
        voltage: (data['voltage'] as num).toDouble(),
        current: (data['current'] as num).toDouble(),
        odometer: (data['odometer'] as num).toDouble(),
        timeOfDay: data['timeOfDay'] as int,
        dayOfWeek: data['dayOfWeek'] as int,
        avgSpeed: (data['avgSpeed'] as num).toDouble(),
        elevationGain: (data['elevationGain'] as num).toDouble(),
        weatherCondition: data['weatherCondition'] as String,
      );

      // Get prediction
      final result = await _socService.predictSOC(input);

      _sendJson(response, HttpStatus.ok, {
        'success': true,
        'data': result.toJson(),
      });
    } catch (e) {
      print('❌ Error in predict endpoint: $e');
      _sendError(response, HttpStatus.internalServerError, 'Prediction failed: $e');
    }
  }

  /// Handle model status request
  Future<void> _handleStatus(HttpRequest request, HttpResponse response) async {
    try {
      final status = _socService.getModelStatus();
      
      _sendJson(response, HttpStatus.ok, {
        'success': true,
        'data': status,
      });
    } catch (e) {
      print('❌ Error in status endpoint: $e');
      _sendError(response, HttpStatus.internalServerError, 'Status check failed: $e');
    }
  }

  /// Handle prediction history request
  Future<void> _handleHistory(HttpRequest request, HttpResponse response) async {
    try {
      final vehicleId = request.uri.queryParameters['vehicleId'];
      final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '10') ?? 10;

      if (vehicleId == null || vehicleId.isEmpty) {
        _sendError(response, HttpStatus.badRequest, 'vehicleId parameter required');
        return;
      }

      final history = await _socService.getPredictionHistory(vehicleId, limit: limit);

      _sendJson(response, HttpStatus.ok, {
        'success': true,
        'data': {
          'vehicleId': vehicleId,
          'predictions': history.map((h) => h.toJson()).toList(),
          'count': history.length,
        },
      });
    } catch (e) {
      print('❌ Error in history endpoint: $e');
      _sendError(response, HttpStatus.internalServerError, 'History retrieval failed: $e');
    }
  }

  /// Validate predict input
  bool _validatePredictInput(Map<String, dynamic> data) {
    final requiredFields = [
      'currentBattery', 'temperature', 'voltage', 'current',
      'odometer', 'timeOfDay', 'dayOfWeek', 'avgSpeed',
      'elevationGain', 'weatherCondition'
    ];

    for (final field in requiredFields) {
      if (!data.containsKey(field)) {
        print('❌ Missing required field: $field');
        return false;
      }
    }

    // Validate ranges
    final battery = data['currentBattery'] as num;
    if (battery < 0 || battery > 100) {
      print('❌ Invalid battery percentage: $battery');
      return false;
    }

    final timeOfDay = data['timeOfDay'] as int;
    if (timeOfDay < 0 || timeOfDay > 23) {
      print('❌ Invalid timeOfDay: $timeOfDay');
      return false;
    }

    final dayOfWeek = data['dayOfWeek'] as int;
    if (dayOfWeek < 0 || dayOfWeek > 6) {
      print('❌ Invalid dayOfWeek: $dayOfWeek');
      return false;
    }

    return true;
  }

  /// Send JSON response
  void _sendJson(HttpResponse response, int statusCode, Map<String, dynamic> data) {
    response.statusCode = statusCode;
    response.write(json.encode(data));
    response.close();
  }

  /// Send error response
  void _sendError(HttpResponse response, int statusCode, String message) {
    _sendJson(response, statusCode, {
      'success': false,
      'error': message,
    });
  }

  /// Get server status
  bool get isRunning => _server != null;
  int? get port => _server?.port;
}

/// Provider cho SOCApiService
final socApiServiceProvider = Provider<SOCApiService>((ref) {
  final socService = ref.watch(socPredictionServiceProvider);
  return SOCApiService(socService);
});
