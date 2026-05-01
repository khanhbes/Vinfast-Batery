import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/services/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_popup.dart';
import 'features/auth/auth_gate.dart';
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
    // initialize() sẽ notifyListeners() ngay sau khi đọc xong prefs,
    // AnimatedBuilder dưới đây tự rebuild — không cần setState ở đây.
    _settings.initialize();
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe SettingsService để theme & locale áp dụng ngay lập tức
    // mỗi khi user đổi cài đặt — không yêu cầu restart.
    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => MaterialApp(
        title: 'VinFast Battery',
        debugShowCheckedModeBanner: false,

        // Theme support (Light/Dark/System per PLAN1)
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _settings.getThemeModeValue(),

        // Localization support (Vietnamese/English per PLAN1)
        locale: _settings.getLocale(),
        supportedLocales: const [
          Locale('vi'),
          Locale('en'),
        ],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        scaffoldMessengerKey: AppPopup.messengerKey,
        home: const AuthGate(),
      ),
    );
  }
}
