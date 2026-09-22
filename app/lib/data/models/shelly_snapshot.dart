import 'smart_charger_status.dart';

/// Configuration returned by Shelly's switch settings endpoint.
///
/// These fields are intentionally nullable: a missing field means that the
/// device could not be safety-verified and must never be treated as false.
class ShellySwitchConfig {
  const ShellySwitchConfig({
    this.initialState,
    this.autoOn,
    this.autoOff,
    this.schedule,
  });

  final String? initialState;
  final bool? autoOn;
  final bool? autoOff;
  final bool? schedule;

  bool get isSafeForCharging =>
      initialState?.toLowerCase() == 'off' && autoOn == false;

  static ShellySwitchConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final hasRelevantField = json.keys.any(
      (key) =>
          {'initial_state', 'initialState', 'auto_on', 'autoOn'}.contains(key),
    );
    if (!hasRelevantField) return null;
    bool? boolValue(Object? value) => value is bool
        ? value
        : value == null
        ? null
        : switch (value.toString().toLowerCase()) {
            'true' || '1' || 'on' => true,
            'false' || '0' || 'off' => false,
            _ => null,
          };
    return ShellySwitchConfig(
      initialState: (json['initial_state'] ?? json['initialState'])?.toString(),
      autoOn: boolValue(json['auto_on'] ?? json['autoOn']),
      autoOff: boolValue(json['auto_off'] ?? json['autoOff']),
      schedule: boolValue(json['schedule']),
    );
  }
}

class ShellyDeviceSnapshot {
  const ShellyDeviceSnapshot({
    required this.deviceId,
    required this.model,
    required this.generation,
    required this.online,
    required this.status,
    required this.powerMeterFieldsPresent,
    this.switchConfig,
  });

  final String deviceId;
  final String model;
  final int? generation;
  final bool online;
  final SmartChargerStatus status;
  final bool powerMeterFieldsPresent;
  final ShellySwitchConfig? switchConfig;

  ShellyDeviceIdentity get identity => ShellyDeviceIdentity(
    deviceId: deviceId,
    model: model,
    cloudProtocolGeneration: generation,
    hardwareGeneration: model.trim().toUpperCase() == 'S3PL-00112EU' ? 3 : null,
    type: 'relay',
  );

  /// Shelly Cloud reports the API generation (`G1`/`G2`), not the product's
  /// marketing generation. Plug S Gen3 is therefore commonly reported as G2.
  bool get isSupportedPlugSGen3 {
    final normalized = model.trim().toUpperCase();
    return normalized == 'S3PL-00112EU' && (generation == 2 || generation == 3);
  }
}

class ShellyDeviceIdentity {
  const ShellyDeviceIdentity({
    required this.deviceId,
    required this.model,
    required this.cloudProtocolGeneration,
    required this.hardwareGeneration,
    required this.type,
  });

  final String deviceId;
  final String model;
  final int? cloudProtocolGeneration;
  final int? hardwareGeneration;
  final String type;
}

class ShellySafetyTestResult {
  const ShellySafetyTestResult({
    required this.initialStatus,
    required this.onObserved,
    required this.timerObserved,
    required this.offVerified,
    required this.noLoadPowerW,
    required this.noLoadCurrentA,
    required this.verifiedAt,
  });

  final SmartChargerStatus initialStatus;
  final bool onObserved;
  final bool timerObserved;
  final bool offVerified;
  final double noLoadPowerW;
  final double noLoadCurrentA;
  final DateTime verifiedAt;

  bool get passed => onObserved && timerObserved && offVerified;
}
