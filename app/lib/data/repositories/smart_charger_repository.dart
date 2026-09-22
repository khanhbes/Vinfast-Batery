import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/smart_charger_binding.dart';
import '../models/smart_charger_capabilities.dart';
import '../models/smart_charger_status.dart';
import '../models/smart_charge_history.dart';
import '../models/smart_charging_session.dart';
import '../services/charging_prediction_adapter.dart';
import '../services/server_smart_charger_service.dart';
import '../services/smart_charger_credentials_service.dart';
import '../services/smart_charger_service.dart';
import '../services/shelly_charge_log_service.dart';

abstract interface class SmartChargerRepository {
  bool get calibrationIsServerOwned;
  SmartChargeTelemetryOwner get telemetryOwner;
  Future<SmartChargerBinding?> binding({String? vehicleId});
  Future<SmartChargerCapabilities> capabilities({String? vehicleId});
  Future<SmartChargerStatus> status({String? vehicleId});
  Future<SmartChargerLiveSnapshot> live({String? vehicleId});
  Future<SmartChargingPlanPreview> preview(SmartChargingPlanDraft draft);
  Future<SmartChargingSession> start(
    SmartChargingPlanPreview preview,
    String idempotencyKey,
  );
  Future<SmartChargingSession?> current({String? vehicleId});
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
    String? vehicleId,
  });
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(
    String sessionId, {
    String? after,
    int limit = 120,
  });
  Future<SmartChargeEnergySummary> confirmActualEndSoc(
    SmartChargingSession session,
    double soc,
  );
  Future<void> recordStatusSample(
    SmartChargingSession session,
    SmartChargerStatus status,
  );
  Future<void> saveActiveSession(SmartChargingSession session);
  Future<void> flushPendingTelemetry(String sessionId);
  Future<void> hideSession(String sessionId);
  Future<void> privacyEraseSession(String sessionId, String confirmation);
  Future<SmartChargeStopResult> stop(
    String? sessionId, {
    int? expectedVersion,
    UserStopReason userStopReason = UserStopReason.none,
  });
  Future<SmartChargingSession> rearm(Duration duration);
  Future<void> manualOff({String? vehicleId});
  Future<SmartChargingSession> manualOn(
    Duration duration,
    String idempotencyKey, {
    required String vehicleId,
    required double currentSoc,
  });
}

class SmartChargerLiveSnapshot {
  const SmartChargerLiveSnapshot({required this.status, this.session});
  final SmartChargerStatus status;
  final SmartChargingSession? session;
}

enum SmartChargeTelemetryOwner { clientDirect, server }

class DirectSmartChargerRepository implements SmartChargerRepository {
  DirectSmartChargerRepository(
    this.service,
    this.predictor, {
    ServerSmartChargerService? previewService,
    ShellyChargeLogService? chargeLogs,
  }) : _previewService = previewService,
       _chargeLogs = chargeLogs;
  final SmartChargerService service;
  final ChargingPredictionAdapter predictor;
  final ServerSmartChargerService? _previewService;
  final ShellyChargeLogService? _chargeLogs;

  String _normalizeDeviceId(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  @override
  bool get calibrationIsServerOwned => false;
  @override
  SmartChargeTelemetryOwner get telemetryOwner =>
      SmartChargeTelemetryOwner.clientDirect;

  @override
  Future<SmartChargerBinding?> binding({String? vehicleId}) async {
    final profile = await SmartChargerCredentialsService().readProfile(
      vehicleId: vehicleId,
    );
    if (profile == null) return null;
    final verification = await SmartChargerCredentialsService()
        .readVerification();
    return SmartChargerBinding(
      deviceId: profile.deviceId,
      displayName: profile.deviceName,
      model: profile.model,
      provider: 'direct',
      mode: SmartChargerConnectionMode.advancedDirect,
      powerMeterVerified: verification.powerMeterVerified,
      safeBootVerified: verification.safeBootVerified,
      noLoadTestVerified: verification.noLoadTestVerified,
      lastVerifiedAt: verification.lastVerifiedAt,
    );
  }

  @override
  Future<SmartChargerCapabilities> capabilities({String? vehicleId}) =>
      service.capabilities();

  @override
  Future<SmartChargerStatus> status({String? vehicleId}) => service.getStatus();
  @override
  Future<SmartChargerLiveSnapshot> live({String? vehicleId}) async {
    final status = await service.getStatus();
    return SmartChargerLiveSnapshot(status: status);
  }

  @override
  Future<SmartChargingPlanPreview> preview(SmartChargingPlanDraft draft) async {
    if (_previewService != null) {
      try {
        return await _previewService.createPreview(draft);
      } catch (_) {
        // Remote server preview failed; fall back to local predictor
      }
    }
    return predictor.predict(draft);
  }

  @override
  Future<SmartChargingSession> start(
    SmartChargingPlanPreview preview,
    String key,
  ) => service.startAutomaticSession(
    SmartChargingSessionRequest(
      vehicleId: preview.draft.vehicleId,
      startSoc: preview.draft.currentSoc,
      targetSoc: preview.draft.targetSoc,
      predictedMinutes: preview.predictedMinutes,
      startedAt: DateTime.now(),
      predictedFullAt: preview.aiStopAt,
      chargingMode: preview.draft.chargingMode,
      predictionSource: preview.predictionSource,
      predictionConfidence: preview.predictionConfidence,
      strategy: preview.draft.strategy,
      // targetSoc/aiTarget use a relative ten-hour safety window created by
      // SmartChargerService at the moment the relay is armed. Forwarding the
      // draft's initialization-time deadline could silently shorten a fresh
      // a long ETA to only the time left since the screen was first opened.
      hardDeadlineAt:
          preview.draft.strategy == ChargingStrategy.deadline ||
              preview.draft.strategy == ChargingStrategy.smartCombined
          ? preview.draft.hardDeadlineAt
          : null,
      estimatedCapacityWh: preview.draft.estimatedCapacityWh,
      acknowledgeEstimatedSoc: true,
      predictedDurationSeconds: preview.predictedDurationSeconds,
      modelKey: preview.modelKey,
      modelVersion: preview.modelVersion,
      runtimeHealth: preview.runtimeHealth,
      predictionWarnings: preview.warnings,
      fallbackReason: preview.fallbackReason,
      predictionAnalyzedAt: preview.analyzedAt,
      etaCandidates: preview.etaCandidates,
      fusionReason: preview.fusionReason,
      profileVersion: preview.profileVersion,
      adapterVersion: preview.adapterVersion,
    ),
    idempotencyKey: key,
  );
  @override
  Future<SmartChargingSession?> current({String? vehicleId}) async {
    // Check identity before reconciliation so merely browsing another
    // vehicle cannot terminalize or clear the active session.
    final local = await service.getCurrentSessionForVehicle(vehicleId);
    if (local != null) return local;
    // A second device has no local session. Restore the durable account
    // record, but do not treat it as permission to issue ON/rearm commands.
    return _chargeLogs?.getActiveSession(vehicleId: vehicleId);
  }

  @override
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
    String? vehicleId,
  }) async =>
      _chargeLogs?.getHistoryPage(
        limit: limit,
        cursor: cursor,
        strategy: strategy,
        vehicleId: vehicleId,
      ) ??
      _filteredLocalHistory(
        limit: limit,
        strategy: strategy,
        vehicleId: vehicleId,
      );

  Future<SmartChargeHistoryPage> _filteredLocalHistory({
    required int limit,
    ChargingStrategy? strategy,
    String? vehicleId,
  }) async {
    final all = await service.getSessionHistory(limit: 100);
    final filtered = all
        .where((item) {
          if (vehicleId != null &&
              vehicleId.isNotEmpty &&
              item.vehicleId != vehicleId) {
            return false;
          }
          if (strategy != null && item.strategy != strategy) return false;
          return true;
        })
        .take(limit)
        .toList();
    return SmartChargeHistoryPage(items: filtered);
  }

  @override
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(
    String sessionId, {
    String? after,
    int limit = 120,
  }) => _chargeLogs?.getTelemetry(sessionId) ?? Future.value(const []);

  @override
  Future<SmartChargeEnergySummary> confirmActualEndSoc(
    SmartChargingSession session,
    double soc,
  ) {
    final logs = _chargeLogs;
    if (logs == null) throw StateError('Charge log service is unavailable.');
    return logs.confirmActualEndSoc(session, soc);
  }

  @override
  Future<void> recordStatusSample(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) => _chargeLogs?.recordStatusSample(session, status) ?? Future.value();

  @override
  Future<void> saveActiveSession(SmartChargingSession session) =>
      _chargeLogs?.saveActiveSession(session) ?? Future.value();

  @override
  Future<void> flushPendingTelemetry(String sessionId) =>
      _chargeLogs?.flushPendingTelemetry(sessionId) ?? Future.value();
  @override
  Future<void> hideSession(String sessionId) =>
      _chargeLogs?.hideSession(sessionId) ??
      Future.error(StateError('Charge log service is unavailable.'));
  @override
  Future<void> privacyEraseSession(
    String sessionId,
    String confirmation,
  ) async {
    // Privacy erase is authoritative on the authenticated backend. Admin SDK
    // can remove terminal legacy documents and every nested collection without
    // exposing broad Firestore delete permissions to the mobile client.
    final remote = _previewService;
    if (remote != null) {
      try {
        await remote.privacyEraseSession(sessionId, confirmation);
        return;
      } on SmartChargerException catch (error) {
        final mayUseDirectFallback =
            error.retryable ||
            error.statusCode == 404 ||
            error.code == 'sessionNotFound';
        if (!mayUseDirectFallback) rethrow;
      } on Object {
        // Offline Direct mode may still use owner-scoped Firestore rules.
      }
    }
    final logs = _chargeLogs;
    if (logs == null) {
      throw StateError('Charge log service is unavailable.');
    }
    await logs.privacyEraseSession(sessionId, confirmation);
  }

  @override
  Future<SmartChargeStopResult> stop(
    String? id, {
    int? expectedVersion,
    UserStopReason userStopReason = UserStopReason.none,
  }) async {
    final remoteSessions = id == null
        ? const <SmartChargingSession>[]
        : await _chargeLogs?.getActiveSessions() ?? const [];
    SmartChargingSession? remoteActive;
    for (final item in remoteSessions) {
      if (item.sessionId == id) {
        remoteActive = item;
        break;
      }
    }
    if (remoteActive != null) {
      // A session restored on another device is controllable only when this
      // device has the same account-scoped profile and a live Cloud snapshot
      // confirms the exact Shelly identity/model. Metadata alone is never a
      // permission to send OFF to an arbitrary relay.
      final expectedDeviceId = remoteActive.deviceId;
      if (expectedDeviceId == null || expectedDeviceId.trim().isEmpty) {
        throw const SmartChargerException(
          'Phiên đồng bộ thiếu Device ID Shelly để xác minh an toàn.',
          code: 'deviceMismatch',
        );
      }
      final profile = await SmartChargerCredentialsService().readProfile(
        vehicleId: remoteActive.vehicleId,
      );
      if (profile == null) {
        throw const SmartChargerException(
          'Chưa khôi phục được cấu hình Shelly của tài khoản này.',
          code: 'notConfigured',
          retryable: true,
        );
      }
      final snapshot = await service.getCloudSnapshot(profile: profile);
      if (_normalizeDeviceId(snapshot.deviceId) !=
          _normalizeDeviceId(expectedDeviceId)) {
        throw const SmartChargerException(
          'Shelly hiện tại không khớp thiết bị của phiên đang sạc.',
          code: 'deviceMismatch',
        );
      }
    }
    final stopped = id == null
        ? await service.turnOffAndVerify()
        : await service.stopSession(id, expectedVersion: expectedVersion);
    final recovered =
        stopped ??
        remoteActive?.copyWith(
          state: ChargingSessionState.cancelled,
          stoppedAt: DateTime.now(),
          updatedAt: DateTime.now(),
          stopReason: ChargingStopReason.manual,
          userStopReason: userStopReason,
          relayVerified: true,
          version: remoteActive.version + 1,
        );
    if (stopped == null && recovered != null) {
      await _chargeLogs?.saveTerminalSession(recovered);
    }
    final withReason = recovered?.copyWith(userStopReason: userStopReason);
    return SmartChargeStopResult(
      // SmartChargerService only returns after an OFF readback. Preserve that
      // invariant in the public result instead of claiming success merely
      // because the command request completed.
      relayOffVerified: withReason == null || withReason.relayVerified,
      session: withReason,
      alreadyStopped: withReason == null,
      historySyncPending: withReason != null && _chargeLogs == null,
    );
  }

  @override
  Future<SmartChargingSession> rearm(Duration duration) =>
      service.rearmTimer(duration);
  @override
  Future<void> manualOff({String? vehicleId}) async {
    await service.turnOff();
  }

  @override
  Future<SmartChargingSession> manualOn(
    Duration duration,
    String idempotencyKey, {
    required String vehicleId,
    required double currentSoc,
  }) => service.manualOn(
    duration,
    idempotencyKey: idempotencyKey,
    vehicleId: vehicleId,
    currentSoc: currentSoc,
  );
}

class ServerSmartChargerRepository implements SmartChargerRepository {
  ServerSmartChargerRepository(
    this.service, {
    ShellyChargeLogService? chargeLogs,
  }) : _chargeLogs = chargeLogs;
  final ServerSmartChargerService service;
  final ShellyChargeLogService? _chargeLogs;
  @override
  bool get calibrationIsServerOwned => true;
  @override
  SmartChargeTelemetryOwner get telemetryOwner =>
      SmartChargeTelemetryOwner.server;
  @override
  Future<SmartChargerBinding?> binding({String? vehicleId}) =>
      service.getBinding(vehicleId: vehicleId);
  @override
  Future<SmartChargerCapabilities> capabilities({String? vehicleId}) =>
      service.getCapabilities(vehicleId: vehicleId);
  @override
  Future<SmartChargerStatus> status({String? vehicleId}) =>
      service.getStatus(vehicleId: vehicleId);
  @override
  Future<SmartChargerLiveSnapshot> live({String? vehicleId}) async {
    final data = await service.getLive(vehicleId: vehicleId);
    final status = SmartChargerStatus.fromJson(
      Map<String, dynamic>.from(data['status'] as Map? ?? const {}),
    );
    final rawSession = data['session'];
    return SmartChargerLiveSnapshot(
      status: status,
      session: rawSession is Map
          ? SmartChargingSession.fromJson(Map<String, dynamic>.from(rawSession))
          : null,
    );
  }

  @override
  Future<SmartChargingPlanPreview> preview(SmartChargingPlanDraft draft) =>
      service.createPreview(draft);
  @override
  Future<SmartChargingSession> start(
    SmartChargingPlanPreview preview,
    String key,
  ) => service.start(preview, key);
  @override
  Future<SmartChargingSession?> current({String? vehicleId}) =>
      service.current(vehicleId: vehicleId);
  @override
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
    String? vehicleId,
  }) async {
    final chargeLogs = _chargeLogs;
    if (chargeLogs != null) {
      try {
        // ChargeLogs is the shared canonical history for Direct and Easy.
        // It also preserves restored partial sessions that predate the API.
        return await chargeLogs.getHistoryPage(
          limit: limit,
          cursor: cursor,
          strategy: strategy,
          vehicleId: vehicleId,
        );
      } on Object {
        // A temporary Firestore issue must not remove server-owned history.
      }
    }
    return service.historyPage(
      limit: limit,
      cursor: cursor,
      strategy: strategy,
      vehicleId: vehicleId,
    );
  }

  @override
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(
    String sessionId, {
    String? after,
    int limit = 120,
  }) => service.telemetry(sessionId, after: after, limit: limit);

  @override
  Future<SmartChargeEnergySummary> confirmActualEndSoc(
    SmartChargingSession session,
    double soc,
  ) async {
    final updated = await service.confirmActualSoc(session.sessionId, soc);
    final points = await service.telemetry(session.sessionId);
    return SmartChargeEnergySummary.calculate(
      session: updated,
      points: points,
      confirmedEndSoc: soc,
    );
  }

  @override
  Future<void> recordStatusSample(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) => service.recordTelemetry(session.sessionId, status);

  @override
  Future<void> saveActiveSession(SmartChargingSession session) =>
      _chargeLogs?.saveActiveSession(session) ?? Future.value();

  @override
  Future<void> flushPendingTelemetry(String sessionId) =>
      _chargeLogs?.flushPendingTelemetry(sessionId) ?? Future.value();
  @override
  Future<void> hideSession(String sessionId) => service.hideSession(sessionId);
  @override
  Future<void> privacyEraseSession(String sessionId, String confirmation) =>
      service.privacyEraseSession(sessionId, confirmation);
  @override
  Future<SmartChargeStopResult> stop(
    String? id, {
    int? expectedVersion,
    UserStopReason userStopReason = UserStopReason.none,
  }) async {
    final stopped = id == null
        ? await service.off()
        : await service.stop(
            id,
            expectedVersion: expectedVersion ?? 1,
            userStopReason: userStopReason.wireValue,
          );
    return SmartChargeStopResult(
      // The server must persist relay verification on the terminal session;
      // an already-stopped (null) response is safe by definition.
      relayOffVerified: stopped == null || stopped.relayVerified,
      session: stopped,
      alreadyStopped: stopped == null,
    );
  }

  @override
  Future<SmartChargingSession> rearm(Duration duration) =>
      throw const SmartChargerException(
        'Server tự hiệu chỉnh timer.',
        code: 'serverOwned',
      );
  @override
  Future<void> manualOff({String? vehicleId}) async {
    await service.off(vehicleId: vehicleId);
  }

  @override
  Future<SmartChargingSession> manualOn(
    Duration duration,
    String idempotencyKey, {
    required String vehicleId,
    required double currentSoc,
  }) => service.manualOn(
    duration,
    idempotencyKey: idempotencyKey,
    vehicleId: vehicleId,
    currentSoc: currentSoc,
  );
}

class SmartChargerRepositoryFactory {
  static const _modeKey = 'smart_charger.connection_mode.v1';
  static String? _scopedModeKey() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return uid == null ? null : '$_modeKey.$uid';
    } on Object {
      return _modeKey;
    }
  }

  static Future<SmartChargerConnectionMode> currentMode() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scopedModeKey();
    if (key == null) return SmartChargerConnectionMode.serverCloud;
    final raw = prefs.getString(key);
    if (raw == 'advanced_direct') {
      return SmartChargerConnectionMode.advancedDirect;
    }
    final credentials = SmartChargerCredentialsService();
    if (raw == null &&
        await credentials.readProfile() != null &&
        (await credentials.readVerification()).readyForControl) {
      await prefs.setString(key, 'advanced_direct');
      return SmartChargerConnectionMode.advancedDirect;
    }
    return SmartChargerConnectionMode.serverCloud;
  }

  static Future<void> setMode(SmartChargerConnectionMode mode) async =>
      _scopedModeKey() == null
      ? Future.value()
      : (await SharedPreferences.getInstance()).setString(
          _scopedModeKey()!,
          mode == SmartChargerConnectionMode.serverCloud
              ? 'server_cloud'
              : 'advanced_direct',
        );
  static Future<SmartChargerRepository> create() async {
    final mode = await currentMode();
    if (mode == SmartChargerConnectionMode.serverCloud) {
      final chargeLogs = ShellyChargeLogService();
      await chargeLogs.flushAllPending();
      return ServerSmartChargerRepository(
        ServerSmartChargerService(),
        chargeLogs: chargeLogs,
      );
    }
    final chargeLogs = ShellyChargeLogService();
    // Retry durable telemetry/terminal buffers whenever Direct Smart Charge
    // is opened. A previous Firestore rules/index outage must not strand a
    // valid charging session permanently on the device.
    await chargeLogs.flushAllPending();
    return DirectSmartChargerRepository(
      SmartChargerService(),
      ChargingPredictionAdapter(allowPhysicsFallback: true),
      previewService: ServerSmartChargerService(),
      chargeLogs: chargeLogs,
    );
  }
}
