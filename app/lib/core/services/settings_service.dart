import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode options
enum AppThemeMode {
  system,
  light,
  dark,
}

/// Language options
enum AppLanguage {
  system,
  vietnamese,
  english,
}

/// Service quản lý cài đặt app (theme, language)
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _themeKey = 'app_theme_mode';
  static const _languageKey = 'app_language';

  SharedPreferences? _prefs;

  /// Khởi tạo service
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get theme mode
  AppThemeMode getThemeMode() {
    final value = _prefs?.getString(_themeKey) ?? 'system';
    switch (value) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.system;
    }
  }

  /// Set theme mode
  Future<void> setThemeMode(AppThemeMode mode) async {
    final value = switch (mode) {
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
      AppThemeMode.system => 'system',
    };
    await _prefs?.setString(_themeKey, value);
  }

  /// Get language
  AppLanguage getLanguage() {
    final value = _prefs?.getString(_languageKey) ?? 'system';
    switch (value) {
      case 'vi':
      case 'vietnamese':
        return AppLanguage.vietnamese;
      case 'en':
      case 'english':
        return AppLanguage.english;
      default:
        return AppLanguage.system;
    }
  }

  /// Set language
  Future<void> setLanguage(AppLanguage language) async {
    final value = switch (language) {
      AppLanguage.vietnamese => 'vi',
      AppLanguage.english => 'en',
      AppLanguage.system => 'system',
    };
    await _prefs?.setString(_languageKey, value);
  }

  /// Get locale từ language setting
  Locale? getLocale() {
    final lang = getLanguage();
    switch (lang) {
      case AppLanguage.vietnamese:
        return const Locale('vi');
      case AppLanguage.english:
        return const Locale('en');
      case AppLanguage.system:
        return null; // Use system locale
    }
  }

  /// Get ThemeMode từ theme setting
  ThemeMode getThemeModeValue() {
    final mode = getThemeMode();
    switch (mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// Stream để lắng nghe thay đổi (đơn giản hóa - dùng polling)
  Stream<SettingsChange> watchChanges() async* {
    var lastTheme = getThemeMode();
    var lastLang = getLanguage();

    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      final currentTheme = getThemeMode();
      final currentLang = getLanguage();

      if (currentTheme != lastTheme || currentLang != lastLang) {
        yield SettingsChange(
          themeMode: currentTheme,
          language: currentLang,
        );
        lastTheme = currentTheme;
        lastLang = currentLang;
      }
    }
  }
}

/// Class đại diện cho thay đổi settings
class SettingsChange {
  final AppThemeMode themeMode;
  final AppLanguage language;

  SettingsChange({
    required this.themeMode,
    required this.language,
  });
}
