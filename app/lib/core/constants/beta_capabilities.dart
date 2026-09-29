/// Compile-time beta surface. Remote configuration cannot enable unfinished
/// features in an already distributed beta APK.
abstract final class BetaCapabilities {
  static const bool enabled = bool.fromEnvironment(
    'BETA_BUILD',
    defaultValue: true,
  );

  static const bool advancedAi = !enabled;
  static const bool tripPlanner = !enabled;
  static const bool developerMode = !enabled;
}
