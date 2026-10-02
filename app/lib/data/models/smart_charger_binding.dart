enum SmartChargerConnectionMode { serverCloud, advancedDirect }

class SmartChargerBinding {
  const SmartChargerBinding({
    required this.deviceId,
    required this.displayName,
    required this.model,
    required this.provider,
    required this.mode,
    this.online = false,
    this.powerMeterVerified = false,
    this.safeBootVerified = false,
    this.noLoadTestVerified = false,
    this.lastVerifiedAt,
    this.codeRefreshRequired = false,
  });

  final String deviceId;
  final String displayName;
  final String model;
  final String provider;
  final SmartChargerConnectionMode mode;
  final bool online;
  final bool powerMeterVerified;
  final bool safeBootVerified;
  final bool noLoadTestVerified;
  final DateTime? lastVerifiedAt;
  final bool codeRefreshRequired;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId, 'displayName': displayName, 'model': model,
    'provider': provider,
    'connectionMode': mode == SmartChargerConnectionMode.serverCloud
        ? 'server_cloud'
        : 'advanced_direct',
    'powerMeterVerified': powerMeterVerified,
    'safeBootVerified': safeBootVerified,
    'noLoadTestVerified': noLoadTestVerified,
    'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
    'codeRefreshRequired': codeRefreshRequired,
    // Online/readiness is never restored from this historical cache.
  };

  factory SmartChargerBinding.fromJson(Map<String, dynamic> json) =>
      SmartChargerBinding(
        codeRefreshRequired: json['codeRefreshRequired'] == true,
        deviceId: json['deviceId']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? 'Shelly sạc xe',
        model: json['model']?.toString() ?? '',
        provider: json['provider']?.toString() ?? 'integrator',
        mode: json['connectionMode'] == 'advanced_direct'
            ? SmartChargerConnectionMode.advancedDirect
            : SmartChargerConnectionMode.serverCloud,
        online: json['online'] == true,
        powerMeterVerified: json['powerMeterVerified'] == true,
        safeBootVerified: json['safeBootVerified'] == true,
        noLoadTestVerified: json['noLoadTestVerified'] == true,
        lastVerifiedAt: DateTime.tryParse(
          json['lastVerifiedAt']?.toString() ?? '',
        ),
      );
}
