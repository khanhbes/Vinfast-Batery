import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_popup.dart';
import 'data/services/notification_service.dart';
import 'data/services/push_notification_service.dart';
import 'features/ai/services/learning_flow.dart';
import 'features/auth/auth_gate.dart';
import 'navigation/app_navigation.dart';
import 'core/providers/app_providers.dart';
import 'l10n/app_localizations.dart';

class VinFastBatteryApp extends StatefulWidget {
  const VinFastBatteryApp({super.key});

  @override
  State<VinFastBatteryApp> createState() => _VinFastBatteryAppState();
}

class _VinFastBatteryAppState extends State<VinFastBatteryApp> {
  final SettingsService _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    NotificationService().setTapHandler(_openNotification);
    PushNotificationService.instance.setDeepLinkHandler(_openPushNotification);
    // initialize() sẽ notifyListeners() ngay sau khi đọc xong prefs,
    // AnimatedBuilder dưới đây tự rebuild — không cần setState ở đây.
    _settings.initialize();
  }

  void _openPushNotification(Map<String, dynamic> data) {
    final sessionId = data['sessionId']?.toString();
    final vehicleId = data['vehicleId']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    _openNotification(
      'smart_charge/session/${Uri.encodeComponent(vehicleId ?? '')}/${Uri.encodeComponent(sessionId)}',
    );
  }

  void _openNotification(String payload) {
    if (payload.startsWith('learning/')) {
      // Task 127: "enough data to train" opens AI cá nhân for that vehicle.
      final vehicleId = Uri.decodeComponent(payload.substring(9));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = AppPopup.navigatorKey.currentContext;
        if (context == null || vehicleId.isEmpty) return;
        TrainingReadiness.openSettings(context, vehicleId);
      });
      return;
    }
    if (!payload.startsWith('smart_charge/')) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = AppPopup.navigatorKey.currentContext;
      if (context == null) return;
      final parts = payload.split('/');
      // V4 payload: smart_charge/session/<vehicleId>/<sessionId>. Legacy
      // payloads without a vehicle never guess a default vehicle; they open
      // the history tab and let the user choose the correct context.
      if (parts.length >= 2 && parts[1].startsWith('current')) {
        // Ongoing-charge notification: the Charge tab (Task 126).
        AppNavigation.navigateToTab(context, 1);
        return;
      }
      if (parts.length >= 4 && parts[1] == 'session') {
        final vehicleId = Uri.decodeComponent(parts[2]);
        final sessionId = Uri.decodeComponent(parts.sublist(3).join('/'));
        if (vehicleId.isNotEmpty && sessionId.isNotEmpty) {
          try {
            final container = ProviderScope.containerOf(context, listen: false);
            container.read(pendingSmartChargeTargetProvider.notifier).state = (
              vehicleId: vehicleId,
              sessionId: sessionId,
            );
          } on Object {
            // If the shell is not mounted yet, history still remains the safe
            // destination instead of silently selecting another vehicle.
          }
        }
      }
      AppNavigation.navigateToTab(context, 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe SettingsService để theme & locale áp dụng ngay lập tức
    // mỗi khi user đổi cài đặt — không yêu cầu restart.
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        // LUXE is dark only (Task 117): one theme for every screen.
        final theme = AppTheme.darkTheme;
        return MaterialApp(
          title: 'VinFast Battery',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.dark,

          // Localization support (Vietnamese/English per PLAN1)
          locale: _settings.getLocale(),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          scaffoldMessengerKey: AppPopup.messengerKey,
          navigatorKey: AppPopup.navigatorKey,
          home: const AuthGate(),
        );
      },
    );
  }
}
