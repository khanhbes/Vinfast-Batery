import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/smart_charger_binding.dart';
import '../models/smart_charger_capabilities.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';
import '../models/shelly_connection.dart';
import 'smart_charger_service.dart';

class ServerSmartChargerService {
  ServerSmartChargerService({http.Client? client, FirebaseAuth? auth})
    : _client = client ?? http.Client(),
      _auth = auth ?? FirebaseAuth.instance;

  final http.Client _client;
  final FirebaseAuth _auth;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const SmartChargerException(
        'Cần đăng nhập để dùng Easy Connect.',
        code: 'unauthorized',
      );
    }
    final uri = Uri.parse('${AppConstants.apiBaseUrl}$path');
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        ...?headers,
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      final error = decoded['error'] is Map
          ? Map<String, dynamic>.from(decoded['error'] as Map)
          : const <String, dynamic>{};
      throw SmartChargerException(
        error['message']?.toString() ??
            'Không thể kết nối dịch vụ Sạc thông minh.',
        statusCode: response.statusCode,
        code: error['code']?.toString(),
        retryable: error['retryable'] == true,
      );
    }
    final data = decoded['data'];
    if (data == null) return const {'_null': true};
    return data is Map ? Map<String, dynamic>.from(data) : {'items': data};
  }

  Future<SmartChargerBinding?> getBinding() async {
    final data = await _request('GET', '/api/shelly/device');
    return data['_null'] == true ? null : SmartChargerBinding.fromJson(data);
  }

  Future<SmartChargerCapabilities> getCapabilities() async =>
      SmartChargerCapabilities.fromJson(
        await _request('GET', '/api/shelly/capabilities'),
      );

  Future<Map<String, dynamic>> startConsent() =>
      _request('POST', '/api/shelly/consent/start');

  Future<void> revokeBinding() async =>
      _request('DELETE', '/api/shelly/device');

  Future<SmartChargerStatus> getStatus() async {
    final raw = await _request('GET', '/api/smart-charging/status');
    final status = SmartChargerStatus.fromJson(raw);
    SmartChargerBinding? selected;
    try {
      selected = await getBinding();
    } on SmartChargerException {
      // Telemetry remains useful even if binding metadata refresh fails.
    }
    return SmartChargerStatus(
      online: status.online,
      relay: status.relay,
      powerW: status.powerW,
      voltageV: status.voltageV,
      currentA: status.currentA,
      frequencyHz: status.frequencyHz,
      temperatureC: status.temperatureC,
      energyWh: status.energyWh,
      timerRemaining: status.timerRemaining,
      transport: ShellyTransport.cloud,
      deviceName: selected?.displayName ?? 'Shelly sạc xe',
    );
  }

  Future<SmartChargingPlanPreview> createPreview(
    SmartChargingPlanDraft draft,
  ) async {
    final data = await _request(
      'POST',
      '/api/smart-charging/preview',
      body: {
        'vehicleId': draft.vehicleId,
        'currentSoc': draft.currentSoc,
        'targetSoc': draft.targetSoc,
        'chargingMode': draft.chargingMode,
        'estimatedCapacityWh': draft.estimatedCapacityWh,
        // Compatibility with the currently deployed predictor contract.
        'batteryCapacityWh': draft.estimatedCapacityWh,
      },
    );
    final minutes = (data['predictedMinutes'] as num).round();
    final stop = DateTime.parse(data['predictedStopAt'].toString());
    final warnings = ((data['warnings'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList();
    if (draft.estimatedCapacityWh <= 0) {
      warnings.add(
        'Chưa có dung lượng pin; các chỉ số Wh/SOC sau sạc sẽ để trống.',
      );
    }
    return SmartChargingPlanPreview(
      draft: draft,
      predictedMinutes: minutes,
      aiStopAt: stop,
      effectiveStopAt: stop,
      predictionSource: data['modelSource']?.toString() ?? 'physics_fallback',
      predictionConfidence: (data['confidence'] as num?)?.toDouble(),
      isPhysicsFallback: data['modelSource'] == 'physics_fallback',
      isImpossible: false,
      previewId: data['previewId']?.toString(),
      expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
      predictedDurationSeconds: (data['predictedDurationSeconds'] as num?)
          ?.round(),
      modelKey: data['modelKey']?.toString() ?? 'charging_time',
      modelVersion: data['modelVersion']?.toString() ?? 'unknown',
      runtimeHealth: data['runtimeHealth']?.toString() ?? 'unknown',
      warnings: warnings,
      fallbackReason: data['fallbackReason']?.toString(),
      analyzedAt: DateTime.tryParse(data['analyzedAt']?.toString() ?? ''),
      aiChargeEligible: data['aiChargeEligible'] == true,
    );
  }

  Future<SmartChargingSession> start(
    SmartChargingPlanPreview preview,
    String key,
  ) async {
    final id = preview.previewId;
    if (id == null) {
      throw const SmartChargerException(
        'Dự đoán server không hợp lệ.',
        code: 'previewMissing',
      );
    }
    return SmartChargingSession.fromJson(
      await _request(
        'POST',
        '/api/smart-charging/sessions',
        body: {'previewId': id},
        headers: {'Idempotency-Key': key},
      ),
    );
  }

  Future<SmartChargingSession?> current() async {
    final data = await _request('GET', '/api/smart-charging/session/current');
    return data['_null'] == true ? null : SmartChargingSession.fromJson(data);
  }

  Future<List<SmartChargingSession>> history({int limit = 20}) async {
    final data = await _request(
      'GET',
      '/api/smart-charging/sessions?limit=$limit',
    );
    return ((data['items'] as List?) ?? const [])
        .map(
          (item) => SmartChargingSession.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<SmartChargingSession?> off([String? sessionId]) async {
    final data = await _request(
      'POST',
      sessionId == null
          ? '/api/smart-charging/off'
          : '/api/smart-charging/session/$sessionId/stop',
    );
    return data['_null'] == true ? null : SmartChargingSession.fromJson(data);
  }

  Future<SmartChargingSession> manualOn(
    Duration duration, {
    required String idempotencyKey,
    required String vehicleId,
    required double currentSoc,
  }) async => SmartChargingSession.fromJson(
    await _request(
      'POST',
      '/api/smart-charging/on',
      body: {
        'durationSeconds': duration.inSeconds,
        'vehicleId': vehicleId,
        'currentSoc': currentSoc,
      },
      headers: {'Idempotency-Key': idempotencyKey},
    ),
  );
}
