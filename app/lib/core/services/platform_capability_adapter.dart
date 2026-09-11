import 'dart:io';

/// Centralized platform policy. Android retains its foreground-service behavior;
/// iOS deliberately uses foreground reconciliation + server-side timers.
class PlatformCapabilityAdapter {
  PlatformCapabilityAdapter._();

  static bool get isIOS => Platform.isIOS;
  static bool get isAndroid => Platform.isAndroid;
  static String get operatingSystem => Platform.operatingSystem;
  static const bundleId = 'com.khanhbes.vinfastbattery';

  static bool get supportsContinuousForegroundService => isAndroid;
  static bool get usesBackendSmartChargeTimer => isIOS;
  static bool get needsLocalNetworkPermission => isIOS;
}
