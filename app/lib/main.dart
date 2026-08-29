import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';

import 'app.dart';
import 'data/services/notification_service.dart';
import 'data/services/background_service_config.dart';
import 'core/widgets/app_popup.dart';
import 'core/services/app_error_reporter.dart';
import 'data/services/charging_prediction_adapter.dart';
import 'data/services/shelly_clients.dart';
import 'data/services/smart_charger_service.dart';

/// Provider toàn cục cho trạng thái recovery cần hiển thị dialog
final pendingRecoveryProvider = StateProvider<String?>((ref) => null);

/// Provider nắm lỗi `Firebase.initializeApp()` ở cold start để `AuthGate`
/// có thể render màn hình lỗi/retry thay vì đẩy thẳng user về Login khi
/// Firebase chưa sẵn sàng.
final firebaseInitErrorProvider = StateProvider<Object?>((ref) => null);

bool _isExpectedOperationalError(Object error) =>
    error is SmartChargerException ||
    error is ShellyClientException ||
    error is SmartChargePredictionException;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppErrorReporter.report(
      details.exception,
      details.stack,
      source: 'FlutterError',
    );
    if (_isExpectedOperationalError(details.exception)) return;
    FlutterError.presentError(details);
    AppPopup.showError('Đã xảy ra lỗi trong ứng dụng. Vui lòng thử lại.');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppErrorReporter.report(error, stack, source: 'PlatformDispatcher');
    if (_isExpectedOperationalError(error)) return true;
    AppPopup.showError('Ứng dụng gặp lỗi ngoài luồng chính.');
    return true;
  };

  await runZonedGuarded(
    () async {
      // Khởi tạo Firebase
      Object? firebaseInitError;
      try {
        await Firebase.initializeApp();
      } catch (e, stack) {
        AppErrorReporter.report(e, stack, source: 'Firebase');
        firebaseInitError = e;
      }

      // Khởi tạo Notification Service
      try {
        await NotificationService().initialize();
      } catch (e, stack) {
        AppErrorReporter.report(e, stack, source: 'NotificationService');
      }

      // Khởi tạo Background Service
      try {
        await BackgroundServiceConfig.initialize();
      } catch (e, stack) {
        AppErrorReporter.report(e, stack, source: 'BackgroundService');
      }

      // Kiểm tra session tracking chưa kết thúc (crash recovery)
      String? pendingRecovery;
      try {
        final prefs = await SharedPreferences.getInstance();
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
            firebaseInitErrorProvider.overrideWith((ref) => firebaseInitError),
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
