import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

final chatHistoryStorageProvider = Provider<ChatHistoryStorage>((ref) {
  return ChatHistoryStorage();
});

class ChatHistoryStorage {
  ChatHistoryStorage({http.Client? client, String? Function()? uidResolver})
    : _client = client ?? http.Client(),
      _uidResolver = uidResolver ?? _firebaseUid;

  final String? Function() _uidResolver;
  static String? _firebaseUid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  String get _scope => Uri.encodeComponent(_uidResolver() ?? 'guest');
  String get _sessionIndexKey => 'vinfast_chat_sessions_index_v2_$_scope';
  String get _msgPrefix => 'vinfast_chat_msgs_v2_${_scope}_';

  final http.Client _client;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  Future<void> _writeTail = Future<void>.value();

  Future<void> _serializeWrite(Future<void> Function() operation) {
    final uid = _uidResolver();
    final next = _writeTail.then((_) async {
      if (uid == _uidResolver()) {
        await operation();
      }
    });
    _writeTail = next.catchError((Object _) {});
    return next;
  }

  /// Lưu toàn bộ tin nhắn của một session vào local storage
  Future<void> saveSessionMessages(
    String sessionId,
    List<ChatMessage> messages, {
    String? title,
  }) {
    final snapshot = List<ChatMessage>.of(messages);
    return _serializeWrite(
      () => _saveSessionMessages(sessionId, snapshot, title: title),
    );
  }

  Future<void> _saveSessionMessages(
    String sessionId,
    List<ChatMessage> messages, {
    String? title,
  }) async {
    try {
      final uid = _uidResolver();
      final indexKey = _sessionIndexKey;
      final msgPrefix = _msgPrefix;
      final prefs = _secure;
      if (uid != _uidResolver()) return;
      final serialized = jsonEncode(messages.map((m) => m.toJson()).toList());
      await prefs.write(key: '$msgPrefix$sessionId', value: serialized);

      // Cập nhật session index
      final sessions = await listSavedSessions(limit: 100000);
      if (uid != _uidResolver()) return;
      final now = DateTime.now();
      final existingIndex = sessions.indexWhere(
        (s) => s.sessionId == sessionId,
      );

      final sessionTitle =
          title ??
          (messages.isNotEmpty
              ? messages
                    .firstWhere((m) => !m.fromBot, orElse: () => messages.first)
                    .content
              : 'Cuộc trò chuyện');

      final trimmedTitle = sessionTitle;

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

      await prefs.write(
        key: indexKey,
        value: jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Local save unavailable.');
    }
  }

  /// Nạp danh sách tin nhắn của một session từ local storage
  Future<List<ChatMessage>> loadSessionMessages(String sessionId) async {
    try {
      final uid = _uidResolver();
      final msgPrefix = _msgPrefix;
      final prefs = _secure;
      if (uid != _uidResolver()) return [];
      final raw = await prefs.read(key: '$msgPrefix$sessionId');
      if (uid != _uidResolver()) return [];
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi loadSessionMessages.');
    }
    return [];
  }

  /// Liệt kê các session đã lưu ở local (hỗ trợ phân trang limit / offset)
  Future<List<ChatSession>> listSavedSessions({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final uid = _uidResolver();
      final indexKey = _sessionIndexKey;
      final prefs = _secure;
      if (uid != _uidResolver()) return [];
      final raw = await prefs.read(key: indexKey);
      if (uid != _uidResolver()) return [];
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        final all = list
            .map((item) => ChatSession.fromJson(item as Map<String, dynamic>))
            .toList();
        if (offset >= all.length) return [];
        final end = (offset + limit < all.length) ? offset + limit : all.length;
        return all.sublist(offset, end);
      }
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi listSavedSessions.');
    }
    return [];
  }

  /// Alias cho listSavedSessions với hỗ trợ phân trang
  Future<List<ChatSession>> listSessions({int limit = 50, int offset = 0}) =>
      listSavedSessions(limit: limit, offset: offset);

  /// Xóa một session khỏi local storage
  Future<void> deleteSession(String sessionId) async {
    await _serializeWrite(() => _deleteSession(sessionId));
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      final uid = _uidResolver();
      final indexKey = _sessionIndexKey;
      final msgPrefix = _msgPrefix;
      final prefs = _secure;
      if (uid != _uidResolver()) return;
      await prefs.delete(key: '$msgPrefix$sessionId');
      final sessions = await listSavedSessions(limit: 100000);
      if (uid != _uidResolver()) return;
      sessions.removeWhere((s) => s.sessionId == sessionId);
      await prefs.write(
        key: indexKey,
        value: jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi deleteSession.');
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
      if (user == null || user.uid != _uidResolver()) return false;
      final uid = user.uid;
      final token = await user.getIdToken();
      if (uid != _uidResolver() || token == null) return false;

      final res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'sessionId': sessionId,
              'userId': user.uid,
              'title': title,
              'messages': messages.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      return uid == _uidResolver() && res.statusCode == 200;
    } catch (e) {
      debugPrint('[ChatHistoryStorage] Lỗi backupToCloud.');
      return false;
    }
  }
}
