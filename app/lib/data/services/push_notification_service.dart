import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';

/// FCM/APNs token lifecycle. Push token documents are server-only; the app
/// communicates through authenticated REST endpoints and never touches them in
/// Firestore client rules.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<User?>? _authSubscription;
  String? _registeredUid;
  void Function(Map<String, dynamic>)? _deepLinkHandler;
  final List<Map<String, dynamic>> _pendingDeepLinks = [];

  static const _deviceIdKey = 'push.device_id';

  void setDeepLinkHandler(void Function(Map<String, dynamic>) handler) {
    _deepLinkHandler = handler;
    for (final data in List<Map<String, dynamic>>.from(_pendingDeepLinks)) {
      handler(data);
    }
    _pendingDeepLinks.clear();
  }

  Future<void> initialize({void Function(Map<String, dynamic>)? onDeepLink}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (Platform.isIOS) {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    final handler = onDeepLink ?? _deepLinkHandler;
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (handler != null) {
        handler(message.data);
      } else {
        _pendingDeepLinks.add(message.data);
      }
    });
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      if (handler != null) {
        handler(initial.data);
      } else {
        _pendingDeepLinks.add(initial.data);
      }
    }
    _tokenRefresh ??= _messaging.onTokenRefresh.listen((_) => syncCurrentUser());
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((_) {
      syncCurrentUser();
    });
    await syncCurrentUser();
  }

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: value);
    return value;
  }

  Future<void> syncCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _registeredUid = null;
      return;
    }
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    final info = await PackageInfo.fromPlatform();
    final deviceId = await _deviceId();
    final idToken = await user.getIdToken();
    final response = await http.put(
      Uri.parse('${AppConstants.apiBaseUrl}/api/mobile/push-tokens/$deviceId'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'bundleId': Platform.isIOS ? 'com.khanhbes.vinfastbattery' : 'com.bes.vinbatery',
        'appVersion': '${info.version}+${info.buildNumber}',
        'locale': Platform.localeName,
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _registeredUid = user.uid;
    } else {
      debugPrint('[Push] token registration failed ${response.statusCode}');
    }
  }

  Future<void> revokeCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final deviceId = await _deviceId();
    final idToken = await user.getIdToken();
    await http.delete(
      Uri.parse('${AppConstants.apiBaseUrl}/api/mobile/push-tokens/$deviceId'),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    _registeredUid = null;
  }

  void dispose() {
    _tokenRefresh?.cancel();
    _authSubscription?.cancel();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Data-only pushes are reconciled by the foreground app; iOS displays
  // notification payloads through APNs while the app is suspended.
}
