import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/smart_charger_binding.dart';
import '../models/smart_charger_capabilities.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';
import '../models/personal_charging_profile.dart';
import '../models/smart_charge_history.dart';
import '../models/shelly_connection.dart';
import 'smart_charger_service.dart';

class ServerSmartChargerService {
  ServerSmartChargerService({http.Client? client, FirebaseAuth? auth})
    : _client = client ?? http.Client(),
      _auth = auth ?? FirebaseAuth.instance;

  final http.Client _client;
  final FirebaseAuth _auth;

  /// Metadata returned by the server vault resolver. Secrets are populated
  /// only after [restoreDirectProfile] succeeds over authenticated HTTPS.
  Future<Map<String, dynamic>?> resolveDirectProfile({String? vehicleId}) async {
    final data = await _request(
      'POST',
      '/api/shelly/profiles/resolve',
      body: {if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId},
    );
    final profile = data['profile'];
    return profile is Map ? Map<String, dynamic>.from(profile) : null;
  }

  Future<List<Map<String, dynamic>>> listDirectProfiles({String? vehicleId}) async {
    final suffix = vehicleId == null || vehicleId.isEmpty
        ? ''
        : '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}';
    final data = await _request('GET', '/api/shelly/profiles$suffix');
    return ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<ShellyConnectionProfile?> restoreDirectProfile(String deviceId) async {
    final data = await _request(
      'POST',
      '/api/shelly/profiles/${Uri.encodeComponent(deviceId)}/restore',
    );
    if (data['_null'] == true || data.isEmpty) return null;
    return ShellyConnectionProfile.fromJson(data);
  }

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

  Future<SmartChargerBinding?> getBinding({String? vehicleId}) async {
    final suffix = vehicleId == null || vehicleId.isEmpty
        ? ''
        : '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}';
    final data = await _request('GET', '/api/shelly/device$suffix');
    return data['_null'] == true ? null : SmartChargerBinding.fromJson(data);
  }

  /// Associate an already-owned physical Shelly with the selected vehicle.
  /// The server validates vehicle ownership; no credentials are sent here.
  Future<SmartChargerBinding> selectDevice(
    String deviceId, {
    required String vehicleId,
    bool shared = false,
  }) async => SmartChargerBinding.fromJson(
    await _request(
      'POST',
      '/api/shelly/devices/${Uri.encodeComponent(deviceId)}/select',
      body: {'vehicleId': vehicleId, 'shared': shared},
    ),
  );

  Future<SmartChargerCapabilities> getCapabilities({String? vehicleId}) async {
    final suffix = vehicleId == null || vehicleId.isEmpty
        ? ''
        : '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}';
    return SmartChargerCapabilities.fromJson(
      await _request('GET', '/api/shelly/capabilities$suffix'),
    );
  }

  Future<Map<String, dynamic>> startConsent() =>
      _request('POST', '/api/shelly/consent/start');

  /// Register/sync Shelly device credentials with user account on the backend server.
  Future<Map<String, dynamic>> registerShellyDevice(
    ShellyConnectionProfile profile, {
    String? vehicleId,
    int? expectedRevision,
    Map<String, dynamic>? verification,
  }) => _request(
    'PUT',
    '/api/shelly/profiles/${Uri.encodeComponent(profile.deviceId)}',
    body: {
      ...profile.toJson(),
      if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
      if (verification != null) 'verification': verification,
      'source': 'android',
    },
  );

  /// Retrieve registered Shelly connection profile for the current user from backend.
  Future<ShellyConnectionProfile?> fetchRegisteredProfile() async {
    try {
      final metadata = await resolveDirectProfile();
      if (metadata == null) return null;
      return restoreDirectProfile(metadata['deviceId']?.toString() ?? '');
    } on Object {
      return null;
    }
  }

  Future<Map<String, dynamic>> verifyDirectProfile(
    String deviceId,
    Map<String, dynamic> verification,
  ) => _request(
    'POST',
    '/api/shelly/profiles/${Uri.encodeComponent(deviceId)}/verify',
    body: verification,
  );

  Future<void> revokeDirectProfile(String deviceId) async {
    await _request(
      'DELETE',
      '/api/shelly/profiles/${Uri.encodeComponent(deviceId)}',
    );
  }

  Future<void> revokeBinding() async =>
      _request('DELETE', '/api/shelly/device');

  Future<SmartChargerStatus> getStatus({String? vehicleId}) async {
    final raw = await _request(
      'GET',
      '/api/smart-charging/status${vehicleId == null || vehicleId.isEmpty ? '' : '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}'}',
    );
    final status = SmartChargerStatus.fromJson(raw);
    SmartChargerBinding? selected;
    try {
      selected = await getBinding(vehicleId: vehicleId);
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
      etaCandidates: ((data['etaCandidates'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => EtaCandidate.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      fusionReason: data['fusionReason']?.toString() ?? 'global_ai_only',
      profileVersion: data['profileVersion']?.toString(),
      adapterVersion: data['adapterVersion']?.toString(),
      capacityConfidence: (data['capacityConfidence'] as num?)?.toDouble(),
      efficiencyConfidence: (data['efficiencyConfidence'] as num?)?.toDouble(),
      effectiveCapacityWh: (data['effectiveCapacityWh'] as num?)?.toDouble(),
      personalizationStage: data['personalizationStage']?.toString() ?? 'base',
      guardrailClamped:
          data['guardrail'] is Map &&
          (data['guardrail'] as Map)['clamped'] == true,
      guardrailWarnings: data['guardrail'] is Map
          ? (((data['guardrail'] as Map)['warnings'] as List?) ?? const [])
                .map((item) => item.toString())
                .toList()
          : const [],
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

  Future<SmartChargingSession?> current({String? vehicleId}) async {
    final data = await _request(
      'GET',
      '/api/smart-charging/session/current${vehicleId == null || vehicleId.isEmpty ? '' : '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}'}',
    );
    return data['_null'] == true ? null : SmartChargingSession.fromJson(data);
  }

  /// V4 global view used by the dashboard/persistent charging pill. It does
  /// not change the selected vehicle context.
  Future<List<SmartChargingSession>> activeSessions() async {
    final data = await _request('GET', '/api/smart-charging/sessions/active');
    return ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              SmartChargingSession.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
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

  Future<SmartChargeHistoryPage> historyPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
    String? vehicleId,
  }) async {
    final query = <String>[
      'limit=$limit',
      if (cursor != null && cursor.isNotEmpty)
        'cursor=${Uri.encodeQueryComponent(cursor)}',
      if (strategy != null) 'strategy=${strategy.wireValue}',
      if (vehicleId != null && vehicleId.isNotEmpty)
        'vehicleId=${Uri.encodeQueryComponent(vehicleId)}',
    ].join('&');
    final data = await _request('GET', '/api/smart-charging/history?$query');
    return SmartChargeHistoryPage(
      items: ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                SmartChargingSession.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      nextCursor: data['nextCursor']?.toString(),
    );
  }

  Future<SmartChargingSession?> off({
    String? sessionId,
    String? vehicleId,
  }) async {
    final query = sessionId == null && vehicleId != null && vehicleId.isNotEmpty
        ? '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}'
        : '';
    final data = await _request(
      'POST',
      sessionId == null
          ? '/api/smart-charging/off$query'
          : '/api/smart-charging/session/$sessionId/stop',
    );
    return data['_null'] == true ? null : SmartChargingSession.fromJson(data);
  }

  Future<SmartChargingSession?> stop(
    String sessionId, {
    required int expectedVersion,
    String userStopReason = 'none',
  }) async {
    final data = await _request(
      'POST',
      '/api/smart-charging/session/$sessionId/stop',
      body: {
        'expectedVersion': expectedVersion,
        'userStopReason': userStopReason,
      },
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

  Future<PersonalChargingProfile> getPersonalProfile(String vehicleId) async =>
      PersonalChargingProfile.fromJson(
        await _request(
          'GET',
          '/api/smart-charging/personal-profile/$vehicleId',
        ),
      );

  Future<PersonalChargingProfile> setPersonalAiConsent(
    String vehicleId,
    bool enabled,
  ) async => PersonalChargingProfile.fromJson(
    await _request(
      'PUT',
      '/api/smart-charging/personal-profile/$vehicleId',
      body: {'consentEnabled': enabled},
    ),
  );

  Future<void> deletePersonalProfile(String vehicleId) async =>
      _request('DELETE', '/api/smart-charging/personal-profile/$vehicleId');

  Future<void> hideSession(String sessionId) async =>
      _request('POST', '/api/smart-charging/sessions/$sessionId/hide');

  Future<void> privacyEraseSession(
    String sessionId,
    String confirmation,
  ) async {
    await _request(
      'DELETE',
      '/api/smart-charging/sessions/$sessionId/privacy-erase',
      body: {'confirmation': confirmation},
    );
  }

  Future<bool> developerTrainingAccess() async {
    try {
      final data = await _request(
        'GET',
        '/api/smart-charging/developer/training-access',
      );
      return data['canEditTrainingData'] == true;
    } on SmartChargerException catch (error) {
      if (error.statusCode == 403 || error.code == 'developerRequired') {
        return false;
      }
      rethrow;
    }
  }

  Future<void> reviewTrainingSample({
    required String sessionId,
    required String vehicleId,
    required bool trainingExcluded,
    required String developerNote,
    double? durationSecondsOverride,
    double? predictedMinutesOverride,
  }) async {
    await _request(
      'PATCH',
      '/api/smart-charging/developer/training-samples/${Uri.encodeComponent(sessionId)}',
      body: {
        'vehicleId': vehicleId,
        'trainingExcluded': trainingExcluded,
        'developerNote': developerNote,
        'durationSecondsOverride': durationSecondsOverride,
        'predictedMinutesOverride': predictedMinutesOverride,
      },
    );
  }

  Future<Map<String, dynamic>> ingestPersonalTraining(String sessionId) =>
      _request(
        'POST',
        '/api/smart-charging/personal/ingest-session',
        body: {'sessionId': sessionId},
      );

  Future<List<SmartChargeTelemetryPoint>> telemetry(String sessionId) async {
    final data = await _request(
      'GET',
      '/api/smart-charging/sessions/$sessionId/telemetry',
    );
    return ((data['items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) => SmartChargeTelemetryPoint.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<void> recordTelemetry(
    String sessionId,
    SmartChargerStatus status,
  ) async {
    await _request(
      'POST',
      '/api/smart-charging/sessions/$sessionId/telemetry',
      body: {
        'powerW': status.powerW,
        'voltageV': status.voltageV,
        'currentA': status.currentA,
        'temperatureC': status.temperatureC,
        'energyWh': status.energyWh,
        'relay': status.relay,
        'timerRemainingSeconds': status.timerRemaining?.inSeconds,
        'transport': status.transport?.name,
      },
    );
  }

  Future<SmartChargingSession> confirmActualSoc(
    String sessionId,
    double soc,
  ) async => SmartChargingSession.fromJson(
    await _request(
      'PATCH',
      '/api/smart-charging/sessions/$sessionId/actual-soc',
      body: {'actualSoc': soc},
    ),
  );
}
