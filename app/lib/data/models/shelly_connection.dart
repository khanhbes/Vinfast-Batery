enum ShellyTransport { cloud, lan }

enum SmartChargerErrorCode {
  notConfigured,
  cloudAuthInvalid,
  cloudRateLimited,
  deviceOffline,
  lanUnavailable,
  timerNotArmed,
  relayUnverified,
  unsafeDuration,
  invalidProfile,
}

class ShellyConnectionProfile {
  const ShellyConnectionProfile({
    required this.cloudHost,
    required this.cloudAuthKey,
    required this.deviceId,
    this.deviceName = 'Shelly Plug S Gen3',
    this.model = 'S3PL-00112EU',
    this.firmware,
    this.lanAddress,
    this.localUsername = 'admin',
    this.localPassword,
  });

  final String cloudHost;
  final String cloudAuthKey;
  final String deviceId;
  final String deviceName;
  final String model;
  final String? firmware;
  final String? lanAddress;
  final String localUsername;
  final String? localPassword;

  Uri? get cloudUri => Uri.tryParse(cloudHost.trim());
  bool get hasLan => lanAddress?.trim().isNotEmpty == true;

  String? validate() {
    final uri = cloudUri;
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.host == 'shelly.cloud' || uri.host.endsWith('.shelly.cloud'))) {
      return 'Server URI phải là HTTPS shelly.cloud và không chứa path/query.';
    }
    if (cloudAuthKey.trim().isEmpty) {
      return 'Cloud Authorization Key còn trống.';
    }
    if (deviceId.trim().isEmpty) return 'Device ID còn trống.';
    if (hasLan && !isAllowedLanAddress(lanAddress!)) {
      return 'LAN chỉ chấp nhận IP riêng/link-local hoặc hostname .local.';
    }
    return null;
  }

  /// Serializes the complete profile for encrypted FlutterSecureStorage only.
  ///
  /// Do not use this payload for diagnostics, Firestore, analytics or logs:
  /// it intentionally contains the Cloud key and optional LAN password.
  Map<String, dynamic> toJson() => {
    'cloudHost': cloudHost,
    'cloudAuthKey': cloudAuthKey,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'model': model,
    if (firmware != null) 'firmware': firmware,
    if (lanAddress != null) 'lanAddress': lanAddress,
    'localUsername': localUsername,
    if (localPassword != null) 'localPassword': localPassword,
  };

  /// Safe representation for diagnostics/UI and any non-secure persistence.
  /// Secrets are deliberately omitted rather than masked, so they cannot be
  /// accidentally re-used by a downstream caller.
  Map<String, dynamic> toRedactedJson() => {
    'cloudHost': cloudHost,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'model': model,
    if (firmware != null) 'firmware': firmware,
    if (lanAddress != null) 'lanAddress': lanAddress,
    'localUsername': localUsername,
    'hasCloudAuthKey': cloudAuthKey.trim().isNotEmpty,
    'hasLocalPassword': localPassword?.isNotEmpty == true,
  };

  factory ShellyConnectionProfile.fromJson(Map<String, dynamic> json) =>
      ShellyConnectionProfile(
        cloudHost: json['cloudHost']?.toString() ?? '',
        cloudAuthKey: json['cloudAuthKey']?.toString() ?? '',
        deviceId: json['deviceId']?.toString() ?? '',
        deviceName: json['deviceName']?.toString() ?? 'Shelly Plug S Gen3',
        model: json['model']?.toString() ?? 'S3PL-00112EU',
        firmware: json['firmware']?.toString(),
        lanAddress: json['lanAddress']?.toString(),
        localUsername: json['localUsername']?.toString() ?? 'admin',
        localPassword: json['localPassword']?.toString(),
      );
}

class DiscoveredShellyDevice {
  const DiscoveredShellyDevice({
    required this.id,
    required this.address,
    required this.model,
    this.name,
    this.generation,
  });

  final String id;
  final String address;
  final String model;
  final String? name;
  final int? generation;

  bool get isPlugSGen3 {
    final value = model.toLowerCase();
    return generation == 3 &&
        (value.contains('plugs') || value == 's3pl-00112eu');
  }
}

class SmartChargePlan {
  const SmartChargePlan({
    required this.vehicleId,
    required this.currentSoc,
    required this.targetSoc,
    required this.duration,
    required this.estimatedCapacityWh,
    required this.predictionSource,
    this.predictionConfidence,
    this.hardDeadlineAt,
  });

  static const maxDuration = Duration(hours: 10);
  final String vehicleId;
  final double currentSoc;
  final double targetSoc;
  final Duration duration;
  final double estimatedCapacityWh;
  final String predictionSource;
  final double? predictionConfidence;
  final DateTime? hardDeadlineAt;

  Duration effectiveDuration(DateTime now) {
    var result = duration;
    final deadline = hardDeadlineAt;
    if (deadline != null) {
      final toDeadline = deadline.difference(now);
      if (toDeadline < result) result = toDeadline;
    }
    return result;
  }
}

bool isAllowedLanAddress(String raw) {
  var value = raw.trim().toLowerCase();
  final parsed = Uri.tryParse(value.contains('://') ? value : 'http://$value');
  final host = parsed?.host.toLowerCase() ?? '';
  if (host.endsWith('.local')) return true;
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final a = parts[0]!;
  final b = parts[1]!;
  return a == 10 ||
      a == 127 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 169 && b == 254);
}
