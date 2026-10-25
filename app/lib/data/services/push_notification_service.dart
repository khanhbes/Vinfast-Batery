import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/firebase_bootstrap_coordinator.dart';
import '../repositories/vehicle_spec_repository.dart';
import '../repositories/notification_repository.dart';
import 'notification_service.dart';
import 'charge_progress_notification.dart';
import '../../core/services/smart_charge_remote_events.dart';

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
  StreamSubscription<RemoteMessage>? _openedMessages;
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

  void _dispatchDeepLink(Map<String, dynamic> data) {
    final handler = _deepLinkHandler;
    if (handler != null) {
      handler(data);
    } else {
      _pendingDeepLinks.add(data);
    }
  }

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
    _foregroundMessages ??= FirebaseMessaging.onMessage.listen(_handleMessage);
    // One listener, and the handler is read when the tap happens: a handler
    // registered after init (or a retried init) still receives it (Task 125).
    _openedMessages ??= FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _dispatchDeepLink(message.data),
    );
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _dispatchDeepLink(initial.data);
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

  static const enabledPreferenceKey = 'pushNotifications';

  /// Last choice applied through [setEnabledByUser], so an open Settings
  /// screen follows a change made by BatteryBot.
  final ValueNotifier<bool?> userChoice = ValueNotifier(null);

  /// The user's push choice, true only while the OS still allows it.
  Future<bool> isEnabledByUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(enabledPreferenceKey) ?? false)) return false;
    return (await Permission.notification.status).isGranted;
  }

  /// Applies the user's push choice (Settings switch, BatteryBot). Returns
  /// the resulting state: false when the OS permission was refused.
  Future<bool> setEnabledByUser(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final granted = await requestPermissionFromUser();
      await prefs.setBool(enabledPreferenceKey, granted);
      userChoice.value = granted;
      if (!granted) return false;
      await initialize();
      await syncCurrentUser();
      return true;
    }
    await prefs.setBool(enabledPreferenceKey, false);
    userChoice.value = false;
    try {
      await revokeCurrentUser();
    } on Object {
      // Revocation is best effort; the server drops stale tokens on send.
    }
    return false;
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
    // QA 135: a safety cutoff / night-charging problem rings even with the
    // app open (the system shows background ones on the urgent channel).
    if (message.data['urgent'] == '1') {
      unawaited(
        NotificationService().showUrgent(
          title: message.notification?.title ?? 'Cảnh báo sạc',
          message:
              message.notification?.body ??
              'Mở Pinova để xem trạng thái ổ sạc.',
          payload: 'smart_charge/current',
        ),
      );
    }
    // Another phone / the server changed Smart Charge: refresh, never jump.
    SmartChargeRemoteEvents.instance.addFromPush(message.data);
    // Progress while no live monitor runs; a final state clears it.
    unawaited(ChargeProgressNotification.handlePush(message.data));
    // A message received while the app is open is not a tap: deep links run
    // only from onMessageOpenedApp/getInitialMessage. Navigating here moved
    // the user to History mid-command on every session push (Task 123).
  }

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: value);
    return value;
  }

  Future<void> syncCurrentUser() async {
    try {
      await _syncCurrentUserInternal();
    } catch (error) {
      // Push registration is best-effort background work. A missing backend,
      // timeout or messaging plugin error must not interrupt onboarding.
      debugPrint('[Push] token sync deferred (${error.runtimeType})');
    }
  }

  Future<void> _syncCurrentUserInternal() async {
    final generation = _authGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('pushNotifications') ?? false)) return;
    if (!AppConstants.isApiConfigured) {
      debugPrint('[Push] token sync deferred (API not configured)');
      return;
    }
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
    final endpoint = AppConstants.tryBuildApiUri(
      '/api/mobile/push-tokens/$deviceId',
    );
    if (endpoint == null) {
      debugPrint('[Push] token sync deferred (API not configured)');
      return;
    }
    final client = http.Client();
    _registrationClient = client;
    late final http.Response response;
    try {
      response = await client
          .put(
            endpoint,
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
    final endpoint = AppConstants.tryBuildApiUri(
      '/api/mobile/push-tokens/$deviceId',
    );
    if (endpoint == null) {
      debugPrint('[Push] token revoke deferred (API not configured)');
      return;
    }
    final idToken = await user.getIdToken();
    await http
        .delete(endpoint, headers: {'Authorization': 'Bearer $idToken'})
        .timeout(const Duration(seconds: 3));
  }

  void dispose() {
    _tokenRefresh?.cancel();
    _foregroundMessages?.cancel();
    _openedMessages?.cancel();
    _authSubscription?.cancel();
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Data-only pushes are otherwise reconciled by the foreground app; iOS
  // displays notification payloads through APNs while suspended. Task 126:
  // the worker's progress pushes keep the "charging now" notification fresh
  // while Android has killed the app.
  DartPluginRegistrant.ensureInitialized();
  await ChargeProgressNotification.handlePush(message.data);
}
