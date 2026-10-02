import 'package:flutter/foundation.dart';
import 'function_call_action.dart';

enum ChatRole {
  user,
  model,
  system;

  static ChatRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'user':
        return ChatRole.user;
      case 'assistant':
      case 'bot':
      case 'model':
        return ChatRole.model;
      case 'system':
        return ChatRole.system;
      default:
        return ChatRole.user;
    }
  }

  String toWire() {
    switch (this) {
      case ChatRole.user:
        return 'user';
      case ChatRole.model:
        return 'model';
      case ChatRole.system:
        return 'system';
    }
  }
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.action,
    this.actionCard,
    this.isStreaming = false,
    this.isQueued = false,
    this.hasError = false,
    this.errorMessage,
    this.userFeedback,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime timestamp;
  final String? action;
  final FunctionCallAction? actionCard;
  final bool isStreaming;
  final bool isQueued;
  final bool hasError;
  final String? errorMessage;
  final String? userFeedback; // 'like' | 'dislike' | null

  bool get fromBot => role == ChatRole.model || role == ChatRole.system;

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    DateTime? timestamp,
    String? action,
    FunctionCallAction? actionCard,
    bool? isStreaming,
    bool? isQueued,
    bool? hasError,
    String? errorMessage,
    String? userFeedback,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      action: action ?? this.action,
      actionCard: actionCard ?? this.actionCard,
      isStreaming: isStreaming ?? this.isStreaming,
      isQueued: isQueued ?? this.isQueued,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      userFeedback: userFeedback ?? this.userFeedback,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? 'msg-${DateTime.now().millisecondsSinceEpoch}',
      role: ChatRole.fromString(json['role'] as String? ?? 'user'),
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      action: json['action'] as String?,
      actionCard: json['actionCard'] != null
          ? FunctionCallAction.fromJson(json['actionCard'] as Map<String, dynamic>)
          : null,
      isStreaming: json['isStreaming'] as bool? ?? false,
      isQueued: json['isQueued'] as bool? ?? false,
      hasError: json['hasError'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      userFeedback: json['userFeedback'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.toWire(),
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      if (action != null) 'action': action,
      if (actionCard != null) 'actionCard': actionCard!.toJson(),
      if (isQueued) 'isQueued': true,
      if (hasError) 'hasError': true,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (userFeedback != null) 'userFeedback': userFeedback,
    };
  }
}
