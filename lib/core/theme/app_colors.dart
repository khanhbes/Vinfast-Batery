import 'dart:ui';

/// Bảng màu thiết kế VinFast Battery App
/// Dark theme với điểm nhấn xanh lá VinFast
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────
  static const Color primaryGreen = Color(0xFF00C853);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color lightGreen = Color(0xFF69F0AE);

  // ── Surfaces ──────────────────────────────────────────
  static const Color background = Color(0xFF0F0F1A);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFF222240);
  static const Color card = Color(0xFF1E1E36);
  static const Color cardElevated = Color(0xFF262650);

  // ── Borders ───────────────────────────────────────────
  static const Color border = Color(0xFF2E2E4E);
  static const Color borderLight = Color(0xFF3A3A5E);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8888AA);
  static const Color textTertiary = Color(0xFF5A5A7A);
  static const Color textHint = Color(0xFF4A4A6A);

  // ── Status ────────────────────────────────────────────
  static const Color error = Color(0xFFFF6B6B);
  static const Color errorDark = Color(0xFFE53935);
  static const Color warning = Color(0xFFFFB74D);
  static const Color info = Color(0xFF448AFF);
  static const Color success = Color(0xFF00C853);

  // ── Chart Colors ──────────────────────────────────────
  static const Color chartLine1 = Color(0xFF00C853);
  static const Color chartLine2 = Color(0xFF448AFF);
  static const Color chartLine3 = Color(0xFFFF6B6B);
  static const Color chartFill1 = Color(0x3300C853);
  static const Color chartFill2 = Color(0x33448AFF);

  // ── Battery Levels ────────────────────────────────────
  static const Color batteryFull = Color(0xFF00C853);
  static const Color batteryMedium = Color(0xFFFFB74D);
  static const Color batteryLow = Color(0xFFFF6B6B);
  static const Color batteryCritical = Color(0xFFE53935);
}
