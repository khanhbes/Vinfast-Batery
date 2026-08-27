import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';

class SmartChargerException implements Exception {
  const SmartChargerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SmartChargerService {
  SmartChargerService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = (baseUrl ?? AppConstants.smartChargerApiBaseUrl).replaceAll(
        RegExp(r'/$'),
        '',
      );

  static const Duration _timeout = Duration(seconds: 3);

  final http.Client _client;
  final String baseUrl;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<SmartChargerStatus> getStatus() async {
    final json = await _request('GET', '/api/charger/status');
    try {
      return SmartChargerStatus.fromJson(json);
    } on FormatException catch (error) {
      throw SmartChargerException(error.message);
    }
  }

  Future<SmartChargerCommandResult> turnOn() => _command('/api/charger/on');

  Future<SmartChargerCommandResult> turnOff() => _command('/api/charger/off');

  Future<SmartChargingSessionResponse> startMonitoringSession(
    SmartChargingSessionRequest request,
  ) async {
    final json = await _request(
      'POST',
      '/api/charging/session',
      body: request.toJson(),
    );
    try {
      return SmartChargingSessionResponse.fromJson(json);
    } on FormatException catch (error) {
      throw SmartChargerException(error.message);
    }
  }

  Future<SmartChargerCommandResult> _command(String path) async {
    final json = await _request('POST', path);
    try {
      return SmartChargerCommandResult.fromJson(json);
    } on FormatException catch (error) {
      throw SmartChargerException(error.message);
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!isConfigured) {
      throw const SmartChargerException('Smart Charger chưa được cấu hình.');
    }

    final uri = Uri.tryParse('$baseUrl$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SmartChargerException('Địa chỉ Smart Charger không hợp lệ.');
    }

    try {
      final response = method == 'GET'
          ? await _client.get(uri).timeout(_timeout)
          : await _client
                .post(
                  uri,
                  headers: const {'Content-Type': 'application/json'},
                  body: body == null ? null : jsonEncode(body),
                )
                .timeout(_timeout);

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw SmartChargerException(
          'Gateway trả về dữ liệu không hợp lệ.',
          statusCode: response.statusCode,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw SmartChargerException(
          'Gateway trả về dữ liệu không hợp lệ.',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded['detail']?.toString();
        throw SmartChargerException(
          detail?.isNotEmpty == true
              ? detail!
              : 'Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on SmartChargerException {
      rethrow;
    } on TimeoutException {
      throw const SmartChargerException(
        'Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.',
      );
    } on SocketException {
      throw const SmartChargerException(
        'Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.',
      );
    } on http.ClientException {
      throw const SmartChargerException(
        'Không thể kết nối bộ điều khiển sạc trong mạng Wi-Fi.',
      );
    }
  }
}
