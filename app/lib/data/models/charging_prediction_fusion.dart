import 'personal_charging_profile.dart';

class ChargingPredictionFusion {
  const ChargingPredictionFusion({
    required this.finalDurationSeconds,
    required this.candidates,
    required this.reason,
    required this.personalizationStage,
    this.effectiveCapacityWh,
    this.clamped = false,
    this.warnings = const [],
  });

  final int finalDurationSeconds;
  final List<EtaCandidate> candidates;
  final String reason;
  final String personalizationStage;
  final double? effectiveCapacityWh;
  final bool clamped;
  final List<String> warnings;

  EtaCandidate? candidate(String source) {
    for (final value in candidates) {
      if (value.source == source && value.available) return value;
    }
    return null;
  }

  String get friendlyStageLabel => switch (personalizationStage) {
    'personalized' => 'Đã cá nhân hóa cho xe này',
    'calibrating' => 'AI đang học thói quen sạc',
    _ => 'AI đang làm quen với xe của bạn',
  };

  factory ChargingPredictionFusion.fromJson(Map<String, dynamic> json) {
    final guardrail = json['guardrail'] is Map
        ? Map<String, dynamic>.from(json['guardrail'] as Map)
        : const <String, dynamic>{};
    return ChargingPredictionFusion(
      finalDurationSeconds:
          (json['predictedDurationSeconds'] as num?)?.round() ?? 0,
      candidates: ((json['etaCandidates'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => EtaCandidate.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      reason: json['fusionReason']?.toString() ?? 'base',
      personalizationStage: json['personalizationStage']?.toString() ?? 'base',
      effectiveCapacityWh: (json['effectiveCapacityWh'] as num?)?.toDouble(),
      clamped: guardrail['clamped'] == true,
      warnings: ((guardrail['warnings'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}
