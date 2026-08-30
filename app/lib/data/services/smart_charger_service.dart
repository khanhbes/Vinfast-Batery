import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shelly_connection.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charger_capabilities.dart';
import '../models/smart_charging_session.dart';
import '../models/personal_charging_profile.dart';
import 'shelly_clients.dart';
import 'shelly_discovery_service.dart';
import 'smart_charger_credentials_service.dart';

class SmartChargerException implements Exception {
  const SmartChargerException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryable = false,
    this.sessionId,
  });
  final String message;
  final int? statusCode;
  final String? code;
  final bool retryable;
  final String? sessionId;
  @override
  String toString() => message;
}

class SmartChargerConnectionTest {
  const SmartChargerConnectionTest({
    this.cloudStatus,
    this.lanStatus,
    required this.deviceVerified,
    required this.powerMeterAvailable,
  });
  final SmartChargerStatus? cloudStatus;
  final SmartChargerStatus? lanStatus;
  final bool deviceVerified;
  final bool powerMeterAvailable;
}

class SmartChargeDirectSafetyPolicy {
  const SmartChargeDirectSafetyPolicy({
    this.cutoffCurrentA = 11.5,
    this.cutoffPowerW = 2450,
    this.cutoffShellyTemperatureC = 75,
    this.cutoffVoltageMinV = 190,
    this.cutoffVoltageMaxV = 255,
    this.consecutiveSamples = 2,
  });

  final double cutoffCurrentA;
  final double cutoffPowerW;
  final double cutoffShellyTemperatureC;
  final double cutoffVoltageMinV;
  final double cutoffVoltageMaxV;
  final int consecutiveSamples;
}

class SmartChargerService {
  SmartChargerService({
    http.Client? client,
    SmartChargerCredentialsService? credentials,
    ShellyCloudClient? cloudClient,
    ShellyLanClient? lanClient,
    ShellyDiscoveryService? discovery,
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    SmartChargeDirectSafetyPolicy safetyPolicy =
        const SmartChargeDirectSafetyPolicy(),
    @Deprecated('Gateway base URL is no longer used.') String? baseUrl,
    @Deprecated('Gateway bearer token is no longer used.')
    Future<String?> Function()? tokenProvider,
  }) : _credentials = credentials ?? SmartChargerCredentialsService(),
       _cloud = cloudClient ?? ShellyCloudClient(client: client),
       _lan = lanClient ?? ShellyLanClient(client: client),
       _discovery = discovery ?? const ShellyDiscoveryService(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _safetyPolicy = safetyPolicy;

  static const _activeSessionKey = 'smart_charger.active_shelly_session.v1';
  static const maxSessionDuration = Duration(hours: 10);
  final SmartChargerCredentialsService _credentials;
  final ShellyCloudClient _cloud;
  final ShellyLanClient _lan;
  final ShellyDiscoveryService _discovery;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final SmartChargeDirectSafetyPolicy _safetyPolicy;
  ShellyTransport? _lastTransport;
  int _criticalSafetySamples = 0;

  // Kept synchronous for existing entry points. Missing configuration is
  // reported by getStatus/armSmartCharge with the typed notConfigured error.
  bool get isConfigured => true;

  Future<bool> isConfiguredSecurely() async =>
      (await _credentials.readProfile()) != null;

  Future<List<DiscoveredShellyDevice>> discoverDevices() =>
      _discovery.discover();

  Future<SmartChargerConnectionTest> testConnection({
    ShellyConnectionProfile? profile,
  }) async {
    final selected = profile ?? await _requireProfile();
    SmartChargerStatus? cloud;
    SmartChargerException? cloudError;
    try {
      cloud = await _translate(() => _cloud.getStatus(selected));
    } on SmartChargerException catch (error) {
      cloudError = error;
    }
    SmartChargerStatus? lan;
    if (selected.hasLan) {
      final info = await _translate(() => _lan.getDeviceInfo(selected));
      final foundId = (info['id'] ?? info['mac'])?.toString().toLowerCase();
      if (foundId != null &&
          !_sameDeviceId(foundId, selected.deviceId.toLowerCase())) {
        throw const SmartChargerException(
          'Thiết bị LAN không khớp Device ID trên Shelly Cloud.',
          code: 'deviceMismatch',
        );
      }
      final foundModel = (info['model'] ?? info['app'])?.toString() ?? '';
      final generation = (info['gen'] as num?)?.toInt();
      final isPlugS =
          foundModel.toLowerCase().contains('plugs') ||
          foundModel.toLowerCase() == 's3pl-00112eu';
      if (!isPlugS || (generation != null && generation != 3)) {
        throw const SmartChargerException(
          'Chỉ hỗ trợ đúng Shelly Plug S Gen3.',
          code: 'unsupportedDevice',
        );
      }
      lan = await _translate(() => _lan.getStatus(selected));
    }
    if (cloud == null && lan == null) {
      throw cloudError ??
          const SmartChargerException(
            'Cloud và LAN đều không khả dụng.',
            code: 'deviceOffline',
          );
    }
    return SmartChargerConnectionTest(
      cloudStatus: cloud,
      lanStatus: lan,
      deviceVerified: true,
      powerMeterAvailable:
          (cloud?.voltageV ?? 0) > 0 || (lan?.voltageV ?? 0) > 0,
    );
  }

  Future<void> configureSafeBoot({ShellyConnectionProfile? profile}) async {
    final selected = profile ?? await _requireProfile();
    await _translate(() => _lan.configureSafeBoot(selected));
    final status = await _translate(() => _lan.getStatus(selected));
    if (status.relay) {
      await _translate(() => _lan.setSwitch(selected, on: false));
      final verified = await _translate(() => _lan.getStatus(selected));
      if (verified.relay) {
        throw const SmartChargerException(
          'Không xác minh được relay OFF sau cấu hình safe boot.',
          code: 'relayUnverified',
        );
      }
    }
  }

  Future<void> runNoLoadTest({ShellyConnectionProfile? profile}) async {
    final selected = profile ?? await _requireProfile();
    try {
      await _translate(
        () => _lan.setSwitch(
          selected,
          on: true,
          toggleAfter: const Duration(seconds: 5),
        ),
      );
      await _delay(const Duration(seconds: 6));
    } finally {
      await _bestEffortOff(selected);
    }
    final status = await _getStatus(selected);
    if (status.relay) {
      throw const SmartChargerException(
        'Không xác minh được relay OFF. Hãy ngắt tải vật lý ngay.',
        code: 'relayUnverified',
      );
    }
  }

  Future<SmartChargerStatus> getStatus() async {
    final profile = await _requireProfile();
    final status = await _getStatus(profile);
    await _enforceSafety(profile, status);
    return status;
  }

  Future<void> _enforceSafety(
    ShellyConnectionProfile profile,
    SmartChargerStatus status,
  ) async {
    if (!status.relay) {
      _criticalSafetySamples = 0;
      return;
    }
    final critical =
        status.currentA >= _safetyPolicy.cutoffCurrentA ||
        status.powerW >= _safetyPolicy.cutoffPowerW ||
        (status.shellyTemperatureC != null &&
            status.shellyTemperatureC! >=
                _safetyPolicy.cutoffShellyTemperatureC) ||
        (status.voltageV > 0 &&
            (status.voltageV < _safetyPolicy.cutoffVoltageMinV ||
                status.voltageV > _safetyPolicy.cutoffVoltageMaxV));
    _criticalSafetySamples = critical ? _criticalSafetySamples + 1 : 0;
    if (_criticalSafetySamples < _safetyPolicy.consecutiveSamples) return;
    await _bestEffortOff(profile);
    final verified = await _getStatus(profile);
    if (verified.relay) {
      throw const SmartChargerException(
        'Thông số điện không an toàn và không xác minh được OFF. Hãy ngắt nguồn vật lý ngay.',
        code: 'relayUnverified',
      );
    }
    await turnOffAndVerify(reason: ChargingStopReason.safetyCutoff);
    throw const SmartChargerException(
      'Đã ngắt sạc tự động vì thông số điện vượt ngưỡng an toàn.',
      code: 'safetyCutoff',
    );
  }

  Future<SmartChargerCapabilities> capabilities() async {
    final profile = await _credentials.readProfile();
    final verification = await _credentials.readVerification();
    if (profile == null) return SmartChargerCapabilities.unavailable;
    return SmartChargerCapabilities(
      canReadStatus: verification.cloudVerified || verification.lanVerified,
      canManualOn: verification.readyForControl,
      canManualOff: verification.cloudVerified || verification.lanVerified,
      supportsDeviceTimer:
          verification.cloudVerified || verification.lanVerified,
      canReadPower: verification.powerMeterVerified,
      canConfigureSafeBoot: profile.hasLan,
      cloudAvailable: verification.cloudVerified,
      lanAvailable: verification.lanVerified,
      safeBootVerified: verification.safeBootVerified,
      noLoadTestVerified: verification.noLoadTestVerified,
      readyForControl: verification.readyForControl,
      provider: 'direct',
    );
  }

  Future<SmartChargerStatus> _getStatus(
    ShellyConnectionProfile selected,
  ) async {
    try {
      final result = await _translate(() => _cloud.getStatus(selected));
      _lastTransport = ShellyTransport.cloud;
      return result;
    } on SmartChargerException catch (cloudError) {
      if (!selected.hasLan) rethrow;
      try {
        final result = await _translate(() => _lan.getStatus(selected));
        _lastTransport = ShellyTransport.lan;
        return result;
      } on SmartChargerException {
        throw SmartChargerException(
          '${cloudError.message} LAN fallback cũng không khả dụng.',
          code: 'deviceOffline',
          retryable: true,
        );
      }
    }
  }

  Future<SmartChargingSession> armSmartCharge(
    SmartChargePlan plan, {
    ChargingStrategy strategy = ChargingStrategy.aiTarget,
    String? modelVersion,
    String runtimeHealth = 'unknown',
    List<String> predictionWarnings = const [],
    String? fallbackReason,
    DateTime? predictionAnalyzedAt,
    String? idempotencyKey,
    List<EtaCandidate> etaCandidates = const [],
    String fusionReason = 'global_ai_only',
    String? profileVersion,
    String? adapterVersion,
  }) async {
    final existing = await _readActive();
    if (existing != null) {
      if (idempotencyKey != null && existing.idempotencyKey == idempotencyKey) {
        return existing;
      }
      throw const SmartChargerException(
        'Đang có một phiên sạc khác. Hãy OFF và xác minh trước khi bắt đầu lại.',
        code: 'activeSessionConflict',
      );
    }
    final now = _clock();
    final duration = plan.effectiveDuration(now);
    if (duration <= Duration.zero || duration > maxSessionDuration) {
      throw const SmartChargerException(
        'Phiên sạc phải lớn hơn 0 và không vượt quá 10 giờ.',
        code: 'unsafeDuration',
      );
    }
    final profile = await _requireProfile();
    final session = SmartChargingSession(
      sessionId: '${now.toUtc().microsecondsSinceEpoch}-${profile.deviceId}',
      vehicleId: plan.vehicleId,
      state: ChargingSessionState.arming,
      strategy: strategy,
      startSoc: plan.currentSoc,
      targetSoc: plan.targetSoc,
      predictedMinutes: duration.inMinutes,
      predictionSource: plan.predictionSource,
      predictionConfidence: plan.predictionConfidence,
      estimatedCapacityWh: plan.estimatedCapacityWh,
      createdAt: now,
      updatedAt: now,
      aiStopAt: now.add(plan.duration),
      hardDeadlineAt: plan.hardDeadlineAt ?? now.add(maxSessionDuration),
      effectiveStopAt: now.add(duration),
      absoluteSafetyStopAt: now.add(maxSessionDuration),
      shadowMode: false,
      version: 1,
      deviceId: profile.deviceId,
      predictedDurationSeconds: duration.inSeconds,
      modelKey: strategy == ChargingStrategy.manualTimed
          ? 'none'
          : 'charging_time',
      modelVersion:
          modelVersion ??
          (strategy == ChargingStrategy.manualTimed ? 'manual' : 'unknown'),
      runtimeHealth: runtimeHealth,
      predictionWarnings: predictionWarnings,
      fallbackReason: fallbackReason,
      predictionAnalyzedAt: predictionAnalyzedAt,
      idempotencyKey: idempotencyKey,
      etaCandidates: etaCandidates,
      fusionReason: fusionReason,
      profileVersion: profileVersion,
      adapterVersion: adapterVersion,
    );
    await _saveActive(session);
    try {
      await _cloud.setSwitch(profile, on: true, toggleAfter: duration);
      _lastTransport = ShellyTransport.cloud;
    } on ShellyClientException catch (cloudError) {
      if (!profile.hasLan) {
        await _clearActive();
        throw _map(cloudError);
      }
      try {
        await _lan.setSwitch(profile, on: true, toggleAfter: duration);
        _lastTransport = ShellyTransport.lan;
      } on ShellyClientException catch (lanError) {
        await _clearActive();
        throw SmartChargerException(
          '${_map(cloudError).message} ${_map(lanError).message}',
          code: 'deviceOffline',
          retryable: true,
        );
      }
    }
    await _delay(const Duration(seconds: 1));
    final deadline = _clock().add(const Duration(seconds: 9));
    SmartChargerStatus? verified;
    while (!_clock().isAfter(deadline)) {
      try {
        final status = await _getStatus(profile);
        if (status.relay && (status.timerRemaining?.inSeconds ?? 0) > 0) {
          verified = status;
          break;
        }
      } on SmartChargerException {
        // Continue readback until the ten-second safety deadline.
      }
      await _delay(const Duration(seconds: 1));
    }
    if (verified == null) {
      await _bestEffortOff(profile);
      await _clearActive();
      throw const SmartChargerException(
        'Không xác minh được timer trên Shelly sau 10 giây. Đã gửi OFF qua Cloud và LAN; hãy kiểm tra ổ cắm vật lý.',
        code: 'timerNotArmed',
      );
    }
    final active = session.copyWith(
      state: ChargingSessionState.active,
      updatedAt: _clock(),
      startedAt: now,
      relayVerified: true,
      timerVerified: true,
      baselineEnergyWh: verified.energyWh,
      transport: verified.transport?.name ?? _lastTransport?.name,
      version: 2,
    );
    await _saveActive(active);
    return active;
  }

  Future<SmartChargingSession> rearmTimer(Duration duration) async {
    if (duration <= Duration.zero || duration > maxSessionDuration) {
      throw const SmartChargerException(
        'Timer hiệu chỉnh không an toàn.',
        code: 'unsafeDuration',
      );
    }
    final session = await _readActive();
    if (session == null) {
      throw const SmartChargerException('Không có phiên sạc đang hoạt động.');
    }
    final maxRemaining = session.absoluteSafetyStopAt.difference(_clock());
    final safeDuration = duration < maxRemaining ? duration : maxRemaining;
    final profile = await _requireProfile();
    if (_lastTransport == ShellyTransport.lan) {
      await _translate(
        () => _lan.setSwitch(profile, on: true, toggleAfter: safeDuration),
      );
    } else {
      try {
        await _translate(
          () => _cloud.setSwitch(profile, on: true, toggleAfter: safeDuration),
        );
      } on SmartChargerException {
        await _translate(
          () => _lan.setSwitch(profile, on: true, toggleAfter: safeDuration),
        );
      }
    }
    await _delay(const Duration(seconds: 1));
    final status = await _getStatus(profile);
    if (!status.relay || (status.timerRemaining?.inSeconds ?? 0) <= 0) {
      throw const SmartChargerException(
        'Shelly không xác nhận timer hiệu chỉnh; timer trước vẫn được giữ.',
        code: 'timerNotArmed',
      );
    }
    final updated = session.copyWith(
      effectiveStopAt: _clock().add(status.timerRemaining!),
      updatedAt: _clock(),
      version: session.version + 1,
      transport: status.transport?.name,
    );
    await _saveActive(updated);
    return updated;
  }

  Future<SmartChargingSession?> turnOffAndVerify({
    ChargingStopReason reason = ChargingStopReason.manual,
  }) async {
    final profile = await _requireProfile();
    await _bestEffortOff(profile);
    SmartChargerStatus? status;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        status = await _getStatus(profile);
        if (!status.relay) break;
      } on SmartChargerException {
        // Verify again through the Cloud/LAN failover path.
      }
      await _delay(const Duration(seconds: 1));
    }
    if (status == null || status.relay) {
      throw const SmartChargerException(
        'Không xác minh được relay OFF. Hãy rút phích cắm hoặc tắt Shelly vật lý ngay.',
        code: 'relayUnverified',
      );
    }
    final active = await _readActive();
    if (active == null) return null;
    final stopped = active.copyWith(
      state: reason == ChargingStopReason.manual
          ? ChargingSessionState.cancelled
          : reason == ChargingStopReason.safetyCutoff
          ? ChargingSessionState.interrupted
          : reason == ChargingStopReason.commandFailed
          ? ChargingSessionState.failed
          : ChargingSessionState.completed,
      stoppedAt: _clock(),
      updatedAt: _clock(),
      stopReason: reason,
      relayVerified: true,
      energyUsedWh: max(
        0,
        status.energyWh - (active.baselineEnergyWh ?? status.energyWh),
      ),
      transport: status.transport?.name,
      version: active.version + 1,
    );
    await _clearActive();
    return stopped;
  }

  Future<SmartChargingSession?> reconcileActiveSession() async {
    final active = await _readActive();
    if (active == null) return null;
    final status = await getStatus();
    final now = _clock();
    if (status.relay) {
      if ((status.timerRemaining?.inSeconds ?? 0) <= 0) {
        try {
          return await turnOffAndVerify(
            reason: ChargingStopReason.commandFailed,
          );
        } finally {
          await _clearActive();
        }
      }
      final updated = active.copyWith(
        state: ChargingSessionState.active,
        updatedAt: now,
        effectiveStopAt: now.add(status.timerRemaining!),
        estimatedSoc: _estimatedSoc(active, status),
        energyUsedWh: max(
          0,
          status.energyWh - (active.baselineEnergyWh ?? status.energyWh),
        ),
        transport: status.transport?.name,
      );
      await _saveActive(updated);
      return updated;
    }
    final nearPlanned =
        now.difference(active.effectiveStopAt).abs() <=
        const Duration(minutes: 2);
    final stopped = active.copyWith(
      state: nearPlanned
          ? ChargingSessionState.completed
          : ChargingSessionState.interrupted,
      updatedAt: now,
      stoppedAt: now,
      stopReason: nearPlanned
          ? ChargingStopReason.plannedTimer
          : ChargingStopReason.relayOff,
      relayVerified: true,
      energyUsedWh: max(
        0,
        status.energyWh - (active.baselineEnergyWh ?? status.energyWh),
      ),
      estimatedSoc: _estimatedSoc(active, status),
      transport: status.transport?.name,
    );
    await _clearActive();
    return stopped;
  }

  static int calibratedRemainingMinutes({
    required double remainingBatteryWh,
    required Iterable<double> powerSamplesW,
  }) {
    final samples = powerSamplesW.where((value) => value > 0).toList()..sort();
    if (samples.length < 6 || remainingBatteryWh <= 0) return 0;
    final middle = samples.length ~/ 2;
    final median = samples.length.isOdd
        ? samples[middle]
        : (samples[middle - 1] + samples[middle]) / 2;
    return (remainingBatteryWh / (median * 0.90) * 60).ceil();
  }

  @Deprecated('Use manualOn with a required device safety timer.')
  Future<SmartChargerCommandResult> turnOn() =>
      throw const SmartChargerException(
        'Bật sạc bắt buộc phải có safety timer trên Shelly.',
        code: 'unsafeDuration',
      );

  Future<SmartChargingSession> manualOn(
    Duration duration, {
    required String idempotencyKey,
    required String vehicleId,
    required double currentSoc,
  }) async {
    final capabilities = await this.capabilities();
    if (!capabilities.readyForControl) {
      throw const SmartChargerException(
        'Shelly chưa vượt qua kiểm tra an toàn và test không tải.',
        code: 'notReadyForControl',
      );
    }
    return armSmartCharge(
      SmartChargePlan(
        vehicleId: vehicleId,
        currentSoc: currentSoc,
        targetSoc: currentSoc,
        duration: duration,
        estimatedCapacityWh: 1,
        predictionSource: 'manual_timer',
      ),
      strategy: ChargingStrategy.manualTimed,
      modelVersion: 'manual',
      runtimeHealth: 'not_applicable',
      idempotencyKey: idempotencyKey,
    );
  }

  Future<SmartChargerCommandResult> turnOff() async {
    await turnOffAndVerify();
    return const SmartChargerCommandResult(success: true, relay: false);
  }

  Future<SmartChargingSession> startAutomaticSession(
    SmartChargingSessionRequest request, {
    required String idempotencyKey,
  }) => armSmartCharge(
    SmartChargePlan(
      vehicleId: request.vehicleId,
      currentSoc: request.startSoc,
      targetSoc: request.targetSoc,
      duration: Duration(
        seconds:
            request.predictedDurationSeconds ?? request.predictedMinutes * 60,
      ),
      estimatedCapacityWh: request.estimatedCapacityWh ?? 0,
      predictionSource: request.predictionSource ?? 'unknown',
      predictionConfidence: request.predictionConfidence,
      hardDeadlineAt: request.hardDeadlineAt,
    ),
    strategy: ChargingStrategy.aiTarget,
    modelVersion: request.modelVersion,
    runtimeHealth: request.runtimeHealth,
    predictionWarnings: request.predictionWarnings,
    fallbackReason: request.fallbackReason,
    predictionAnalyzedAt: request.predictionAnalyzedAt,
    idempotencyKey: idempotencyKey,
    etaCandidates: request.etaCandidates,
    fusionReason: request.fusionReason,
    profileVersion: request.profileVersion,
    adapterVersion: request.adapterVersion,
  );

  Future<SmartChargingSession?> getCurrentSession() => reconcileActiveSession();
  Future<List<SmartChargingSession>> getSessionHistory({
    int limit = 20,
  }) async => const [];

  Future<SmartChargingSession?> stopSession(
    String sessionId, {
    int? expectedVersion,
  }) async {
    return turnOffAndVerify();
  }

  Future<SmartChargingSessionResponse> startMonitoringSession(
    SmartChargingSessionRequest request,
  ) {
    throw const SmartChargerException(
      'Chế độ gateway monitor-only đã được chuyển sang legacy.',
    );
  }

  Future<SmartChargingSession> getSession(String sessionId) async {
    final active = await _readActive();
    if (active?.sessionId == sessionId) return active!;
    throw const SmartChargerException('Không tìm thấy phiên sạc.');
  }

  Future<SmartChargingSession> updateSession(
    String sessionId, {
    required int expectedVersion,
    DateTime? hardDeadlineAt,
    double? targetSoc,
    int? predictedMinutes,
    bool acknowledgeExtension = false,
  }) => rearmTimer(Duration(minutes: predictedMinutes ?? 1));

  Future<ShellyConnectionProfile> _requireProfile() async {
    final profile = await _credentials.readProfile();
    if (profile == null) {
      throw const SmartChargerException(
        'Shelly chưa kết nối.',
        code: 'notConfigured',
      );
    }
    final error = profile.validate();
    if (error != null) {
      throw SmartChargerException(error, code: 'notConfigured');
    }
    return profile;
  }

  Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ShellyClientException catch (error) {
      throw _map(error);
    }
  }

  SmartChargerException _map(ShellyClientException error) =>
      SmartChargerException(
        error.message,
        code: error.code.name,
        retryable: error.retryable,
      );

  Future<void> _bestEffortOff(ShellyConnectionProfile profile) async {
    await Future.wait([
      _cloud.setSwitch(profile, on: false).catchError((_) {}),
      if (profile.hasLan) _lan.setSwitch(profile, on: false).catchError((_) {}),
    ]);
  }

  Future<SmartChargingSession?> _readActive() async {
    final raw = (await _preferences()).getString(_activeSessionKey);
    if (raw == null) return null;
    try {
      return SmartChargingSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      await _clearActive();
      return null;
    }
  }

  Future<void> _saveActive(SmartChargingSession session) async {
    await (await _preferences()).setString(
      _activeSessionKey,
      jsonEncode(session.toJson()),
    );
  }

  Future<void> _clearActive() async {
    await (await _preferences()).remove(_activeSessionKey);
  }

  double _estimatedSoc(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) {
    final capacity = session.estimatedCapacityWh ?? 0;
    if (capacity <= 0) return session.startSoc;
    final used = max(
      0,
      status.energyWh - (session.baselineEnergyWh ?? status.energyWh),
    );
    return min(
      session.targetSoc,
      session.startSoc + used * 0.90 / capacity * 100,
    );
  }

  bool _sameDeviceId(String left, String right) {
    String clean(String value) => value.replaceAll(RegExp('[^a-z0-9]'), '');
    return clean(left).endsWith(clean(right)) ||
        clean(right).endsWith(clean(left));
  }
}
