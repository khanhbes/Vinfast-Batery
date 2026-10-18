/// Compile-time beta surface. Remote configuration cannot enable unfinished
/// features in an already distributed beta APK.
abstract final class BetaCapabilities {
  static const bool enabled = bool.fromEnvironment(
    'BETA_BUILD',
    defaultValue: true,
  );

  static const bool advancedAi = !enabled;
  // Task 126: on-phone trip estimate with OpenStreetMap routing.
  static const bool tripPlanner = true;
  static const bool developerMode = !enabled;
}
