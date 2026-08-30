class EtaCandidate {
  const EtaCandidate({
    required this.source,
    required this.durationSeconds,
    required this.weight,
    required this.confidence,
    this.available = true,
    this.reason,
  });

  final String source;
  final int durationSeconds;
  final double weight;
  final double confidence;
  final bool available;
  final String? reason;

  factory EtaCandidate.fromJson(Map<String, dynamic> json) => EtaCandidate(
    source: json['source']?.toString() ?? 'unknown',
    durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
    weight: (json['weight'] as num?)?.toDouble() ?? 0,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    available: json['available'] != false,
    reason: json['reason']?.toString(),
  );
}

class PersonalChargingProfile {
  const PersonalChargingProfile({
    required this.vehicleId,
    required this.consentEnabled,
    required this.validSessions,
    required this.powerSessions,
    required this.adapterVersion,
    required this.active,
    this.validationMape,
    this.updatedAt,
    this.personalizationStage = 'base',
    this.profileVersion = 0,
    this.trainingSegments = 0,
    this.nominalCapacityWh,
    this.estimatedEffectiveCapacityWh,
    this.capacityConfidence = 0,
    this.stateOfHealth,
    this.globalTimeScale = 1,
    this.globalTimeBiasMinutes = 0,
    this.powerScale = 1,
    this.socBands = const {},
    this.qualityConfidence = 0,
    this.lastTrainingError,
    this.lastTrainedAt,
  });

  final String vehicleId;
  final bool consentEnabled;
  final int validSessions;
  final int powerSessions;
  final String adapterVersion;
  final bool active;
  final double? validationMape;
  final DateTime? updatedAt;
  final String personalizationStage;
  final int profileVersion;
  final int trainingSegments;
  final double? nominalCapacityWh;
  final double? estimatedEffectiveCapacityWh;
  final double capacityConfidence;
  final double? stateOfHealth;
  final double globalTimeScale;
  final double globalTimeBiasMinutes;
  final double powerScale;
  final Map<String, dynamic> socBands;
  final double qualityConfidence;
  final String? lastTrainingError;
  final DateTime? lastTrainedAt;

  String get friendlyStageLabel => switch (personalizationStage) {
    'personalized' => 'Đã cá nhân hóa cho xe này',
    'calibrating' => 'AI đang học thói quen sạc',
    _ => 'AI đang làm quen với xe của bạn',
  };

  factory PersonalChargingProfile.fromJson(
    Map<String, dynamic> json,
  ) => PersonalChargingProfile(
    vehicleId: json['vehicleId']?.toString() ?? '',
    consentEnabled: json['consentEnabled'] == true,
    validSessions: (json['validSessions'] as num?)?.round() ?? 0,
    powerSessions: (json['powerSessions'] as num?)?.round() ?? 0,
    adapterVersion: json['adapterVersion']?.toString() ?? 'personal-v0',
    active: json['active'] == true,
    validationMape: (json['validationMape'] as num?)?.toDouble(),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    personalizationStage: json['personalizationStage']?.toString() ?? 'base',
    profileVersion: (json['profileVersion'] as num?)?.round() ?? 0,
    trainingSegments: (json['trainingSegments'] as num?)?.round() ?? 0,
    nominalCapacityWh: (json['nominalCapacityWh'] as num?)?.toDouble(),
    estimatedEffectiveCapacityWh: (json['estimatedEffectiveCapacityWh'] as num?)
        ?.toDouble(),
    capacityConfidence: (json['capacityConfidence'] as num?)?.toDouble() ?? 0,
    stateOfHealth: (json['stateOfHealth'] as num?)?.toDouble(),
    globalTimeScale:
        ((json['correction'] as Map?)?['globalTimeScale'] as num?)
            ?.toDouble() ??
        1,
    globalTimeBiasMinutes:
        ((json['correction'] as Map?)?['globalTimeBiasMinutes'] as num?)
            ?.toDouble() ??
        0,
    powerScale:
        ((json['correction'] as Map?)?['powerScale'] as num?)?.toDouble() ?? 1,
    socBands: json['socBands'] is Map
        ? Map<String, dynamic>.from(json['socBands'] as Map)
        : const {},
    qualityConfidence:
        ((json['quality'] as Map?)?['confidence'] as num?)?.toDouble() ?? 0,
    lastTrainingError: (json['quality'] as Map?)?['lastTrainingError']
        ?.toString(),
    lastTrainedAt: DateTime.tryParse(json['lastTrainedAt']?.toString() ?? ''),
  );
}

class SmartChargeSafetyEvent {
  const SmartChargeSafetyEvent({
    required this.kind,
    required this.severity,
    required this.message,
    this.observedValue,
    this.createdAt,
  });

  final String kind;
  final String severity;
  final String message;
  final double? observedValue;
  final DateTime? createdAt;

  factory SmartChargeSafetyEvent.fromJson(Map<String, dynamic> json) =>
      SmartChargeSafetyEvent(
        kind: json['kind']?.toString() ?? 'unknown',
        severity: json['severity']?.toString() ?? 'warning',
        message: json['message']?.toString() ?? '',
        observedValue: (json['observedValue'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}
