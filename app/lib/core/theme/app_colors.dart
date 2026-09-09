import 'dart:ui';

// Re-export Light/Dark palettes from app_theme.dart
export 'app_theme.dart' show AppColorsLight, AppColorsDark;

/// Bảng màu thiết kế VinFast Battery App — Design System V4
/// Material 3 dark theme — VinFast Feliz Neo companion app
/// Ref: current VinFast Battery UI/UX synchronization.
class AppColors {
  AppColors._();

  // ── Brand / Primary (Material 3 tonal) ───────────────
  // primary: pale blue (on-dark readable)
  static const Color primary = Color(0xFF34D399);
  static const Color primaryContainer = Color(0xFF123A2D);
  static const Color onPrimaryContainer = Color(0xFFD1FAE5);
  static const Color vinfastBlue = Color(0xFF34D399);
  static const Color vinfastRed = Color(0xFFE31B23);

  // Legacy aliases (để không break code cũ)
  static const Color primaryGreen = vinfastBlue;
  static const Color accentGreen = Color(0xFF10B981);
  static const Color lightGreen = Color(0xFF6EE7B7);

  // ── Surfaces (Material 3 dark) ───────────────────────
  static const Color background = Color(0xFF050505);
  static const Color surface = Color(0xFF0C0C0C);
  static const Color surfaceVariant = Color(0xFF171A20);
  static const Color surfaceLight = Color(0xFF171A20);
  static const Color card = Color(0xFF101216);
  static const Color cardElevated = Color(0xFF171A20);

  // ── Borders ───────────────────────────────────────────
  static const Color border = Color(0xFF1E232B);
  static const Color borderLight = Color(0xFF282F3B);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF64748B);

  // ── Status (PLAN1 spec) ───────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24); // #fbbf24
  static const Color error = Color(0xFFF87171);
  static const Color errorDark = Color(0xFFD50000);
  static const Color info = Color(0xFF448AFF);

  // ── Semantic Background Tints ─────────────────────────
  static const Color errorBg = Color(0x1AFFB4AB);
  static const Color warningBg = Color(0x1AFBBF24);
  static const Color infoBg = Color(0x1A448AFF);
  static const Color successBg = Color(0x1A4ADE80);
  static const Color blueBg = Color(0x1A00497D);

  // ── Chart Colors ──────────────────────────────────────
  static const Color chartLine1 = Color(0xFF34D399);
  static const Color chartLine2 = Color(0xFF60A5FA);
  static const Color chartLine3 = Color(0xFFF87171);
  static const Color chartFill1 = Color(0x4D34D399);
  static const Color chartFill2 = Color(0x3334D399);

  // ── Battery Levels ────────────────────────────────────
  static const Color batteryFull = Color(0xFF4ADE80);
  static const Color batteryMedium = Color(0xFFFBBF24);
  static const Color batteryLow = Color(0xFFFF6D00);
  static const Color batteryCritical = Color(0xFFFFB4AB);

  // ── Glass / Overlay ───────────────────────────────────
  static const Color glass = Color(0x08FFFFFF);
  static const Color glassBorder = Color(0xFF282F3B);

  // ── Legacy aliases ────────────────────────────────────
  static const Color cardBackground = card;
}
