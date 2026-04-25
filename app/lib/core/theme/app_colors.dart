import 'dart:ui';

/// Bảng màu thiết kế VinFast Battery App — Design System V4
/// Material 3 dark theme — VinFast Feliz Neo companion app
/// Ref: vinfast-battery-app + PLAN1.md UI/UX Sync
class AppColors {
  AppColors._();

  // ── Brand / Primary (Material 3 tonal) ───────────────
  // primary: pale blue (on-dark readable)
  static const Color primary = Color(0xFFD1E4FF);         // #d1e4ff
  static const Color primaryContainer = Color(0xFF00497D); // #00497d
  static const Color onPrimaryContainer = Color(0xFFD1E4FF);
  static const Color vinfastBlue = Color(0xFF008DFF);     // accent / legacy
  static const Color vinfastRed = Color(0xFFE31B23);

  // Legacy aliases (để không break code cũ)
  static const Color primaryGreen = vinfastBlue;
  static const Color accentGreen = Color(0xFF0099FF);
  static const Color lightGreen = Color(0xFF4DB8FF);

  // ── Surfaces (Material 3 dark) ───────────────────────
  static const Color background = Color(0xFF1A1C1E);      // #1a1c1e
  static const Color surface = Color(0xFF1A1C1E);
  static const Color surfaceVariant = Color(0xFF43474E);  // #43474e
  static const Color surfaceLight = Color(0xFF2A2D31);
  static const Color card = Color(0xFF21252B);
  static const Color cardElevated = Color(0xFF282C33);

  // ── Borders ───────────────────────────────────────────
  static const Color border = Color(0xFF2E3238);
  static const Color borderLight = Color(0xFF3A3F47);

  // ── Text ──────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFFAAB4BE);
  static const Color textTertiary = Color(0xFF888888);
  static const Color textHint = Color(0xFF555C66);

  // ── Status (PLAN1 spec) ───────────────────────────────
  static const Color success = Color(0xFF4ADE80);         // #4ade80
  static const Color warning = Color(0xFFFBBF24);         // #fbbf24
  static const Color error = Color(0xFFFFB4AB);           // #ffb4ab
  static const Color errorDark = Color(0xFFD50000);
  static const Color info = Color(0xFF448AFF);

  // ── Semantic Background Tints ─────────────────────────
  static const Color errorBg = Color(0x1AFFB4AB);
  static const Color warningBg = Color(0x1AFBBF24);
  static const Color infoBg = Color(0x1A448AFF);
  static const Color successBg = Color(0x1A4ADE80);
  static const Color blueBg = Color(0x1A00497D);

  // ── Chart Colors ──────────────────────────────────────
  static const Color chartLine1 = Color(0xFFD1E4FF);
  static const Color chartLine2 = Color(0xFF4ADE80);
  static const Color chartLine3 = Color(0xFFFFB4AB);
  static const Color chartFill1 = Color(0x4DD1E4FF);
  static const Color chartFill2 = Color(0x334ADE80);

  // ── Battery Levels ────────────────────────────────────
  static const Color batteryFull = Color(0xFF4ADE80);
  static const Color batteryMedium = Color(0xFFFBBF24);
  static const Color batteryLow = Color(0xFFFF6D00);
  static const Color batteryCritical = Color(0xFFFFB4AB);

  // ── Glass / Overlay ───────────────────────────────────
  static const Color glass = Color(0x08FFFFFF);
  static const Color glassBorder = Color(0x1AFFFFFF);
}
