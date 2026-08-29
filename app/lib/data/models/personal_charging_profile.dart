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
  });

  final String vehicleId;
  final bool consentEnabled;
  final int validSessions;
  final int powerSessions;
  final String adapterVersion;
  final bool active;
  final double? validationMape;
  final DateTime? updatedAt;

  factory PersonalChargingProfile.fromJson(Map<String, dynamic> json) =>
      PersonalChargingProfile(
        vehicleId: json['vehicleId']?.toString() ?? '',
        consentEnabled: json['consentEnabled'] == true,
        validSessions: (json['validSessions'] as num?)?.round() ?? 0,
        powerSessions: (json['powerSessions'] as num?)?.round() ?? 0,
        adapterVersion: json['adapterVersion']?.toString() ?? 'personal-v0',
        active: json['active'] == true,
        validationMape: (json['validationMape'] as num?)?.toDouble(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
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
