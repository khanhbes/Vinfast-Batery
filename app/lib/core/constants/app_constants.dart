/// Hằng số toàn app
class AppConstants {
  AppConstants._();

  static const String appName = 'VinFast Battery';

  // API Base URL — truyền qua --dart-define=APP_API_BASE_URL=https://...
  // Fallback: 10.0.2.2 cho Android emulator, localhost cho iOS simulator
  /// API Base URL — PLAN1: production default là api.evbattery.live
  /// Chỉ dùng localhost/emulator khi build dev với --dart-define
  static const String apiBaseUrl = String.fromEnvironment(
    'APP_API_BASE_URL',
    defaultValue: 'http://api.evbattery.live',
  );
  static const String appVersion = '1.0.60';

  // Firestore Collection Names
  static const String vehiclesCollection = 'Vehicles';
  static const String chargeLogsCollection = 'ChargeLogs';
  static const String tripLogsCollection = 'TripLogs';
  static const String maintenanceCollection = 'MaintenanceTasks';

  // Validation
  static const int batteryMin = 0;
  static const int batteryMax = 100;
  static const int maxOdoDigits = 7;

  // Defaults
  static const String defaultVehicleId = 'VF-OPES-001';

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
