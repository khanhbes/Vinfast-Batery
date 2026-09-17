import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../data/services/push_notification_service.dart';
import '../../firebase_options.dart';

/// Owns Firebase startup for every Flutter isolate.
///
/// Android may already have a native default Firebase app when Dart starts,
/// and hot restart can race another call to [initializeApp]. Both are normal
/// situations and must not be surfaced as a bootstrap failure.
class FirebaseBootstrapCoordinator {
  FirebaseBootstrapCoordinator._();

  static Future<FirebaseApp>? _initializing;
  static Future<void>? _initializingPush;
  static bool _pushReady = false;

  /// Returns true when the default Firebase app is already initialized and valid.
  static bool get isReady {
    try {
      final app = _defaultAppOrNull();
      if (app == null) return false;
      _validate(app);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<FirebaseApp> ensureInitialized() {
    final existing = _defaultAppOrNull();
    if (existing != null) {
      _validate(existing);
      return Future.value(existing);
    }
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  static Future<FirebaseApp> _initialize() async {
    final options = DefaultFirebaseOptions.currentPlatform;
    try {
      final app = await Firebase.initializeApp(options: options);
      _validate(app);
      return app;
    } on FirebaseException catch (error) {
      // A second isolate or hot restart can win the race. Resolve the native
      // default app again before deciding this is a real failure.
      if (error.code == 'duplicate-app') {
        final existing = _defaultAppOrNull();
        if (existing != null) {
          _validate(existing);
          return existing;
        }
      }
      rethrow;
    }
  }

  static FirebaseApp? _defaultAppOrNull() {
    for (final app in Firebase.apps) {
      if (app.name == defaultFirebaseAppName) return app;
    }
    return null;
  }

  static void _validate(FirebaseApp app) {
    final expected = DefaultFirebaseOptions.currentPlatform;
    final actual = app.options;
    if (actual.projectId != expected.projectId || actual.appId != expected.appId) {
      throw StateError(
        'Firebase default app does not match the VinFast Battery configuration.',
      );
    }
  }

  /// Starts Firebase-dependent services once, after [ensureInitialized].
  static Future<void> initializePushServices() async {
    if (_pushReady) return;
    final active = _initializingPush;
    if (active != null) return active;
    final task = _initializePushServices();
    _initializingPush = task;
    try {
      await task;
      _pushReady = true;
    } finally {
      _initializingPush = null;
    }
  }

  static Future<void> _initializePushServices() async {
    await ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushNotificationService.instance.initialize();
  }
}
