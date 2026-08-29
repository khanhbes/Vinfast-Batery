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
  Future<SmartChargerBinding?> binding();
  Future<SmartChargerCapabilities> capabilities();
  Future<SmartChargerStatus> status();
  Future<SmartChargingPlanPreview> preview(SmartChargingPlanDraft draft);
  Future<SmartChargingSession> start(
    SmartChargingPlanPreview preview,
    String idempotencyKey,
  );
  Future<SmartChargingSession?> current();
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
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
  Future<void> flushPendingTelemetry(String sessionId);
  Future<SmartChargeStopResult> stop(String? sessionId, {int? expectedVersion});
  Future<SmartChargingSession> rearm(Duration duration);
  Future<void> manualOff();
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
  Future<SmartChargerBinding?> binding() async {
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
  Future<SmartChargerCapabilities> capabilities() => service.capabilities();

  @override
  Future<SmartChargerStatus> status() => service.getStatus();
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
      hardDeadlineAt: preview.draft.hardDeadlineAt,
      estimatedCapacityWh: preview.draft.estimatedCapacityWh,
      acknowledgeEstimatedSoc: true,
      predictedDurationSeconds: preview.predictedDurationSeconds,
      modelKey: preview.modelKey,
      modelVersion: preview.modelVersion,
      runtimeHealth: preview.runtimeHealth,
      predictionWarnings: preview.warnings,
      fallbackReason: preview.fallbackReason,
      predictionAnalyzedAt: preview.analyzedAt,
    ),
    idempotencyKey: key,
  );
  @override
  Future<SmartChargingSession?> current() => service.getCurrentSession();
  @override
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
  }) async =>
      _chargeLogs?.getHistoryPage(
        limit: limit,
        cursor: cursor,
        strategy: strategy,
      ) ??
      SmartChargeHistoryPage(
        items: await service.getSessionHistory(limit: limit),
      );

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
  Future<void> flushPendingTelemetry(String sessionId) =>
      _chargeLogs?.flushPendingTelemetry(sessionId) ?? Future.value();
  @override
  Future<SmartChargeStopResult> stop(String? id, {int? expectedVersion}) async {
    final stopped = id == null
        ? await service.turnOffAndVerify()
        : await service.stopSession(id, expectedVersion: expectedVersion);
    return SmartChargeStopResult(
      relayOffVerified: true,
      session: stopped,
      alreadyStopped: stopped == null,
      historySyncPending: stopped != null && _chargeLogs == null,
    );
  }

  @override
  Future<SmartChargingSession> rearm(Duration duration) =>
      service.rearmTimer(duration);
  @override
  Future<void> manualOff() async {
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
  ServerSmartChargerRepository(this.service);
  final ServerSmartChargerService service;
  @override
  bool get calibrationIsServerOwned => true;
  @override
  Future<SmartChargerBinding?> binding() => service.getBinding();
  @override
  Future<SmartChargerCapabilities> capabilities() => service.getCapabilities();
  @override
  Future<SmartChargerStatus> status() => service.getStatus();
  @override
  Future<SmartChargingPlanPreview> preview(SmartChargingPlanDraft draft) =>
      service.createPreview(draft);
  @override
  Future<SmartChargingSession> start(
    SmartChargingPlanPreview preview,
    String key,
  ) => service.start(preview, key);
  @override
  Future<SmartChargingSession?> current() => service.current();
  @override
  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
  }) async {
    final items = await service.history(limit: limit);
    final filtered = strategy == null
        ? items
        : items
              .where(
                (item) => strategy == ChargingStrategy.aiTarget
                    ? item.strategy != ChargingStrategy.manualTimed
                    : item.strategy == strategy,
              )
              .toList();
    return SmartChargeHistoryPage(items: filtered);
  }

  @override
  Future<List<SmartChargeTelemetryPoint>> getTelemetry(
    String sessionId,
  ) async => const [];

  @override
  Future<SmartChargeEnergySummary> confirmActualEndSoc(
    SmartChargingSession session,
    double soc,
  ) => throw const SmartChargerException(
    'Xác nhận SOC chưa khả dụng ở chế độ Easy.',
    code: 'notSupported',
  );

  @override
  Future<void> recordStatusSample(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) async {}

  @override
  Future<void> flushPendingTelemetry(String sessionId) async {}
  @override
  Future<SmartChargeStopResult> stop(String? id, {int? expectedVersion}) async {
    final stopped = await service.off(id);
    return SmartChargeStopResult(
      relayOffVerified: true,
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
  Future<void> manualOff() async {
    await service.off();
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
    return mode == SmartChargerConnectionMode.serverCloud
        ? ServerSmartChargerRepository(ServerSmartChargerService())
        : DirectSmartChargerRepository(
            SmartChargerService(),
            ChargingPredictionAdapter(),
            previewService: ServerSmartChargerService(),
            chargeLogs: ShellyChargeLogService(),
          );
  }
}
