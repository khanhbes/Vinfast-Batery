import 'package:flutter/foundation.dart';

@immutable
class ProactiveSuggestion {
  const ProactiveSuggestion({
    required this.ruleId,
    required this.title,
    required this.message,
    required this.priority, // 'HIGH' | 'MEDIUM' | 'LOW'
    this.action,
    required this.suggestedAt,
    this.metadata,
  });

  final String ruleId;
  final String title;
  final String message;
  final String priority;
  final String? action;
  final DateTime suggestedAt;
  final Map<String, dynamic>? metadata;

  bool get isHighPriority => priority == 'HIGH';
  bool get isMediumPriority => priority == 'MEDIUM';
  bool get isLowPriority => priority == 'LOW';

  factory ProactiveSuggestion.fromJson(Map<String, dynamic> json) {
    return ProactiveSuggestion(
      ruleId: json['ruleId'] as String? ?? 'R000',
      title: json['title'] as String? ?? 'Gợi ý từ BatteryBot',
      message: json['message'] as String? ?? '',
      priority: json['priority'] as String? ?? 'LOW',
      action: json['action'] as String?,
      suggestedAt: json['suggestedAt'] != null
          ? DateTime.tryParse(json['suggestedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'title': title,
        'message': message,
        'priority': priority,
        if (action != null) 'action': action,
        'suggestedAt': suggestedAt.toIso8601String(),
        if (metadata != null) 'metadata': metadata,
      };
}
