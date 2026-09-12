/// Model thông số kỹ thuật xe VinFast từ catalog.
///
/// Field mới (optional, backward-compat):
/// - [modelLine]: nhóm model (Feliz, Klara, Evo, Vento, Theon, Tempest, …).
/// - [tagline]: mô tả ngắn hiển thị ở picker.
/// - [releaseYear]: năm ra mắt (default 2024).
/// - [topSpeedKmh]: tốc độ tối đa (km/h).
/// - [rangeKm]: tầm hoạt động đầy pin (km).
/// - [imageAsset]: đường dẫn asset ảnh (rỗng = dùng icon mặc định).
class VinFastModelSpec {
  final String modelId;
  final String modelName;
  final String brandId;
  final String brandName;
  final String variant;
  final String market;
  final String vehicleType;
  final bool selectable;
  final List<String> aliases;
  final double nominalCapacityWh;
  final double nominalCapacityAh;
  final double nominalVoltageV;
  final double maxChargePowerW;
  final double ratedMotorPowerW;
  final double peakMotorPowerW;
  final double defaultEfficiencyKmPerPercent;
  final String source;
  final int specVersion;
  final DateTime? updatedAt;

  // ── Display / marketing (optional) ──
  final String? modelLine;
  final String? tagline;
  final int? releaseYear;
  final double? topSpeedKmh;
  final double? rangeKm;
  final String? imageAsset;
  final String? imageUrl;
  final String? description;
  final String? batteryChemistry;
  final String? connector;
  final String? rangeTestCycle;
  final double? usableCapacityWh;
  final double? maxDcChargePowerW;
  final List<Map<String, dynamic>> sources;

  VinFastModelSpec({
    required this.modelId,
    required this.modelName,
    this.brandId = 'vinfast',
    this.brandName = 'VinFast',
    this.variant = '',
    this.market = 'VN',
    this.vehicleType = 'scooter',
    this.selectable = true,
    this.aliases = const [],
    required this.nominalCapacityWh,
    required this.nominalCapacityAh,
    required this.nominalVoltageV,
    required this.maxChargePowerW,
    required this.ratedMotorPowerW,
    required this.peakMotorPowerW,
    required this.defaultEfficiencyKmPerPercent,
    this.source = 'vinfast_catalog',
    this.specVersion = 1,
    this.updatedAt,
    this.modelLine,
    this.tagline,
    this.releaseYear,
    this.topSpeedKmh,
    this.rangeKm,
    this.imageAsset,
    this.imageUrl,
    this.description,
    this.batteryChemistry,
    this.connector,
    this.rangeTestCycle,
    this.usableCapacityWh,
    this.maxDcChargePowerW,
    this.sources = const [],
  });

  factory VinFastModelSpec.fromMap(
    Map<String, dynamic> data, {
    String? id,
    String locale = 'vi',
  }) {
    double? optDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? optInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    final localized = data['localized'] is Map
        ? Map<String, dynamic>.from(data['localized'] as Map)
        : const <String, dynamic>{};
    final vi = localized['vi'] is Map
        ? Map<String, dynamic>.from(localized['vi'] as Map)
        : const <String, dynamic>{};
    final en = localized['en'] is Map
        ? Map<String, dynamic>.from(localized['en'] as Map)
        : const <String, dynamic>{};
    final selectedLocale = locale == 'en' ? en : vi;
    final fallbackLocale = locale == 'en' ? vi : en;
    final battery = data['battery'] is Map
        ? Map<String, dynamic>.from(data['battery'] as Map)
        : const <String, dynamic>{};
    final charging = data['charging'] is Map
        ? Map<String, dynamic>.from(data['charging'] as Map)
        : const <String, dynamic>{};
    final performance = data['performance'] is Map
        ? Map<String, dynamic>.from(data['performance'] as Map)
        : const <String, dynamic>{};
    final defaults = data['appDefaults'] is Map
        ? Map<String, dynamic>.from(data['appDefaults'] as Map)
        : const <String, dynamic>{};
    final media = data['media'] is Map
        ? Map<String, dynamic>.from(data['media'] as Map)
        : const <String, dynamic>{};
    final resolvedName =
        (selectedLocale['displayName'] ??
                fallbackLocale['displayName'] ??
                data['modelName'] ??
                '${data['brandName'] ?? ''} ${data['model'] ?? ''}')
            .toString()
            .trim();
    return VinFastModelSpec(
      modelId: id ?? data['catalogId'] ?? data['modelId'] ?? '',
      modelName: resolvedName,
      brandId: (data['brandId'] ?? 'vinfast').toString(),
      brandName: (data['brandName'] ?? 'VinFast').toString(),
      variant: (data['variant'] ?? '').toString(),
      market: (data['market'] ?? 'VN').toString(),
      vehicleType: (data['vehicleType'] ?? 'scooter').toString(),
      selectable: data['selectable'] != false && data['isDeleted'] != true,
      aliases: List<String>.from(data['aliases'] ?? const []),
      nominalCapacityWh:
          (defaults['calculationCapacityWh'] ??
                  battery['calculationCapacityWh'] ??
                  data['nominalCapacityWh'] ??
                  0)
              .toDouble(),
      nominalCapacityAh:
          (battery['capacityAh'] ?? data['nominalCapacityAh'] ?? 0).toDouble(),
      nominalVoltageV: (battery['voltageV'] ?? data['nominalVoltageV'] ?? 0)
          .toDouble(),
      maxChargePowerW:
          (defaults['maxSafeChargePowerW'] ??
                  charging['maxSafeChargePowerW'] ??
                  charging['maxAcPowerW'] ??
                  data['maxChargePowerW'] ??
                  0)
              .toDouble(),
      ratedMotorPowerW:
          (performance['ratedMotorPowerW'] ?? data['ratedMotorPowerW'] ?? 0)
              .toDouble(),
      peakMotorPowerW:
          (performance['peakMotorPowerW'] ?? data['peakMotorPowerW'] ?? 0)
              .toDouble(),
      defaultEfficiencyKmPerPercent:
          (defaults['defaultEfficiencyKmPerPercent'] ??
                  data['defaultEfficiencyKmPerPercent'] ??
                  1.2)
              .toDouble(),
      source:
          data['source'] ??
          (data['sources'] is List ? 'reviewed_catalog' : 'vinfast_catalog'),
      specVersion: optInt(data['revision'] ?? data['specVersion']) ?? 1,
      updatedAt: data['updatedAt'] is DateTime
          ? data['updatedAt'] as DateTime
          : data['updatedAt'] != null
          ? DateTime.tryParse(data['updatedAt'].toString())
          : null,
      modelLine: (data['model'] ?? data['modelLine']) as String?,
      tagline:
          (selectedLocale['tagline'] ??
                  fallbackLocale['tagline'] ??
                  data['tagline'])
              as String?,
      releaseYear: optInt(data['modelYear'] ?? data['releaseYear']),
      topSpeedKmh: optDouble(performance['topSpeedKmh'] ?? data['topSpeedKmh']),
      rangeKm: optDouble(performance['rangeKm'] ?? data['rangeKm']),
      imageAsset: data['imageAsset'] as String?,
      imageUrl:
          (media['thumbnailUrl'] ?? media['heroUrl'] ?? data['imageUrl'])
              as String?,
      description:
          (selectedLocale['description'] ?? fallbackLocale['description'])
              as String?,
      batteryChemistry: battery['chemistry'] as String?,
      connector: charging['connector'] as String?,
      rangeTestCycle: performance['rangeTestCycle'] as String?,
      usableCapacityWh: optDouble(battery['usableCapacityWh']),
      maxDcChargePowerW: optDouble(charging['maxDcPowerW']),
      sources: data['sources'] is List
          ? (data['sources'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'modelId': modelId,
      'catalogId': modelId,
      'modelName': modelName,
      'brandId': brandId,
      'brandName': brandName,
      'variant': variant,
      'market': market,
      'vehicleType': vehicleType,
      'selectable': selectable,
      'aliases': aliases,
      'nominalCapacityWh': nominalCapacityWh,
      'nominalCapacityAh': nominalCapacityAh,
      'nominalVoltageV': nominalVoltageV,
      'maxChargePowerW': maxChargePowerW,
      'ratedMotorPowerW': ratedMotorPowerW,
      'peakMotorPowerW': peakMotorPowerW,
      'defaultEfficiencyKmPerPercent': defaultEfficiencyKmPerPercent,
      'source': source,
      'specVersion': specVersion,
      'updatedAt': updatedAt?.toIso8601String(),
      if (modelLine != null) 'modelLine': modelLine,
      if (tagline != null) 'tagline': tagline,
      if (releaseYear != null) 'releaseYear': releaseYear,
      if (topSpeedKmh != null) 'topSpeedKmh': topSpeedKmh,
      if (rangeKm != null) 'rangeKm': rangeKm,
      if (imageAsset != null) 'imageAsset': imageAsset,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (description != null) 'description': description,
      if (batteryChemistry != null) 'batteryChemistry': batteryChemistry,
      if (connector != null) 'connector': connector,
      if (rangeTestCycle != null) 'rangeTestCycle': rangeTestCycle,
      if (usableCapacityWh != null) 'usableCapacityWh': usableCapacityWh,
      if (maxDcChargePowerW != null) 'maxDcChargePowerW': maxDcChargePowerW,
      'sources': sources,
    };
  }

  /// Kiểm tra tên xe có match với model này qua aliases
  bool matchesName(String vehicleName) {
    final lowerName = vehicleName.toLowerCase().trim();
    if (lowerName.isEmpty) return false;
    if (modelName.toLowerCase().contains(lowerName) ||
        lowerName.contains(modelName.toLowerCase())) {
      return true;
    }
    for (final alias in aliases) {
      if (lowerName.contains(alias.toLowerCase()) ||
          alias.toLowerCase().contains(lowerName)) {
        return true;
      }
    }
    return false;
  }
}
