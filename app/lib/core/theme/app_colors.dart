import 'dart:ui';

// Re-export Light/Dark palettes from app_theme.dart
export 'app_theme.dart' show AppColorsDark;

/// Bảng màu legacy — từ Task 117 trỏ về bảng LUXE (platinum + emerald).
/// Material 3 dark theme — VinFast Feliz Neo companion app
/// Ref: current VinFast Battery UI/UX synchronization.
class AppColors {
  AppColors._();

  // ── Brand / Primary (Material 3 tonal) ───────────────
  // primary: pale blue (on-dark readable)
  static const Color primary = Color(0xFF34D399);
  static const Color primaryContainer = Color(0xFF0E2A20);
  static const Color onPrimaryContainer = Color(0xFFD1FAE5);
  static const Color vinfastBlue = Color(0xFF34D399);
  static const Color vinfastRed = Color(0xFFF59E9E);

  // Legacy aliases (để không break code cũ)
  static const Color primaryGreen = vinfastBlue;
  static const Color accentGreen = Color(0xFF10B981);
  static const Color lightGreen = Color(0xFF6EE7B7);

  // ── Surfaces (Material 3 dark) ───────────────────────
  static const Color background = Color(0xFF050506);
  static const Color surface = Color(0xFF0E0F11);
  static const Color surfaceVariant = Color(0xFF17181B);
  static const Color surfaceLight = Color(0xFF17181B);
  static const Color card = Color(0xFF121315);
  static const Color cardElevated = Color(0xFF17181B);

  // ── Borders ───────────────────────────────────────────
  static const Color border = Color(0xFF222428);
  static const Color borderLight = Color(0xFF33363B);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF2F2F0);
  static const Color textSecondary = Color(0xFF9A9EA5);
  static const Color textTertiary = Color(0xFF858990);
  static const Color textHint = Color(0xFF858990);

  // ── Status (PLAN1 spec) ───────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFE8C170); // champagne
  static const Color error = Color(0xFFF59E9E);
  static const Color errorDark = Color(0xFFD50000);
  static const Color info = Color(0xFF9DB8E8);

  // ── Semantic Background Tints ─────────────────────────
  static const Color errorBg = Color(0x1AFFB4AB);
  static const Color warningBg = Color(0x1AE8C170);
  static const Color infoBg = Color(0x1A9DB8E8);
  static const Color successBg = Color(0x1A34D399);
  static const Color blueBg = Color(0x1A00497D);

  // ── Chart Colors ──────────────────────────────────────
  static const Color chartLine1 = Color(0xFF34D399);
  static const Color chartLine2 = Color(0xFFD6D8DB);
  static const Color chartLine3 = Color(0xFFF59E9E);
  static const Color chartFill1 = Color(0x4D34D399);
  static const Color chartFill2 = Color(0x3334D399);

  // ── Battery Levels ────────────────────────────────────
  static const Color batteryFull = Color(0xFF34D399);
  static const Color batteryMedium = Color(0xFFE8C170);
  static const Color batteryLow = Color(0xFFF0A46B);
  static const Color batteryCritical = Color(0xFFF59E9E);

  // ── Glass / Overlay ───────────────────────────────────
  static const Color glass = Color(0x08FFFFFF);
  static const Color glassBorder = Color(0xFF2A2C30);

  // ── Legacy aliases ────────────────────────────────────
  static const Color cardBackground = card;
}
