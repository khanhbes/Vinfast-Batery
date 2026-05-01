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

  VinFastModelSpec({
    required this.modelId,
    required this.modelName,
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
  });

  factory VinFastModelSpec.fromMap(Map<String, dynamic> data, {String? id}) {
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

    return VinFastModelSpec(
      modelId: id ?? data['modelId'] ?? '',
      modelName: data['modelName'] ?? '',
      aliases: List<String>.from(data['aliases'] ?? const []),
      nominalCapacityWh: (data['nominalCapacityWh'] ?? 0).toDouble(),
      nominalCapacityAh: (data['nominalCapacityAh'] ?? 0).toDouble(),
      nominalVoltageV: (data['nominalVoltageV'] ?? 0).toDouble(),
      maxChargePowerW: (data['maxChargePowerW'] ?? 0).toDouble(),
      ratedMotorPowerW: (data['ratedMotorPowerW'] ?? 0).toDouble(),
      peakMotorPowerW: (data['peakMotorPowerW'] ?? 0).toDouble(),
      defaultEfficiencyKmPerPercent:
          (data['defaultEfficiencyKmPerPercent'] ?? 1.2).toDouble(),
      source: data['source'] ?? 'vinfast_catalog',
      specVersion: (data['specVersion'] ?? 1) is int
          ? data['specVersion'] as int
          : int.tryParse(data['specVersion'].toString()) ?? 1,
      updatedAt: data['updatedAt'] is DateTime
          ? data['updatedAt'] as DateTime
          : data['updatedAt'] != null
              ? DateTime.tryParse(data['updatedAt'].toString())
              : null,
      modelLine: data['modelLine'] as String?,
      tagline: data['tagline'] as String?,
      releaseYear: optInt(data['releaseYear']),
      topSpeedKmh: optDouble(data['topSpeedKmh']),
      rangeKm: optDouble(data['rangeKm']),
      imageAsset: data['imageAsset'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'modelId': modelId,
      'modelName': modelName,
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
