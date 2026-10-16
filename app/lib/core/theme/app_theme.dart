import 'package:flutter/material.dart';

import 'cockpit_design_system.dart';
import 'luxe_theme.dart';

/// App theme entry points. Since Task 117 the app is LUXE dark only: every
/// getter returns [LuxeTheme.data], so legacy callers (tests, sheets) that
/// still ask for a light or AMOLED theme get the same platinum language.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => LuxeTheme.data();

  @Deprecated('LUXE is dark only (Task 117); returns darkTheme.')
  static ThemeData get lightTheme => LuxeTheme.data();

  @Deprecated('LUXE is dark only (Task 117); returns darkTheme.')
  static ThemeData get amoledTheme => LuxeTheme.data();
}

// ═════════════════════════════════════════════════════════════════
// DARK COLOR PALETTE (original)
// ═════════════════════════════════════════════════════════════════
class AppColorsDark {
  AppColorsDark._();

  // Primary palette (VinFast-inspired)
  static const Color primary = CockpitColors.emerald;
  static const Color primaryContainer = Color(0xFF0E2A20);
  static const Color onPrimaryContainer = Color(0xFFD1FAE5);
  static const Color secondary = CockpitColors.emeraldStrong;
  static const Color accent = CockpitColors.danger;

  // Background & Surface
  static const Color background = CockpitColors.background;
  static const Color surface = CockpitColors.shell;
  static const Color surfaceVariant = CockpitColors.elevated;
  static const Color card = CockpitColors.surface;
  static const Color cardElevated = CockpitColors.elevated;

  // Text
  static const Color textPrimary = CockpitColors.text;
  static const Color textSecondary = CockpitColors.muted;
  static const Color textTertiary = CockpitColors.dim;
  static const Color textHint = CockpitColors.dim;
  static const Color textInverse = Color(0xFF0B0C0E);

  // Semantic
  static const Color success = CockpitColors.emerald;
  static const Color warning = CockpitColors.amber;
  static const Color error = CockpitColors.danger;
  static const Color info = CockpitColors.info;

  // Borders & Dividers
  static const Color border = CockpitColors.border;
  static const Color borderLight = CockpitColors.borderStrong;
  static const Color divider = CockpitColors.border;
  static const Color glass = Color(0x0FFFFFFF);
  static const Color glassBorder = CockpitColors.borderStrong;
}
