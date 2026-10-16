import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode options
enum AppThemeMode { system, light, dark, amoled }

/// Language options
enum AppLanguage { system, vietnamese, english }

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
  static const _splashChannel = MethodChannel('com.vinfast.battery/splash');

  SharedPreferences? _prefs;
  bool _initialized = false;
  AppThemeMode _themeMode = AppThemeMode.dark;
  AppLanguage _language = AppLanguage.vietnamese;

  bool get isInitialized => _initialized;

  /// Khởi tạo: đọc giá trị từ SharedPreferences và cache lại.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _themeMode = _decodeThemeMode(_prefs?.getString(_themeKey));
      _language = _decodeLanguage(_prefs?.getString(_languageKey));
      await _syncNativeSplashTheme(_themeMode);
    } catch (e) {
      debugPrint('[SettingsService] init error (${e.runtimeType}).');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  // ── Theme ──────────────────────────────────────────────────────────

  AppThemeMode getThemeMode() => _themeMode;

  /// The app renders the LUXE dark language only (Task 117). The stored
  /// preference is kept for compatibility but never switches to light.
  ThemeMode getThemeModeValue() => ThemeMode.dark;

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _syncNativeSplashTheme(mode);
    final value = switch (mode) {
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
      AppThemeMode.amoled => 'amoled',
      AppThemeMode.system => 'system',
    };
    try {
      await _prefs?.setString(_themeKey, value);
    } catch (e) {
      debugPrint('[SettingsService] persist theme error (${e.runtimeType}).');
    }
  }

  Future<void> _syncNativeSplashTheme(AppThemeMode mode) async {
    // The native splash always matches the dark LUXE launch frame.
    const theme = 'dark';
    try {
      await _splashChannel.invokeMethod<void>('setSplashTheme', theme);
    } on MissingPluginException {
      // iOS and older embedding builds use their platform default splash.
    } on PlatformException catch (error) {
      debugPrint(
        '[SettingsService] Native splash theme unavailable (${error.code}).',
      );
    }
  }

  // ── Language ───────────────────────────────────────────────────────

  AppLanguage getLanguage() => _language;

  /// App content exists in Vietnamese only (Task 125): English is hidden
  /// until the screens are translated, so the locale is always `vi`.
  Locale? getLocale() => const Locale('vi');

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
      case 'system':
        return AppThemeMode.system;
      case 'amoled':
        return AppThemeMode.amoled;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.dark;
    }
  }

  /// A stored `en`/`system` from older builds resolves to Vietnamese.
  static AppLanguage _decodeLanguage(String? raw) => AppLanguage.vietnamese;
}
