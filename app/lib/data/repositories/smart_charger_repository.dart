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
  Future<SmartChargerBinding?> binding({String? vehicleId});
  Future<SmartChargerCapabilities> capabilities({String? vehicleId});
  Future<SmartChargerStatus> status({String? vehicleId});
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
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(String sessionId);
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
  @override
  bool get calibrationIsServerOwned => false;

  @override
  Future<SmartChargerBinding?> binding({String? vehicleId}) async {
    if (!await service.isConfiguredSecurely()) return null;
    return const SmartChargerBinding(
      deviceId: 'local-secure-profile',
      displayName: 'Shelly Plug S Gen3',
      model: 'S3PL-00112EU',
      provider: 'direct',
      mode: SmartChargerConnectionMode.advancedDirect,
      powerMeterVerified: true,
    );
  }

  @override
  Future<SmartChargerCapabilities> capabilities({String? vehicleId}) =>
      service.capabilities();

  @override
  Future<SmartChargerStatus> status({String? vehicleId}) => service.getStatus();
  @override
  Future<SmartChargingPlanPreview> preview(SmartChargingPlanDraft draft) =>
      _previewService?.createPreview(draft) ?? predictor.predict(draft);
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
    return service.getCurrentSessionForVehicle(vehicleId);
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
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(String sessionId) =>
      _chargeLogs?.getTelemetry(sessionId) ?? Future.value(const []);

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
    final stopped = id == null
        ? await service.turnOffAndVerify()
        : await service.stopSession(id, expectedVersion: expectedVersion);
    final withReason = stopped?.copyWith(userStopReason: userStopReason);
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
  Future<SmartChargerBinding?> binding({String? vehicleId}) =>
      service.getBinding(vehicleId: vehicleId);
  @override
  Future<SmartChargerCapabilities> capabilities({String? vehicleId}) =>
      service.getCapabilities(vehicleId: vehicleId);
  @override
  Future<SmartChargerStatus> status({String? vehicleId}) =>
      service.getStatus(vehicleId: vehicleId);
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
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(String sessionId) =>
      service.telemetry(sessionId);

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
  static Future<SmartChargerConnectionMode> currentMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modeKey);
    if (raw == 'advanced_direct') {
      return SmartChargerConnectionMode.advancedDirect;
    }
    if (raw == null &&
        await SmartChargerCredentialsService().readProfile() != null) {
      await prefs.setString(_modeKey, 'advanced_direct');
      return SmartChargerConnectionMode.advancedDirect;
    }
    return SmartChargerConnectionMode.serverCloud;
  }

  static Future<void> setMode(SmartChargerConnectionMode mode) async =>
      (await SharedPreferences.getInstance()).setString(
        _modeKey,
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
      ChargingPredictionAdapter(),
      previewService: ServerSmartChargerService(),
      chargeLogs: chargeLogs,
    );
  }
}
