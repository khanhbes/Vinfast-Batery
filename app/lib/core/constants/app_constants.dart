/// Hằng số toàn app
class AppConstants {
  AppConstants._();

  static const String appName = 'VinFast Battery';

  // API Base URL — mặc định dùng Tailscale Funnel.
  // Có thể ghi đè linh hoạt trong Developer Mode hoặc SharedPreferences.
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'APP_API_BASE_URL',
    defaultValue: 'https://khanhbes.tailaafca5.ts.net',
  );

  static String? _customApiBaseUrl;

  static String get apiBaseUrl => _customApiBaseUrl ?? defaultApiBaseUrl;

  static void setCustomApiBaseUrl(String? url) {
    if (url != null && url.trim().isNotEmpty) {
      _customApiBaseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    } else {
      _customApiBaseUrl = null;
    }
  }
  static const String appVersion = '1.1.3';

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
