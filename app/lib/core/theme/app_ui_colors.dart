import 'package:flutter/material.dart';

/// Semantic colors for settings/workspaces. Never infer meaning from luminance.
class AppUiColors {
  AppUiColors.of(BuildContext context) : theme = Theme.of(context);
  final ThemeData theme;
  bool get dark => theme.brightness == Brightness.dark;
  Color get background => theme.scaffoldBackgroundColor;
  Color get surface => theme.colorScheme.surface;
  Color get elevated => theme.colorScheme.surfaceContainerHighest;
  Color get border => theme.colorScheme.outlineVariant;
  Color get text => theme.colorScheme.onSurface;
  Color get muted => theme.colorScheme.onSurfaceVariant;
  Color get primary => theme.colorScheme.primary;
  Color get onPrimary => theme.colorScheme.onPrimary;
  Color get primarySurface => theme.colorScheme.primaryContainer;
  Color get shell => dark ? const Color(0xFF0C0C0C) : const Color(0xFFF1F5F9);
  Color get surfaceSoft => dark ? const Color(0xFF1D2128) : const Color(0xFFE2E8F0);
  Color get cardBackground => dark ? const Color(0xFF101216) : Colors.white;
  Color get dim => dark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  Color get borderStrong => dark ? const Color(0x24FFFFFF) : const Color(0xFFCBD5E1);
  Color get emerald => const Color(0xFF10B981);
  Color get emeraldGlow => const Color(0x3310B981);
  Color get amber => dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get warning => dark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
  Color get warningSurface =>
      dark ? const Color(0xFF3D2C10) : const Color(0xFFFEF3C7);
  Color get danger => theme.colorScheme.error;
  Color get dangerSurface => theme.colorScheme.errorContainer;
  Color get info => dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
}
