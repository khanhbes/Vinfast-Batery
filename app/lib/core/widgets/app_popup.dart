import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AppPopup {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void showError(String message) {
    _show(message, background: AppColors.error);
  }

  static void showSuccess(String message) {
    _show(message, background: AppColors.primary);
  }

  static void _show(String message, {required Color background}) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }
}
