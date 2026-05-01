import 'package:flutter/foundation.dart';
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

/// Reactive settings service (theme + language).
///
/// Là singleton + [ChangeNotifier]: mọi setter sẽ `notifyListeners()` để
/// `MaterialApp` (và bất kỳ widget nào lắng nghe) rebuild ngay lập tức,
/// không cần restart app.
class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _themeKey = 'app_theme_mode';
  static const _languageKey = 'app_language';

  SharedPreferences? _prefs;
  bool _initialized = false;
  AppThemeMode _themeMode = AppThemeMode.system;
  AppLanguage _language = AppLanguage.system;

  bool get isInitialized => _initialized;

  /// Khởi tạo: đọc giá trị từ SharedPreferences và cache lại.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _themeMode = _decodeThemeMode(_prefs?.getString(_themeKey));
      _language = _decodeLanguage(_prefs?.getString(_languageKey));
    } catch (e) {
      debugPrint('[SettingsService] init error: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  // ── Theme ──────────────────────────────────────────────────────────

  AppThemeMode getThemeMode() => _themeMode;

  ThemeMode getThemeModeValue() {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final value = switch (mode) {
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
      AppThemeMode.system => 'system',
    };
    try {
      await _prefs?.setString(_themeKey, value);
    } catch (e) {
      debugPrint('[SettingsService] persist theme error: $e');
    }
  }

  // ── Language ───────────────────────────────────────────────────────

  AppLanguage getLanguage() => _language;

  Locale? getLocale() {
    switch (_language) {
      case AppLanguage.vietnamese:
        return const Locale('vi');
      case AppLanguage.english:
        return const Locale('en');
      case AppLanguage.system:
        return null;
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    final value = switch (language) {
      AppLanguage.vietnamese => 'vi',
      AppLanguage.english => 'en',
      AppLanguage.system => 'system',
    };
    try {
      await _prefs?.setString(_languageKey, value);
    } catch (e) {
      debugPrint('[SettingsService] persist language error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  static AppThemeMode _decodeThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.system;
    }
  }

  static AppLanguage _decodeLanguage(String? raw) {
    switch (raw) {
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
}
