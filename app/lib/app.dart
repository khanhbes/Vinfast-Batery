import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/app_popup.dart';
import 'features/auth/auth_gate.dart';

class VinFastBatteryApp extends StatelessWidget {
  const VinFastBatteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VinFast Battery',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      scaffoldMessengerKey: AppPopup.messengerKey,
      home: const AuthGate(),
    );
  }
}
