import 'package:flutter/foundation.dart';

@immutable
class ActionConfirmationCardData {
  const ActionConfirmationCardData({
    required this.title,
    required this.description,
    this.estimatedTime,
    this.safetyNote,
    this.actions = const ['confirm', 'cancel'],
    this.targetSoc,
    this.maxAmps,
    this.startTime,
  });

  final String title;
  final String description;
  final String? estimatedTime;
  final String? safetyNote;
  final List<String> actions;
  final int? targetSoc;
  final double? maxAmps;
  final String? startTime;

  factory ActionConfirmationCardData.fromJson(Map<String, dynamic> json) {
    return ActionConfirmationCardData(
      title: json['title'] as String? ?? 'Xác nhận hành động',
      description: json['description'] as String? ?? '',
      estimatedTime: json['estimatedTime'] as String?,
      safetyNote: json['safetyNote'] as String?,
      actions: (json['actions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['confirm', 'cancel'],
      targetSoc: (json['targetSoc'] as num?)?.toInt(),
      maxAmps: (json['maxAmps'] as num?)?.toDouble(),
      startTime: json['startTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        if (estimatedTime != null) 'estimatedTime': estimatedTime,
        if (safetyNote != null) 'safetyNote': safetyNote,
        'actions': actions,
        if (targetSoc != null) 'targetSoc': targetSoc,
        if (maxAmps != null) 'maxAmps': maxAmps,
        if (startTime != null) 'startTime': startTime,
      };
}

@immutable
class FunctionCallAction {
  const FunctionCallAction({
    required this.callId,
    required this.toolName,
    this.args = const {},
    this.requiresConfirmation = true,
    this.cardData,
    this.status = 'pending', // 'pending' | 'confirmed' | 'cancelled' | 'executed'
    this.resultMessage,
  });

  final String callId;
  final String toolName;
  final Map<String, dynamic> args;
  final bool requiresConfirmation;
  final ActionConfirmationCardData? cardData;
  final String status;
  final String? resultMessage;

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed' || status == 'executed';
  bool get isCancelled => status == 'cancelled';

  FunctionCallAction copyWith({
    String? callId,
    String? toolName,
    Map<String, dynamic>? args,
    bool? requiresConfirmation,
    ActionConfirmationCardData? cardData,
    String? status,
    String? resultMessage,
  }) {
    return FunctionCallAction(
      callId: callId ?? this.callId,
      toolName: toolName ?? this.toolName,
      args: args ?? this.args,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      cardData: cardData ?? this.cardData,
      status: status ?? this.status,
      resultMessage: resultMessage ?? this.resultMessage,
    );
  }

  factory FunctionCallAction.fromJson(Map<String, dynamic> json) {
    return FunctionCallAction(
      callId: json['callId'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      args: (json['args'] as Map<String, dynamic>?) ?? {},
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? true,
      cardData: json['confirmationCard'] != null
          ? ActionConfirmationCardData.fromJson(
              json['confirmationCard'] as Map<String, dynamic>)
          : null,
      status: json['status'] as String? ?? 'pending',
      resultMessage: json['resultMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'toolName': toolName,
        'args': args,
        'requiresConfirmation': requiresConfirmation,
        if (cardData != null) 'confirmationCard': cardData!.toJson(),
        'status': status,
        if (resultMessage != null) 'resultMessage': resultMessage,
      };
}
