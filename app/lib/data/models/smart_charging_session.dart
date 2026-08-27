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
