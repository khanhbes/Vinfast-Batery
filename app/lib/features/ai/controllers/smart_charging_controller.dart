import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/smart_charger_status.dart';
import '../../../data/models/smart_charge_history.dart';
import '../../../data/models/smart_charger_capabilities.dart';
import '../../../data/models/smart_charging_session.dart';
import '../../../data/repositories/charge_log_repository.dart';
import '../../../data/services/charging_prediction_adapter.dart';
import '../../../data/services/smart_charger_service.dart';
import '../../../data/services/smart_charge_telemetry_foreground_service.dart';
import '../../../data/services/shelly_charge_log_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/repositories/smart_charger_repository.dart';
import '../../../data/repositories/vehicle_spec_repository.dart';
import '../../../core/services/notification_center_service.dart';
import '../../../core/services/app_error_reporter.dart';

typedef SmartChargingNotificationSink =
    Future<void> Function(SmartChargingSession session);
typedef SmartChargingLogSink =
    Future<void> Function(SmartChargingSession session);
typedef SmartChargingReminderScheduler =
    Future<void> Function(DateTime scheduledAt, int targetPercent);

enum SmartChargingViewPhase {
  loading,
  editing,
  preview,
  starting,
  active,
  stopping,
  error,
}

enum ChargerDisplayState { connecting, charging, off, offline, error }

class SmartChargingUiState {
  const SmartChargingUiState({
    required this.phase,
    required this.draft,
    required this.now,
    this.preview,
    this.session,
    this.chargerStatus,
    this.history = const [],
    this.gatewayError,
    this.sessionError,
    this.historyError,
    this.historyStatus = SmartChargeHistoryStatus.loading,
    this.telemetryStatus = SmartChargeTelemetryStatus.idle,
    this.historySyncedAt,
    this.actionError,
    this.safetyWarning,
    this.refreshing = false,
    this.capabilities = SmartChargerCapabilities.unavailable,
  });

  final SmartChargingViewPhase phase;
  final SmartChargingPlanDraft draft;
  final SmartChargingPlanPreview? preview;
  final SmartChargingSession? session;
  final SmartChargerStatus? chargerStatus;
  final List<SmartChargingSession> history;
  final String? gatewayError;
  final String? sessionError;
  final String? historyError;
  final SmartChargeHistoryStatus historyStatus;
  final SmartChargeTelemetryStatus telemetryStatus;
  final DateTime? historySyncedAt;
  final String? actionError;
  final String? safetyWarning;
  final bool refreshing;
  final SmartChargerCapabilities capabilities;
  final DateTime now;

  /// Pure hardware-derived charger status for UI representation
  ChargerDisplayState get displayState {
    if (phase == SmartChargingViewPhase.loading || refreshing) {
      return ChargerDisplayState.connecting;
    }
    if (gatewayError != null) {
      return ChargerDisplayState.error;
    }
    final status = chargerStatus;
    if (status == null || !status.online) {
      return ChargerDisplayState.offline;
    }
    if (status.relay) {
      return ChargerDisplayState.charging;
    }
    return ChargerDisplayState.off;
  }

  /// Active session determined by physical relay verification
  bool get hasActiveSession {
    if (session != null && !session!.state.isTerminal) {
      return true;
    }
    // Also consider active if relay is physically ON and charger is online
    if (chargerStatus?.online == true && chargerStatus?.relay == true) {
      return true;
    }
    return false;
  }

  SmartChargingUiState copyWith({
    SmartChargingViewPhase? phase,
    SmartChargingPlanDraft? draft,
    Object? preview = _unset,
    Object? session = _unset,
    Object? chargerStatus = _unset,
    List<SmartChargingSession>? history,
    Object? gatewayError = _unset,
    Object? sessionError = _unset,
    Object? historyError = _unset,
    SmartChargeHistoryStatus? historyStatus,
    SmartChargeTelemetryStatus? telemetryStatus,
    Object? historySyncedAt = _unset,
    Object? actionError = _unset,
    Object? safetyWarning = _unset,
    bool? refreshing,
    SmartChargerCapabilities? capabilities,
    DateTime? now,
  }) => SmartChargingUiState(
    phase: phase ?? this.phase,
    draft: draft ?? this.draft,
    preview: identical(preview, _unset)
        ? this.preview
        : preview as SmartChargingPlanPreview?,
    session: identical(session, _unset)
        ? this.session
        : session as SmartChargingSession?,
    chargerStatus: identical(chargerStatus, _unset)
        ? this.chargerStatus
        : chargerStatus as SmartChargerStatus?,
    history: history ?? this.history,
    gatewayError: identical(gatewayError, _unset)
        ? this.gatewayError
        : gatewayError as String?,
    sessionError: identical(sessionError, _unset)
        ? this.sessionError
        : sessionError as String?,
    historyError: identical(historyError, _unset)
        ? this.historyError
        : historyError as String?,
    historyStatus: historyStatus ?? this.historyStatus,
    telemetryStatus: telemetryStatus ?? this.telemetryStatus,
    historySyncedAt: identical(historySyncedAt, _unset)
        ? this.historySyncedAt
        : historySyncedAt as DateTime?,
    actionError: identical(actionError, _unset)
        ? this.actionError
        : actionError as String?,
    safetyWarning: identical(safetyWarning, _unset)
        ? this.safetyWarning
        : safetyWarning as String?,
    refreshing: refreshing ?? this.refreshing,
    capabilities: capabilities ?? this.capabilities,
    now: now ?? this.now,
  );
}

const _unset = Object();

class SmartChargingController extends StateNotifier<SmartChargingUiState> {
  static const String lastTargetSocKey = 'smart_charge_last_target_soc';

  SmartChargingController({
    required String vehicleId,
    required double currentSoc,
    double estimatedCapacityWh = 0,
    SmartChargerService? service,
    SmartChargerRepository? repository,
    ChargingPredictionAdapter? predictionAdapter,
    DateTime Function()? clock,
    SmartChargingNotificationSink? notificationSink,
    SmartChargingLogSink? logSink,
    SmartChargingReminderScheduler? reminderScheduler,
    Future<void> Function()? reminderCanceller,
    bool autoInitialize = true,
  }) : _repository =
           repository ??
           (service == null && predictionAdapter == null
               ? null
               : DirectSmartChargerRepository(
                   service ?? SmartChargerService(),
                   predictionAdapter ?? ChargingPredictionAdapter(),
                 )),
       _clock = clock ?? DateTime.now,
       _notificationSink = notificationSink,
       _logSink = logSink,
       _reminderScheduler = reminderScheduler,
       _reminderCanceller = reminderCanceller,
       super(
         SmartChargingUiState(
           phase: SmartChargingViewPhase.loading,
           draft: SmartChargingPlanDraft(
             vehicleId: vehicleId,
             currentSoc: currentSoc,
             targetSoc: (currentSoc + 30).clamp(1, 100).toDouble(),
             hardDeadlineAt: (clock ?? DateTime.now)().add(
               const Duration(hours: 10),
             ),
             strategy: ChargingStrategy.targetSoc,
             estimatedCapacityWh: estimatedCapacityWh,
           ),
           now: (clock ?? DateTime.now)(),
         ),
       ) {
    if (autoInitialize) unawaited(initialize());
  }

  SmartChargerRepository? _repository;
  final DateTime Function() _clock;
  final SmartChargingNotificationSink? _notificationSink;
  final SmartChargingLogSink? _logSink;
  final SmartChargingReminderScheduler? _reminderScheduler;
  final Future<void> Function()? _reminderCanceller;
  Timer? _statusTimer;
  Timer? _sessionTimer;
  Timer? _countdownTimer;
  bool _statusRequestRunning = false;
  bool _sessionRequestRunning = false;
  bool _disposed = false;
  String? _idempotencyKey;
  String? _lastNotifiedTerminalId;
  String? _lastLoggedTerminalId;
  final List<double> _stablePowerSamples = [];
  DateTime? _powerSamplingStartedAt;
  DateTime? _lastCalibrationAt;
  StreamSubscription<SmartChargerStatus>? _foregroundStatusSubscription;
  bool _foregroundPolling = false;

  Future<void> initialize() async {
    try {
      _repository ??= await SmartChargerRepositoryFactory.create();
      await _attachForegroundMonitor();
      await _loadLastTargetSoc();
      await _loadVehicleCapacity();
      await Future.wait([
        _refreshCapabilities(),
        _refreshStatus(),
        _refreshSession(),
        _refreshHistory(),
      ]);
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(gatewayError: error.message);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.initialize',
      );
      if (!_disposed) {
        state = state.copyWith(
          gatewayError: 'Không thể khởi tạo Smart Charge. Hãy thử lại.',
        );
      }
    } finally {
      if (!_disposed) {
        state = state.copyWith(
          phase: state.hasActiveSession
              ? SmartChargingViewPhase.active
              : SmartChargingViewPhase.editing,
          refreshing: false,
        );
        _startPolling();
      }
    }
  }

  Future<void> _loadLastTargetSoc() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTarget = prefs.getDouble(lastTargetSocKey);
      if (savedTarget != null && !_disposed) {
        final current = state.draft.currentSoc;
        final target = max(savedTarget, current + 1).clamp(1, 100).toDouble();
        if (target > current) {
          state = state.copyWith(
            draft: SmartChargingPlanDraft(
              vehicleId: state.draft.vehicleId,
              currentSoc: current,
              targetSoc: target,
              hardDeadlineAt: state.draft.hardDeadlineAt,
              strategy: state.draft.strategy,
              timeMode: state.draft.timeMode,
              chargingMode: state.draft.chargingMode,
              estimatedCapacityWh: state.draft.estimatedCapacityWh,
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadVehicleCapacity() async {
    try {
      final vehicle = await ChargeLogRepository().getVehicle(
        state.draft.vehicleId,
      );
      var capacityWh = vehicle?.batteryCapacityWh ?? 0;
      final modelId = vehicle?.vinfastModelId;
      if (capacityWh <= 0 && modelId != null && modelId.isNotEmpty) {
        final spec = await VehicleSpecRepository().getSpec(modelId);
        capacityWh = spec?.nominalCapacityWh ?? 0;
      }
      if (_disposed || capacityWh <= 0) return;
      final old = state.draft;
      state = state.copyWith(
        draft: SmartChargingPlanDraft(
          vehicleId: old.vehicleId,
          currentSoc: old.currentSoc,
          targetSoc: old.targetSoc,
          hardDeadlineAt: old.hardDeadlineAt,
          strategy: old.strategy,
          timeMode: old.timeMode,
          chargingMode: old.chargingMode,
          estimatedCapacityWh: capacityWh,
        ),
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.vehicleCapacity',
      );
      // Missing/offline vehicle metadata must not look like a Shelly failure.
    }
  }

  Future<void> _attachForegroundMonitor() async {
    try {
      SmartChargeTelemetryForegroundService.initialize();
      _foregroundStatusSubscription ??= SmartChargeTelemetryForegroundService
          .statuses
          .listen((status) {
            if (_disposed) return;
            state = state.copyWith(
              chargerStatus: status,
              gatewayError: null,
              safetyWarning: _safetyWarning(status),
            );
            if (!status.relay) {
              _foregroundPolling = false;
              state = state.copyWith(
                telemetryStatus: SmartChargeTelemetryStatus.complete,
              );
              unawaited(_refreshSession());
            }
            final session = state.session;
            if (session != null && !session.state.isTerminal) {
              unawaited(_maybeCalibrate(status));
            }
          });
      _foregroundPolling =
          await SmartChargeTelemetryForegroundService.isRunning;
    } catch (error, stack) {
      // Unit tests and unsupported platforms do not register the Android
      // plugin. Shelly's timer remains the independent safety control.
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.attachForegroundTelemetry',
      );
      _foregroundPolling = false;
    }
  }

  Future<void> _startForegroundMonitor(SmartChargingSession session) async {
    try {
      await SmartChargeTelemetryForegroundService.start(session);
      _foregroundPolling = true;
      state = state.copyWith(
        telemetryStatus: SmartChargeTelemetryStatus.recording,
      );
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.foregroundTelemetry',
      );
      _foregroundPolling = false;
      if (!_disposed) {
        state = state.copyWith(
          telemetryStatus: SmartChargeTelemetryStatus.partial,
        );
      }
    }
  }

  Future<void> _stopForegroundMonitor() async {
    _foregroundPolling = false;
    try {
      await SmartChargeTelemetryForegroundService.stop();
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.stopForegroundTelemetry',
      );
    }
  }

  void _startPolling() {
    _statusTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refreshStatus()),
    );
    _sessionTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refreshSession()),
    );
    _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed) state = state.copyWith(now: _clock());
    });
  }

  Future<void> refresh() async {
    state = state.copyWith(refreshing: true);
    await Future.wait([
      _refreshCapabilities(),
      _refreshStatus(),
      _refreshSession(),
      _refreshHistory(),
    ]);
    if (!_disposed) state = state.copyWith(refreshing: false);
  }

  Future<void> _refreshStatus() async {
    if (_foregroundPolling) return;
    if (_statusRequestRunning || _disposed) return;
    _statusRequestRunning = true;
    try {
      final status = await _repository!.status();
      if (!_disposed) {
        state = state.copyWith(
          chargerStatus: status,
          gatewayError: null,
          safetyWarning: _safetyWarning(status),
        );
        final session = state.session;
        if (session != null && !session.state.isTerminal) {
          unawaited(_recordTelemetry(session, status));
        }
        unawaited(_maybeCalibrate(status));
      }
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(gatewayError: error.message);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.status',
      );
      if (!_disposed) {
        state = state.copyWith(
          gatewayError: 'Không thể đọc trạng thái Shelly. Hãy thử lại.',
        );
      }
    } finally {
      _statusRequestRunning = false;
    }
  }

  String? _safetyWarning(SmartChargerStatus status) {
    if (!status.relay) return null;
    if (status.currentA >= 10.5)
      return 'Dòng điện đang cao (${status.currentA.toStringAsFixed(1)} A).';
    if (status.powerW >= 2300)
      return 'Công suất đang gần giới hạn (${status.powerW.toStringAsFixed(0)} W).';
    if (status.temperatureC != null && status.temperatureC! >= 65) {
      return 'Nhiệt độ Shelly đang cao (${status.temperatureC!.toStringAsFixed(1)} °C).';
    }
    if (status.voltageV > 0 &&
        (status.voltageV < 200 || status.voltageV > 250)) {
      return 'Điện áp đang ngoài vùng khuyến nghị (${status.voltageV.toStringAsFixed(1)} V).';
    }
    return null;
  }

  Future<void> _refreshCapabilities() async {
    try {
      final value = await _repository!.capabilities();
      if (!_disposed) state = state.copyWith(capabilities: value);
    } on SmartChargerException {
      if (!_disposed) {
        state = state.copyWith(
          capabilities: SmartChargerCapabilities.unavailable,
        );
      }
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.capabilities',
      );
      if (!_disposed) {
        state = state.copyWith(
          capabilities: SmartChargerCapabilities.unavailable,
        );
      }
    }
  }

  Future<void> _refreshSession() async {
    if (_foregroundPolling &&
        state.session?.state == ChargingSessionState.active) {
      return;
    }
    if (_sessionRequestRunning || _disposed) return;
    _sessionRequestRunning = true;
    try {
      final current = await _repository!.current();
      if (_disposed) return;
      final previousSession = state.session;
      final previouslyActive = state.hasActiveSession;
      state = state.copyWith(
        session: current,
        history: current == null
            ? state.history
            : [
                current,
                ...state.history.where(
                  (item) => item.sessionId != current.sessionId,
                ),
              ],
        phase: current != null && !current.state.isTerminal
            ? SmartChargingViewPhase.active
            : (state.preview == null
                  ? SmartChargingViewPhase.editing
                  : SmartChargingViewPhase.preview),
        sessionError: null,
      );
      if (current?.state.isTerminal == true) _notify(current!);
      if (current?.state.isTerminal == true) {
        unawaited(_stopForegroundMonitor());
      }
      if (previouslyActive && current == null) {
        unawaited(
          _refreshHistory(completedSessionId: previousSession?.sessionId),
        );
      }
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(sessionError: error.message);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.session',
      );
      if (!_disposed) {
        state = state.copyWith(
          sessionError: 'Không thể đồng bộ phiên sạc. Hãy thử lại.',
        );
      }
    } finally {
      _sessionRequestRunning = false;
    }
  }

  Future<void> _refreshHistory({String? completedSessionId}) async {
    if (!_disposed) {
      state = state.copyWith(historyStatus: SmartChargeHistoryStatus.loading);
    }
    try {
      final history = (await _repository!.getHistoryPage()).items;
      if (!_disposed) {
        SmartChargingSession? completed;
        if (completedSessionId != null) {
          for (final item in history) {
            if (item.sessionId == completedSessionId && item.state.isTerminal) {
              completed = item;
              break;
            }
          }
        }
        final active = state.session;
        final merged = active != null && !active.state.isTerminal
            ? [
                active,
                ...history.where((item) => item.sessionId != active.sessionId),
              ]
            : history;
        state = state.copyWith(
          history: merged,
          session: completed ?? state.session,
          historyError: null,
          historyStatus: merged.isEmpty
              ? SmartChargeHistoryStatus.empty
              : SmartChargeHistoryStatus.ready,
          historySyncedAt: _clock(),
        );
        if (completed != null) _notify(completed);
      }
    } on SmartChargerException catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          historyError: error.message,
          historyStatus: state.history.isEmpty
              ? SmartChargeHistoryStatus.error
              : SmartChargeHistoryStatus.stale,
        );
      }
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.history',
      );
      if (!_disposed) {
        state = state.copyWith(
          historyError: 'Không thể đồng bộ lịch sử sạc.',
          historyStatus: state.history.isEmpty
              ? SmartChargeHistoryStatus.error
              : SmartChargeHistoryStatus.stale,
        );
      }
    }
  }

  Future<void> _recordTelemetry(
    SmartChargingSession session,
    SmartChargerStatus status,
  ) async {
    try {
      if (!_disposed) {
        state = state.copyWith(
          telemetryStatus: SmartChargeTelemetryStatus.recording,
        );
      }
      await _repository!.recordStatusSample(session, status);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.telemetry',
      );
      if (!_disposed) {
        state = state.copyWith(
          telemetryStatus: SmartChargeTelemetryStatus.partial,
        );
      }
    }
  }

  void updateDraft({
    double? currentSoc,
    double? targetSoc,
    DateTime? hardDeadlineAt,
    ChargingStrategy? strategy,
    ChargingTimeMode? timeMode,
    String? chargingMode,
  }) {
    final old = state.draft;
    final draft = SmartChargingPlanDraft(
      vehicleId: old.vehicleId,
      currentSoc: currentSoc ?? old.currentSoc,
      targetSoc: targetSoc ?? old.targetSoc,
      hardDeadlineAt: hardDeadlineAt ?? old.hardDeadlineAt,
      strategy: strategy ?? old.strategy,
      timeMode: timeMode ?? old.timeMode,
      chargingMode: chargingMode ?? old.chargingMode,
      estimatedCapacityWh: old.estimatedCapacityWh,
    );
    _idempotencyKey = null;

    if (targetSoc != null) {
      unawaited(
        Future(() async {
          try {
            final p = await SharedPreferences.getInstance();
            await p.setDouble(lastTargetSocKey, targetSoc);
          } catch (_) {}
        }),
      );
    }

    state = state.copyWith(
      draft: draft,
      preview: null,
      phase: SmartChargingViewPhase.editing,
      actionError: null,
    );
  }

  Future<void> createPreview() async {
    final now = _clock();
    var draft = state.draft;
    // A target-SOC prediction has no user-selected wall-clock deadline. Keep
    // its safety ceiling relative to the prediction/start time so a screen
    // left open for hours cannot reduce the device timer unexpectedly.
    if (draft.strategy == ChargingStrategy.targetSoc ||
        draft.strategy == ChargingStrategy.aiTarget) {
      draft = SmartChargingPlanDraft(
        vehicleId: draft.vehicleId,
        currentSoc: draft.currentSoc,
        targetSoc: draft.targetSoc,
        hardDeadlineAt: now.add(SmartChargerService.maxSessionDuration),
        strategy: draft.strategy,
        timeMode: draft.timeMode,
        chargingMode: draft.chargingMode,
        estimatedCapacityWh: draft.estimatedCapacityWh,
      );
      state = state.copyWith(draft: draft);
    }
    final error = draft.validate(now: now);
    if (error != null) {
      state = state.copyWith(
        phase: SmartChargingViewPhase.error,
        actionError: error,
      );
      return;
    }
    state = state.copyWith(
      phase: SmartChargingViewPhase.loading,
      actionError: null,
    );
    try {
      final preview = await _repository!.preview(draft);
      if (_disposed) return;
      if (preview.predictedMinutes > 600) {
        state = state.copyWith(
          preview: null,
          phase: SmartChargingViewPhase.error,
          actionError:
              'Thời gian sạc vượt giới hạn an toàn 10 giờ. Vui lòng chọn mức pin thấp hơn.',
        );
        return;
      }
      state = state.copyWith(
        preview: preview,
        phase: SmartChargingViewPhase.preview,
        actionError: null,
      );
    } on SmartChargerException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.previewApi',
      );
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.error,
          actionError: error.message,
        );
      }
    } on SmartChargePredictionException catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.error,
          actionError: error.message,
        );
      }
    } catch (error, stack) {
      AppErrorReporter.report(error, stack, source: 'SmartChargingController');
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.error,
          actionError: 'Không thể tính thời gian sạc. Hãy thử lại.',
        );
      }
    }
  }

  void _notify(SmartChargingSession session) {
    final sink = _notificationSink;
    if (session.state.isTerminal) {
      if (_lastNotifiedTerminalId == session.sessionId) return;
      _lastNotifiedTerminalId = session.sessionId;
      unawaited(
        _reminderCanceller?.call().catchError((_) {}) ?? Future.value(),
      );
      if (_lastLoggedTerminalId != session.sessionId) {
        _lastLoggedTerminalId = session.sessionId;
        unawaited(_persistTerminal(session));
      }
    }
    if (sink == null) return;
    unawaited(sink(session).catchError((_) {}));
  }

  Future<void> _persistTerminal(SmartChargingSession session) async {
    try {
      await _repository?.flushPendingTelemetry(session.sessionId);
      await _logSink?.call(session);
    } catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.terminalLog',
      );
      if (!_disposed) {
        state = state.copyWith(
          telemetryStatus: SmartChargeTelemetryStatus.partial,
        );
      }
    }
  }

  Future<void> _maybeCalibrate(SmartChargerStatus status) async {
    if (_repository?.calibrationIsServerOwned == true) return;
    final session = state.session;
    if (session == null ||
        session.state != ChargingSessionState.active ||
        !status.relay ||
        status.powerW <= 0) {
      _stablePowerSamples.clear();
      _powerSamplingStartedAt = null;
      return;
    }
    _powerSamplingStartedAt ??= _clock();
    _stablePowerSamples.add(status.powerW);
    if (_stablePowerSamples.length > 18) _stablePowerSamples.removeAt(0);
    if (_stablePowerSamples.length < 6 ||
        _clock().difference(_powerSamplingStartedAt!) <
            const Duration(seconds: 60) ||
        (_lastCalibrationAt != null &&
            _clock().difference(_lastCalibrationAt!) <
                const Duration(minutes: 5))) {
      return;
    }
    final capacity = session.estimatedCapacityWh ?? 0;
    final estimatedSoc = session.estimatedSoc ?? session.startSoc;
    final remainingWh =
        capacity * ((session.targetSoc - estimatedSoc).clamp(0, 100) / 100);
    final minutes = SmartChargerService.calibratedRemainingMinutes(
      remainingBatteryWh: remainingWh,
      powerSamplesW: _stablePowerSamples,
    );
    final shellyMinutes =
        status.timerRemaining?.inMinutes ??
        session.remaining(_clock()).inMinutes;
    if (minutes <= 0 || (minutes - shellyMinutes).abs() < 3) return;
    final safetyMinutes = session.absoluteSafetyStopAt
        .difference(_clock())
        .inMinutes;
    if (safetyMinutes <= 0) return;
    try {
      final updated = await _repository!.rearm(
        Duration(minutes: minutes.clamp(1, safetyMinutes)),
      );
      _lastCalibrationAt = _clock();
      if (!_disposed) state = state.copyWith(session: updated);
    } on SmartChargerException {
      // The original device timer remains armed; calibration is best effort.
    }
  }

  Future<bool> start({required bool confirmed}) async {
    final preview = state.preview;
    if (!confirmed || preview == null) return false;
    if (!preview.aiChargeEligible) {
      state = state.copyWith(
        actionError: 'Model AI chưa sẵn sàng. Không thể bắt đầu sạc theo AI.',
      );
      return false;
    }
    if (!state.capabilities.readyForControl) {
      state = state.copyWith(
        actionError: 'Ổ sạc chưa sẵn sàng điều khiển an toàn.',
      );
      return false;
    }
    state = state.copyWith(
      phase: SmartChargingViewPhase.starting,
      actionError: null,
    );
    _idempotencyKey ??=
        '${preview.draft.vehicleId}-${_clock().toUtc().microsecondsSinceEpoch}';
    try {
      final session = await _repository!.start(preview, _idempotencyKey!);
      if (_disposed) return false;

      // Status readback
      SmartChargerStatus? currentStatus;
      try {
        currentStatus = await _repository!.status();
      } catch (_) {}

      if (currentStatus != null &&
          !currentStatus.relay &&
          !session.relayVerified) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.preview,
          actionError: 'Không thể bật sạc: Chưa xác nhận được ổ sạc bật.',
        );
        return false;
      }

      state = state.copyWith(
        session: session,
        history: [
          session,
          ...state.history.where((item) => item.sessionId != session.sessionId),
        ],
        chargerStatus: currentStatus ?? state.chargerStatus,
        phase: SmartChargingViewPhase.active,
        gatewayError: null,
      );
      unawaited(_startForegroundMonitor(session));
      _notify(session);
      final scheduler = _reminderScheduler;
      if (scheduler != null) {
        unawaited(
          scheduler(
            session.effectiveStopAt,
            session.targetSoc.round(),
          ).catchError((_) {}),
        );
      }
      return true;
    } on SmartChargerException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.start',
      );
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.preview,
          actionError: error.message,
        );
      }
      return false;
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        source: 'SmartChargingController.start',
      );
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.preview,
          actionError: 'Không thể bật sạc: $e',
        );
      }
      return false;
    }
  }

  Future<bool> stop() async {
    final session = state.session;
    if (session == null) return manualOff();
    state = state.copyWith(
      phase: SmartChargingViewPhase.stopping,
      actionError: null,
    );
    try {
      final result = await _repository!.stop(
        session.sessionId,
        expectedVersion: session.version,
      );
      if (_disposed) return false;

      // Readback to verify relay OFF
      SmartChargerStatus? currentStatus;
      try {
        currentStatus = await _repository!.status();
      } catch (_) {}

      if (currentStatus != null && currentStatus.relay) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.active,
          actionError: 'Chưa xác nhận được ổ sạc đã tắt. Hãy kiểm tra ổ sạc.',
        );
        return false;
      }

      final stopped = result.session;
      if (!result.relayOffVerified) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.active,
          actionError: 'Chưa xác nhận được ổ sạc đã tắt. Hãy kiểm tra ổ sạc.',
        );
        return false;
      }
      if (stopped != null) {
        await _persistTerminal(stopped);
        _lastLoggedTerminalId = stopped.sessionId;
      }
      await _stopForegroundMonitor();
      state = state.copyWith(
        session: stopped,
        chargerStatus: currentStatus ?? state.chargerStatus,
        phase: SmartChargingViewPhase.editing,
        actionError: null,
        history: stopped == null
            ? state.history
            : [
                stopped,
                ...state.history.where(
                  (item) => item.sessionId != stopped.sessionId,
                ),
              ],
      );
      if (stopped != null) _notify(stopped);
      unawaited(_refreshHistory(completedSessionId: session.sessionId));
      return true;
    } on SmartChargerException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.stop',
      );
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.active,
          actionError: error.message,
        );
      }
      return false;
    } catch (e, stack) {
      AppErrorReporter.report(e, stack, source: 'SmartChargingController.stop');
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.active,
          actionError: 'Lỗi khi dừng sạc: $e',
        );
      }
      return false;
    }
  }

  Future<bool> manualOn(Duration duration) async {
    if (!state.capabilities.readyForControl) {
      state = state.copyWith(
        actionError: 'Ổ sạc chưa sẵn sàng điều khiển an toàn.',
      );
      return false;
    }
    state = state.copyWith(
      phase: SmartChargingViewPhase.starting,
      actionError: null,
    );
    final key =
        'manual-${state.draft.vehicleId}-${_clock().toUtc().microsecondsSinceEpoch}';
    try {
      final session = await _repository!.manualOn(
        duration,
        key,
        vehicleId: state.draft.vehicleId,
        currentSoc: state.draft.currentSoc,
      );
      if (_disposed) return false;
      state = state.copyWith(
        session: session,
        history: [
          session,
          ...state.history.where((item) => item.sessionId != session.sessionId),
        ],
        phase: SmartChargingViewPhase.active,
        actionError: null,
      );
      unawaited(_startForegroundMonitor(session));
      return true;
    } on SmartChargerException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.manualOn',
      );
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.editing,
          actionError: error.message,
        );
      }
      return false;
    }
  }

  Future<bool> manualOff() async {
    try {
      await _repository!.manualOff();
      await _stopForegroundMonitor();
      await Future.wait([_refreshStatus(), _refreshSession()]);
      return true;
    } on SmartChargerException catch (error, stack) {
      AppErrorReporter.report(
        error,
        stack,
        source: 'SmartChargingController.manualOff',
      );
      if (!_disposed) state = state.copyWith(actionError: error.message);
      return false;
    }
  }

  Future<SmartChargeHistoryPage> getHistoryPage({
    int limit = 20,
    String? cursor,
    ChargingStrategy? strategy,
  }) async {
    _repository ??= await SmartChargerRepositoryFactory.create();
    return _repository!.getHistoryPage(
      limit: limit,
      cursor: cursor,
      strategy: strategy,
    );
  }

  Future<List<SmartChargeTelemetryPoint>> getTelemetry(String sessionId) async {
    _repository ??= await SmartChargerRepositoryFactory.create();
    return _repository!.getTelemetry(sessionId);
  }

  Future<SmartChargeEnergySummary> confirmActualEndSoc(
    SmartChargingSession session,
    double soc,
  ) async {
    _repository ??= await SmartChargerRepositoryFactory.create();
    return _repository!.confirmActualEndSoc(session, soc);
  }

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
    unawaited(_foregroundStatusSubscription?.cancel());
    super.dispose();
  }
}

class SmartChargingControllerArgs {
  const SmartChargingControllerArgs({
    required this.vehicleId,
    required this.currentSoc,
  });

  final String vehicleId;
  final double currentSoc;

  @override
  bool operator ==(Object other) =>
      other is SmartChargingControllerArgs &&
      other.vehicleId == vehicleId &&
      other.currentSoc == currentSoc;

  @override
  int get hashCode => Object.hash(vehicleId, currentSoc);
}

final smartChargingControllerProvider = StateNotifierProvider.autoDispose
    .family<
      SmartChargingController,
      SmartChargingUiState,
      SmartChargingControllerArgs
    >(
      (ref, args) => SmartChargingController(
        vehicleId: args.vehicleId,
        currentSoc: args.currentSoc,
        notificationSink: (session) async {
          await NotificationCenterService().notifySmartChargingState(
            sessionId: session.sessionId,
            state: session.state.wireValue,
            targetPercent: session.targetSoc.round(),
          );
          if (session.state == ChargingSessionState.failed) {
            await NotificationService().notifySmartChargeUnsafe(
              sessionId: session.sessionId,
              message:
                  session.lastError ??
                  'Không thể xác minh đã tắt sạc. Hãy kiểm tra ổ sạc trực tiếp.',
            );
          } else if (session.state.isTerminal && session.relayVerified) {
            await NotificationService().notifySmartChargeRelayOff(
              sessionId: session.sessionId,
              interrupted: session.state != ChargingSessionState.completed,
            );
          }
        },
        logSink: ShellyChargeLogService().saveTerminalSession,
        reminderScheduler: (scheduledAt, targetPercent) async {
          await NotificationService().scheduleChargeReminder(
            scheduledAt,
            targetPercent,
          );
        },
        reminderCanceller: () => NotificationService().cancelChargeReminder(),
      ),
    );
