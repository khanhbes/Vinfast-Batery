import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';

/// A request the server answered with an error (or never answered).
/// [message] is the server's user-facing Vietnamese copy, safe to show;
/// it is never the raw exception text.
class PinovaApiException implements Exception {
  const PinovaApiException(this.code, {this.message, this.status = 0});

  final String code;
  final String? message;
  final int status;

  bool get offline => code == 'network' || code == 'unconfigured';
  bool get notDeployed => status == 404 && code == 'http404';

  @override
  String toString() => message ?? code;
}

/// Authorized JSON calls for the QA 135 APIs (billing, support, scan,
/// battery health, night charging): Firebase ID token, one retry with a
/// fresh token after a 401, `{success, data}` envelopes.
class PinovaApi {
  PinovaApi({
    http.Client? client,
    Future<String?> Function()? tokenResolver,
    Future<String?> Function()? refreshedTokenResolver,
    this.timeout = const Duration(seconds: 25),
  }) : _client = client ?? http.Client(),
       _tokenResolver = tokenResolver ?? _firebaseToken,
       _refreshedTokenResolver =
           refreshedTokenResolver ??
           (tokenResolver == null ? _refreshedFirebaseToken : null);

  final http.Client _client;
  final Future<String?> Function() _tokenResolver;
  final Future<String?> Function()? _refreshedTokenResolver;
  final Duration timeout;

  static Future<String?> _firebaseToken() async => Firebase.apps.isEmpty
      ? null
      : FirebaseAuth.instance.currentUser?.getIdToken();

  static Future<String?> _refreshedFirebaseToken() async =>
      Firebase.apps.isEmpty
      ? null
      : FirebaseAuth.instance.currentUser?.getIdToken(true);

  Future<Map<String, dynamic>> get(String path) => call('GET', path);
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      call('POST', path, body: body ?? const {});
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      call('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => call('DELETE', path);

  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    final uri = AppConstants.tryBuildApiUri(path);
    if (uri == null || !AppConstants.isApiConfigured) {
      throw const PinovaApiException('unconfigured');
    }
    final String? token;
    try {
      token = await _tokenResolver().timeout(const Duration(seconds: 12));
    } on Object {
      throw const PinovaApiException('auth');
    }
    if (token == null) throw const PinovaApiException('auth');

    Future<http.Response> send(String bearer) async {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $bearer',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...headers,
        });
      if (body != null) request.body = jsonEncode(body);
      try {
        return await http.Response.fromStream(
          await _client.send(request).timeout(timeout),
        ).timeout(timeout);
      } on Object {
        throw const PinovaApiException('network');
      }
    }

    var response = await send(token);
    final refresh = _refreshedTokenResolver;
    if (response.statusCode == 401 && refresh != null) {
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
      throw PinovaApiException(
        'http${response.statusCode}',
        status: response.statusCode,
      );
    }
    if (response.statusCode >= 300 || decoded['success'] != true) {
      final error = decoded['error'];
      final code =
          (error is Map ? error['code']?.toString() : null) ??
          decoded['code']?.toString() ??
          'http${response.statusCode}';
      final message =
          decoded['userMessage']?.toString() ??
          (error is Map
              ? (error['userMessage'] ?? error['message'])?.toString()
              : null);
      throw PinovaApiException(
        code,
        message: message,
        status: response.statusCode,
      );
    }
    final data = decoded['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
