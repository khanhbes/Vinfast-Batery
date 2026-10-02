import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

final chatHistoryStorageProvider = Provider<ChatHistoryStorage>((ref) {
  return ChatHistoryStorage();
});

class ChatHistoryStorage {
  ChatHistoryStorage({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _sessionIndexKey = 'vinfast_chat_sessions_index';
  static const String _msgPrefix = 'vinfast_chat_msgs_';

  /// Lưu toàn bộ tin nhắn của một session vào local storage
  Future<void> saveSessionMessages(
    String sessionId,
    List<ChatMessage> messages, {
    String? title,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = jsonEncode(messages.map((m) => m.toJson()).toList());
      await prefs.setString('$_msgPrefix$sessionId', serialized);

      // Cập nhật session index
      final sessions = await listSavedSessions();
      final now = DateTime.now();
      final existingIndex = sessions.indexWhere((s) => s.sessionId == sessionId);

      final sessionTitle = title ??
          (messages.isNotEmpty
              ? messages.firstWhere((m) => !m.fromBot, orElse: () => messages.first).content
              : 'Cuộc trò chuyện');

      final trimmedTitle = sessionTitle.length > 36
          ? '${sessionTitle.substring(0, 36)}...'
          : sessionTitle;

      final updatedSession = ChatSession(
        sessionId: sessionId,
        title: trimmedTitle,
        createdAt: existingIndex >= 0 ? sessions[existingIndex].createdAt : now,
        updatedAt: now,
        messageCount: messages.length,
        lastMessage: messages.isNotEmpty ? messages.last.content : null,
      );

      if (existingIndex >= 0) {
        sessions[existingIndex] = updatedSession;
      } else {
        sessions.insert(0, updatedSession);
      }

      await prefs.setString(
        _sessionIndexKey,
        jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi saveSessionMessages: $e');
    }
  }

  /// Nạp danh sách tin nhắn của một session từ local storage
  Future<List<ChatMessage>> loadSessionMessages(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_msgPrefix$sessionId');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((item) => ChatMessage.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi loadSessionMessages: $e');
    }
    return [];
  }

  /// Liệt kê các session đã lưu ở local (hỗ trợ phân trang limit / offset)
  Future<List<ChatSession>> listSavedSessions({int limit = 50, int offset = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionIndexKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final all = list.map((item) => ChatSession.fromJson(item as Map<String, dynamic>)).toList();
        if (offset >= all.length) return [];
        final end = (offset + limit < all.length) ? offset + limit : all.length;
        return all.sublist(offset, end);
      }
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi listSavedSessions: $e');
    }
    return [];
  }

  /// Alias cho listSavedSessions với hỗ trợ phân trang
  Future<List<ChatSession>> listSessions({int limit = 50, int offset = 0}) =>
      listSavedSessions(limit: limit, offset: offset);

  /// Xóa một session khỏi local storage
  Future<void> deleteSession(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_msgPrefix$sessionId');
      final sessions = await listSavedSessions();
      sessions.removeWhere((s) => s.sessionId == sessionId);
      await prefs.setString(
        _sessionIndexKey,
        jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi deleteSession: $e');
    }
  }

  /// Sao lưu phiên chat lên Firestore qua Backend API (TTL 30 ngày)
  Future<bool> backupToCloud(
    String sessionId,
    List<ChatMessage> messages, {
    String? title,
  }) async {
    final uri = AppConstants.tryBuildApiUri('/api/chat/backup');
    if (uri == null || !AppConstants.isApiConfigured) return false;

    try {
      User? user;
      if (Firebase.apps.isNotEmpty) {
        user = FirebaseAuth.instance.currentUser;
      }
      final token = await user?.getIdToken();

      final res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'sessionId': sessionId,
              'userId': user?.uid,
              'title': title,
              'messages': messages.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi backupToCloud: $e');
      return false;
    }
  }
}
