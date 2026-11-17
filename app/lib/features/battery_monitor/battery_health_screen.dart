import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/dev_view.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/utils/number_text.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_skeleton.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/entitlement.dart';
import '../premium/premium_gate.dart';
import 'charge_habits_screen.dart';
import 'widgets/health_trend_chart.dart';
import '../../core/theme/plan_style.dart';

/// What `/api/learning/<vehicle>/health` returns (QA 135).
class BatteryHealth {
  const BatteryHealth({
    this.nominalCapacityWh,
    this.estimate,
    this.test,
    this.trend = const [],
    this.vehicleSohPct,
    this.testMaxStartPct = 30,
    this.full = true,
    this.uncertaintyPct,
    this.baseline,
    this.lowPct,
    this.highPct,
    this.trendWeak = const [],
    this.charges = const [],
    this.tracking,
    this.totalPct,
  });

  /// QA 164: against the battery's own start (the main figure).
  final HealthTracking? tracking;

  /// QA 164: the absolute figure's error with the charger efficiency's doubt.
  final double? totalPct;

  final double? nominalCapacityWh;
  final HealthValue? estimate;
  final HealthValue? test;
  final List<(DateTime?, double)> trend;
  final double? vehicleSohPct;
  final double testMaxStartPct;

  /// Trend and guided test included (Pro/Ultra; QA 140).
  final bool full;

  /// QA 152: how far the estimate itself may be off, in points (from how
  /// much the single charges scatter). Null from an older server.
  final double? uncertaintyPct;

  /// QA 152: the first charges against the latest ones.
  final HealthBaseline? baseline;

  /// QA 162: the range the capacity left most likely sits in (% of rated).
  final double? lowPct;
  final double? highPct;

  /// QA 162: per trend point, read long after a full charge (fainter).
  final List<bool> trendWeak;

  /// QA 162: the latest charges, each with why it counts or not (Pro/Ultra).
  final List<HealthCharge> charges;

  /// The test was done in the last 90 days (it then counts double).
  bool get testRecent {
    final at = test?.at;
    return at != null && DateTime.now().difference(at).inDays <= 90;
  }

  static BatteryHealth fromMap(Map<String, dynamic> map) => BatteryHealth(
    nominalCapacityWh: (map['nominalCapacityWh'] as num?)?.toDouble(),
    estimate: HealthValue.fromMap(map['estimate']),
    test: HealthValue.fromMap(map['test']),
    trend: [
      for (final p in (map['trend'] as List? ?? const []))
        if (p is Map && p['sohPct'] is num)
          (
            DateTime.tryParse(p['at']?.toString() ?? ''),
            (p['sohPct'] as num).toDouble(),
          ),
    ],
    vehicleSohPct: (map['vehicleSohPct'] as num?)?.toDouble(),
    testMaxStartPct: (map['testMaxStartPct'] as num?)?.toDouble() ?? 30,
    full: map['full'] != false,
    uncertaintyPct: switch (map['spread']) {
      {'uncertaintyPct': final num u} => u.toDouble(),
      _ => null,
    },
    baseline: HealthBaseline.fromMap(map['baseline']),
    lowPct: switch (map['spread']) {
      {'lowPct': final num v} => v.toDouble(),
      _ => null,
    },
    highPct: switch (map['spread']) {
      {'highPct': final num v} => v.toDouble(),
      _ => null,
    },
    trendWeak: [
      for (final p in (map['trend'] as List? ?? const []))
        if (p is Map && p['sohPct'] is num) p['trust'] == 'low',
    ],
    charges: [
      for (final c in (map['charges'] as List? ?? const []))
        ?HealthCharge.fromMap(c),
    ],
    tracking: HealthTracking.fromMap(map['tracking']),
    totalPct: switch (map['spread']) {
      {'totalPct': final num v} => v.toDouble(),
      _ => null,
    },
  );
}

/// QA 164 (owner's choice): the battery against the first months the app
/// followed it. The charger efficiency the absolute figure assumes cancels
/// out, so this is the figure that stays right over the years.
class HealthTracking {
  const HealthTracking({
    required this.ready,
    this.relativePct,
    this.uncertaintyPct,
    this.since,
    this.until,
    this.needCharges = 0,
    this.needDays = 0,
    this.monthly = const [],
  });

  /// The reference is fixed (else it is still being built).
  final bool ready;
  final double? relativePct;
  final double? uncertaintyPct;
  final DateTime? since;
  final DateTime? until;
  final int needCharges;
  final int needDays;

  /// (first day of the month, % against the start), oldest first.
  final List<(DateTime, double)> monthly;

  /// "9/2026" or "9–10/2026".
  String get sinceText {
    final a = since, b = until;
    if (a == null) return '';
    if (b == null || (a.month == b.month && a.year == b.year)) {
      return '${a.month}/${a.year}';
    }
    return a.year == b.year
        ? '${a.month}–${b.month}/${a.year}'
        : '${a.month}/${a.year}–${b.month}/${b.year}';
  }

  /// "Cần thêm 2 lần sạc và 10 ngày".
  String get needText {
    final parts = [
      if (needCharges > 0) '$needCharges lần sạc',
      if (needDays > 0) '$needDays ngày',
    ];
    return parts.isEmpty ? '' : 'Cần thêm ${parts.join(' và ')}';
  }

  static HealthTracking? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return HealthTracking(
      ready: raw['status'] == 'ready',
      relativePct: (raw['relativePct'] as num?)?.toDouble(),
      uncertaintyPct: (raw['uncertaintyPct'] as num?)?.toDouble(),
      since: DateTime.tryParse(raw['since']?.toString() ?? '')?.toLocal(),
      until: DateTime.tryParse(raw['until']?.toString() ?? '')?.toLocal(),
      needCharges: (raw['needCharges'] as num?)?.toInt() ?? 0,
      needDays: (raw['needDays'] as num?)?.toInt() ?? 0,
      monthly: [
        for (final m in (raw['monthly'] as List? ?? const []))
          if (m is Map && m['relativePct'] is num && m['month'] is String)
            if (DateTime.tryParse('${m['month']}-01') case final at?)
              (at, (m['relativePct'] as num).toDouble()),
      ],
    );
  }
}

/// One charge in "Từng lần sạc" (QA 162, like a battery app's session list).
class HealthCharge {
  const HealthCharge({
    required this.startPct,
    required this.endPct,
    required this.used,
    this.at,
    this.sohPct,
    this.trust,
    this.reason,
    this.test = false,
  });

  final DateTime? at;
  final double startPct;
  final double endPct;
  final double? sohPct;
  final String? trust;
  final bool used;

  /// short | outlier | censored | old (when not used).
  final String? reason;
  final bool test;

  /// Why this charge is not in the result, or how much it was trusted.
  String get note => switch ((used, reason)) {
    (false, 'short') => 'Quá ngắn để tính',
    (false, 'outlier') => 'Lệch nhiều so với các lần khác, không tính',
    (false, 'censored') => 'Sạc đầy không có tín hiệu đầy, không tính',
    (false, 'old') => 'Đã cũ, không tính',
    _ when test => 'Bài kiểm tra pin',
    _ when trust == 'high' => 'Ngay sau lần sạc đầy, tin cậy nhất',
    _ when trust == 'low' => 'Lâu chưa sạc đầy, đồng hồ ít tin cậy',
    _ => 'Đã tính',
  };

  static HealthCharge? fromMap(Object? raw) {
    if (raw is! Map || raw['startPct'] is! num || raw['endPct'] is! num) {
      return null;
    }
    return HealthCharge(
      at: DateTime.tryParse(raw['at']?.toString() ?? '')?.toLocal(),
      startPct: (raw['startPct'] as num).toDouble(),
      endPct: (raw['endPct'] as num).toDouble(),
      sohPct: (raw['sohPct'] as num?)?.toDouble(),
      trust: raw['trust']?.toString(),
      used: raw['used'] == true,
      reason: raw['reason']?.toString(),
      test: raw['test'] == true,
    );
  }
}

/// QA 162: one reading of the capacity left for every place that shows it
/// (Sức khỏe pin, the Overview card and strip, the Utilities tile): the
/// same number, label and basis everywhere. The server's estimate already
/// includes the guided test (it counts double while recent); a figure above
/// the rating is shown as measured (owner's choice).
class HealthVerdict {
  const HealthVerdict({
    required this.pct,
    required this.label,
    required this.detail,
    required this.basis,
    required this.short,
    this.capacityText,
    this.relative = false,
    this.stale = false,
    this.building,
  });

  /// QA 164: the main figure. Against the battery's own start when the
  /// reference is fixed ([relative]), else % of the rated capacity. As
  /// measured either way (may pass 100).
  final double pct;

  /// [pct] is against the first months the app followed the battery.
  final bool relative;

  /// No counted charge lately: the figure comes from older months.
  final bool stale;

  /// "Đang lập mốc theo dõi · Cần thêm 2 lần sạc" while there is no
  /// reference yet.
  final String? building;

  /// What [pct] is measured against, under the number.
  String get unit => relative ? 'so với lúc đầu' : 'dung lượng hãng';

  /// QA 165: the one line the owner's view shows under the label.
  String get brief {
    final b = building;
    if (stale) return detail;
    if (b != null) return b.replaceFirst('Đang lập mốc theo dõi · ', '');
    return detail;
  }

  /// "Pin còn như mới" … "Pin chai nhiều, nên đưa xe đi kiểm tra".
  final String label;

  /// "Đã chai khoảng 6%" / "Chưa thấy chai rõ (trong sai số ±2%)".
  final String detail;

  /// "Dựa trên 8 lần sạc · sai số ±2% · có bài kiểm tra".
  final String basis;

  /// "8 lần sạc · ±2%" for small places.
  final String short;

  /// "khoảng 2 330–2 420 Wh / 2 400 Wh danh định".
  final String? capacityText;

  static double _tens(double wh) => (wh / 10).round() * 10.0;

  static HealthVerdict? of(BatteryHealth health) {
    final v = health.estimate;
    final nominal = health.nominalCapacityWh;
    if (v == null || nominal == null) return null;
    final tracking = health.tracking;
    final relative = tracking?.relativePct;
    if (tracking != null && tracking.ready && relative != null) {
      return _relative(health, v, nominal, tracking, relative);
    }
    final pct = v.sohPct;
    final uncertainty = health.totalPct ?? health.uncertaintyPct;
    final margin = uncertainty ?? 3;
    final label = pct >= 100 - margin
        ? 'Pin còn như mới'
        : pct >= 80
        ? 'Pin còn tốt'
        : pct >= 70
        ? 'Pin đã chai, nên theo dõi'
        : 'Pin chai nhiều, nên đưa xe đi kiểm tra';
    final fade = 100 - pct;
    final detail = pct > 100
        ? 'Bằng hoặc hơn danh định. Pin mới thường đo được hơn danh định '
              'một chút.'
        : fade > margin
        ? 'Đã chai khoảng ${fade.round()}%'
        : 'Chưa thấy chai rõ (trong sai số ±${margin.round().clamp(1, 99)}%)';
    final n = v.samples ?? 0;
    final plusMinus = uncertainty == null
        ? null
        : '±${uncertainty.round().clamp(1, 99)}%';
    final basis = [
      'Dựa trên $n lần sạc',
      if (plusMinus != null) 'sai số $plusMinus',
      if (health.testRecent) 'có bài kiểm tra',
    ].join(' · ');
    final short = ['$n lần sạc', ?plusMinus].join(' · ');
    return HealthVerdict(
      pct: pct,
      label: label,
      detail: detail,
      basis: basis,
      short: short,
      capacityText: _capacityText(health, v, nominal),
      stale: v.stale,
      building: tracking == null || tracking.ready
          ? null
          : [
              'Đang lập mốc theo dõi',
              tracking.needText.isNotEmpty
                  ? '${tracking.needText} để bắt đầu theo dõi'
                  : 'Sắp bắt đầu theo dõi',
            ].join(' · '),
    );
  }

  /// QA 164: the battery against its own start, the absolute capacity as
  /// the second line (with the charger efficiency's doubt in its range).
  static HealthVerdict _relative(
    BatteryHealth health,
    HealthValue v,
    double nominal,
    HealthTracking tracking,
    double pct,
  ) {
    final margin = (tracking.uncertaintyPct ?? 3).clamp(1.0, 99.0);
    final drop = 100 - pct;
    // Service advice still follows the absolute figure (under 70 % of the
    // rated capacity), which is what a workshop measures.
    final worn = v.sohPct < 70;
    final label = worn
        ? 'Pin chai nhiều, nên đưa xe đi kiểm tra'
        : drop <= margin
        ? 'Pin giữ như lúc đầu'
        : drop < 10
        ? 'Pin giảm nhẹ'
        : drop < 20
        ? 'Pin giảm rõ, nên theo dõi'
        : 'Pin giảm nhiều, nên đưa xe đi kiểm tra';
    final since = tracking.sinceText;
    final from = since.isEmpty
        ? 'lúc bắt đầu theo dõi'
        : 'lúc bắt đầu theo dõi ($since)';
    final detail = drop <= margin
        ? 'Chưa thấy giảm rõ so với $from'
              '${pct > 100 ? '; cao hơn một chút là sai số đo, pin không tự '
                        'hồi phục' : ''}.'
        : 'Giảm khoảng ${drop.round()}% so với $from.';
    final plusMinus = '±${margin.round()}%';
    final n = v.samples ?? 0;
    return HealthVerdict(
      pct: pct,
      relative: true,
      stale: v.stale,
      label: label,
      detail: detail,
      basis: [
        'Dựa trên $n lần sạc',
        'sai số $plusMinus',
        if (health.testRecent) 'có bài kiểm tra',
      ].join(' · '),
      short: '$plusMinus · so với $since',
      capacityText: _capacityText(health, v, nominal),
    );
  }

  /// "khoảng 2 290–2 450 Wh / 2 400 Wh danh định": the range carries the
  /// assumed charger efficiency's doubt when the server sends it.
  static String _capacityText(
    BatteryHealth health,
    HealthValue v,
    double nominal,
  ) {
    final total = health.totalPct;
    final low = total != null ? v.sohPct - total : health.lowPct;
    final high = total != null ? v.sohPct + total : health.highPct;
    return low != null && high != null && high > low
        ? 'khoảng ${groupThousands(_tens(nominal * low / 100))}–'
              '${groupThousands(_tens(nominal * high / 100))} Wh / '
              '${groupThousands(nominal)} Wh danh định'
        : 'khoảng ${groupThousands(v.capacityWh)} Wh / '
              '${groupThousands(nominal)} Wh danh định';
  }
}

/// How the estimate moved since the app started following this battery.
class HealthBaseline {
  const HealthBaseline({
    required this.changePct,
    required this.charges,
    this.since,
  });

  final double changePct;
  final int charges;
  final DateTime? since;

  static HealthBaseline? fromMap(Object? raw) {
    if (raw is! Map || raw['changePct'] is! num) return null;
    return HealthBaseline(
      changePct: (raw['changePct'] as num).toDouble(),
      charges: (raw['charges'] as num?)?.toInt() ?? 0,
      since: DateTime.tryParse(raw['since']?.toString() ?? '')?.toLocal(),
    );
  }

  /// One honest sentence. A difference inside the measurement's own error
  /// is reported as no clear change, and a rise is never called recovery.
  String sentence(double? uncertaintyPct) {
    final from = since == null
        ? 'lúc bắt đầu theo dõi'
        : 'lúc bắt đầu theo dõi (${since!.day}/${since!.month}/${since!.year})';
    final noise = ((uncertaintyPct ?? 1) * 2).clamp(1.5, 6.0);
    if (changePct.abs() <= noise) {
      return 'Chưa thấy thay đổi rõ so với $from, qua $charges lần sạc.';
    }
    final by = changePct.abs().toStringAsFixed(1);
    return changePct < 0
        ? 'Giảm khoảng $by% so với $from, qua $charges lần sạc.'
        : 'Cao hơn khoảng $by% so với $from, qua $charges lần sạc. Pin '
              'không tự hồi phục; chênh lệch này đến từ sai số đo.';
  }
}

class HealthValue {
  const HealthValue({
    required this.sohPct,
    required this.capacityWh,
    this.samples,
    this.confidence,
    this.startPct,
    this.at,
    this.stale = false,
  });

  /// QA 164: from older months (no counted charge lately).
  final bool stale;

  final double sohPct;
  final double capacityWh;
  final int? samples;

  /// low | medium | high (estimate only).
  final String? confidence;
  final double? startPct;
  final DateTime? at;

  String get confidenceLabel => switch (confidence) {
    'high' => 'Tin cậy cao',
    'medium' => 'Tin cậy vừa',
    _ => 'Tin cậy thấp',
  };

  static HealthValue? fromMap(Object? raw) {
    if (raw is! Map || raw['sohPct'] is! num) return null;
    return HealthValue(
      sohPct: (raw['sohPct'] as num).toDouble(),
      capacityWh: (raw['capacityWh'] as num?)?.toDouble() ?? 0,
      samples: (raw['samples'] as num?)?.toInt(),
      confidence: raw['confidence']?.toString(),
      startPct: (raw['startPct'] as num?)?.toDouble(),
      at: DateTime.tryParse((raw['at'] ?? raw['asOf'])?.toString() ?? ''),
      stale: raw['stale'] == true,
    );
  }
}

final batteryHealthProvider = FutureProvider.autoDispose
    .family<BatteryHealth, String>((ref, vehicleId) async {
      final data = await PinovaApi().get(
        '/api/learning/${Uri.encodeComponent(vehicleId)}/health',
      );
      try {
        return BatteryHealth.fromMap(data);
      } on Object catch (error, stack) {
        // QA 164: a reading the app cannot read is logged (type and place).
        debugPrint('[BatteryHealth] unreadable: $error');
        debugPrint('$stack');
        rethrow;
      }
    });

/// % pin chai (QA 135, Pro): how much of its rated capacity the battery
/// still holds, estimated from the charges whose % the owner confirmed,
/// plus a guided test that measures it in one charge. The scooter sends no
/// cell data, so this stays an estimate (champagne, never emerald).
class BatteryHealthScreen extends ConsumerWidget {
  const BatteryHealthScreen({super.key, required this.vehicleId});
  final String vehicleId;

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    String vehicleId,
  ) async {
    // QA 140: open on every plan (the estimate); the trend and the guided
    // test are locked inside for Free.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BatteryHealthScreen(vehicleId: vehicleId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => _screen(context, ref);

  Widget _screen(BuildContext context, WidgetRef ref) {
    final async = ref.watch(batteryHealthProvider(vehicleId));
    return LuxeScaffold(
      title: 'Sức khỏe pin',
      body: RefreshIndicator(
        color: context.planAccent,
        onRefresh: () => ref.refresh(batteryHealthProvider(vehicleId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            async.when(
              loading: () =>
                  const LuxeSkeleton.cards(label: 'Đang tải sức khỏe pin'),
              error: (error, _) => LuxeNotice(
                icon: Icons.cloud_off_rounded,
                color: LuxeColors.champagne,
                message: error is PinovaApiException && error.notDeployed
                    ? 'Máy chủ chưa cập nhật tính năng này.'
                    : error is PinovaApiException && error.message != null
                    ? error.message!
                    : 'Chưa tải được dữ liệu pin. Kéo xuống để thử lại.',
              ),
              data: (health) => _Body(health: health, vehicleId: vehicleId),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.health, required this.vehicleId});
  final BatteryHealth health;
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // QA 165 (owner's choice): as little text as possible; "Chế độ develop"
    // adds how the figure was made.
    final dev = ref.watch(devViewProvider).on;
    final monthly = (health.tracking?.monthly.length ?? 0) >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(health: health, dev: dev),
        if (dev) _TechnicalDetail(health: health),
        if (health.baseline case final baseline?
            when dev && health.tracking?.ready != true) ...[
          const SizedBox(height: 10),
          LuxeNotice(
            key: const ValueKey('health-baseline'),
            icon: Icons.timeline_rounded,
            message: baseline.sentence(health.uncertaintyPct),
          ),
        ],
        // QA 164: the battery's life, month by month (Pro/Ultra).
        if (monthly) ...[
          const LuxeSectionLabel('Theo tháng'),
          HealthTrendChart(
            key: const ValueKey('health-monthly'),
            points: [for (final (at, v) in health.tracking!.monthly) (at, v)],
            estimate: health.tracking!.relativePct,
            monthly: true,
            showNote: dev,
          ),
        ],
        // One chart for the owner: the months once there are some.
        if (health.trend.length >= 2 && (dev || !monthly)) ...[
          const LuxeSectionLabel('Theo từng lần sạc'),
          HealthTrendChart(
            points: health.trend,
            estimate: health.estimate?.sohPct,
            weak: health.trendWeak,
            showNote: dev,
          ),
        ],
        if (dev && health.full && health.charges.isNotEmpty) ...[
          const LuxeSectionLabel('Từng lần sạc'),
          _ChargeList(charges: health.charges),
        ],
        const LuxeSectionLabel('Bài kiểm tra pin'),
        if (health.full)
          _TestCard(health: health, vehicleId: vehicleId, dev: dev)
        else
          PremiumLocked(
            feature: PremiumFeature.batteryHealth,
            // QA 143: the PRO tag sat on top of the text.
            reserveTagSpace: true,
            child: const LuxeNotice(
              icon: Icons.science_rounded,
              message: 'Đo dung lượng thật trong một lần sạc.',
            ),
          ),
        const SizedBox(height: 12),
        // QA 140: the overall assessment of the owner's charging habits.
        FilledButton.icon(
          key: const ValueKey('health-assessment'),
          onPressed: () => ChargeHabitsScreen.open(context, vehicleId),
          icon: const Icon(Icons.insights_rounded, size: 18),
          label: const Text('Đánh giá tổng quát cách sạc'),
        ),
        const SizedBox(height: 16),
        if (dev)
          const LuxeNotice(
            key: ValueKey('health-method'),
            message:
                'Xe không gửi dữ liệu pin cho app, nên app tính từ điện năng ổ '
                'Shelly đo và % bạn đọc trên đồng hồ. Mỗi lần sạc tăng từ 20% trở '
                'lên được tính, lần ngay sau một lần sạc đầy được tin nhất, lần '
                'lệch nhiều so với các lần quanh nó bị bỏ. Số chính so với những '
                'tháng đầu app theo dõi pin này, nên không phụ thuộc hiệu suất bộ '
                'sạc; dung lượng theo Wh giả định hiệu suất 90% nên khoảng của nó '
                'rộng hơn. App giữ số theo từng tháng suốt đời pin. Sạc đầy định '
                'kỳ giúp số chính xác hơn. Dưới 70% dung lượng hãng nên đưa xe đi '
                'kiểm tra.',
          ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.health, this.dev = false});
  final BatteryHealth health;
  final bool dev;

  static String _month(DateTime? at) {
    final d = at?.toLocal();
    return d == null ? 'cũ' : 'tháng ${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (health.nominalCapacityWh == null) {
      return const LuxeNotice(
        icon: Icons.info_outline_rounded,
        color: LuxeColors.champagne,
        message:
            'Xe chưa có dung lượng pin danh định trong danh mục, nên chưa tính '
            'được sức khỏe pin.',
      );
    }
    final verdict = HealthVerdict.of(health);
    if (verdict == null) {
      // QA 143: a Free plan has no test to point to, and the estimate comes
      // from energy the Shelly outlet measured.
      return LuxeNotice(
        key: const ValueKey('health-need-data'),
        icon: Icons.hourglass_empty_rounded,
        color: LuxeColors.champagne,
        message: !dev
            ? 'Chưa đủ dữ liệu. Sạc qua ổ Shelly rồi nhập % trên đồng hồ xe.'
            : health.full
            ? 'Chưa đủ dữ liệu. Sau mỗi lần sạc qua ổ Shelly (tăng từ 20% trở '
                  'lên), nhập % trên đồng hồ xe hoặc làm bài kiểm tra bên dưới '
                  'để app ước tính.'
            : 'Chưa đủ dữ liệu. Sau mỗi lần sạc qua ổ Shelly (tăng từ 20% trở '
                  'lên), nhập % trên đồng hồ xe để app ước tính.',
      );
    }
    // QA 152: the same glass as every other card, raised because it is what
    // this screen is about. QA 162: the measured % (it may pass 100), the
    // ring full at 100.
    return LuxeGlass(
      raised: true,
      radius: 26,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LuxeRing(
                value: (verdict.pct / 100).clamp(0.0, 1.0),
                size: 104,
                color: LuxeColors.platinum,
                child: Text(
                  '${verdict.pct.round()}%',
                  key: const ValueKey('health-soh'),
                  style: const TextStyle(
                    color: LuxeColors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // QA 164: what the figure is against, under the ring.
              SizedBox(
                width: 104,
                child: Text(
                  verdict.unit,
                  key: const ValueKey('health-unit'),
                  textAlign: TextAlign.center,
                  style: LuxeText.caption,
                ),
              ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict.label,
                  key: const ValueKey('health-label'),
                  style: LuxeText.item,
                ),
                const SizedBox(height: 4),
                Text(
                  dev ? verdict.detail : verdict.brief,
                  key: const ValueKey('health-detail'),
                  style: LuxeText.caption,
                ),
                if (dev) ...[
                  if (verdict.capacityText case final capacity?) ...[
                    const SizedBox(height: 2),
                    Text(
                      verdict.relative
                          ? 'Dung lượng ước tính $capacity'
                          : 'Còn $capacity',
                      key: const ValueKey('health-capacity'),
                      style: LuxeText.caption,
                    ),
                  ],
                  if (verdict.building case final building?) ...[
                    const SizedBox(height: 2),
                    Text(
                      building,
                      key: const ValueKey('health-building'),
                      style: LuxeText.caption,
                    ),
                  ],
                  if (verdict.stale) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Lâu chưa có lần sạc qua ổ Shelly để tính, đây là số '
                      '${_month(health.estimate?.at)}',
                      key: const ValueKey('health-stale'),
                      style: LuxeText.caption.copyWith(
                        color: LuxeColors.champagne,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  LuxeTag(verdict.basis, color: LuxeColors.platinumMid),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// QA 165: what "Chế độ develop" adds: the inputs and errors behind the
/// figure, in the server's own terms.
class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.health});
  final BatteryHealth health;

  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final e = health.estimate;
    final t = health.tracking;
    final rows = <(String, String)>[
      if (e != null) ...[
        (
          'Dung lượng / danh định',
          '${_pct(e.sohPct)} · ${e.capacityWh.round()} Wh',
        ),
        (
          'Sai số đo · gồm hiệu suất',
          '±${_pct(health.uncertaintyPct)} · ±${_pct(health.totalPct)}',
        ),
        ('Khoảng (đo)', '${_pct(health.lowPct)} – ${_pct(health.highPct)}'),
        ('Lần sạc dùng · độ tin', '${e.samples ?? 0} · ${e.confidence ?? '—'}'),
        if (e.stale)
          ('Số cũ', '${e.at?.toLocal().month}/${e.at?.toLocal().year}'),
      ],
      if (t != null && t.ready) ...[
        ('So với mốc', '${_pct(t.relativePct)} ±${_pct(t.uncertaintyPct)}'),
        ('Mốc', t.sinceText),
        ('Số tháng trong sổ', '${t.monthly.length}'),
      ],
      if (t != null && !t.ready)
        ('Lập mốc', 'cần ${t.needCharges} lần sạc · ${t.needDays} ngày'),
      ('Danh định', '${health.nominalCapacityWh?.round() ?? '—'} Wh'),
      ('Hiệu suất giả định', '90% (87–93%)'),
      if (health.test case final test?)
        (
          'Bài kiểm tra',
          '${_pct(test.sohPct)} từ ${test.startPct?.round() ?? '?'}%',
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LuxeGlass(
        key: const ValueKey('health-technical'),
        quiet: true,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('CHI TIẾT KỸ THUẬT', style: LuxeText.eyebrow),
            const SizedBox(height: 6),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text(k, style: LuxeText.caption),
                    Text(
                      v,
                      style: LuxeText.caption.copyWith(color: LuxeColors.text),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// QA 162: the latest charges, newest first, each with its own figure and
/// why it counts or not.
class _ChargeList extends StatelessWidget {
  const _ChargeList({required this.charges});
  final List<HealthCharge> charges;

  @override
  Widget build(BuildContext context) {
    final shown = charges.reversed.take(10).toList();
    String date(DateTime? d) => d == null ? '' : '${d.day}/${d.month} · ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSettingsGroup(
          children: [
            for (final c in shown)
              LuxeSettingsRow(
                key: ValueKey('health-charge-${c.at?.millisecondsSinceEpoch}'),
                icon: c.used
                    ? Icons.check_circle_rounded
                    : Icons.do_not_disturb_on_rounded,
                accent: c.used ? LuxeColors.platinum : LuxeColors.dim,
                title:
                    '${date(c.at)}${c.startPct.round()}% → ${c.endPct.round()}%'
                    '${c.sohPct == null ? '' : ' · ${c.sohPct!.round()}%'}',
                subtitle: c.note,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Số sau mỗi lần sạc là dung lượng lần đó cho ra. Đồng hồ xe trôi dần '
          'giữa hai lần sạc đầy, nên lần ngay sau sạc đầy được tin nhất.',
          style: LuxeText.caption,
        ),
      ],
    );
  }
}

class _TestCard extends ConsumerWidget {
  const _TestCard({
    required this.health,
    required this.vehicleId,
    this.dev = false,
  });
  final BatteryHealth health;
  final String vehicleId;
  final bool dev;

  /// QA 141: step 3 opens the Charge tab with 100% already set.
  void _chargeToFull(BuildContext context, WidgetRef ref) {
    ref.read(pendingChargeTargetSocProvider.notifier).state = (
      vehicleId: vehicleId,
      targetSoc: 100,
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
    openChargeControl(ref, ai: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final test = health.test;
    final max = health.testMaxStartPct.round();
    final steps = [
      ('Đi xe đến khi pin còn ≤ $max%', Icons.two_wheeler_rounded),
      (
        'Quét đồng hồ hoặc nhập % lúc bắt đầu sạc',
        Icons.document_scanner_rounded,
      ),
      (
        'Sạc đến 100% (tab Sạc pin), để máy chủ tự ngắt khi pin đầy',
        Icons.battery_charging_full_rounded,
      ),
      ('App tính dung lượng thật từ điện năng đã nạp', Icons.insights_rounded),
    ];
    return LuxeSettingsGroup(
      children: [
        // QA 165: the owner's view is one row that starts the test.
        if (!dev)
          LuxeSettingsRow(
            key: const ValueKey('health-test-charge'),
            icon: Icons.battery_charging_full_rounded,
            title: 'Làm bài kiểm tra pin',
            subtitle: 'Đi xe xuống ≤ $max% rồi sạc đầy',
            onTap: vehicleId.isNotEmpty
                ? () => _chargeToFull(context, ref)
                : null,
          ),
        if (dev)
          for (final (i, (text, icon)) in steps.indexed)
            LuxeSettingsRow(
              key: i == 2 ? const ValueKey('health-test-charge') : null,
              icon: icon,
              title: '${i + 1}. $text',
              onTap: i == 2 && vehicleId.isNotEmpty
                  ? () => _chargeToFull(context, ref)
                  : null,
            ),
        if (test != null)
          LuxeSettingsRow(
            key: const ValueKey('health-test-result'),
            icon: Icons.verified_rounded,
            accent: LuxeColors.platinum,
            title: 'Lần kiểm tra gần nhất: ${test.sohPct.round()}%',
            subtitle:
                'Từ ${test.startPct?.round() ?? '?'}% lên đầy'
                '${test.at == null ? '' : ' · ${test.at!.toLocal().day}/${test.at!.toLocal().month}/${test.at!.toLocal().year}'}',
          ),
      ],
    );
  }
}
