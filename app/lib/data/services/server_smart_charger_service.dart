import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/utils/app_error_formatter.dart';
import '../models/smart_charger_binding.dart';
import '../models/smart_charger_capabilities.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charging_session.dart';
import '../models/personal_charging_profile.dart';
import '../models/smart_charge_history.dart';
import '../models/shelly_connection.dart';
import 'smart_charger_service.dart';
import 'shelly_api_transport.dart';

class ServerSmartChargerService {
  ServerSmartChargerService({
    http.Client? client,
    FirebaseAuth? auth,
    bool Function()? requestValid,
  }) : _client = client ?? http.Client(),
       _requestValid = requestValid,
       _auth = auth ?? FirebaseAuth.instance;

  final http.Client _client;
  final FirebaseAuth _auth;
  final bool Function()? _requestValid;
  bool _closed = false;

  /// Release the client owned by this service, including pending requests.
  /// Closing a request is not evidence that a relay command did not arrive.
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  /// Metadata returned by the server vault resolver. Secrets are populated
  /// only after [restoreDirectProfile] succeeds over authenticated HTTPS.
  Future<Map<String, dynamic>?> resolveDirectProfile({
    String? vehicleId,
  }) async {
    final data = await _request(
      'POST',
      '/api/shelly/profiles/resolve',
      body: {
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
      },
    );
    final profile = data['profile'];
    return profile is Map ? Map<String, dynamic>.from(profile) : null;
  }

  Future<List<Map<String, dynamic>>> listDirectProfiles({
    String? vehicleId,
  }) async {
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
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (method != 'GET') forgetLive();
    if (_closed) {
      throw const SmartChargerException(
        'Yêu cầu đã hết hiệu lực. Hãy thử lại.',
        code: 'account_changed',
        statusCode: 401,
      );
    }
    final uri = AppConstants.tryBuildApiUri(path);
    if (uri == null) {
      throw const SmartChargerException(
        'Máy chủ chưa được cấu hình. Vui lòng kiểm tra kết nối mạng.',
        code: 'unconfigured_server',
        statusCode: 503,
        retryable: false,
      );
    }

    if (_closed || _requestValid?.call() == false) {
      throw const SmartChargerException(
        'Yêu cầu đã hết hiệu lực.',
        code: 'account_changed',
        statusCode: 401,
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const SmartChargerException(
        'Vui lòng đăng nhập lại để tiếp tục.',
        code: 'unauthenticated',
        statusCode: 401,
      );
    }
    final token = await user.getIdToken().timeout(const Duration(seconds: 12));
    if (_auth.currentUser?.uid != user.uid ||
        _closed ||
        token == null ||
        _requestValid?.call() == false) {
      throw const SmartChargerException(
        'Phiên đăng nhập đã thay đổi.',
        code: 'account_changed',
        statusCode: 401,
      );
    }
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...?headers,
      });
    if (body != null) request.body = jsonEncode(body);

    final response = await ShellyApiTransport.send(
      _client,
      request,
      timeout: timeout,
    );
    if (_closed ||
        _auth.currentUser?.uid != user.uid ||
        _requestValid?.call() == false) {
      throw const SmartChargerException(
        'Phiên đăng nhập đã thay đổi.',
        code: 'account_changed',
        statusCode: 401,
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw SmartChargerException(
        'Máy chủ phản hồi không đúng định dạng (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
        code: 'invalid_response',
        retryable: response.statusCode >= 500,
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      String? code;
      bool retryable = response.statusCode >= 500;
      final errObj = decoded['error'];
      if (errObj is Map) {
        code = errObj['code']?.toString();
        if (errObj['retryable'] is bool) {
          retryable = errObj['retryable'] as bool;
        }
      }
      code ??= decoded['code']?.toString();
      final message = switch (code) {
        'STAGING_HARDWARE_DISABLED' =>
          'Máy chủ thử nghiệm chưa mở thao tác này. Liên kết Shelly hiện có vẫn được giữ.',
        'bindingVehicleConflict' =>
          'Shelly đang liên kết với xe khác. Hãy chọn lại bộ sạc cho xe này.',
        'bindingChanged' => 'Liên kết đã thay đổi. Hãy xác nhận yêu cầu mới.',
        'vehicleForbidden' => 'Hãy chọn xe hợp lệ thuộc tài khoản này.',
        'DEVICE_MEMBER_LIMIT_REACHED' =>
          'Shelly đã liên kết tối đa hai tài khoản.',
        'connectionCodeUnavailable' ||
        'redemptionRevoked' => 'Mã kết nối không còn hiệu lực. Hãy xin mã mới.',
        'safetyVerificationRequired' =>
          'Cần kiểm tra an toàn bộ sạc trước khi bật.',
        'deviceUnverified' => 'Chưa xác minh được đúng bộ sạc. Hãy thử lại.',
        'unauthorized' ||
        'unauthenticated' => 'Vui lòng đăng nhập lại để tiếp tục.',
        _ => AppErrorFormatter.format(code),
      };
      throw SmartChargerException(
        message,
        statusCode: response.statusCode,
        code: code,
        retryable: retryable,
      );
    }
    final data = decoded['data'];
    if (decoded.containsKey('data') && data == null) return {'_null': true};
    if (data != null) {
      return data is Map ? Map<String, dynamic>.from(data) : {'items': data};
    }
    // Return the root map when 'data' is not specifically separated
    return decoded;
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
      // Full readiness includes a live Cloud safety check that may wait for
      // the shared Cloud slot (up to ~12s server-side) (Task108).
      await _request(
        'GET',
        '/api/shelly/capabilities$suffix',
        timeout: const Duration(seconds: 30),
      ),
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
      'expectedRevision': ?expectedRevision,
      'verification': ?verification,
      'source': Platform.operatingSystem,
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

  Future<void> claimLanDevice({
    required String deviceId,
    required String model,
  }) async {
    await _request(
      'POST',
      '/api/shelly/devices/claim',
      body: {'deviceId': deviceId, 'model': model},
    );
  }

  Future<void> authorizeDeviceControl({
    required String deviceId,
    required String operationId,
  }) async {
    final data = await _request(
      'POST',
      '/api/shelly/devices/${Uri.encodeComponent(deviceId)}/authorize',
      body: {'operationId': operationId},
    );
    if (data['authorized'] != true) {
      throw const SmartChargerException(
        'Không xác minh được quyền điều khiển Shelly.',
        code: 'ownershipUnavailable',
        statusCode: 409,
      );
    }
  }

  Future<void> releaseDeviceControl({
    required String deviceId,
    required String operationId,
  }) async {
    await _request(
      'POST',
      '/api/shelly/devices/${Uri.encodeComponent(deviceId)}/release-control',
      body: {'operationId': operationId, 'relayOffVerified': true},
    );
  }

  Future<Map<String, dynamic>> runSafetyTest({
    required String deviceId,
    required String operationId,
  }) => _request(
    'POST',
    '/api/shelly/devices/${Uri.encodeComponent(deviceId)}/safety-test',
    body: {'operationId': operationId, 'confirmedUnplugged': true},
    // The server-side no-load test spaces Cloud calls (>=1.1s), waits for the
    // 5s device timer to self-OFF and reads back; 12s always timed out (Task108).
    timeout: safetyTestTimeout,
  );

  static const safetyTestTimeout = Duration(seconds: 75);

  /// ON/OFF waits for the shared Cloud slot, sends the command and reads the
  /// relay/timer back server-side; 12s timed out while the relay did switch
  /// (Task108 E3). Retries reuse the same Idempotency-Key.
  static const controlTimeout = Duration(seconds: 45);

  Future<void> revokeBinding() async =>
      _request('DELETE', '/api/shelly/device');

  /// Redeem an admin-generated connection code to bind a Shelly device.
  Future<ShellyConnectionProfile> redeemConnectionCode(
    String code, {
    String? vehicleId,
    String? operationId,
  }) async {
    final raw = await _request(
      'POST',
      '/api/shelly/redeem-code',
      body: {
        'code': code.trim().toUpperCase(),
        'vehicleId': ?vehicleId,
        'operationId': ?operationId,
      },
      headers: {'Idempotency-Key': ?operationId},
    );
    final profileData = raw['profile'] is Map
        ? Map<String, dynamic>.from(raw['profile'] as Map)
        : raw;
    return ShellyConnectionProfile.fromJson(profileData);
  }

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
      shellyTemperatureC: status.shellyTemperatureC,
      batteryTemperatureC: status.batteryTemperatureC,
      energyWh: status.energyWh,
      timerRemaining: status.timerRemaining,
      transport: status.transport ?? ShellyTransport.cloud,
      deviceId: status.deviceId,
      codeRefreshRequired: status.codeRefreshRequired,
      deviceName: selected?.deviceId == status.deviceId
          ? selected?.displayName
          : status.deviceName ?? 'Shelly sạc xe',
    );
  }

  // One /live read shared by every screen, controller instance and the chat
  // within a few seconds (Task108: duplicate polling exhausted Firestore).
  static final Map<String, Future<Map<String, dynamic>>> _liveInFlight = {};
  static final Map<String, (DateTime, Map<String, dynamic>)> _liveRecent = {};
  static const liveShareWindow = Duration(seconds: 4);

  /// Drop the shared result after a command so the next read is fresh.
  static void forgetLive() {
    _liveRecent.clear();
  }

  /// [shared] lets periodic display polls reuse a result from the last few
  /// seconds. Control paths (chat prepare/execute, post-command readback) keep
  /// the default fresh read.
  Future<Map<String, dynamic>> getLive({
    String? vehicleId,
    bool shared = false,
  }) {
    String? uid;
    try {
      uid = _auth.currentUser?.uid;
    } on Object {
      uid = null;
    }
    final key = '${uid ?? '-'}|${vehicleId ?? ''}';
    if (shared) {
      final recent = _liveRecent[key];
      if (recent != null &&
          DateTime.now().difference(recent.$1) <= liveShareWindow) {
        return Future.value(Map<String, dynamic>.from(recent.$2));
      }
      final pending = _liveInFlight[key];
      if (pending != null) return pending;
    }
    final request =
        _request(
          'GET',
          '/api/smart-charging/live${vehicleId == null || vehicleId.isEmpty ? '' : '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}'}',
        ).then((data) {
          _liveRecent[key] = (DateTime.now(), Map<String, dynamic>.from(data));
          return data;
        });
    _liveInFlight[key] = request;
    request.whenComplete(() {
      if (identical(_liveInFlight[key], request)) _liveInFlight.remove(key);
    }).ignore();
    return request;
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
    if (preview.isDisplayOnly || id == null) {
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
        timeout: controlTimeout,
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
    String? expectedDeviceId,
    String? operationId,
  }) async {
    final query = sessionId == null && vehicleId != null && vehicleId.isNotEmpty
        ? '?vehicleId=${Uri.encodeQueryComponent(vehicleId)}'
        : '';
    final data = await _request(
      'POST',
      sessionId == null
          ? '/api/smart-charging/off$query'
          : '/api/smart-charging/session/$sessionId/stop',
      body: {'expectedDeviceId': ?expectedDeviceId},
      headers: {'Idempotency-Key': ?operationId},
      timeout: controlTimeout,
    );
    return data['_null'] == true ? null : SmartChargingSession.fromJson(data);
  }

  Future<SmartChargingSession?> stop(
    String sessionId, {
    required int expectedVersion,
    String userStopReason = 'none',
    String? idempotencyKey,
  }) async {
    final data = await _request(
      'POST',
      '/api/smart-charging/session/$sessionId/stop',
      headers: {'Idempotency-Key': ?idempotencyKey},
      body: {
        'expectedVersion': expectedVersion,
        'userStopReason': userStopReason,
      },
      timeout: controlTimeout,
    );
    return data['_null'] == true ? null : SmartChargingSession.fromJson(data);
  }

  Future<SmartChargingSession> manualOn(
    Duration duration, {
    required String idempotencyKey,
    required String vehicleId,
    required double currentSoc,
    String? expectedDeviceId,
  }) async => SmartChargingSession.fromJson(
    await _request(
      'POST',
      '/api/smart-charging/on',
      body: {
        'durationSeconds': duration.inSeconds,
        'vehicleId': vehicleId,
        'currentSoc': currentSoc,
        'expectedDeviceId': ?expectedDeviceId,
      },
      headers: {'Idempotency-Key': idempotencyKey},
      timeout: controlTimeout,
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

  Future<List<SmartChargeTelemetryPoint>> telemetry(
    String sessionId, {
    String? after,
    int limit = 120,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (after != null && after.isNotEmpty) params['after'] = after;
    final query = Uri(queryParameters: params).query;
    final data = await _request(
      'GET',
      '/api/smart-charging/sessions/$sessionId/telemetry?$query',
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

  /// Lấy toàn bộ danh sách mẫu dữ liệu từ file dataset trên server
  Future<Map<String, dynamic>> getAiDataset({
    String? vehicleId,
    bool? confirmedOnly,
  }) async {
    final query = <String>[];
    if (vehicleId != null && vehicleId.isNotEmpty) {
      query.add('vehicle_id=${Uri.encodeQueryComponent(vehicleId)}');
    }
    if (confirmedOnly == true) {
      query.add('confirmed=true');
    }
    final suffix = query.isEmpty ? '' : '?${query.join('&')}';
    final res = await _request('GET', '/api/ai/dataset$suffix');
    final recordsRaw =
        res['records'] ?? (res['data'] is Map ? res['data']['records'] : null);
    final statsRaw =
        res['stats'] ?? (res['data'] is Map ? res['data']['stats'] : null);
    return {
      'success': true,
      'records': recordsRaw is List ? recordsRaw : const [],
      'stats': statsRaw is Map ? Map<String, dynamic>.from(statsRaw) : const {},
      'data': res,
    };
  }

  /// Cập nhật trực tiếp 1 mẫu vào file dataset (Developer Mode)
  Future<Map<String, dynamic>> updateAiDatasetRecord(
    String sessionId,
    Map<String, dynamic> updates,
  ) async {
    final res = await _request(
      'PUT',
      '/api/ai/dataset/records/${Uri.encodeComponent(sessionId)}',
      body: updates,
    );
    return {'success': true, 'data': res};
  }

  /// Thêm mẫu thử nghiệm mới vào file dataset (Developer Mode)
  Future<Map<String, dynamic>> addAiDatasetRecord(
    Map<String, dynamic> record,
  ) async {
    final res = await _request('POST', '/api/ai/dataset/records', body: record);
    return {'success': true, 'data': res};
  }

  /// Kích hoạt fine-tune model charging_time từ file dataset kèm siêu tham số
  Future<Map<String, dynamic>> triggerChargingTimeFineTune({
    double? learningRate,
    int? nEstimators,
    int? maxDepth,
    double? testSplit,
  }) async {
    final payload = <String, dynamic>{};
    if (learningRate != null) payload['learningRate'] = learningRate;
    if (nEstimators != null) payload['nEstimators'] = nEstimators;
    if (maxDepth != null) payload['maxDepth'] = maxDepth;
    if (testSplit != null) payload['testSplit'] = testSplit;
    final res = await _request(
      'POST',
      '/api/ai/models/charging_time/fine-tune',
      body: payload,
    );
    return {'success': true, 'data': res};
  }

  /// Lấy danh sách mẫu học fine-tune cá nhân từ máy chủ (bỏ qua giới hạn quyền Firestore)
  Future<List<Map<String, dynamic>>> getPersonalTrainingSamples(
    String vehicleId,
  ) async {
    try {
      final res = await _request(
        'GET',
        '/api/smart-charging/training-samples?vehicleId=${Uri.encodeQueryComponent(vehicleId)}',
      );
      final items =
          res['items'] ?? (res['data'] is Map ? res['data']['items'] : null);
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Kiểm tra kết nối nhanh tới máy chủ backend (Ping & Latency)
  Future<Map<String, dynamic>> pingServer({String? customUrl}) async {
    final url = (customUrl != null && customUrl.trim().isNotEmpty)
        ? customUrl.trim().replaceAll(RegExp(r'/+$'), '')
        : AppConstants.apiBaseUrl;
    final uri = Uri.parse('$url/api/health');
    final sw = Stopwatch()..start();
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      sw.stop();
      if (res.statusCode >= 200 && res.statusCode < 400) {
        return {
          'online': true,
          'latencyMs': sw.elapsedMilliseconds,
          'url': url,
          'status': res.statusCode,
        };
      }
      return {
        'online': false,
        'latencyMs': sw.elapsedMilliseconds,
        'url': url,
        'error': 'HTTP ${res.statusCode}',
      };
    } catch (e) {
      sw.stop();
      return {
        'online': false,
        'latencyMs': sw.elapsedMilliseconds,
        'url': url,
        'error': e.toString(),
      };
    }
  }
}
