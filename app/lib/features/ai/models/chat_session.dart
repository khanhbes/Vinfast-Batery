import 'package:flutter/foundation.dart';

@immutable
class ChatSession {
  const ChatSession({
    required this.sessionId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.lastMessage,
  });

  final String sessionId;
  String get id => sessionId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final String? lastMessage;

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      sessionId: json['sessionId'] as String? ?? '',
      title: json['title'] as String? ?? 'Cuộc trò chuyện',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      lastMessage: json['lastMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messageCount': messageCount,
      if (lastMessage != null) 'lastMessage': lastMessage,
    };
  }
}
