/// Model thông số kỹ thuật xe VinFast từ catalog
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
  });

  factory VinFastModelSpec.fromMap(Map<String, dynamic> data, {String? id}) {
    return VinFastModelSpec(
      modelId: id ?? data['modelId'] ?? '',
      modelName: data['modelName'] ?? '',
      aliases: List<String>.from(data['aliases'] ?? []),
      nominalCapacityWh: (data['nominalCapacityWh'] ?? 0).toDouble(),
      nominalCapacityAh: (data['nominalCapacityAh'] ?? 0).toDouble(),
      nominalVoltageV: (data['nominalVoltageV'] ?? 0).toDouble(),
      maxChargePowerW: (data['maxChargePowerW'] ?? 0).toDouble(),
      ratedMotorPowerW: (data['ratedMotorPowerW'] ?? 0).toDouble(),
      peakMotorPowerW: (data['peakMotorPowerW'] ?? 0).toDouble(),
      defaultEfficiencyKmPerPercent:
          (data['defaultEfficiencyKmPerPercent'] ?? 1.2).toDouble(),
      source: data['source'] ?? 'vinfast_catalog',
      specVersion: data['specVersion'] ?? 1,
      updatedAt: data['updatedAt'] is DateTime
          ? data['updatedAt']
          : data['updatedAt'] != null
              ? DateTime.tryParse(data['updatedAt'].toString())
              : null,
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
