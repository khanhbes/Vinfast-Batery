import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/firebase_bootstrap_coordinator.dart';
import '../repositories/vehicle_spec_repository.dart';
import '../repositories/notification_repository.dart';
import 'notification_service.dart';

/// FCM/APNs token lifecycle. Push token documents are server-only; the app
/// communicates through authenticated REST endpoints and never touches them in
/// Firestore client rules.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<User?>? _authSubscription;
  String? _registeredUid;
  String? _lastRegisteredFingerprint;
  int _authGeneration = 0;
  http.Client? _registrationClient;
  bool _initialized = false;
  Future<void>? _initializing;
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

  Future<void> initialize({
    void Function(Map<String, dynamic>)? onDeepLink,
  }) async {
    if (onDeepLink != null) setDeepLinkHandler(onDeepLink);
    if (_initialized) return;
    final active = _initializing;
    if (active != null) return active;
    final task = _initializeInternal();
    _initializing = task;
    try {
      await task;
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeInternal() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (!FirebaseBootstrapCoordinator.isReady) {
      await FirebaseBootstrapCoordinator.ensureInitialized();
    }
    final handler = _deepLinkHandler;
    _foregroundMessages ??= FirebaseMessaging.onMessage.listen(_handleMessage);
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
    _tokenRefresh ??= _messaging.onTokenRefresh.listen(
      (_) => syncCurrentUser(),
    );
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((_) {
      syncCurrentUser();
    });
    await syncCurrentUser();
  }

  /// Requests notification permission after an explicit user choice.
  Future<bool> requestPermissionFromUser() async {
    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        return true;
      }
      return false;
    }
    final granted = await NotificationService().requestPermission();
    return granted;
  }

  void _handleMessage(RemoteMessage message) {
    final event = message.data['event']?.toString();
    if (event == 'catalog_updated' ||
        message.data['catalogUpdated'] == 'true') {
      VehicleSpecRepository().invalidateRemoteCache();
    }
    if (event == 'notification_updated' ||
        message.data['notificationUpdated'] == 'true') {
      NotificationRepository().invalidateUnread();
    }
    final handler = _deepLinkHandler;
    if (handler != null && message.data.isNotEmpty) {
      handler(message.data);
    }
  }

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: value);
    return value;
  }

  Future<void> syncCurrentUser() async {
    final generation = _authGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('pushNotifications') ?? false)) return;
    if (Platform.isAndroid || Platform.isIOS) {
      final settings = await _messaging.getNotificationSettings();
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!authorized) return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _registeredUid = null;
      return;
    }
    try {
      await _messaging.subscribeToTopic('vehicle_catalog');
    } catch (error) {
      debugPrint(
        '[Push] catalog topic subscription deferred: ${error.runtimeType}',
      );
    }
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    final info = await PackageInfo.fromPlatform();
    final deviceId = await _deviceId();
    final idToken = await user.getIdToken();
    if (generation != _authGeneration ||
        FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return;
    }
    final fingerprint =
        '${user.uid}|$token|${info.version}+${info.buildNumber}|${Platform.localeName}';
    if (_registeredUid == user.uid &&
        _lastRegisteredFingerprint == fingerprint) {
      return;
    }
    final client = http.Client();
    _registrationClient = client;
    late final http.Response response;
    try {
      response = await client
          .put(
            Uri.parse(
              '${AppConstants.apiBaseUrl}/api/mobile/push-tokens/$deviceId',
            ),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'token': token,
              'platform': Platform.isIOS ? 'ios' : 'android',
              'bundleId': Platform.isIOS
                  ? 'com.khanhbes.vinfastbattery'
                  : 'com.bes.vinbatery',
              'appVersion': '${info.version}+${info.buildNumber}',
              'locale': Platform.localeName,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } finally {
      if (identical(_registrationClient, client)) _registrationClient = null;
      client.close();
    }
    if (generation != _authGeneration ||
        FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _registeredUid = user.uid;
      _lastRegisteredFingerprint = fingerprint;
    } else {
      debugPrint('[Push] token registration failed ${response.statusCode}');
    }
  }

  Future<void> revokeCurrentUser() async {
    // Invalidate earlier asynchronous token registration before revocation.
    _authGeneration += 1;
    _registrationClient?.close();
    _registrationClient = null;
    _registeredUid = null;
    _lastRegisteredFingerprint = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final deviceId = await _deviceId();
    final idToken = await user.getIdToken();
    await http
        .delete(
          Uri.parse(
            '${AppConstants.apiBaseUrl}/api/mobile/push-tokens/$deviceId',
          ),
          headers: {'Authorization': 'Bearer $idToken'},
        )
        .timeout(const Duration(seconds: 3));
  }

  void dispose() {
    _tokenRefresh?.cancel();
    _foregroundMessages?.cancel();
    _authSubscription?.cancel();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Data-only pushes are reconciled by the foreground app; iOS displays
  // notification payloads through APNs while the app is suspended.
}
