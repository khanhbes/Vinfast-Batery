import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../achievements/controllers/achievements_controller.dart';
import '../../achievements/services/achievement_engine.dart';

/// Last 7 days of real charging, from the on-device session ledger (the
/// same one the achievements use — no extra reads, no placeholder data).
class RecentChargingChart extends ConsumerWidget {
  const RecentChargingChart({super.key, this.onViewHistory, this.now});

  final VoidCallback? onViewHistory;

  /// Test seam for "today".
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(
      achievementsControllerProvider.select((s) => s.sessions),
    );
    return RecentChargingPanel(
      sessions: sessions,
      onViewHistory: onViewHistory,
      now: now,
    );
  }
}

/// Day bucket of the trend.
class ChargingDay {
  const ChargingDay(this.day, this.kwh, this.sessions);
  final DateTime day;
  final double kwh;
  final int sessions;
}

/// Buckets valid sessions into the 7 local days ending today.
List<ChargingDay> chargingWeek(Iterable<LedgerSession> sessions, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
  final kwh = List<double>.filled(7, 0);
  final count = List<int>.filled(7, 0);
  for (final s in sessions) {
    if (!s.valid) continue;
    final at = s.startedAt.toLocal();
    final d = DateTime(at.year, at.month, at.day);
    final i = days.indexOf(d);
    if (i < 0) continue;
    kwh[i] += s.energyWh / 1000;
    count[i]++;
  }
  return [for (var i = 0; i < 7; i++) ChargingDay(days[i], kwh[i], count[i])];
}

class RecentChargingPanel extends StatefulWidget {
  const RecentChargingPanel({
    super.key,
    required this.sessions,
    this.onViewHistory,
    this.now,
  });

  final List<LedgerSession> sessions;
  final VoidCallback? onViewHistory;
  final DateTime? now;

  @override
  State<RecentChargingPanel> createState() => _RecentChargingPanelState();
}

class _RecentChargingPanelState extends State<RecentChargingPanel> {
  int? _selected;

  static const _weekday = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  Widget build(BuildContext context) {
    final week = chargingWeek(widget.sessions, widget.now ?? DateTime.now());
    final total = week.fold<double>(0, (s, d) => s + d.kwh);
    final count = week.fold<int>(0, (s, d) => s + d.sessions);
    final selected = _selected == null ? null : week[_selected!];

    return LuxeGlass(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('7 NGÀY QUA', style: LuxeText.eyebrow),
                    SizedBox(height: 4),
                    Text(
                      'Năng lượng đã nạp',
                      style: TextStyle(
                        color: LuxeColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onViewHistory != null)
                TextButton(
                  onPressed: widget.onViewHistory,
                  style: TextButton.styleFrom(
                    foregroundColor: LuxeColors.emerald,
                  ),
                  child: const Text('Lịch sử'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Figure(value: _kwh(total), label: 'kWh 7 ngày'),
              _Figure(value: '$count', label: 'phiên sạc'),
              _Figure(
                value: count == 0 ? '—' : _kwh(total / count),
                label: 'kWh mỗi phiên',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (count == 0)
            const _EmptyWeek()
          else ...[
            SizedBox(
              height: 140,
              child: LayoutBuilder(
                builder: (context, c) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    final i = (d.localPosition.dx / c.maxWidth * 7)
                        .floor()
                        .clamp(0, 6);
                    HapticFeedback.selectionClick();
                    setState(() => _selected = _selected == i ? null : i);
                  },
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 1100),
                    curve: LuxeMotion.enter,
                    builder: (context, grow, _) => CustomPaint(
                      size: Size(c.maxWidth, 140),
                      painter: _BarsPainter(
                        values: [for (final d in week) d.kwh],
                        grow: grow,
                        selected: _selected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Text(
                      i == 6 ? 'Hôm nay' : _weekday[week[i].day.weekday - 1],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: i == _selected || i == 6
                            ? LuxeColors.text
                            : LuxeColors.dim,
                        fontSize: 11,
                        fontWeight: i == 6 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: selected == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${selected.day.day}/${selected.day.month}: ${_kwh(selected.kwh)} kWh · ${selected.sessions} phiên',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: LuxeColors.emerald,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  static String _kwh(double v) =>
      v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(v == 0 ? 0 : 1);
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w300,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: LuxeColors.dim, fontSize: 11.5),
        ),
      ],
    ),
  );
}

class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: LuxeColors.hairline),
    ),
    child: const Row(
      children: [
        Icon(Icons.bar_chart_rounded, color: LuxeColors.platinumMid, size: 26),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Chưa có phiên sạc nào trong 7 ngày qua. Số liệu lấy từ các phiên Smart Charge đã hoàn tất trên tài khoản.',
            style: LuxeText.caption,
          ),
        ),
      ],
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.grow,
    required this.selected,
  });
  final List<double> values;
  final double grow;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.fold<double>(0, math.max);
    final slot = size.width / values.length;
    final barW = math.min(18.0, slot * 0.42);
    // Faint baseline and midline.
    for (final f in [0.0, 0.5]) {
      final y = size.height - 4 - (size.height - 18) * f;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0x12FFFFFF)
          ..strokeWidth = 1,
      );
    }
    for (var i = 0; i < values.length; i++) {
      final cx = slot * (i + 0.5);
      final h = maxV <= 0
          ? 0.0
          : (size.height - 18) * (values[i] / maxV) * grow;
      final bottom = size.height - 4;
      final today = i == values.length - 1;
      final hot = i == selected || (selected == null && today);
      if (h <= 0.5) {
        canvas.drawCircle(
          Offset(cx, bottom),
          2,
          Paint()..color = const Color(0x33FFFFFF),
        );
        continue;
      }
      final rect = RRect.fromLTRBR(
        cx - barW / 2,
        bottom - h,
        cx + barW / 2,
        bottom,
        Radius.circular(barW / 2),
      );
      if (hot) {
        canvas.drawRRect(
          rect.inflate(3),
          Paint()
            ..color = LuxeColors.emerald.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.outerRect.topCenter,
            rect.outerRect.bottomCenter,
            hot
                ? const [Color(0xFFB9F5DC), LuxeColors.emeraldDeep]
                : const [LuxeColors.platinum, Color(0xFF3A3C41)],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.grow != grow || old.selected != selected || old.values != values;
}
