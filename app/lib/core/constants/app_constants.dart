import 'package:flutter/foundation.dart';

/// Hằng số toàn app
class AppConstants {
  AppConstants._();

  static const String appName = 'EV Battery';

  // Production URL is injected at build time. Never ship a laptop/Tailscale
  // endpoint as a release default. Debug builds may use the developer override
  // for local QA, while release builds accept only the CI-provided HTTPS URL.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'APP_API_BASE_URL',
    defaultValue: '',
  );

  static String? _customApiBaseUrl;

  static String get apiBaseUrl => _customApiBaseUrl ?? defaultApiBaseUrl;

  /// Release builds must always use a real HTTPS endpoint. Debug/profile builds
  /// may target the Android emulator host bridge for local-only QA without
  /// exposing a laptop API publicly. This is intentionally restricted to
  /// loopback/host-bridge addresses and cannot be enabled in release mode.
  static bool _isAllowedEndpoint(Uri uri) {
    if (uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    if (kReleaseMode || uri.scheme != 'http') return false;
    return uri.host == '10.0.2.2' ||
        uri.host == '127.0.0.1' ||
        uri.host == 'localhost';
  }

  static bool get isApiConfigured {
    final value = apiBaseUrl.trim();
    final uri = Uri.tryParse(value);
    return value.isNotEmpty && uri != null && _isAllowedEndpoint(uri);
  }
  static bool get isApiConfigurationError => !isApiConfigured;

  static void setCustomApiBaseUrl(String? url) {
    final candidate = url?.trim().replaceAll(RegExp(r'/+$'), '');
    if (candidate == null || candidate.isEmpty) {
      _customApiBaseUrl = null;
      return;
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null || !_isAllowedEndpoint(uri)) return;
    if (kReleaseMode) return;
    _customApiBaseUrl = candidate;
  }
  static const String appVersion = '1.1.5';

  // Firestore Collection Names
  static const String vehiclesCollection = 'Vehicles';
  static const String chargeLogsCollection = 'ChargeLogs';
  static const String tripLogsCollection = 'TripLogs';
  static const String maintenanceCollection = 'MaintenanceTasks';

  // Validation
  static const int batteryMin = 0;
  static const int batteryMax = 100;
  static const int maxOdoDigits = 7;
  /// Absolute device-side Smart Charge safety window.
  static const int smartChargeMaxMinutes = 600;

  // Defaults
  // Capacity must come from the selected vehicle/model record. A fabricated
  // default would make Smart Charge publish misleading Wh/SOC estimates.
  static const double? defaultBatteryCapacityWh = null;

  // VinFast Feliz 2025 specs
  static const double defaultEfficiency = 1.35; // km per 1% battery
  static const double defaultChargeRate = 0.42; // % per minute (600W / 2400Wh)

  // Battery health thresholds
  static const double batteryHealthGood = 80;
  static const double batteryHealthFair = 60;
  static const double batteryHealthPoor = 40;

  // Maintenance
  static const int maintenanceWarningKm = 50; // Cảnh báo trước 50km
}
