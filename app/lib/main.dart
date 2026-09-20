import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';

import 'app.dart';
import 'data/services/notification_service.dart';
import 'data/services/background_service_config.dart';
import 'core/constants/app_constants.dart';
import 'core/widgets/app_popup.dart';
import 'core/services/app_error_reporter.dart';
import 'data/services/charging_prediction_adapter.dart';
import 'data/services/shelly_clients.dart';
import 'data/services/smart_charger_service.dart';
import 'core/services/firebase_bootstrap_coordinator.dart';

/// Provider toàn cục cho trạng thái recovery cần hiển thị dialog
final pendingRecoveryProvider = StateProvider<String?>((ref) => null);

/// Provider nắm lỗi `Firebase.initializeApp()` ở cold start để `AuthGate`
/// có thể render màn hình lỗi/retry thay vì đẩy thẳng user về Login khi
/// Firebase chưa sẵn sàng.
final firebaseInitErrorProvider = StateProvider<Object?>((ref) => null);

bool _isExpectedOperationalError(Object error) {
  final str = error.toString();
  if (str.contains('google_fonts') ||
      str.contains('Failed to load font') ||
      str.contains('HandshakeException') ||
      str.contains('SocketException') ||
      str.contains('TimeoutException') ||
      str.contains('Zone mismatch')) {
    return true;
  }
  return error is SmartChargerException ||
      error is ShellyClientException ||
      error is SmartChargePredictionException;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A production APK without an injected HTTPS API endpoint is unsafe to
  // ship: fail before Firebase/network work rather than silently running
  // against an empty or developer URL.
  if (kReleaseMode && !AppConstants.isApiConfigured) {
    throw StateError('APP_API_BASE_URL must be an HTTPS URL in release builds');
  }

  FlutterError.onError = (details) {
    AppErrorReporter.report(
      details.exception,
      details.stack,
      source: 'FlutterError',
    );
    if (_isExpectedOperationalError(details.exception)) return;
    FlutterError.presentError(details);
    if (WidgetsBinding.instance.rootElement != null) {
      Future.microtask(() {
        AppPopup.showError(
          'Đã xảy ra lỗi trong ứng dụng. Vui lòng thử lại.',
          error: details.exception,
          stackTrace: details.stack,
        );
      });
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppErrorReporter.report(error, stack, source: 'PlatformDispatcher');
    if (_isExpectedOperationalError(error)) return true;
    if (WidgetsBinding.instance.rootElement != null) {
      Future.microtask(() {
        AppPopup.showError(
          'Ứng dụng gặp lỗi ngoài luồng chính.',
          error: error,
          stackTrace: stack,
        );
      });
    }
    return true;
  };

  await runZonedGuarded(
    () async {
      // Khởi động Firebase trong nền (AuthGate sẽ await phối hợp hiển thị splash/retry)
      unawaited(
        () async {
          try {
            await FirebaseBootstrapCoordinator.ensureInitialized();
          } catch (e, stack) {
            AppErrorReporter.report(e, stack, source: 'FirebaseBootstrap');
          }
        }(),
      );

      // Kiểm tra session tracking chưa kết thúc (crash recovery)
      String? pendingRecovery;
      try {
        final prefs = await SharedPreferences.getInstance();
        final customUrl = prefs.getString('custom_api_base_url');
        if (customUrl != null && customUrl.isNotEmpty) {
          AppConstants.setCustomApiBaseUrl(customUrl);
        }
        final chargeActive = prefs.getBool('charge_active') ?? false;
        final tripActive = prefs.getBool('trip_active') ?? false;
        if (chargeActive) {
          pendingRecovery = 'charge';
        } else if (tripActive) {
          pendingRecovery = 'trip';
        }
      } catch (e, stack) {
        AppErrorReporter.report(e, stack, source: 'CrashRecovery');
      }

      // Khởi tạo Notification Service trong nền (không chặn first frame)
      unawaited(
        NotificationService().initialize().catchError((e, stack) {
          AppErrorReporter.report(e, stack, source: 'NotificationService');
        }),
      );

      // Khởi tạo Background Service trong nền (không chặn first frame)
      unawaited(
        BackgroundServiceConfig.initialize().catchError((e, stack) {
          AppErrorReporter.report(e, stack, source: 'BackgroundService');
        }),
      );

      // Lock to portrait mode
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      // Set system UI style for dark theme
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF050505),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );

      runApp(
        ProviderScope(
          overrides: [
            pendingRecoveryProvider.overrideWith((ref) => pendingRecovery),
          ],
          child: const VinFastBatteryApp(),
        ),
      );
    },
    (error, stack) {
      AppErrorReporter.report(error, stack, source: 'ZonedGuarded');
      if (_isExpectedOperationalError(error)) return;
      AppPopup.showError('Đã bắt được lỗi không mong muốn.');
    },
  );
}
