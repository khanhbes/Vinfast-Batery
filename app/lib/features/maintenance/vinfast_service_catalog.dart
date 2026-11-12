import '../../data/models/maintenance_task_model.dart';

/// Một mẫu (preset) hạng mục bảo dưỡng theo sổ tay VinFast.
class VinFastServicePreset {
  final ServiceType type;
  final String title;
  final String? subtitle;
  final int suggestedOdoInterval; // km giữa 2 lần
  final String group; // nhóm (Hệ điều khiển, Phanh, Bánh xe, …)

  const VinFastServicePreset({
    required this.type,
    required this.title,
    this.subtitle,
    required this.suggestedOdoInterval,
    required this.group,
  });
}

/// Catalog 20 hạng mục bảo dưỡng định kỳ theo sổ tay VinFast (mục 6.1.2).
/// Khoảng cách `suggestedOdoInterval` là gợi ý chu kỳ kiểm tra; user có thể
/// điều chỉnh khi tạo task.
class VinFastServiceCatalog {
  VinFastServiceCatalog._();

  static const List<VinFastServicePreset> presets = [
    // ── Hệ điều khiển ──
    VinFastServicePreset(
      type: ServiceType.brakeLever,
      title: 'Tay phanh',
      subtitle: 'Kiểm tra & bôi trơn',
      suggestedOdoInterval: 1000,
      group: 'Hệ điều khiển',
    ),
    VinFastServicePreset(
      type: ServiceType.lightsHornDash,
      title: 'Đèn / Còi / Đồng hồ',
      subtitle: 'Kiểm tra hoạt động',
      suggestedOdoInterval: 1000,
      group: 'Hệ điều khiển',
    ),
    VinFastServicePreset(
      type: ServiceType.throttleGrip,
      title: 'Vỏ bọc, tay ga',
      subtitle: 'Kiểm tra độ rơ',
      suggestedOdoInterval: 1000,
      group: 'Hệ điều khiển',
    ),

    // ── Khung & khoá ──
    VinFastServicePreset(
      type: ServiceType.sideStand,
      title: 'Chân chống cạnh / giữa',
      subtitle: 'Kiểm tra & bôi trơn',
      suggestedOdoInterval: 1000,
      group: 'Khung & khoá',
    ),
    VinFastServicePreset(
      type: ServiceType.seatLock,
      title: 'Cơ cấu khoá yên xe',
      subtitle: 'Kiểm tra hoạt động',
      suggestedOdoInterval: 2000,
      group: 'Khung & khoá',
    ),

    // ── Pin ──
    VinFastServicePreset(
      type: ServiceType.battery,
      title: 'Pin / ắc quy',
      subtitle: 'Cổng kết nối + hình dáng vỏ',
      suggestedOdoInterval: 1000,
      group: 'Pin',
    ),

    // ── Phanh ──
    VinFastServicePreset(
      type: ServiceType.brakeFluid,
      title: 'Dầu phanh',
      subtitle: 'Kiểm tra mức / thay định kỳ',
      suggestedOdoInterval: 5000,
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeFront,
      title: 'Phanh trước',
      subtitle: 'Kiểm tra má phanh',
      suggestedOdoInterval: 2000,
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeHose,
      title: 'Ống dầu phanh trước',
      subtitle: 'Kiểm tra rò rỉ / nứt',
      suggestedOdoInterval: 5000,
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeRear,
      title: 'Phanh sau',
      subtitle: 'Kiểm tra má phanh',
      suggestedOdoInterval: 2000,
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeCable,
      title: 'Dây phanh sau',
      subtitle: 'Kiểm tra độ căng / sờn',
      suggestedOdoInterval: 2000,
      group: 'Phanh',
    ),

    // ── Bánh xe ──
    VinFastServicePreset(
      type: ServiceType.wheelFront,
      title: 'Vành xe trước',
      subtitle: 'Hình dạng • Bu-lông • Bi trục',
      suggestedOdoInterval: 5000,
      group: 'Bánh xe',
    ),
    VinFastServicePreset(
      type: ServiceType.tireFront,
      title: 'Lốp xe trước',
      subtitle: 'Độ sâu hoa + áp suất hơi',
      suggestedOdoInterval: 1000,
      group: 'Bánh xe',
    ),
    VinFastServicePreset(
      type: ServiceType.wheelRear,
      title: 'Vành xe sau',
      subtitle: 'Hình dạng • Bu-lông • Bi trục',
      suggestedOdoInterval: 5000,
      group: 'Bánh xe',
    ),
    VinFastServicePreset(
      type: ServiceType.tireRear,
      title: 'Lốp xe sau',
      subtitle: 'Độ sâu hoa + áp suất hơi',
      suggestedOdoInterval: 1000,
      group: 'Bánh xe',
    ),

    // ── Hệ treo ──
    VinFastServicePreset(
      type: ServiceType.steeringBearing,
      title: 'Cổ phốt',
      subtitle: 'Kiểm tra / bôi trơn',
      suggestedOdoInterval: 5000,
      group: 'Hệ treo',
    ),
    VinFastServicePreset(
      type: ServiceType.suspensionFront,
      title: 'Giảm xóc trước',
      subtitle: 'Kiểm tra rò dầu / hành trình',
      suggestedOdoInterval: 5000,
      group: 'Hệ treo',
    ),
    VinFastServicePreset(
      type: ServiceType.suspensionRear,
      title: 'Giảm xóc sau',
      subtitle: 'Kiểm tra rò dầu / hành trình',
      suggestedOdoInterval: 5000,
      group: 'Hệ treo',
    ),

    // ── Động cơ ──
    VinFastServicePreset(
      type: ServiceType.motor,
      title: 'Động cơ',
      subtitle: 'Kiểm tra hoạt động + tiếng kêu',
      suggestedOdoInterval: 5000,
      group: 'Động cơ',
    ),
    VinFastServicePreset(
      type: ServiceType.motorSeal,
      title: 'Phớt động cơ',
      subtitle: 'Kiểm tra rò rỉ',
      suggestedOdoInterval: 10000,
      group: 'Động cơ',
    ),
  ];

  /// QA 150 (owner's choice): the milestone to offer once [done] is marked
  /// complete, or null. Only for a service with a published interval, and
  /// only when no other open milestone of that service exists (the standard
  /// schedule already lists them). The owner still confirms and may edit.
  static MaintenanceTaskModel? nextAfter(
    MaintenanceTaskModel done, {
    required int currentOdo,
    required List<MaintenanceTaskModel> all,
  }) {
    VinFastServicePreset? preset;
    for (final p in presets) {
      if (p.type == done.serviceType) preset = p;
    }
    if (preset == null) return null;
    final open = all.any(
      (t) =>
          t.taskId != done.taskId &&
          !t.isCompleted &&
          t.serviceType == done.serviceType,
    );
    if (open) return null;
    final from = currentOdo > done.targetOdo ? currentOdo : done.targetOdo;
    return MaintenanceTaskModel(
      vehicleId: done.vehicleId,
      title: done.title,
      description: done.description,
      targetOdo: from + preset.suggestedOdoInterval,
      serviceType: done.serviceType,
    );
  }

  /// Nhóm theo `group` để hiển thị section.
  static Map<String, List<VinFastServicePreset>> grouped() {
    final out = <String, List<VinFastServicePreset>>{};
    for (final p in presets) {
      out.putIfAbsent(p.group, () => []).add(p);
    }
    return out;
  }
}
