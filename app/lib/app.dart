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
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _settings.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VinFast Battery',
      debugShowCheckedModeBanner: false,
      
      // Theme support (Light/Dark/System per PLAN1)
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _settings.getThemeModeValue(),
      
      // Localization support (Vietnamese/English per PLAN1)
      locale: _settings.getLocale(),
      supportedLocales: const [
        Locale('vi'), // Vietnamese
        Locale('en'), // English
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      
      scaffoldMessengerKey: AppPopup.messengerKey,
      home: const AuthGate(),
    );
  }
}
