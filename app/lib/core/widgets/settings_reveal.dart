import 'package:flutter/material.dart';
import '../theme/app_motion.dart';

/// One-shot entrance; never delays interaction or loops during polling.
class SettingsReveal extends StatelessWidget {
  const SettingsReveal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppReveal(duration: AppMotion.slow, child: child);
  }
}
