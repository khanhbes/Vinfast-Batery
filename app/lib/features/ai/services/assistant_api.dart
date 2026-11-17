import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';

/// QA 142: when Pinova Bot is locked for this account (server-owned; the
/// sheet shows it above the input).
abstract final class AssistantLock {
  static final until = ValueNotifier<DateTime?>(null);
}

/// QA 163: what the last server turn said besides its text, for the sheet:
/// the questions the owner may ask next and the messages left today.
abstract final class AssistantSignals {
  static final followUps = ValueNotifier<List<String>>(const []);
  static final remainingToday = ValueNotifier<int?>(null);

  /// QA 164: the answer as Pinova Bot writes it (server-sent events). The
  /// sheet shows it while the turn runs; the final, checked reply replaces
  /// it. Empty when nothing has arrived yet.
  static final liveText = ValueNotifier<String>('');

  /// QA 164: what Pinova Bot is reading right now ("Đang xem ổ Shelly…").
  static final liveStatus = ValueNotifier<String?>(null);

  static void clearLive() {
    liveText.value = '';
    liveStatus.value = null;
  }
}

/// QA 163: the owner's Pinova Bot settings (`/api/assistant/settings`).
class AssistantSettings {
  const AssistantSettings({
    this.learningEnabled = true,
    this.persona = 'companion',
    this.length = 'medium',
    this.callMe = '',
    this.aboutMe = '',
    this.followUps = true,
    this.conciergeAllowed = false,
    this.quotaUsed,
    this.quotaLimit,
    this.botVersion,
    this.promptVersion,
  });

  final bool learningEnabled;

  /// companion | concise | expert | concierge (Pro/Ultra)
  final String persona;

  /// short | medium | long
  final String length;
  final String callMe;
  final String aboutMe;
  final bool followUps;
  final bool conciergeAllowed;
  final int? quotaUsed;
  final int? quotaLimit;
  final String? botVersion;
  final String? promptVersion;

  int? get quotaLeft => quotaUsed == null || quotaLimit == null
      ? null
      : (quotaLimit! - quotaUsed!).clamp(0, quotaLimit!);

  static AssistantSettings fromMap(Map<String, dynamic> data) {
    final quota = data['quota'] is Map ? data['quota'] as Map : const {};
    return AssistantSettings(
      learningEnabled: data['learningEnabled'] != false,
      persona: data['persona']?.toString() ?? 'companion',
      length: data['length']?.toString() ?? 'medium',
      callMe: data['callMe']?.toString() ?? '',
      aboutMe: data['aboutMe']?.toString() ?? '',
      followUps: data['followUps'] != false,
      conciergeAllowed: data['conciergeAllowed'] == true,
      quotaUsed: (quota['used'] as num?)?.toInt(),
      quotaLimit: (quota['limit'] as num?)?.toInt(),
      botVersion: data['botVersion']?.toString(),
      promptVersion: data['promptVersion']?.toString(),
    );
  }
}

/// One server turn of BatteryBot v2 (Task 124).
class AssistantTurn {
  const AssistantTurn({
    required this.reply,
    required this.actions,
    this.memoryChanged = false,
    this.remainingToday,
    this.card,
    this.lockedUntil,
    this.emergency = false,
    this.followUps = const [],
  });

  /// QA 163: up to three questions the owner may ask next.
  final List<String> followUps;

  /// QA 143: the server's fire/smoke/shock safety reply (SOS). Its text is
  /// always shown; the stop card is added only when there is a session.
  final bool emergency;

  /// QA 142: the server locked Pinova Bot for this account until then
  /// (Community rules, 3 strikes).
  final DateTime? lockedUntil;

  final String reply;
  final List<AssistantAction> actions;
  final bool memoryChanged;
  final int? remainingToday;

  /// Rich result card from a server tool (Task 126: `trip_plan`).
  final Map<String, dynamic>? card;
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
    Future<String?> Function()? refreshedTokenResolver,
    this.timeout = const Duration(seconds: 35),
    this.streamReplies = true,
  }) : _client = client ?? http.Client(),
       _tokenResolver = tokenResolver ?? _firebaseToken,
       _refreshedTokenResolver =
           refreshedTokenResolver ??
           (tokenResolver == null ? _refreshedFirebaseToken : null);

  final http.Client _client;
  final Future<String?> Function() _tokenResolver;

  /// Forces a new ID token after a 401 (expired token, QA 129).
  final Future<String?> Function()? _refreshedTokenResolver;
  final Duration timeout;

  /// QA 164: ask for the answer as it is written (`stream: true`). An older
  /// server, or an answer the server gives before the model (SOS, quota,
  /// rules), comes back as JSON and is read the same way as before.
  final bool streamReplies;

  static Future<String?> _firebaseToken() async => Firebase.apps.isEmpty
      ? null
      : FirebaseAuth.instance.currentUser?.getIdToken();

  static Future<String?> _refreshedFirebaseToken() async =>
      Firebase.apps.isEmpty
      ? null
      : FirebaseAuth.instance.currentUser?.getIdToken(true);

  void close() => _client.close();

  /// The parsed `{success, data, error}` body, or the data from the `done`
  /// event of a stream (QA 164).
  Map<String, dynamic> _data(int status, Map<String, dynamic> decoded) {
    if (status != 200 || decoded['success'] != true) {
      final error = decoded['error'];
      final code = error is Map ? error['code']?.toString() : 'http$status';
      throw AssistantUnavailable(
        code ?? 'http$status',
        error is Map ? error['message']?.toString() : null,
      );
    }
    final data = decoded['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// QA 164: one chat turn as server-sent events. `delta`/`status`/`reset`
  /// go to [AssistantSignals]; `done` carries the whole result. Anything
  /// that is not an event stream is read as the JSON answer.
  Future<Map<String, dynamic>> _streamTurn(Map<String, dynamic> body) async {
    final uri = AppConstants.tryBuildApiUri('/api/assistant/chat');
    if (uri == null || !AppConstants.isApiConfigured) {
      throw const AssistantUnavailable('unconfigured');
    }
    String? token;
    try {
      token = await _tokenResolver().timeout(const Duration(seconds: 12));
    } on Object {
      throw const AssistantUnavailable('auth');
    }
    if (token == null) throw const AssistantUnavailable('auth');
    Future<http.StreamedResponse> send(String bearer) async {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $bearer',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream, application/json',
        })
        ..body = jsonEncode({...body, 'stream': true});
      try {
        return await _client.send(request).timeout(timeout);
      } on Object {
        throw const AssistantUnavailable('network');
      }
    }

    var response = await send(token);
    final refresh = _refreshedTokenResolver;
    if (response.statusCode == 401 && refresh != null) {
      await response.stream.drain<void>().catchError((_) {});
      String? fresh;
      try {
        fresh = await refresh().timeout(const Duration(seconds: 12));
      } on Object {
        fresh = null;
      }
      if (fresh != null && fresh != token) response = await send(fresh);
    }
    final type = response.headers['content-type'] ?? '';
    if (!type.startsWith('text/event-stream')) {
      final String text;
      try {
        text = await response.stream.bytesToString().timeout(timeout);
      } on Object {
        throw const AssistantUnavailable('network');
      }
      Map<String, dynamic> decoded;
      try {
        decoded = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } on Object {
        throw AssistantUnavailable('http${response.statusCode}');
      }
      return _data(response.statusCode, decoded);
    }
    var event = '';
    final data = <String>[];
    Map<String, dynamic>? done;
    try {
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          // The server sends nothing for a while only when it is gone.
          .timeout(timeout);
      await for (final line in lines) {
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.add(line.substring(5).trimLeft());
        } else if (line.isEmpty && data.isNotEmpty) {
          final Object? json;
          try {
            json = jsonDecode(data.join('\n'));
          } on FormatException {
            data.clear();
            continue;
          }
          data.clear();
          final map = json is Map ? json : const {};
          switch (event) {
            case 'delta':
              AssistantSignals.liveText.value += '${map['text'] ?? ''}';
              AssistantSignals.liveStatus.value = null;
            case 'status':
              AssistantSignals.liveStatus.value = map['text']?.toString();
            case 'reset':
              AssistantSignals.liveText.value = '';
            case 'done':
              done = Map<String, dynamic>.from(map);
            case 'error':
              throw AssistantUnavailable(
                map['code']?.toString() ?? 'ASSISTANT_UNAVAILABLE',
                map['message']?.toString(),
              );
          }
          if (done != null) break;
        }
      }
    } on AssistantUnavailable {
      rethrow;
    } on Object {
      throw const AssistantUnavailable('network');
    }
    if (done == null) throw const AssistantUnavailable('incomplete');
    return done;
  }

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
    Future<http.Response> send(String bearer) async {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $bearer',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      try {
        return await http.Response.fromStream(
          await _client.send(request).timeout(timeout),
        ).timeout(timeout);
      } on Object {
        throw const AssistantUnavailable('network');
      }
    }

    var response = await send(token);
    final refresh = _refreshedTokenResolver;
    if (response.statusCode == 401 && refresh != null) {
      // Rejected before any work: safe to repeat once with a fresh token.
      String? fresh;
      try {
        fresh = await refresh().timeout(const Duration(seconds: 12));
      } on Object {
        fresh = null;
      }
      if (fresh != null && fresh != token) response = await send(fresh);
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
    final body = {'message': message, 'history': history, 'context': context};
    final data = streamReplies
        ? await _streamTurn(body)
        : await _call('POST', '/api/assistant/chat', body: body);
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
      card: data['card'] is Map
          ? Map<String, dynamic>.from(data['card'] as Map)
          : null,
      lockedUntil: data['assistantLock'] is Map
          ? DateTime.tryParse(
              '${(data['assistantLock'] as Map)['until']}',
            )?.toLocal()
          : null,
      emergency: data['emergencyBypass'] == true,
      followUps: [
        for (final item in (data['followUps'] as List? ?? const []))
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ].take(3).toList(),
    );
  }

  /// QA 163: the owner's Pinova Bot settings and today's messages.
  Future<AssistantSettings> settings() async =>
      AssistantSettings.fromMap(await _call('GET', '/api/assistant/settings'));

  /// Saves the given fields only; returns what the server now holds.
  Future<AssistantSettings> updateSettings(Map<String, dynamic> patch) async =>
      AssistantSettings.fromMap(
        await _call('PUT', '/api/assistant/settings', body: patch),
      );

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
