import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/smart_charger_status.dart';
import '../../../data/models/smart_charging_session.dart';
import '../../../data/services/charging_prediction_adapter.dart';
import '../../../data/services/smart_charger_service.dart';
import '../../../data/services/shelly_charge_log_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../core/services/notification_center_service.dart';

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
    this.actionError,
    this.refreshing = false,
  });

  final SmartChargingViewPhase phase;
  final SmartChargingPlanDraft draft;
  final SmartChargingPlanPreview? preview;
  final SmartChargingSession? session;
  final SmartChargerStatus? chargerStatus;
  final List<SmartChargingSession> history;
  final String? gatewayError;
  final String? actionError;
  final bool refreshing;
  final DateTime now;

  bool get hasActiveSession => session != null && !session!.state.isTerminal;

  SmartChargingUiState copyWith({
    SmartChargingViewPhase? phase,
    SmartChargingPlanDraft? draft,
    Object? preview = _unset,
    Object? session = _unset,
    Object? chargerStatus = _unset,
    List<SmartChargingSession>? history,
    Object? gatewayError = _unset,
    Object? actionError = _unset,
    bool? refreshing,
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
    actionError: identical(actionError, _unset)
        ? this.actionError
        : actionError as String?,
    refreshing: refreshing ?? this.refreshing,
    now: now ?? this.now,
  );
}

const _unset = Object();

class SmartChargingController extends StateNotifier<SmartChargingUiState> {
  SmartChargingController({
    required String vehicleId,
    required double currentSoc,
    SmartChargerService? service,
    ChargingPredictionAdapter? predictionAdapter,
    DateTime Function()? clock,
    SmartChargingNotificationSink? notificationSink,
    SmartChargingLogSink? logSink,
    SmartChargingReminderScheduler? reminderScheduler,
    Future<void> Function()? reminderCanceller,
    bool autoInitialize = true,
  }) : _service = service ?? SmartChargerService(),
       _prediction = predictionAdapter ?? ChargingPredictionAdapter(),
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
               const Duration(hours: 2),
             ),
           ),
           now: (clock ?? DateTime.now)(),
         ),
       ) {
    if (autoInitialize) unawaited(initialize());
  }

  final SmartChargerService _service;
  final ChargingPredictionAdapter _prediction;
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

  Future<void> initialize() async {
    await Future.wait([_refreshStatus(), _refreshSession(), _refreshHistory()]);
    if (_disposed) return;
    state = state.copyWith(
      phase: state.hasActiveSession
          ? SmartChargingViewPhase.active
          : SmartChargingViewPhase.editing,
      refreshing: false,
    );
    _startPolling();
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
    await Future.wait([_refreshStatus(), _refreshSession(), _refreshHistory()]);
    if (!_disposed) state = state.copyWith(refreshing: false);
  }

  Future<void> _refreshStatus() async {
    if (_statusRequestRunning || _disposed) return;
    _statusRequestRunning = true;
    try {
      final status = await _service.getStatus();
      if (!_disposed) {
        state = state.copyWith(chargerStatus: status, gatewayError: null);
        unawaited(_maybeCalibrate(status));
      }
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(gatewayError: error.message);
    } finally {
      _statusRequestRunning = false;
    }
  }

  Future<void> _refreshSession() async {
    if (_sessionRequestRunning || _disposed) return;
    _sessionRequestRunning = true;
    try {
      final current = await _service.getCurrentSession();
      if (_disposed) return;
      final previousSession = state.session;
      final previouslyActive = state.hasActiveSession;
      state = state.copyWith(
        session: current,
        phase: current != null && !current.state.isTerminal
            ? SmartChargingViewPhase.active
            : (state.preview == null
                  ? SmartChargingViewPhase.editing
                  : SmartChargingViewPhase.preview),
        gatewayError: null,
      );
      if (current?.state.isTerminal == true) _notify(current!);
      if (previouslyActive && current == null) {
        unawaited(
          _refreshHistory(completedSessionId: previousSession?.sessionId),
        );
      }
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(gatewayError: error.message);
    } finally {
      _sessionRequestRunning = false;
    }
  }

  Future<void> _refreshHistory({String? completedSessionId}) async {
    try {
      final history = await _service.getSessionHistory();
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
        state = state.copyWith(
          history: history,
          session: completed ?? state.session,
        );
        if (completed != null) _notify(completed);
      }
    } on SmartChargerException catch (error) {
      if (!_disposed && state.gatewayError == null) {
        state = state.copyWith(gatewayError: error.message);
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
    state = state.copyWith(
      draft: draft,
      preview: null,
      phase: SmartChargingViewPhase.editing,
      actionError: null,
    );
  }

  Future<void> createPreview() async {
    final error = state.draft.validate(now: _clock());
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
      final preview = await _prediction.predict(state.draft, now: _clock());
      if (_disposed) return;
      if (preview.predictedMinutes > 360) {
        state = state.copyWith(
          preview: null,
          phase: SmartChargingViewPhase.error,
          actionError:
              'ETA AI vượt giới hạn an toàn tuyệt đối 6 giờ. Không thể bắt đầu phiên này.',
        );
        return;
      }
      state = state.copyWith(
        preview: preview,
        phase: SmartChargingViewPhase.preview,
      );
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.error,
          actionError: error.toString(),
        );
      }
    }
  }

  void _notify(SmartChargingSession session) {
    final sink = _notificationSink;
    if (sink == null) return;
    if (session.state.isTerminal) {
      if (_lastNotifiedTerminalId == session.sessionId) return;
      _lastNotifiedTerminalId = session.sessionId;
      unawaited(
        _reminderCanceller?.call().catchError((_) {}) ?? Future.value(),
      );
      if (_lastLoggedTerminalId != session.sessionId) {
        _lastLoggedTerminalId = session.sessionId;
        unawaited(_logSink?.call(session).catchError((_) {}) ?? Future.value());
      }
    }
    unawaited(sink(session).catchError((_) {}));
  }

  Future<void> _maybeCalibrate(SmartChargerStatus status) async {
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
      final updated = await _service.rearmTimer(
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
    state = state.copyWith(
      phase: SmartChargingViewPhase.starting,
      actionError: null,
    );
    _idempotencyKey ??=
        '${preview.draft.vehicleId}-${_clock().toUtc().microsecondsSinceEpoch}';
    try {
      final session = await _service.startAutomaticSession(
        SmartChargingSessionRequest(
          vehicleId: preview.draft.vehicleId,
          startSoc: preview.draft.currentSoc,
          targetSoc: preview.draft.targetSoc,
          predictedMinutes: preview.predictedMinutes,
          startedAt: _clock(),
          predictedFullAt: preview.aiStopAt,
          chargingMode: preview.draft.chargingMode,
          predictionSource: preview.predictionSource,
          predictionConfidence: preview.predictionConfidence,
          strategy: preview.draft.strategy,
          hardDeadlineAt: preview.draft.hardDeadlineAt,
          estimatedCapacityWh: preview.draft.estimatedCapacityWh,
          acknowledgeEstimatedSoc: true,
        ),
        idempotencyKey: _idempotencyKey!,
      );
      if (_disposed) return false;
      state = state.copyWith(
        session: session,
        phase: SmartChargingViewPhase.active,
        gatewayError: null,
      );
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
      unawaited(_refreshStatus());
      return true;
    } on SmartChargerException catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.preview,
          actionError: error.message,
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
      final stopped = await _service.stopSession(
        session.sessionId,
        expectedVersion: session.version,
      );
      if (_disposed) return false;
      state = state.copyWith(
        session: stopped,
        phase: SmartChargingViewPhase.editing,
        history: [
          stopped,
          ...state.history.where((item) => item.sessionId != stopped.sessionId),
        ],
      );
      _notify(stopped);
      unawaited(_refreshStatus());
      return true;
    } on SmartChargerException catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          phase: SmartChargingViewPhase.active,
          actionError: error.message,
        );
      }
      return false;
    }
  }

  Future<bool> manualOn() async {
    try {
      await _service.turnOn();
      await _refreshStatus();
      return true;
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(actionError: error.message);
      return false;
    }
  }

  Future<bool> manualOff() async {
    try {
      await _service.turnOff();
      await Future.wait([_refreshStatus(), _refreshSession()]);
      return true;
    } on SmartChargerException catch (error) {
      if (!_disposed) state = state.copyWith(actionError: error.message);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    _sessionTimer?.cancel();
    _countdownTimer?.cancel();
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
        notificationSink: (session) =>
            NotificationCenterService().notifySmartChargingState(
              sessionId: session.sessionId,
              state: session.state.wireValue,
              targetPercent: session.targetSoc.round(),
            ),
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
