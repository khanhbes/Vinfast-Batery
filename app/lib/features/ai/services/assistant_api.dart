import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';

/// One server turn of BatteryBot v2 (Task 124).
class AssistantTurn {
  const AssistantTurn({
    required this.reply,
    required this.actions,
    this.memoryChanged = false,
    this.remainingToday,
  });

  final String reply;
  final List<AssistantAction> actions;
  final bool memoryChanged;
  final int? remainingToday;
}

class AssistantAction {
  const AssistantAction(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

class AssistantFact {
  const AssistantFact({
    required this.id,
    required this.text,
    required this.category,
  });
  final String id;
  final String text;
  final String category;
}

class AssistantMemorySnapshot {
  const AssistantMemorySnapshot({
    required this.learningEnabled,
    required this.facts,
    required this.usedToday,
    required this.dailyLimit,
  });
  final bool learningEnabled;
  final List<AssistantFact> facts;
  final int usedToday;
  final int dailyLimit;
}

/// Server said "use the basic engine" (no network, quota, not configured).
class AssistantUnavailable implements Exception {
  const AssistantUnavailable(this.code, [this.message]);
  final String code;
  final String? message;
  bool get quota => code == 'ASSISTANT_QUOTA';
  @override
  String toString() => message ?? code;
}

class AssistantApi {
  AssistantApi({
    http.Client? client,
    Future<String?> Function()? tokenResolver,
    this.timeout = const Duration(seconds: 35),
  }) : _client = client ?? http.Client(),
       _tokenResolver = tokenResolver ?? _firebaseToken;

  final http.Client _client;
  final Future<String?> Function() _tokenResolver;
  final Duration timeout;

  static Future<String?> _firebaseToken() async => Firebase.apps.isEmpty
      ? null
      : FirebaseAuth.instance.currentUser?.getIdToken();

  void close() => _client.close();

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = AppConstants.tryBuildApiUri(path);
    if (uri == null || !AppConstants.isApiConfigured) {
      throw const AssistantUnavailable('unconfigured');
    }
    final String? token;
    try {
      token = await _tokenResolver().timeout(const Duration(seconds: 12));
    } on Object {
      throw const AssistantUnavailable('auth');
    }
    if (token == null) throw const AssistantUnavailable('auth');
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on Object {
      throw const AssistantUnavailable('network');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } on Object {
      throw AssistantUnavailable('http${response.statusCode}');
    }
    if (response.statusCode != 200 || decoded['success'] != true) {
      final error = decoded['error'];
      final code = error is Map
          ? error['code']?.toString()
          : 'http${response.statusCode}';
      throw AssistantUnavailable(
        code ?? 'http${response.statusCode}',
        error is Map ? error['message']?.toString() : null,
      );
    }
    final data = decoded['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<AssistantTurn> chat({
    required String message,
    required List<Map<String, String>> history,
    required Map<String, dynamic> context,
  }) async {
    final data = await _call(
      'POST',
      '/api/assistant/chat',
      body: {'message': message, 'history': history, 'context': context},
    );
    final actions = <AssistantAction>[];
    for (final item in (data['actions'] as List? ?? const [])) {
      if (item is Map && item['name'] is String) {
        actions.add(
          AssistantAction(
            item['name'] as String,
            item['args'] is Map
                ? Map<String, dynamic>.from(item['args'] as Map)
                : const {},
          ),
        );
      }
    }
    return AssistantTurn(
      reply: (data['reply'] as String? ?? '').trim(),
      actions: actions,
      memoryChanged: data['memoryChanged'] == true,
      remainingToday: (data['remainingToday'] as num?)?.toInt(),
    );
  }

  Future<AssistantMemorySnapshot> memory() async {
    final data = await _call('GET', '/api/assistant/memory');
    final settings = data['settings'] is Map ? data['settings'] as Map : {};
    final usage = data['usage'] is Map ? data['usage'] as Map : {};
    return AssistantMemorySnapshot(
      learningEnabled: settings['learningEnabled'] != false,
      facts: [
        for (final item in (data['facts'] as List? ?? const []))
          if (item is Map && item['id'] is String)
            AssistantFact(
              id: item['id'] as String,
              text: item['text']?.toString() ?? '',
              category: item['category']?.toString() ?? 'other',
            ),
      ],
      usedToday: (usage['usedToday'] as num?)?.toInt() ?? 0,
      dailyLimit: (usage['limit'] as num?)?.toInt() ?? 50,
    );
  }

  Future<void> forget(String id) =>
      _call('DELETE', '/api/assistant/memory/${Uri.encodeComponent(id)}');

  Future<void> forgetAll() => _call('DELETE', '/api/assistant/memory');

  Future<bool> setLearning(bool enabled) async {
    final data = await _call(
      'PUT',
      '/api/assistant/settings',
      body: {'learningEnabled': enabled},
    );
    return data['learningEnabled'] != false;
  }
}
