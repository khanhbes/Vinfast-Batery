import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/pinova_api.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/theme/plan_style.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../data/models/entitlement.dart';
import '../../data/services/charge_estimator.dart';
import '../../data/services/notification_service.dart';
import '../premium/premium_gate.dart';
import '../smart_charging/night_charging_screen.dart';

/// The server's "Đánh giá tổng quát" (QA 140): charging habits of the last
/// 60 days, a score with comments built only from those numbers, charts
/// and a suggested schedule.
@immutable
class ChargeAssessment {
  const ChargeAssessment({
    required this.sessions,
    required this.enough,
    required this.minSessions,
    required this.full,
    this.score,
    this.grade,
    this.stats = const {},
    this.comments = const [],
    this.suggestions = const [],
    this.weekdayHour,
    this.startPct = const [],
    this.endPct = const [],
    this.weeklyKWh = const [],
    this.schedule,
  });

  final int sessions;
  final bool enough;
  final int minSessions;

  /// Charts, every comment and the schedule (Pro and Ultra).
  final bool full;
  final int? score;
  final String? grade;
  final Map<String, dynamic> stats;
  final List<({String level, String text})> comments;
  final List<String> suggestions;
  final List<List<int>>? weekdayHour;
  final List<int> startPct;
  final List<int> endPct;
  final List<({String week, double kWh})> weeklyKWh;
  final ChargeSchedule? schedule;

  factory ChargeAssessment.fromMap(Map<String, dynamic> m) {
    List<int> ints(Object? v) => [
      for (final x in (v as List? ?? const [])) (x as num).toInt(),
    ];
    final charts = m['charts'] is Map
        ? Map<String, dynamic>.from(m['charts'] as Map)
        : null;
    final heat = charts?['weekdayHour'];
    return ChargeAssessment(
      sessions: (m['sessions'] as num?)?.toInt() ?? 0,
      enough: m['enough'] == true,
      minSessions: (m['minSessions'] as num?)?.toInt() ?? 3,
      full: m['full'] != false,
      score: (m['score'] as num?)?.toInt(),
      grade: m['grade'] as String?,
      stats: m['stats'] is Map
          ? Map<String, dynamic>.from(m['stats'] as Map)
          : const {},
      comments: [
        for (final c in (m['comments'] as List? ?? const []))
          if (c is Map)
            (
              level: c['level']?.toString() ?? 'info',
              text: c['text']?.toString() ?? '',
            ),
      ],
      suggestions: [
        for (final s in (m['suggestions'] as List? ?? const [])) s.toString(),
      ],
      weekdayHour: heat is List ? [for (final row in heat) ints(row)] : null,
      startPct: ints(charts?['startPct']),
      endPct: ints(charts?['endPct']),
      weeklyKWh: [
        for (final w in (charts?['weeklyKWh'] as List? ?? const []))
          if (w is Map)
            (
              week: w['week']?.toString() ?? '',
              kWh: (w['kWh'] as num?)?.toDouble() ?? 0,
            ),
      ],
      schedule: m['schedule'] is Map
          ? ChargeSchedule.fromMap(Map<String, dynamic>.from(m['schedule']))
          : null,
    );
  }
}

@immutable
class ChargeSchedule {
  const ChargeSchedule({
    required this.startHour,
    required this.weekdays,
    required this.typicalStartPct,
    required this.targetPct,
    this.estimatedMinutes,
  });

  final int startHour;

  /// 0 = Monday … 6 = Sunday.
  final List<int> weekdays;
  final int typicalStartPct;
  final int targetPct;
  final int? estimatedMinutes;

  factory ChargeSchedule.fromMap(Map<String, dynamic> m) => ChargeSchedule(
    startHour: (m['startHour'] as num?)?.toInt() ?? 21,
    weekdays: [
      for (final d in (m['weekdays'] as List? ?? const [])) (d as num).toInt(),
    ],
    typicalStartPct: (m['typicalStartPct'] as num?)?.toInt() ?? 30,
    targetPct: (m['targetPct'] as num?)?.toInt() ?? 85,
    estimatedMinutes: (m['estimatedMinutes'] as num?)?.toInt(),
  );
}

final chargeAssessmentProvider = FutureProvider.autoDispose
    .family<ChargeAssessment, String>((ref, vehicleId) async {
      final data = await PinovaApi().get(
        '/api/learning/${Uri.encodeComponent(vehicleId)}/assessment',
      );
      return ChargeAssessment.fromMap(data);
    });

const _weekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Thói quen sạc (QA 140): every plan sees the score and the main comment;
/// Pro and Ultra also get the charts, every comment and the schedule.
class ChargeHabitsScreen extends ConsumerWidget {
  const ChargeHabitsScreen({super.key, required this.vehicleId});
  final String vehicleId;

  static Future<void> open(BuildContext context, String vehicleId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChargeHabitsScreen(vehicleId: vehicleId),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chargeAssessmentProvider(vehicleId));
    return LuxeScaffold(
      title: 'Thói quen sạc',
      body: RefreshIndicator(
        color: context.planAccent,
        onRefresh: () =>
            ref.refresh(chargeAssessmentProvider(vehicleId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            async.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(color: context.planAccent),
                ),
              ),
              error: (error, _) => LuxeNotice(
                icon: Icons.cloud_off_rounded,
                color: LuxeColors.champagne,
                message: error is PinovaApiException && error.notDeployed
                    ? 'Máy chủ chưa cập nhật tính năng này.'
                    : error is PinovaApiException && error.message != null
                    ? error.message!
                    : 'Chưa tải được đánh giá. Kéo xuống để thử lại.',
              ),
              data: (a) => _Body(assessment: a, vehicleId: vehicleId),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.assessment, required this.vehicleId});
  final ChargeAssessment assessment;
  final String vehicleId;

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final stats = a.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeReveal(child: _ScoreCard(assessment: a)),
        if (!a.enough) ...[
          const SizedBox(height: 12),
          LuxeNotice(
            message:
                'Cần ít nhất ${a.minSessions} lần sạc trong 60 ngày để đánh '
                'giá (hiện có ${a.sessions}). Sau mỗi lần sạc, nhập % trên '
                'đồng hồ xe để kết quả chính xác hơn.',
          ),
        ],
        if (a.comments.isNotEmpty) ...[
          const LuxeSectionLabel('NHẬN XÉT'),
          for (final c in a.comments) _Comment(level: c.level, text: c.text),
        ],
        if (a.suggestions.isNotEmpty) ...[
          const LuxeSectionLabel('NÊN ĐỔI'),
          for (final s in a.suggestions) _Comment(level: 'tip', text: s),
        ],
        if (stats.isNotEmpty) ...[
          const LuxeSectionLabel('60 NGÀY QUA'),
          _StatsGrid(stats: stats),
        ],
        if (!a.full && a.enough) ...[
          const SizedBox(height: 16),
          PremiumLocked(
            feature: PremiumFeature.batteryHealth,
            child: const LuxeNotice(
              icon: Icons.insights_rounded,
              message:
                  'Biểu đồ giờ sạc, mọi nhận xét và lịch sạc gợi ý theo thói '
                  'quen của bạn.',
            ),
          ),
        ],
        if (a.full && a.weekdayHour != null) ...[
          const LuxeSectionLabel('GIỜ CẮM SẠC THEO THỨ'),
          _Heatmap(rows: a.weekdayHour!),
          const LuxeSectionLabel('% LÚC CẮM VÀ LÚC RÚT'),
          _Histogram(start: a.startPct, end: a.endPct),
          if (a.weeklyKWh.isNotEmpty) ...[
            const LuxeSectionLabel('ĐIỆN NẠP MỖI TUẦN'),
            _WeeklyBars(weeks: a.weeklyKWh),
          ],
        ],
        if (a.full && a.schedule != null) ...[
          const LuxeSectionLabel('LỊCH SẠC GỢI Ý'),
          _ScheduleCard(schedule: a.schedule!, vehicleId: vehicleId),
        ],
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.assessment});
  final ChargeAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final score = assessment.score;
    final (label, color) = switch (assessment.grade) {
      'good' => ('Tốt cho pin', context.planAccent),
      'fair' => ('Khá, còn cải thiện được', LuxeColors.champagne),
      'poor' => ('Cần thay đổi', LuxeColors.danger),
      _ => ('Chưa đủ dữ liệu', LuxeColors.muted),
    };
    return LuxeGlass(
      child: Row(
        children: [
          LuxeRing(
            value: (score ?? 0) / 100,
            size: 92,
            stroke: 7,
            color: color,
            semanticLabel: score == null ? null : 'Điểm $score trên 100',
            child: Text(
              score == null ? '—' : '$score',
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 28,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ĐÁNH GIÁ TỔNG QUÁT', style: LuxeText.eyebrow),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${assessment.sessions} lần sạc trong 60 ngày · ước tính',
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Comment extends StatelessWidget {
  const _Comment({required this.level, required this.text});
  final String level;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (level) {
      'good' => (Icons.thumb_up_alt_rounded, context.planAccent),
      'warn' => (Icons.warning_amber_rounded, LuxeColors.champagne),
      'tip' => (Icons.tips_and_updates_rounded, context.planAccent),
      _ => (Icons.info_rounded, LuxeColors.steel),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final Map<String, dynamic> stats;

  String _pct(Object? share) =>
      share is num ? '${(share * 100).round()}%' : '—';

  @override
  Widget build(BuildContext context) {
    final tiles = <(String, String)>[
      ('Số lần mỗi tuần', '${stats['perWeek'] ?? '—'}'),
      ('% lúc cắm (trung bình)', '${stats['avgStartPct'] ?? '—'}%'),
      ('% lúc rút (trung bình)', '${stats['avgEndPct'] ?? '—'}%'),
      ('Sạc gần đầy', _pct(stats['fullShare'])),
      ('Cắm khi dưới 15%', _pct(stats['lowStartShare'])),
      ('Chu kỳ tương đương', '${stats['equivalentCycles'] ?? '—'}'),
      ('Điện đã nạp', '${stats['kWh'] ?? '—'} kWh'),
      ('Sạc ban đêm', _pct(stats['nightShare'])),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final big = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = big || box.maxWidth < 300 ? 1 : 2;
        final w = (box.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value) in tiles)
              SizedBox(
                width: w,
                child: LuxeGlass(
                  radius: 16,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: LuxeText.caption),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: const TextStyle(
                          color: LuxeColors.text,
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Weekday × hour: how often a charge started there.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.rows});
  final List<List<int>> rows;

  @override
  Widget build(BuildContext context) {
    final most = rows
        .expand((r) => r)
        .fold<int>(0, (a, b) => b > a ? b : a)
        .clamp(1, 1 << 30);
    final accent = context.planAccent;
    return Semantics(
      label: 'Biểu đồ giờ bắt đầu sạc theo thứ trong tuần',
      child: LuxeGlass(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            for (var d = 0; d < 7 && d < rows.length; d++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(_weekdayShort[d], style: LuxeText.caption),
                    ),
                    for (var h = 0; h < 24 && h < rows[d].length; h++)
                      Expanded(
                        child: Container(
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 0.5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: rows[d][h] == 0
                                ? const Color(0x0DFFFFFF)
                                : accent.withValues(
                                    alpha: 0.25 + 0.75 * rows[d][h] / most,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Row(
              children: [
                SizedBox(width: 26),
                Expanded(child: Text('0 h', style: LuxeText.caption)),
                Expanded(
                  child: Text(
                    '12 h',
                    textAlign: TextAlign.center,
                    style: LuxeText.caption,
                  ),
                ),
                Expanded(
                  child: Text(
                    '23 h',
                    textAlign: TextAlign.end,
                    style: LuxeText.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Start % (platinum) and end % (accent) in 10 % bins.
class _Histogram extends StatelessWidget {
  const _Histogram({required this.start, required this.end});
  final List<int> start;
  final List<int> end;

  @override
  Widget build(BuildContext context) {
    final most = [...start, ...end].fold<int>(1, (a, b) => b > a ? b : a);
    final accent = context.planAccent;
    Widget bar(int value, Color color) => Expanded(
      child: Container(
        height: 4 + 76 * value / most,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    return Semantics(
      label: 'Phân bố mức pin lúc cắm sạc và lúc rút',
      child: LuxeGlass(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            SizedBox(
              height: 84,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 10; i++)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar(
                            i < start.length ? start[i] : 0,
                            LuxeColors.platinumMid,
                          ),
                          bar(i < end.length ? end[i] : 0, accent),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(child: Text('0%', style: LuxeText.caption)),
                const Expanded(
                  child: Text(
                    '50%',
                    textAlign: TextAlign.center,
                    style: LuxeText.caption,
                  ),
                ),
                const Expanded(
                  child: Text(
                    '100%',
                    textAlign: TextAlign.end,
                    style: LuxeText.caption,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                _Legend(color: LuxeColors.platinumMid, label: 'lúc cắm'),
                _Legend(color: accent, label: 'lúc rút'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: LuxeText.caption),
    ],
  );
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.weeks});
  final List<({String week, double kWh})> weeks;

  @override
  Widget build(BuildContext context) {
    final most = weeks.fold<double>(0.01, (a, w) => w.kWh > a ? w.kWh : a);
    final accent = context.planAccent;
    // Two caption lines grow with the text size; the bars keep 76 dp.
    final line = MediaQuery.textScalerOf(context).scale(11) * 1.6;
    return LuxeGlass(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: SizedBox(
        height: 84 + 2 * line + 10,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final w in weeks)
              Expanded(
                child: Semantics(
                  label:
                      'Tuần từ ${_day(w.week)}: ${w.kWh.toStringAsFixed(2)} kWh',
                  excludeSemantics: true,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        child: Text(
                          w.kWh.toStringAsFixed(2),
                          style: LuxeText.caption,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 6 + 70 * w.kWh / most,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        child: Text(_day(w.week), style: LuxeText.caption),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _day(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.day}/${d.month}';
  }
}

/// When the owner usually plugs in and a battery-friendly plan for it. The
/// owner applies it: a daily reminder, or (Ultra) a night charging plan,
/// which still asks for the ON-style confirmation there.
class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule, required this.vehicleId});
  final ChargeSchedule schedule;
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = schedule;
    final at = TimeOfDay(hour: s.startHour, minute: 0);
    final clock = '${s.startHour.toString().padLeft(2, '0')}:00';
    final days = s.weekdays.length >= 7 || s.weekdays.isEmpty
        ? 'mọi ngày'
        : s.weekdays.map((d) => _weekdayShort[d]).join(', ');
    final length = s.estimatedMinutes == null
        ? null
        : formatChargeDuration(Duration(minutes: s.estimatedMinutes!));
    return LuxeGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bạn thường cắm sạc lúc $clock ($days), pin khoảng '
            '${s.typicalStartPct}%.',
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gợi ý: dừng ở ${s.targetPct}%'
            '${length == null ? '' : ', sạc khoảng $length'}. Dừng trước 100% '
            'giúp pin bền hơn.',
            style: LuxeText.caption,
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            key: const ValueKey('habits-remind'),
            onPressed: () async {
              final ok = await NotificationService()
                  .scheduleChargeHabitReminder(at, targetPct: s.targetPct);
              AppPopup.showMessage(
                ok
                    ? 'Sẽ nhắc bạn sạc lúc $clock hằng ngày.'
                    : 'Hãy bật quyền thông báo cho Pinova để nhận nhắc.',
              );
            },
            child: _ButtonLabel(
              icon: Icons.alarm_rounded,
              text: 'Nhắc tôi lúc $clock hằng ngày',
            ),
          ),
          const SizedBox(height: 8),
          PremiumLocked(
            feature: PremiumFeature.nightCharging,
            tagAlignment: AlignmentDirectional.centerEnd,
            tagPadding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              key: const ValueKey('habits-apply-night'),
              onPressed: () {
                final minutes = (s.estimatedMinutes ?? 180) + 20;
                final wake = DateTime(
                  2000,
                  1,
                  1,
                  s.startHour,
                ).add(Duration(minutes: minutes));
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NightChargingScreen(
                      vehicleId: vehicleId,
                      initialTarget: s.targetPct.clamp(80, 90),
                      initialWake: TimeOfDay(
                        hour: wake.hour,
                        minute: (wake.minute / 5).ceil() * 5 % 60,
                      ),
                    ),
                  ),
                );
              },
              child: const _ButtonLabel(
                icon: Icons.nights_stay_rounded,
                text: 'Áp dụng vào Sạc đêm',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon and a label that wraps at large text (a button's own icon row
/// overflowed at 320 dp ×2).
class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(text, textAlign: TextAlign.center)),
      ],
    ),
  );
}
