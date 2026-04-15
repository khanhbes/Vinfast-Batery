import 'dart:ui';

/// Bảng màu thiết kế VinFast Battery App — Design System V2
/// Light theme workspace-first, lấy cảm hứng từ VinFast Battery Pro
class AppColors {
  AppColors._();

  // ── Brand ─────────────────────────────────────────────
  static const Color vinfastBlue = Color(0xFF00529C);
  static const Color vinfastRed = Color(0xFFE31B23);

  // Legacy aliases (để không break code cũ)
  static const Color primaryGreen = vinfastBlue;
  static const Color accentGreen = Color(0xFF0068C9);
  static const Color lightGreen = Color(0xFF4D9DE0);

  // ── Surfaces ──────────────────────────────────────────
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF1F3F5);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardElevated = Color(0xFFFFFFFF);

  // ── Borders ───────────────────────────────────────────
  static const Color border = Color(0xFFE9ECEF);
  static const Color borderLight = Color(0xFFF1F3F5);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6C757D);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textHint = Color(0xFFADB5BD);

  // ── Status ────────────────────────────────────────────
  static const Color error = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color success = Color(0xFF10B981);

  // ── Semantic Background Tints ─────────────────────────
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color infoBg = Color(0xFFEFF6FF);
  static const Color successBg = Color(0xFFECFDF5);
  static const Color blueBg = Color(0xFFE8F0FE);

  // ── Chart Colors ──────────────────────────────────────
  static const Color chartLine1 = Color(0xFF00529C);
  static const Color chartLine2 = Color(0xFF3B82F6);
  static const Color chartLine3 = Color(0xFFEF4444);
  static const Color chartFill1 = Color(0x3300529C);
  static const Color chartFill2 = Color(0x333B82F6);

  // ── Battery Levels ────────────────────────────────────
  static const Color batteryFull = Color(0xFF10B981);
  static const Color batteryMedium = Color(0xFFF59E0B);
  static const Color batteryLow = Color(0xFFEF4444);
  static const Color batteryCritical = Color(0xFFDC2626);
}
