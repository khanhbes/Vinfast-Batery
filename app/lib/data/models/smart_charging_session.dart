enum ChargingStrategy {
  targetSoc('target_soc'),
  deadline('deadline'),
  smartCombined('smart_combined'),
  aiTarget('ai_target'),
  manualTimed('manual_timed');

  const ChargingStrategy(this.wireValue);
  final String wireValue;

  static ChargingStrategy fromJson(Object? value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw const FormatException('Invalid charging strategy.'),
  );
}

enum ChargingTimeMode { duration, stopTime }

enum ChargingSessionState {
  arming('arming'),
  starting('starting'),
  active('active'),
  stopping('stopping'),
  completed('completed'),
  cancelled('cancelled'),
  interrupted('interrupted'),
  failed('failed');

  const ChargingSessionState(this.wireValue);
  final String wireValue;

  bool get isTerminal =>
      const {completed, cancelled, interrupted, failed}.contains(this);

  static ChargingSessionState fromJson(Object? value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw const FormatException('Invalid session state.'),
  );
}

enum ChargingStopReason {
  plannedTimer('planned_timer'),
  targetSoc('target_soc'),
  deadline('deadline'),
  smartCombined('smart_combined'),
  absoluteSafety('absolute_safety'),
  manual('manual'),
  relayOff('relay_off'),
  gatewayRestartExpired('gateway_restart_expired'),
  commandFailed('command_failed');

  const ChargingStopReason(this.wireValue);
  final String wireValue;

  static ChargingStopReason? fromJson(Object? value) {
    if (value == null) return null;
    return values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => throw const FormatException('Invalid stop reason.'),
    );
  }
}

class SmartChargingPlanDraft {
  const SmartChargingPlanDraft({
    required this.vehicleId,
    required this.currentSoc,
    required this.targetSoc,
    required this.hardDeadlineAt,
    this.strategy = ChargingStrategy.smartCombined,
    this.timeMode = ChargingTimeMode.duration,
    this.chargingMode = 'standard',
    this.estimatedCapacityWh = 0,
  });

  final String vehicleId;
  final double currentSoc;
  final double targetSoc;
  final DateTime hardDeadlineAt;
  final ChargingStrategy strategy;
  final ChargingTimeMode timeMode;
  final String chargingMode;
  final double estimatedCapacityWh;

  String? validate({DateTime? now}) {
    final reference = now ?? DateTime.now();
    if (vehicleId.trim().isEmpty) return 'Chưa chọn xe.';
    if (currentSoc < 0 || currentSoc > 100) {
      return 'Mức pin hiện tại phải từ 0–100%.';
    }
    if (targetSoc <= currentSoc || targetSoc > 100) {
      return 'Mức pin muốn sạc phải cao hơn pin hiện tại.';
    }
    if (!hardDeadlineAt.isAfter(reference)) {
      return 'Thời điểm dừng phải ở tương lai.';
    }
    // Capacity is optional for the deployed AI model. Missing capacity only
    // disables Wh/SOC-derived KPIs and physics fallback; it must not block a
    // real server-side AI prediction.
    return null;
  }
}

class SmartChargingPlanPreview {
  const SmartChargingPlanPreview({
    required this.draft,
    required this.predictedMinutes,
    required this.aiStopAt,
    required this.effectiveStopAt,
    required this.predictionSource,
    required this.isPhysicsFallback,
    required this.isImpossible,
    this.previewId,
    this.expiresAt,
    this.predictionConfidence,
    this.warning,
    this.predictedDurationSeconds,
    this.modelKey = 'charging_time',
    this.modelVersion = 'unknown',
    this.runtimeHealth = 'unknown',
    this.warnings = const [],
    this.fallbackReason,
    this.analyzedAt,
    this.aiChargeEligible = true,
  });

  final SmartChargingPlanDraft draft;
  final int predictedMinutes;
  final DateTime aiStopAt;
  final DateTime effectiveStopAt;
  final String predictionSource;
  final double? predictionConfidence;
  final bool isPhysicsFallback;
  final bool isImpossible;
  final String? warning;
  final int? predictedDurationSeconds;
  final String modelKey;
  final String modelVersion;
  final String runtimeHealth;
  final List<String> warnings;
  final String? fallbackReason;
  final DateTime? analyzedAt;
  final bool aiChargeEligible;

  /// Present for server-generated previews. It prevents clients from changing
  /// the prediction between preview and Start.
  final String? previewId;
  final DateTime? expiresAt;

  factory SmartChargingPlanPreview.fromPrediction({
    required SmartChargingPlanDraft draft,
    required int predictedMinutes,
    required String source,
    double? confidence,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final aiStop = reference.add(Duration(minutes: predictedMinutes));
    final effective = switch (draft.strategy) {
      ChargingStrategy.targetSoc =>
        aiStop.isBefore(draft.hardDeadlineAt) ? aiStop : draft.hardDeadlineAt,
      ChargingStrategy.deadline => draft.hardDeadlineAt,
      ChargingStrategy.smartCombined =>
        aiStop.isBefore(draft.hardDeadlineAt) ? aiStop : draft.hardDeadlineAt,
      ChargingStrategy.aiTarget => aiStop,
      ChargingStrategy.manualTimed => aiStop,
    };
    final impossible = aiStop.isAfter(draft.hardDeadlineAt);
    return SmartChargingPlanPreview(
      draft: draft,
      predictedMinutes: predictedMinutes,
      aiStopAt: aiStop,
      effectiveStopAt: effective,
      predictionSource: source,
      predictionConfidence: confidence,
      isPhysicsFallback: source == 'physics_fallback',
      isImpossible: impossible,
      predictedDurationSeconds: predictedMinutes * 60,
      runtimeHealth: source == 'ai_model' ? 'loaded' : 'fallback',
      modelVersion: source == 'ai_model' ? 'unknown' : 'heuristic-v1',
      fallbackReason: source == 'ai_model' ? null : source,
      aiChargeEligible: source == 'ai_model',
      analyzedAt: reference,
      warning: impossible
          ? 'Không đủ thời gian để đạt mức pin muốn sạc trước hạn dừng.'
          : null,
    );
  }
}

class SmartChargingSessionRequest {
  const SmartChargingSessionRequest({
    required this.vehicleId,
    required this.startSoc,
    required this.targetSoc,
    required this.predictedMinutes,
    required this.startedAt,
    required this.predictedFullAt,
    required this.chargingMode,
    this.predictionSource,
    this.predictionConfidence,
    this.strategy = ChargingStrategy.smartCombined,
    this.hardDeadlineAt,
    this.estimatedCapacityWh,
    this.acknowledgeEstimatedSoc = false,
    this.predictedDurationSeconds,
    this.modelKey = 'charging_time',
    this.modelVersion = 'unknown',
    this.runtimeHealth = 'unknown',
    this.predictionWarnings = const [],
    this.fallbackReason,
    this.predictionAnalyzedAt,
  });

  final String vehicleId;
  final double startSoc;
  final double targetSoc;
  final int predictedMinutes;
  final DateTime startedAt;
  final DateTime predictedFullAt;
  final String chargingMode;
  final String? predictionSource;
  final double? predictionConfidence;
  final ChargingStrategy strategy;
  final DateTime? hardDeadlineAt;
  final double? estimatedCapacityWh;
  final bool acknowledgeEstimatedSoc;
  final int? predictedDurationSeconds;
  final String modelKey;
  final String modelVersion;
  final String runtimeHealth;
  final List<String> predictionWarnings;
  final String? fallbackReason;
  final DateTime? predictionAnalyzedAt;

  Map<String, dynamic> toJson() => {
    'vehicle_id': vehicleId,
    'start_soc': startSoc,
    'target_soc': targetSoc,
    'predicted_minutes': predictedMinutes,
    'started_at': startedAt.toIso8601String(),
    'predicted_full_at': predictedFullAt.toIso8601String(),
    'charging_mode': chargingMode,
    if (predictionSource != null) 'prediction_source': predictionSource,
    if (predictionConfidence != null)
      'prediction_confidence': predictionConfidence,
    if (predictedDurationSeconds != null)
      'predicted_duration_seconds': predictedDurationSeconds,
    'model_key': modelKey,
    'model_version': modelVersion,
    'runtime_health': runtimeHealth,
    'prediction_warnings': predictionWarnings,
    if (fallbackReason != null) 'fallback_reason': fallbackReason,
    if (predictionAnalyzedAt != null)
      'prediction_analyzed_at': predictionAnalyzedAt!.toIso8601String(),
  };

  Map<String, dynamic> toAutomaticJson() => {
    ...toJson(),
    'strategy': strategy.wireValue,
    'hard_deadline_at': (hardDeadlineAt ?? predictedFullAt)
        .toUtc()
        .toIso8601String(),
    if (estimatedCapacityWh != null)
      'estimated_capacity_wh': estimatedCapacityWh,
    'acknowledge_estimated_soc': acknowledgeEstimatedSoc,
  };
}

class SmartChargingSessionResponse {
  const SmartChargingSessionResponse({
    required this.success,
    required this.sessionId,
    required this.mode,
    required this.receivedAt,
  });

  final bool success;
  final String sessionId;
  final String mode;
  final DateTime receivedAt;

  factory SmartChargingSessionResponse.fromJson(Map<String, dynamic> json) {
    final success = json['success'];
    final sessionId = json['session_id'];
    final mode = json['mode'];
    final receivedAt = DateTime.tryParse(json['received_at']?.toString() ?? '');
    if (success is! bool ||
        sessionId is! String ||
        sessionId.isEmpty ||
        mode != 'monitor_only' ||
        receivedAt == null) {
      throw const FormatException('Invalid monitoring session response.');
    }
    return SmartChargingSessionResponse(
      success: success,
      sessionId: sessionId,
      mode: mode as String,
      receivedAt: receivedAt,
    );
  }
}

class SmartChargingSession {
  const SmartChargingSession({
    required this.sessionId,
    required this.vehicleId,
    required this.state,
    required this.strategy,
    required this.startSoc,
    required this.targetSoc,
    required this.predictedMinutes,
    required this.predictionSource,
    required this.createdAt,
    required this.updatedAt,
    required this.aiStopAt,
    required this.hardDeadlineAt,
    required this.effectiveStopAt,
    required this.absoluteSafetyStopAt,
    required this.shadowMode,
    required this.version,
    this.predictionConfidence,
    this.estimatedCapacityWh,
    this.startedAt,
    this.stoppedAt,
    this.stopReason,
    this.relayVerified = false,
    this.baselineEnergyWh,
    this.energyUsedWh = 0,
    this.energyQuality = 'good',
    this.estimatedSoc,
    this.wouldHaveTurnedOffAt,
    this.lastError,
    this.deviceId,
    this.transport,
    this.predictedDurationSeconds,
    this.modelKey = 'charging_time',
    this.modelVersion = 'unknown',
    this.runtimeHealth = 'unknown',
    this.predictionWarnings = const [],
    this.fallbackReason,
    this.predictionAnalyzedAt,
    this.timerVerified = false,
    this.idempotencyKey,
  });

  final String sessionId;
  final String vehicleId;
  final ChargingSessionState state;
  final ChargingStrategy strategy;
  final double startSoc;
  final double targetSoc;
  final int predictedMinutes;
  final String predictionSource;
  final double? predictionConfidence;
  final double? estimatedCapacityWh;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime aiStopAt;
  final DateTime hardDeadlineAt;
  final DateTime effectiveStopAt;
  final DateTime absoluteSafetyStopAt;
  final DateTime? stoppedAt;
  final ChargingStopReason? stopReason;
  final bool relayVerified;
  final double? baselineEnergyWh;
  final double energyUsedWh;
  final String energyQuality;
  final double? estimatedSoc;
  final bool shadowMode;
  final DateTime? wouldHaveTurnedOffAt;
  final int version;
  final String? lastError;
  final String? deviceId;
  final String? transport;
  final int? predictedDurationSeconds;
  final String modelKey;
  final String modelVersion;
  final String runtimeHealth;
  final List<String> predictionWarnings;
  final String? fallbackReason;
  final DateTime? predictionAnalyzedAt;
  final bool timerVerified;
  final String? idempotencyKey;

  Duration remaining([DateTime? now]) {
    final value = effectiveStopAt.difference(now ?? DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  factory SmartChargingSession.fromJson(Map<String, dynamic> json) {
    DateTime requiredTime(String key) {
      final value = DateTime.tryParse(json[key]?.toString() ?? '');
      if (value == null) throw FormatException('Invalid $key.');
      return value;
    }

    double number(String key, [double fallback = 0]) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    final id = json['session_id'];
    final vehicleId = json['vehicle_id'];
    final version = json['version'];
    if (id is! String ||
        id.isEmpty ||
        vehicleId is! String ||
        version is! int) {
      throw const FormatException('Invalid smart charging session.');
    }
    return SmartChargingSession(
      sessionId: id,
      vehicleId: vehicleId,
      state: ChargingSessionState.fromJson(json['state']),
      strategy: ChargingStrategy.fromJson(json['strategy']),
      startSoc: number('start_soc'),
      targetSoc: number('target_soc'),
      predictedMinutes: (json['predicted_minutes'] as num?)?.round() ?? 0,
      predictionSource: json['prediction_source']?.toString() ?? 'unknown',
      predictionConfidence: (json['prediction_confidence'] as num?)?.toDouble(),
      estimatedCapacityWh: (json['estimated_capacity_wh'] as num?)?.toDouble(),
      createdAt: requiredTime('created_at'),
      updatedAt: requiredTime('updated_at'),
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      aiStopAt: requiredTime('ai_stop_at'),
      hardDeadlineAt: requiredTime('hard_deadline_at'),
      effectiveStopAt: requiredTime('effective_stop_at'),
      absoluteSafetyStopAt: requiredTime('absolute_safety_stop_at'),
      stoppedAt: DateTime.tryParse(json['stopped_at']?.toString() ?? ''),
      stopReason: ChargingStopReason.fromJson(json['stop_reason']),
      relayVerified: json['relay_verified'] == true,
      baselineEnergyWh: (json['baseline_energy_wh'] as num?)?.toDouble(),
      energyUsedWh: number('energy_used_wh'),
      energyQuality: json['energy_quality']?.toString() ?? 'good',
      estimatedSoc: (json['estimated_soc'] as num?)?.toDouble(),
      shadowMode: json['shadow_mode'] != false,
      wouldHaveTurnedOffAt: DateTime.tryParse(
        json['would_have_turned_off_at']?.toString() ?? '',
      ),
      version: version,
      lastError: json['last_error']?.toString(),
      deviceId: json['device_id']?.toString(),
      transport: json['transport']?.toString(),
      predictedDurationSeconds: (json['predicted_duration_seconds'] as num?)
          ?.round(),
      modelKey: json['model_key']?.toString() ?? 'charging_time',
      modelVersion: json['model_version']?.toString() ?? 'unknown',
      runtimeHealth: json['runtime_health']?.toString() ?? 'unknown',
      predictionWarnings: ((json['prediction_warnings'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      fallbackReason: json['fallback_reason']?.toString(),
      predictionAnalyzedAt: DateTime.tryParse(
        json['prediction_analyzed_at']?.toString() ?? '',
      ),
      timerVerified: json['timer_verified'] == true,
      idempotencyKey: json['idempotency_key']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'vehicle_id': vehicleId,
    'state': state.wireValue,
    'strategy': strategy.wireValue,
    'start_soc': startSoc,
    'target_soc': targetSoc,
    'predicted_minutes': predictedMinutes,
    'prediction_source': predictionSource,
    if (predictionConfidence != null)
      'prediction_confidence': predictionConfidence,
    if (estimatedCapacityWh != null)
      'estimated_capacity_wh': estimatedCapacityWh,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
    'ai_stop_at': aiStopAt.toIso8601String(),
    'hard_deadline_at': hardDeadlineAt.toIso8601String(),
    'effective_stop_at': effectiveStopAt.toIso8601String(),
    'absolute_safety_stop_at': absoluteSafetyStopAt.toIso8601String(),
    if (stoppedAt != null) 'stopped_at': stoppedAt!.toIso8601String(),
    if (stopReason != null) 'stop_reason': stopReason!.wireValue,
    'relay_verified': relayVerified,
    if (baselineEnergyWh != null) 'baseline_energy_wh': baselineEnergyWh,
    'energy_used_wh': energyUsedWh,
    'energy_quality': energyQuality,
    if (estimatedSoc != null) 'estimated_soc': estimatedSoc,
    'shadow_mode': shadowMode,
    if (wouldHaveTurnedOffAt != null)
      'would_have_turned_off_at': wouldHaveTurnedOffAt!.toIso8601String(),
    'version': version,
    if (lastError != null) 'last_error': lastError,
    if (deviceId != null) 'device_id': deviceId,
    if (transport != null) 'transport': transport,
    if (predictedDurationSeconds != null)
      'predicted_duration_seconds': predictedDurationSeconds,
    'model_key': modelKey,
    'model_version': modelVersion,
    'runtime_health': runtimeHealth,
    'prediction_warnings': predictionWarnings,
    if (fallbackReason != null) 'fallback_reason': fallbackReason,
    if (predictionAnalyzedAt != null)
      'prediction_analyzed_at': predictionAnalyzedAt!.toIso8601String(),
    'timer_verified': timerVerified,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
  };

  SmartChargingSession copyWith({
    ChargingSessionState? state,
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? stoppedAt,
    DateTime? effectiveStopAt,
    ChargingStopReason? stopReason,
    bool? relayVerified,
    double? baselineEnergyWh,
    double? energyUsedWh,
    double? estimatedSoc,
    int? version,
    String? lastError,
    String? transport,
    bool? timerVerified,
  }) => SmartChargingSession(
    sessionId: sessionId,
    vehicleId: vehicleId,
    state: state ?? this.state,
    strategy: strategy,
    startSoc: startSoc,
    targetSoc: targetSoc,
    predictedMinutes: predictedMinutes,
    predictionSource: predictionSource,
    predictionConfidence: predictionConfidence,
    estimatedCapacityWh: estimatedCapacityWh,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    startedAt: startedAt ?? this.startedAt,
    aiStopAt: aiStopAt,
    hardDeadlineAt: hardDeadlineAt,
    effectiveStopAt: effectiveStopAt ?? this.effectiveStopAt,
    absoluteSafetyStopAt: absoluteSafetyStopAt,
    stoppedAt: stoppedAt ?? this.stoppedAt,
    stopReason: stopReason ?? this.stopReason,
    relayVerified: relayVerified ?? this.relayVerified,
    baselineEnergyWh: baselineEnergyWh ?? this.baselineEnergyWh,
    energyUsedWh: energyUsedWh ?? this.energyUsedWh,
    energyQuality: energyQuality,
    estimatedSoc: estimatedSoc ?? this.estimatedSoc,
    shadowMode: shadowMode,
    wouldHaveTurnedOffAt: wouldHaveTurnedOffAt,
    version: version ?? this.version,
    lastError: lastError ?? this.lastError,
    deviceId: deviceId,
    transport: transport ?? this.transport,
    predictedDurationSeconds: predictedDurationSeconds,
    modelKey: modelKey,
    modelVersion: modelVersion,
    runtimeHealth: runtimeHealth,
    predictionWarnings: predictionWarnings,
    fallbackReason: fallbackReason,
    predictionAnalyzedAt: predictionAnalyzedAt,
    timerVerified: timerVerified ?? this.timerVerified,
    idempotencyKey: idempotencyKey,
  );
}
