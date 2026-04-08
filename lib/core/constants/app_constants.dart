/// Hằng số toàn app
class AppConstants {
  AppConstants._();

  static const String appName = 'VinFast Battery';
  static const String appVersion = '1.0.12';

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

  // VinFast Feliz Neo specs
  static const double defaultEfficiency = 1.2; // km per 1% battery
  static const double defaultChargeRate = 0.38; // % per minute

  // Battery health thresholds
  static const double batteryHealthGood = 80;
  static const double batteryHealthFair = 60;
  static const double batteryHealthPoor = 40;

  // Maintenance
  static const int maintenanceWarningKm = 50; // Cảnh báo trước 50km
}
