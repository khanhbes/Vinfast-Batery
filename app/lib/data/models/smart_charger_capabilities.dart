class SmartChargerCapabilities {
  const SmartChargerCapabilities({
    required this.canReadStatus,
    required this.canManualOn,
    required this.canManualOff,
    required this.supportsDeviceTimer,
    required this.canReadPower,
    required this.canConfigureSafeBoot,
    required this.cloudAvailable,
    required this.lanAvailable,
    required this.readyForControl,
    this.safeBootVerified = false,
    this.noLoadTestVerified = false,
    this.provider,
  });

  final bool canReadStatus;
  final bool canManualOn;
  final bool canManualOff;
  final bool supportsDeviceTimer;
  final bool canReadPower;
  final bool canConfigureSafeBoot;
  final bool cloudAvailable;
  final bool lanAvailable;
  final bool safeBootVerified;
  final bool noLoadTestVerified;
  final bool readyForControl;
  final String? provider;

  bool get limited => readyForControl && !(cloudAvailable && lanAvailable);

  factory SmartChargerCapabilities.fromJson(Map<String, dynamic> json) =>
      SmartChargerCapabilities(
        canReadStatus: json['canReadStatus'] == true,
        canManualOn: json['canManualOn'] == true,
        canManualOff: json['canManualOff'] == true,
        supportsDeviceTimer: json['supportsDeviceTimer'] == true,
        canReadPower: json['canReadPower'] == true,
        canConfigureSafeBoot: json['canConfigureSafeBoot'] == true,
        cloudAvailable: json['cloudAvailable'] == true,
        lanAvailable: json['lanAvailable'] == true,
        safeBootVerified: json['safeBootVerified'] == true,
        noLoadTestVerified: json['noLoadTestVerified'] == true,
        readyForControl: json['readyForControl'] == true,
        provider: json['provider']?.toString(),
      );

  static const unavailable = SmartChargerCapabilities(
    canReadStatus: false,
    canManualOn: false,
    canManualOff: false,
    supportsDeviceTimer: false,
    canReadPower: false,
    canConfigureSafeBoot: false,
    cloudAvailable: false,
    lanAvailable: false,
    readyForControl: false,
  );
}
