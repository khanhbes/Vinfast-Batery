import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shelly_connection.dart';
import '../models/shelly_snapshot.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charger_capabilities.dart';
import '../models/smart_charging_session.dart';
import '../models/personal_charging_profile.dart';
import 'shelly_charge_log_service.dart';
import 'shelly_clients.dart';
import 'shelly_discovery_service.dart';
import 'smart_charger_credentials_service.dart';
import 'smart_charge_energy_accumulator.dart';
import '../../core/constants/app_constants.dart';

class SmartChargerException implements Exception {
  const SmartChargerException(
    this.message, {
    this.statusCode,
    this.providerCode,
    this.code,
    this.retryable = false,
    this.sessionId,
    this.commandMayHaveReachedDevice = false,
  });
  final String message;
  final int? statusCode;
  final String? providerCode;
  final String? code;
  final bool retryable;
  final String? sessionId;
  final bool commandMayHaveReachedDevice;
  @override
  String toString() => message;
}

class SmartChargerConnectionTest {
  const SmartChargerConnectionTest({
    this.cloudStatus,
    this.lanStatus,
    required this.deviceVerified,
    required this.powerMeterAvailable,
    this.model,
    this.safeBootVerified = false,
    this.initialState,
    this.autoOn,
  });
  final SmartChargerStatus? cloudStatus;
  final SmartChargerStatus? lanStatus;
  final bool deviceVerified;
  final bool powerMeterAvailable;
  final String? model;
  final bool safeBootVerified;
  final String? initialState;
  final bool? autoOn;
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
  static const _uncertainRelayKey = 'smart_charger.relay_state_uncertain.v1';
  static const maxSessionDuration = Duration(
    minutes: AppConstants.smartChargeMaxMinutes,
  );
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

  String? _scopedKey(String base) {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return uid == null ? null : '$base.$uid';
    } on Object {
      return base;
    }
  }

  // Kept synchronous for existing entry points. Missing configuration is
  // reported by getStatus/armSmartCharge with the typed notConfigured error.
  bool get isConfigured => true;

  Future<bool> isConfiguredSecurely() async =>
      (await _credentials.readProfile()) != null;

  Future<List<DiscoveredShellyDevice>> discoverDevices() =>
      _discovery.discover();

  Future<List<DiscoveredShellyDevice>> discoverAndProbeDevices({
    Duration discoveryTimeout = const Duration(seconds: 5),
    Duration probeTimeout = const Duration(seconds: 3),
  }) => _discovery.discoverAndProbe(
    discoveryTimeout: discoveryTimeout,
    probeTimeout: probeTimeout,
  );

  /// Confirm user-verified actual end SOC to Firestore ChargeLog
  Future<void> confirmActualSoc({
    required String sessionId,
    required double actualSoc,
    ShellyChargeLogService? chargeLogService,
  }) async {
    final service = chargeLogService ?? ShellyChargeLogService();
    await service.confirmActualSoc(sessionId: sessionId, actualSoc: actualSoc);
  }

  Future<SmartChargerConnectionTest> testConnection({
    ShellyConnectionProfile? profile,
  }) async {
    final selected = profile ?? await _requireProfile();
    SmartChargerStatus? cloud;
    ShellyDeviceSnapshot? cloudSnapshot;
    SmartChargerException? cloudError;
    try {
      cloudSnapshot = await _translate(() => _cloud.getSnapshot(selected));
      final snapshot = cloudSnapshot;
      if (snapshot == null ||
          !snapshot.online ||
          !snapshot.isSupportedPlugSGen3) {
        throw const SmartChargerException(
          'Shelly không đúng Plug S Gen3 hoặc đang offline trên Cloud.',
          code: 'unsupportedDevice',
        );
      }
      cloud = snapshot.status;
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
      final generation = int.tryParse(
        info['gen']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      );
      final isPlugSGen3 =
          foundModel.toUpperCase() == 'S3PL-00112EU' && generation == 3;
      if (!isPlugSGen3) {
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
      deviceVerified:
          cloudSnapshot?.isSupportedPlugSGen3 == true || lan != null,
      powerMeterAvailable:
          cloudSnapshot?.powerMeterFieldsPresent == true ||
          (lan?.voltageV ?? 0) > 0,
      model: cloudSnapshot?.model,
      safeBootVerified: cloudSnapshot?.switchConfig?.isSafeForCharging == true,
      initialState: cloudSnapshot?.switchConfig?.initialState,
      autoOn: cloudSnapshot?.switchConfig?.autoOn,
    );
  }

  Future<ShellyDeviceSnapshot> getCloudSnapshot({
    ShellyConnectionProfile? profile,
  }) async {
    final selected = profile ?? await _requireProfile();
    final snapshot = await _translate(() => _cloud.getSnapshot(selected));
    if (!snapshot.online || !snapshot.isSupportedPlugSGen3) {
      throw const SmartChargerException(
        'Shelly không đúng Plug S Gen3 hoặc đang offline trên Cloud.',
        code: 'unsupportedDevice',
      );
    }
    return snapshot;
  }

  Future<void> configureSafeBoot({ShellyConnectionProfile? profile}) async {
    final selected = profile ?? await _requireProfile();
    if (selected.hasLan) {
      await _translate(() => _lan.configureSafeBoot(selected));
      final config = await _translate(() => _lan.getSwitchConfig(selected));
      final safe = ShellySwitchConfig.fromJson(config);
      if (safe?.isSafeForCharging != true) {
        throw const SmartChargerException(
          'Không đọc lại được Safe Boot OFF/Auto ON OFF trên Shelly.',
          code: 'safeBootUnverified',
        );
      }
    } else {
      // Cloud Control cannot change Switch.SetConfig. The user must configure
      // this once in Shelly Smart Control; we only accept a live readback.
      final snapshot = await getCloudSnapshot(profile: selected);
      if (snapshot.switchConfig?.isSafeForCharging != true) {
        throw const SmartChargerException(
          'Hãy đặt Power-on default OFF và tắt Auto ON trong Shelly Smart Control, rồi kiểm tra lại.',
          code: 'safeBootUnverified',
        );
      }
    }
    final status = await _getStatus(selected);
    if (status.relay) {
      // Use the transport that produced the readback. Cloud-only profiles
      // must be able to recover an accidentally-on relay without requiring a
      // LAN address; never assume LAN is available here.
      final transport =
          _lastTransport ??
          (selected.hasLan ? ShellyTransport.lan : ShellyTransport.cloud);
      await _setSwitchAtTransport(selected, transport, on: false);
      final verified = await _getStatus(selected);
      if (verified.relay) {
        throw const SmartChargerException(
          'Không xác minh được relay OFF sau cấu hình safe boot.',
          code: 'relayUnverified',
        );
      }
    }
  }

  Future<ShellySafetyTestResult> runNoLoadTest({
    ShellyConnectionProfile? profile,
  }) async {
    final selected = profile ?? await _requireProfile();
    final initial = await _getStatus(selected);
    if (initial.relay) {
      throw const SmartChargerException(
        'Relay phải OFF trước khi chạy test không tải.',
        code: 'relayUnverified',
      );
    }
    final transport = await _verifyBeforeOn(selected);
    SmartChargerStatus? observedOn;
    SmartChargerStatus? observedOff;
    SmartChargerException? failure;
    try {
      await _setSwitchAtTransport(
        selected,
        transport,
        on: true,
        toggleAfter: const Duration(seconds: 5),
      );
      final deadline = _clock().add(const Duration(seconds: 4));
      while (!_clock().isAfter(deadline)) {
        final status = await _getStatus(selected);
        if (status.relay && (status.timerRemaining?.inSeconds ?? 0) > 0) {
          observedOn = status;
          break;
        }
        await _delay(const Duration(seconds: 1));
      }
      if (observedOn == null) {
        throw const SmartChargerException(
          'Không quan sát được relay ON và timer trên Shelly sau lệnh duy nhất.',
          code: 'timerNotArmed',
        );
      }
      final on = observedOn;
      if (on.powerW > 5 ||
          on.currentA > .1 ||
          on.voltageV < 190 ||
          on.voltageV > 255) {
        throw const SmartChargerException(
          'Test không tải phát hiện công suất/dòng điện hoặc điện áp ngoài ngưỡng an toàn.',
          code: 'unexpectedLoad',
        );
      }
      await _delay(const Duration(seconds: 6));
    } on SmartChargerException catch (error) {
      failure = error;
    } finally {
      await _bestEffortOff(selected);
    }
    try {
      observedOff = await _getStatus(selected);
    } on SmartChargerException {
      await _markUncertainRelay();
      throw const SmartChargerException(
        'Không xác minh được relay OFF sau test; hãy ngắt nguồn vật lý ngay.',
        code: 'relayUnverified',
      );
    }
    final off = observedOff;
    if (off.relay) {
      await _markUncertainRelay();
      throw const SmartChargerException(
        'Không xác minh được relay OFF. Hãy ngắt tải vật lý ngay.',
        code: 'relayUnverified',
      );
    }
    final failureError = failure;
    if (failureError != null) throw failureError;
    return ShellySafetyTestResult(
      initialStatus: initial,
      onObserved: observedOn != null,
      timerObserved: (observedOn?.timerRemaining?.inSeconds ?? 0) > 0,
      offVerified: !off.relay,
      noLoadPowerW: observedOn?.powerW ?? 0,
      noLoadCurrentA: observedOn?.currentA ?? 0,
      verifiedAt: _clock(),
    );
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
      await _markUncertainRelay();
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
    final uncertain =
        (await _preferences()).getBool(_uncertainRelayKey) == true;
    return SmartChargerCapabilities(
      canReadStatus: verification.cloudVerified || verification.lanVerified,
      canManualOn: verification.readyForControl && !uncertain,
      canManualOff: verification.cloudVerified || verification.lanVerified,
      supportsDeviceTimer:
          verification.cloudVerified || verification.lanVerified,
      canReadPower: verification.powerMeterVerified,
      canConfigureSafeBoot: profile.hasLan,
      cloudAvailable: verification.cloudVerified,
      lanAvailable: verification.lanVerified,
      safeBootVerified: verification.safeBootVerified,
      noLoadTestVerified: verification.noLoadTestVerified,
      readyForControl: verification.readyForControl && !uncertain,
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

  Future<ShellyTransport> _verifyBeforeOn(
    ShellyConnectionProfile profile,
  ) async {
    if ((await _preferences()).getBool(_uncertainRelayKey) == true) {
      throw const SmartChargerException(
        'Relay đang ở trạng thái chưa xác định. Hãy đọc lại hoặc tắt Shelly vật lý trước khi bật lại.',
        code: 'uncertainRelayState',
      );
    }
    try {
      final snapshot = await getCloudSnapshot(profile: profile);
      if (!snapshot.powerMeterFieldsPresent) {
        throw const SmartChargerException(
          'Shelly không trả đủ trường đo công suất, dòng, điện áp và điện năng.',
          code: 'powerMeterUnavailable',
        );
      }
      if (snapshot.switchConfig?.isSafeForCharging != true) {
        throw const SmartChargerException(
          'Safe Boot chưa được xác minh. Hãy đặt Power-on default OFF và tắt Auto ON trong Shelly Smart Control.',
          code: 'safeBootUnverified',
        );
      }
      if (snapshot.status.relay) {
        throw const SmartChargerException(
          'Relay đang ON; hãy xác minh phiên hiện tại trước khi bắt đầu lại.',
          code: 'activeSessionConflict',
        );
      }
      await _clearUncertainRelay();
      return ShellyTransport.cloud;
    } on SmartChargerException {
      if (!profile.hasLan) rethrow;
      final info = await _translate(() => _lan.getDeviceInfo(profile));
      final model = (info['model'] ?? info['app'] ?? info['code'])
          ?.toString()
          .toUpperCase();
      final generation = int.tryParse(
        info['gen']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      );
      if (model != 'S3PL-00112EU' || generation != 3) {
        throw const SmartChargerException(
          'Shelly không đúng Plug S Gen3.',
          code: 'unsupportedDevice',
        );
      }
      final config = await _translate(() => _lan.getSwitchConfig(profile));
      final safe = ShellySwitchConfig.fromJson(config);
      if (safe?.isSafeForCharging != true) {
        throw const SmartChargerException(
          'Safe Boot chưa được xác minh trên Shelly.',
          code: 'safeBootUnverified',
        );
      }
      final status = await _translate(() => _lan.getStatus(profile));
      if (status.voltageV <= 0) {
        throw const SmartChargerException(
          'Không đọc được điện áp từ power meter Shelly.',
          code: 'powerMeterUnavailable',
        );
      }
      if (status.relay) {
        throw const SmartChargerException(
          'Relay đang ON; hãy xác minh phiên hiện tại trước khi bắt đầu lại.',
          code: 'activeSessionConflict',
        );
      }
      await _clearUncertainRelay();
      return ShellyTransport.lan;
    }
  }

  Future<void> _setSwitchAtTransport(
    ShellyConnectionProfile profile,
    ShellyTransport transport, {
    required bool on,
    Duration? toggleAfter,
    String? operationId,
  }) async {
    if (transport == ShellyTransport.cloud) {
      await _translate(
        () => _cloud.setSwitch(
          profile,
          on: on,
          toggleAfter: toggleAfter,
          operationId: operationId,
        ),
      );
      _lastTransport = ShellyTransport.cloud;
    } else {
      await _translate(
        () => _lan.setSwitch(profile, on: on, toggleAfter: toggleAfter),
      );
      _lastTransport = ShellyTransport.lan;
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
    final capabilities = await this.capabilities();
    if (!capabilities.readyForControl) {
      throw const SmartChargerException(
        'Shelly chưa hoàn tất kiểm tra an toàn. Hãy xác minh power meter, Safe Boot và test không tải trước khi bật relay.',
        code: 'notReadyForControl',
      );
    }
    final transport = await _verifyBeforeOn(profile);
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
      // The selected transport is fixed by the preflight. If this request
      // times out, do not retry ON through another transport: the device may
      // already have accepted the first command.
      await _setSwitchAtTransport(
        profile,
        transport,
        on: true,
        toggleAfter: duration,
        operationId: session.sessionId,
      );
    } on SmartChargerException catch (error) {
      if (!error.commandMayHaveReachedDevice) {
        await _clearActive();
        rethrow;
      }
      // A timeout/5xx can mean that Shelly accepted ON even though the
      // response was lost. Never retry ON or silently return to idle.
      await _bestEffortOff(profile);
      try {
        final status = await _getStatus(profile);
        if (!status.relay) {
          await _clearActive();
          await _clearUncertainRelay();
          rethrow;
        }
      } on SmartChargerException {
        // Keep the pending operation and lock control until a later readback.
      }
      await _markUncertainRelay();
      throw SmartChargerException(
        'Không xác định được kết quả lệnh bật; đã gửi OFF và cần đọc lại relay trước khi thử lại.',
        statusCode: error.statusCode,
        providerCode: error.providerCode,
        code: 'uncertainRelayState',
        retryable: true,
        sessionId: session.sessionId,
        commandMayHaveReachedDevice: true,
      );
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
      await _markUncertainRelay();
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
      lastMeterEnergyWh: verified.energyWh,
      estimatedSoc: plan.currentSoc,
      chargingEfficiency:
          SmartChargeEnergyAccumulator.defaultChargingEfficiency,
      capacitySource: plan.estimatedCapacityWh > 0 ? 'vehicle_catalog' : null,
      socEstimateSource: plan.estimatedCapacityWh > 0 ? 'shelly_energy' : null,
      socEstimateQuality: plan.estimatedCapacityWh > 0 ? 'live' : 'unavailable',
      socEstimationVersion: 2,
      transport: verified.transport?.name ?? _lastTransport?.name,
      version: 2,
    );
    await _saveActive(active);
    await _clearUncertainRelay();
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
    final before = await _getStatus(profile);
    if (!before.relay || (before.timerRemaining?.inSeconds ?? 0) <= 0) {
      throw const SmartChargerException(
        'Không rearm khi relay hoặc timer hiện tại chưa được xác minh.',
        code: 'uncertainRelayState',
      );
    }
    final transport = _lastTransport ?? await _verifyBeforeOn(profile);
    try {
      await _setSwitchAtTransport(
        profile,
        transport,
        on: true,
        toggleAfter: safeDuration,
        operationId: session.sessionId,
      );
    } on SmartChargerException {
      await _bestEffortOff(profile);
      await _markUncertainRelay();
      throw const SmartChargerException(
        'Không xác minh được timer mới; relay đã được yêu cầu OFF.',
        code: 'uncertainRelayState',
        retryable: true,
      );
    }
    await _delay(const Duration(seconds: 1));
    SmartChargerStatus status;
    try {
      status = await _getStatus(profile);
    } on SmartChargerException {
      await _bestEffortOff(profile);
      await _markUncertainRelay();
      throw const SmartChargerException(
        'Không đọc lại được relay sau khi hiệu chỉnh timer; đã yêu cầu OFF.',
        code: 'uncertainRelayState',
        retryable: true,
      );
    }
    if (!status.relay || (status.timerRemaining?.inSeconds ?? 0) <= 0) {
      await _bestEffortOff(profile);
      await _markUncertainRelay();
      throw const SmartChargerException(
        'Shelly không xác nhận timer hiệu chỉnh; relay đã được yêu cầu OFF.',
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
    await _clearUncertainRelay();
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
      await _markUncertainRelay();
      throw const SmartChargerException(
        'Không xác minh được relay OFF. Hãy rút phích cắm hoặc tắt Shelly vật lý ngay.',
        code: 'relayUnverified',
      );
    }
    final active = await _readActive();
    if (active == null) {
      await _clearUncertainRelay();
      return null;
    }
    final measured = _withMeterReading(active, status);
    final stopped = measured.copyWith(
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
      transport: status.transport?.name,
      version: active.version + 1,
    );
    await _clearActive();
    await _clearUncertainRelay();
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
      final updated = _withMeterReading(active, status).copyWith(
        state: ChargingSessionState.active,
        updatedAt: now,
        effectiveStopAt: now.add(status.timerRemaining!),
        transport: status.transport?.name,
      );
      await _saveActive(updated);
      await _clearUncertainRelay();
      return updated;
    }
    final nearPlanned =
        now.difference(active.effectiveStopAt).abs() <=
        const Duration(minutes: 2);
    final stopped = _withMeterReading(active, status).copyWith(
      state: nearPlanned
          ? ChargingSessionState.completed
          : ChargingSessionState.interrupted,
      updatedAt: now,
      stoppedAt: now,
      stopReason: nearPlanned
          ? ChargingStopReason.plannedTimer
          : ChargingStopReason.relayOff,
      relayVerified: true,
      transport: status.transport?.name,
    );
    await _clearActive();
    await _clearUncertainRelay();
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
        'Shelly chưa hoàn tất kiểm tra an toàn.',
        code: 'notReadyForControl',
      );
    }
    return armSmartCharge(
      SmartChargePlan(
        vehicleId: vehicleId,
        currentSoc: currentSoc,
        targetSoc: currentSoc,
        duration: duration,
        // Manual timed charging has no SOC target; do not inject a fake
        // capacity that would make the live SOC/energy estimate look real.
        estimatedCapacityWh: 0,
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

  Future<SmartChargingSession?> getCurrentSessionForVehicle(
    String? vehicleId,
  ) async {
    // Check identity before reconciliation.  Reconcile may clear/terminalize
    // the persisted active session when the relay is already OFF; doing that
    // while another vehicle is selected would make vehicle A's session appear
    // to disappear when the user merely browses vehicle B.
    final persisted = await _readActive();
    if (persisted == null) return null;
    if (vehicleId != null &&
        vehicleId.isNotEmpty &&
        persisted.vehicleId != vehicleId) {
      return null;
    }
    return reconcileActiveSession();
  }

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
        statusCode: error.statusCode,
        providerCode: error.providerCode,
        code: error.code.name,
        retryable: error.retryable,
        commandMayHaveReachedDevice: error.commandMayHaveReachedDevice,
      );

  Future<void> _bestEffortOff(ShellyConnectionProfile profile) async {
    final operations = <Future<void>>[
      _cloud
          .setSwitch(profile, on: false)
          .then<void>((_) {})
          .catchError((_) {}),
    ];
    if (profile.hasLan) {
      operations.add(_lan.setSwitch(profile, on: false).catchError((_) {}));
    }
    await Future.wait(operations);
  }

  Future<SmartChargingSession?> _readActive() async {
    final key = _scopedKey(_activeSessionKey);
    if (key == null) return null;
    final raw = (await _preferences()).getString(key);
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
    final key = _scopedKey(_activeSessionKey);
    if (key == null) return;
    await (await _preferences()).setString(key, jsonEncode(session.toJson()));
  }

  /// Persists the latest meter-derived state for the Android foreground
  /// isolate. This is deliberately separate from the history writer.
  Future<void> persistActiveTelemetry(SmartChargingSession session) =>
      _saveActive(session);

  Future<void> _clearActive() async {
    final key = _scopedKey(_activeSessionKey);
    if (key != null) await (await _preferences()).remove(key);
  }

  Future<void> _markUncertainRelay() async {
    final key = _scopedKey(_uncertainRelayKey);
    if (key != null) await (await _preferences()).setBool(key, true);
  }

  Future<void> _clearUncertainRelay() async {
    final key = _scopedKey(_uncertainRelayKey);
    if (key != null) await (await _preferences()).remove(key);
  }

  SmartChargingSession _withMeterReading(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) {
    final meter = SmartChargeEnergyAccumulator.ingest(session, status.energyWh);
    final measured = session.copyWith(
      baselineEnergyWh: meter.baselineEnergyWh,
      lastMeterEnergyWh: meter.lastMeterEnergyWh,
      energyUsedWh: meter.energyUsedWh,
      energyQuality: meter.energyQuality,
    );
    final estimate = SmartChargeEnergyAccumulator.estimate(measured);
    return measured.copyWith(
      estimatedSoc: estimate.soc,
      estimatedStoredEnergyWh: estimate.available
          ? estimate.storedEnergyWh
          : null,
      socEstimateSource: estimate.available ? 'shelly_energy' : 'unavailable',
      socEstimateQuality: estimate.available
          ? (meter.energyQuality == 'good' ? 'live' : 'partial')
          : 'unavailable',
      socEstimationVersion: 2,
    );
  }

  bool _sameDeviceId(String left, String right) {
    String clean(String value) => value.replaceAll(RegExp('[^a-z0-9]'), '');
    return clean(left).endsWith(clean(right)) ||
        clean(right).endsWith(clean(left));
  }
}
