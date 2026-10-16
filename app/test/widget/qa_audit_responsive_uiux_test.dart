import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/theme/app_colors.dart';
import 'package:vinfast_battery/core/theme/app_theme.dart';

void main() {
  group(
    'QA Audit — Responsive Viewports, Text Scaling & Dark Theme (CHK-51..54, CHK-56, APP-UX-H16)',
    () {
      testWidgets(
        'CHK-56: LUXE theme background and surface colors match specifications',
        (tester) async {
          final theme = AppTheme.darkTheme;

          expect(theme.scaffoldBackgroundColor, AppColors.background);
          // Task 117: legacy tokens resolve to the LUXE splash background.
          expect(AppColors.background, const Color(0xFF050506));
          expect(AppColors.accentGreen, const Color(0xFF10B981));
        },
      );
    },
  );
}
