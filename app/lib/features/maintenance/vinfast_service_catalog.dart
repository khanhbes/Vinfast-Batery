import '../../core/utils/number_text.dart';
import '../../data/models/maintenance_task_model.dart';

/// When an item is greased ("BT" in the service book).
enum ServiceGrease { never, everyVisitFrom5k, at20kAnd40k }

/// One row of the VinFast periodic schedule.
class VinFastServicePreset {
  final ServiceType type;
  final String title;
  final String? subtitle;

  /// Km between two visits where this item is looked at.
  final int suggestedOdoInterval;
  final String group;

  /// False for the rows the book starts at the 5 000 km visit.
  final bool checkedAtFirstVisit;

  /// False for the one row that is greased but not inspected (seat lock).
  final bool checked;
  final ServiceGrease grease;

  /// A part of the row that only starts at the 5 000 km visit.
  final String? from5kNote;

  const VinFastServicePreset({
    required this.type,
    required this.title,
    this.subtitle,
    this.suggestedOdoInterval = VinFastSchedule.intervalKm,
    required this.group,
    this.checkedAtFirstVisit = true,
    this.checked = true,
    this.grease = ServiceGrease.never,
    this.from5kNote,
  });
}

/// What is done to one item at one visit.
class VisitWork {
  const VisitWork(this.preset, {required this.check, required this.grease});
  final VinFastServicePreset preset;
  final bool check;
  final bool grease;

  String get action => check && grease
      ? 'Kiểm tra, bôi trơn'
      : grease
      ? 'Bôi trơn'
      : 'Kiểm tra';
}

/// QA 155: the periodic schedule as VinFast publishes it (owner's manual of
/// the Feliz S, section 6.1.2 "Lịch trình bảo dưỡng"): one visit at 1 000 km
/// or month 1, then one every 5 000 km or 6 months, whichever comes first,
/// up to 50 000 km / month 60; past that the cycle repeats. Every visit
/// looks at the same 19 items. The book schedules inspections and greasing,
/// no replacements.
abstract final class VinFastSchedule {
  static const firstVisitKm = 1000;
  static const intervalKm = 5000;
  static const intervalMonths = 6;
  static const source = 'sổ hướng dẫn sử dụng VinFast Feliz S, mục 6.1.2';

  /// The milestone a service done at [odo] belongs to.
  static int nearest(int odo) {
    if (odo <= (firstVisitKm + intervalKm) ~/ 2) return firstVisitKm;
    final n = ((odo + intervalKm ~/ 2) ~/ intervalKm) * intervalKm;
    return n < intervalKm ? intervalKm : n;
  }

  static int after(int milestone) => milestone < intervalKm
      ? intervalKm
      : (milestone ~/ intervalKm + 1) * intervalKm;

  /// The month the book pairs with [milestone], counted from the purchase.
  static int monthOf(int milestone) => milestone < intervalKm
      ? 1
      : (milestone ~/ intervalKm) * intervalMonths;

  /// The visit to plan now. [lastDoneOdo] is where the latest recorded
  /// periodic visit was done. May already be behind [currentOdo].
  static int proposed({required int currentOdo, int? lastDoneOdo}) {
    final here = nearest(currentOdo);
    if (lastDoneOdo == null) return here;
    final next = after(nearest(lastDoneOdo));
    return here > next ? here : next;
  }

  /// Months from a visit at [doneMilestone] to the one after it.
  static int monthsToNext(int doneMilestone) =>
      monthOf(after(doneMilestone)) - monthOf(doneMilestone);

  static DateTime addMonths(DateTime from, int months) {
    final m = from.month - 1 + months;
    final year = from.year + m ~/ 12;
    final month = m % 12 + 1;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, from.day > last ? last : from.day);
  }

  static bool isVisit(MaintenanceTaskModel task) =>
      task.serviceType == ServiceType.inspection;

  static String visitTitle(int milestone) =>
      'Bảo dưỡng định kỳ ${groupThousands(milestone)} km';

  /// The book repeats after 50 000 km: 55 000 is done like 5 000.
  static int _inCycle(int milestone) =>
      milestone <= 50000 ? milestone : (milestone - 1) % 50000 + 1;

  static List<VisitWork> workAt(int milestone) {
    final km = _inCycle(milestone);
    final first = km < intervalKm;
    return [
      for (final p in VinFastServiceCatalog.presets)
        if (!first || p.checkedAtFirstVisit)
          VisitWork(
            p,
            check: p.checked,
            grease: switch (p.grease) {
              ServiceGrease.never => false,
              ServiceGrease.everyVisitFrom5k => !first,
              ServiceGrease.at20kAnd40k => km == 20000 || km == 40000,
            },
          ),
    ];
  }

  static String visitDescription(int milestone) {
    final work = workAt(milestone);
    final greased = [
      for (final w in work)
        if (w.grease) w.preset.title.toLowerCase(),
    ];
    return [
      'Kiểm tra ${work.where((w) => w.check).length} hạng mục theo sổ tay',
      if (greased.isNotEmpty) 'bôi trơn ${greased.join(', ')}',
    ].join('; ');
  }
}

/// The 19 items of the schedule, in the book's order.
class VinFastServiceCatalog {
  VinFastServiceCatalog._();

  static const List<VinFastServicePreset> presets = [
    // ── Hệ điều khiển ──
    VinFastServicePreset(
      type: ServiceType.brakeLever,
      title: 'Tay phanh',
      subtitle: 'Kiểm tra; bôi trơn từ mốc 5 000 km',
      group: 'Hệ điều khiển',
      grease: ServiceGrease.everyVisitFrom5k,
    ),
    VinFastServicePreset(
      type: ServiceType.lightsHornDash,
      title: 'Đèn, còi, đồng hồ',
      subtitle: 'Kiểm tra hoạt động',
      group: 'Hệ điều khiển',
    ),
    VinFastServicePreset(
      type: ServiceType.throttleGrip,
      title: 'Vỏ bọc, tay ga',
      subtitle: 'Kiểm tra',
      group: 'Hệ điều khiển',
    ),

    // ── Khung & khoá ──
    VinFastServicePreset(
      type: ServiceType.sideStand,
      title: 'Chân chống cạnh, chân chống đứng',
      subtitle: 'Kiểm tra; bôi trơn từ mốc 5 000 km',
      group: 'Khung & khoá',
      grease: ServiceGrease.everyVisitFrom5k,
    ),
    VinFastServicePreset(
      type: ServiceType.seatLock,
      title: 'Cơ cấu khóa yên xe',
      subtitle: 'Bôi trơn từ mốc 5 000 km',
      group: 'Khung & khoá',
      checkedAtFirstVisit: false,
      checked: false,
      grease: ServiceGrease.everyVisitFrom5k,
    ),

    // ── Pin ──
    VinFastServicePreset(
      type: ServiceType.battery,
      title: 'Pin',
      subtitle: 'Cổng kết nối; hình dáng bên ngoài từ mốc 5 000 km',
      group: 'Pin',
      from5kNote: 'hình dáng bên ngoài',
    ),

    // ── Phanh ──
    VinFastServicePreset(
      type: ServiceType.brakeFluid,
      title: 'Dầu phanh',
      subtitle: 'Kiểm tra',
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeFront,
      title: 'Phanh trước',
      subtitle: 'Kiểm tra',
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeHose,
      title: 'Ống dầu phanh trước',
      subtitle: 'Kiểm tra',
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeRear,
      title: 'Phanh sau',
      subtitle: 'Kiểm tra',
      group: 'Phanh',
    ),
    VinFastServicePreset(
      type: ServiceType.brakeCable,
      title: 'Dây phanh sau',
      subtitle: 'Kiểm tra',
      group: 'Phanh',
    ),

    // ── Bánh xe ──
    VinFastServicePreset(
      type: ServiceType.wheelFront,
      title: 'Vành xe trước',
      subtitle: 'Hình dạng, bu-lông, bi trục',
      group: 'Bánh xe',
    ),
    VinFastServicePreset(
      type: ServiceType.tireFront,
      title: 'Lốp xe trước',
      subtitle: 'Áp suất hơi; độ sâu hoa lốp từ mốc 5 000 km',
      group: 'Bánh xe',
      from5kNote: 'độ sâu hoa lốp',
    ),
    VinFastServicePreset(
      type: ServiceType.wheelRear,
      title: 'Vành xe sau',
      subtitle: 'Hình dạng, bu-lông, bi trục',
      group: 'Bánh xe',
    ),
    VinFastServicePreset(
      type: ServiceType.tireRear,
      title: 'Lốp xe sau',
      subtitle: 'Áp suất hơi; độ sâu hoa lốp từ mốc 5 000 km',
      group: 'Bánh xe',
      from5kNote: 'độ sâu hoa lốp',
    ),

    // ── Hệ treo ──
    VinFastServicePreset(
      type: ServiceType.steeringBearing,
      title: 'Cổ phốt',
      subtitle: 'Kiểm tra; bôi trơn ở 20 000 và 40 000 km',
      group: 'Hệ treo',
      grease: ServiceGrease.at20kAnd40k,
    ),
    VinFastServicePreset(
      type: ServiceType.suspensionFront,
      title: 'Giảm xóc trước',
      subtitle: 'Kiểm tra',
      group: 'Hệ treo',
    ),
    VinFastServicePreset(
      type: ServiceType.suspensionRear,
      title: 'Giảm xóc sau',
      subtitle: 'Kiểm tra',
      group: 'Hệ treo',
    ),

    // ── Động cơ ──
    VinFastServicePreset(
      type: ServiceType.motor,
      title: 'Động cơ',
      subtitle: 'Kiểm tra từ mốc 5 000 km',
      group: 'Động cơ',
      checkedAtFirstVisit: false,
    ),
  ];

  static VinFastServicePreset? presetOf(ServiceType type) {
    for (final p in presets) {
      if (p.type == type) return p;
    }
    return null;
  }

  /// QA 150 (owner's choice): the milestone to offer once [done] is marked
  /// complete, or null. Only for a periodic visit or an item of the book,
  /// and only when no other open milestone of that service exists. The
  /// owner still confirms and may edit.
  ///
  /// QA 155: the next milestone is the book's next visit after the one this
  /// work belongs to (done at 5 398 km: the 5 000 km visit, so next is
  /// 10 000 km), with the date the book pairs with it.
  static MaintenanceTaskModel? nextAfter(
    MaintenanceTaskModel done, {
    required int currentOdo,
    required List<MaintenanceTaskModel> all,
  }) {
    final visit = VinFastSchedule.isVisit(done);
    final preset = presetOf(done.serviceType);
    if (!visit && preset == null) return null;
    final open = all.any(
      (t) =>
          t.taskId != done.taskId &&
          !t.isCompleted &&
          t.serviceType == done.serviceType,
    );
    if (open) return null;
    final from =
        done.completedOdo ??
        (currentOdo > done.targetOdo ? currentOdo : done.targetOdo);
    final doneMilestone = VinFastSchedule.nearest(from);
    final next = VinFastSchedule.after(doneMilestone);
    final doneAt = done.completedDate?.toLocal();
    return MaintenanceTaskModel(
      vehicleId: done.vehicleId,
      title: visit ? VinFastSchedule.visitTitle(next) : done.title,
      description: visit
          ? VinFastSchedule.visitDescription(next)
          : done.description,
      targetOdo: next,
      serviceType: done.serviceType,
      scheduledDate: doneAt == null
          ? null
          : VinFastSchedule.addMonths(
              doneAt,
              VinFastSchedule.monthsToNext(doneMilestone),
            ),
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
