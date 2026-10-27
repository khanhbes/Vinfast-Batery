import 'package:flutter/material.dart';
import '../theme/luxe_theme.dart';

/// One-shot entrance; never delays interaction or loops during polling.
class SettingsReveal extends StatelessWidget {
  const SettingsReveal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // QA 139: the one LUXE entrance (520 ms, LuxeMotion.enter).
    return LuxeReveal(child: child);
  }
}
