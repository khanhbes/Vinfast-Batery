import 'dart:ui';

/// Bảng màu thiết kế VinFast Battery App — Design System V3
/// Dark premium theme, lấy cảm hứng từ vinfast-battery-app web reference
/// Glass morphism + neon accents trên nền tối
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────
  static const Color vinfastBlue = Color(0xFF008DFF);
  static const Color vinfastRed = Color(0xFFE31B23);

  // Legacy aliases (để không break code cũ)
  static const Color primaryGreen = vinfastBlue;
  static const Color accentGreen = Color(0xFF0099FF);
  static const Color lightGreen = Color(0xFF4DB8FF);

  // ── Surfaces ──────────────────────────────────────────
  static const Color background = Color(0xFF050505);
  static const Color surface = Color(0xFF0A0A0A);
  static const Color surfaceLight = Color(0xFF1A1A1A);
  static const Color card = Color(0xFF121212);
  static const Color cardElevated = Color(0xFF181818);

  // ── Borders ───────────────────────────────────────────
  static const Color border = Color(0xFF1F1F1F);
  static const Color borderLight = Color(0xFF2A2A2A);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textTertiary = Color(0xFF888888);
  static const Color textHint = Color(0xFF555555);

  // ── Status ────────────────────────────────────────────
  static const Color error = Color(0xFFFF1744);
  static const Color errorDark = Color(0xFFD50000);
  static const Color warning = Color(0xFFFFD600);
  static const Color info = Color(0xFF448AFF);
  static const Color success = Color(0xFF00E676);

  // ── Semantic Background Tints (dark-theme adapted) ────
  static const Color errorBg = Color(0x1AFF1744);
  static const Color warningBg = Color(0x1AFFD600);
  static const Color infoBg = Color(0x1A448AFF);
  static const Color successBg = Color(0x1A00E676);
  static const Color blueBg = Color(0x1A008DFF);

  // ── Chart Colors ──────────────────────────────────────
  static const Color chartLine1 = Color(0xFF008DFF);
  static const Color chartLine2 = Color(0xFF448AFF);
  static const Color chartLine3 = Color(0xFFFF1744);
  static const Color chartFill1 = Color(0x4D008DFF);
  static const Color chartFill2 = Color(0x33448AFF);

  // ── Battery Levels ────────────────────────────────────
  static const Color batteryFull = Color(0xFF00E676);
  static const Color batteryMedium = Color(0xFFFFD600);
  static const Color batteryLow = Color(0xFFFF6D00);
  static const Color batteryCritical = Color(0xFFFF1744);

  // ── Glass morphism helpers ────────────────────────────
  static const Color glass = Color(0x08FFFFFF);
  static const Color glassBorder = Color(0x1AFFFFFF);
}
