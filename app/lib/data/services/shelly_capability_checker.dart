import '../models/shelly_connection.dart';

enum ModelCompatibility { allowed, probePass, incompatible, denied }

/// Safety allow/deny rules for devices discovered on the local network.
class ShellyModelRules {
  static const allowlist = {'S3PL-00112EU'};
  static const denylist = <String>{};

  static ModelCompatibility check(String model, bool hasPowerMetering) {
    final normalized = model.trim().toUpperCase();
    if (denylist.contains(normalized)) return ModelCompatibility.denied;
    // A known model is not enough to unlock a charger. Firmware, component
    // mapping, or a non-meter relay can still omit required measurements.
    if (!hasPowerMetering) return ModelCompatibility.incompatible;
    if (allowlist.contains(normalized)) return ModelCompatibility.allowed;
    if (hasPowerMetering) return ModelCompatibility.probePass;
    return ModelCompatibility.incompatible;
  }
}

class ShellyCapabilityChecker {
  const ShellyCapabilityChecker();

  ModelCompatibility check(DiscoveredShellyDevice device) =>
      ShellyModelRules.check(device.model, device.hasPowerMetering);

  bool isCompatible(DiscoveredShellyDevice device) =>
      check(device) != ModelCompatibility.incompatible &&
      check(device) != ModelCompatibility.denied;

  /// Password-protected known models remain visible so Normal Mode can ask
  /// only for the local password. They are never considered compatible until
  /// an authenticated status probe proves the complete meter contract.
  bool isPotentiallyCompatible(DiscoveredShellyDevice device) =>
      device.authEnabled &&
      ShellyModelRules.allowlist.contains(device.model.trim().toUpperCase());
}
