import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/number_text.dart';
import '../../../data/services/charge_estimator.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../data/models/smart_charging_session.dart';

/// Amber shared by "stopped early" states across the history surfaces.
const historyAmber = LuxeColors.champagne;

String historyEnergy(double wh) => wh >= 1000
    ? '${(wh / 1000).toStringAsFixed(2)} kWh'
    : '${wh.toStringAsFixed(0)} Wh';

String historyDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return hours == 0
      ? '$minutes phút'
      : '${hours}g ${minutes.toString().padLeft(2, '0')}p';
}

String historyCost(double? vnd) => vnd == null ? '—' : formatVnd(vnd);

String historyStrategy(SmartChargingSession session) =>
    session.strategy == ChargingStrategy.manualTimed
    ? 'Sạc hẹn giờ'
    : session.isTargetMode
    ? 'Sạc đến ${session.targetSoc.round()}%'
    : 'Sạc theo dự đoán';

/// Status label and colour for one session (list node, pill and detail).
///
/// The outcome only: a target charge that reached its target is
/// "Hoàn thành" even when a few meter readings are missing (QA 129: it said
/// "Một phần" while the Charge tab and BatteryBot said "Hoàn thành"). Missing
/// readings are a separate note in the detail sheet and the "Thiếu số đo"
/// filter.
(String, Color) historyStatus(SmartChargingSession session) {
  return switch (session.state) {
    ChargingSessionState.completed => ('Hoàn thành', LuxeColors.emerald),
    ChargingSessionState.cancelled => ('Đã dừng', historyAmber),
    ChargingSessionState.interrupted => ('Gián đoạn', historyAmber),
    ChargingSessionState.failed => ('Gặp lỗi', LuxeColors.danger),
    ChargingSessionState.stopping => ('Đang dừng', historyAmber),
    _ => ('Đang sạc', LuxeColors.emerald),
  };
}

Duration historySessionDuration(SmartChargingSession session) =>
    (session.stoppedAt ?? session.updatedAt).difference(
      session.startedAt ?? session.createdAt,
    );

const _socStyle = TextStyle(
  color: LuxeColors.platinum,
  fontSize: 12,
  fontWeight: FontWeight.w500,
  fontFeatures: [ui.FontFeature.tabularFigures()],
);

Duration _motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

// ───────────────────────────── Energy bars ─────────────────────────────

/// Month (or range) at a glance (QA 136, was a radial ring that was hard to
/// read): the total in large type, then one bar per day (per week for long
/// ranges). Tap or drag across the bars to read a day. Bars rise once;
/// nothing loops. Bar colours follow the plan (Free platinum, Pro steel,
/// Ultra aurora).
class HistoryEnergyBars extends StatefulWidget {
  const HistoryEnergyBars({
    super.key,
    required this.buckets,
    required this.labels,
    required this.details,
    required this.totalWh,
    required this.caption,
    this.highlightIndex,
  });

  /// Energy per bar (Wh).
  final List<double> buckets;

  /// Axis label under each bar ('' for none).
  final List<String> labels;

  /// What a selected bar is ("Thứ Năm 23/10").
  final List<String> details;
  final double totalWh;
  final String caption;

  /// Today's bar, marked under the axis.
  final int? highlightIndex;

  @override
  State<HistoryEnergyBars> createState() => _HistoryEnergyBarsState();
}

class _HistoryEnergyBarsState extends State<HistoryEnergyBars> {
  int? _selected;

  @override
  void didUpdateWidget(HistoryEnergyBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buckets.length != widget.buckets.length) _selected = null;
  }

  void _pick(Offset local, double width) {
    final n = widget.buckets.length;
    if (n == 0 || width <= 0) return;
    final index = (local.dx / width * n).floor().clamp(0, n - 1);
    if (index != _selected) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.totalWh;
    final kwh = total >= 1000;
    final peak = widget.buckets.fold<double>(0, math.max);
    final peakIndex = peak > 0 ? widget.buckets.indexOf(peak) : null;
    final selected = _selected;
    final plan = PlanStyle.of(context);
    final String hint;
    if (selected != null) {
      final wh = widget.buckets[selected];
      hint =
          '${widget.details[selected]} · '
          '${wh > 0 ? historyEnergy(wh) : 'không sạc'}';
    } else if (peakIndex != null) {
      hint =
          'Nhiều nhất: ${widget.details[peakIndex]} · '
          '${historyEnergy(peak)}';
    } else {
      hint = 'Chưa có phiên sạc trong khoảng này';
    }
    return Semantics(
      label:
          'Tổng điện nạp ${historyEnergy(total)}, ${widget.caption}. '
          '${peakIndex == null ? '' : 'Nhiều nhất ${widget.details[peakIndex]}, ${historyEnergy(peak)}.'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: kwh ? total / 1000 : total),
                      duration: _motion(context, 900),
                      curve: LuxeMotion.enter,
                      builder: (context, v, _) => LuxeMetalText(
                        kwh
                            ? v.toStringAsFixed(v >= 100 ? 0 : 1)
                            : '${v.round()}',
                        style: const TextStyle(
                          fontSize: 40,
                          height: 1.0,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -1,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    kwh ? 'kWh' : 'Wh',
                    style: TextStyle(
                      color: plan.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      widget.caption,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      style: LuxeText.label,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedSwitcher(
              duration: _motion(context, 180),
              child: Text(
                hint,
                key: ValueKey(hint),
                maxLines: 2,
                style: LuxeText.caption.copyWith(
                  color: selected != null ? LuxeColors.text : LuxeColors.muted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                key: const ValueKey('history-energy-bars'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition, width),
                onHorizontalDragUpdate: (d) => _pick(d.localPosition, width),
                child: SizedBox(
                  height: 132,
                  width: width,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: _motion(context, 900),
                    curve: LuxeMotion.enter,
                    builder: (context, t, _) => CustomPaint(
                      painter: _BarsPainter(
                        buckets: widget.buckets,
                        labels: widget.labels,
                        today: widget.highlightIndex,
                        selected: selected,
                        reveal: t,
                        colors: plan.accentColors,
                        accent: plan.accent,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.buckets,
    required this.labels,
    required this.today,
    required this.selected,
    required this.reveal,
    required this.colors,
    required this.accent,
  });

  final List<double> buckets;
  final List<String> labels;
  final int? today;
  final int? selected;
  final double reveal;
  final List<Color> colors;
  final Color accent;

  static const _labelBand = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = buckets.length;
    if (n == 0) return;
    final chartH = size.height - _labelBand;
    final slot = size.width / n;
    final barW = (slot * 0.62).clamp(2.0, 18.0);
    final peak = buckets.fold<double>(0, math.max);
    final scale = peak <= 0 ? 0.0 : (chartH - 14) / peak;

    // Quiet guides: the peak level and the baseline.
    final guide = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    if (peak > 0) {
      final y = chartH - peak * scale;
      _dashed(canvas, Offset(0, y), Offset(size.width, y), guide);
      _text(
        canvas,
        historyEnergy(peak),
        Offset(size.width, y - 2),
        LuxeColors.dim,
        alignRight: true,
        above: true,
      );
    }
    canvas.drawLine(
      Offset(0, chartH),
      Offset(size.width, chartH),
      Paint()
        ..color = LuxeColors.hairline
        ..strokeWidth = 1,
    );

    for (var i = 0; i < n; i++) {
      final cx = slot * (i + 0.5);
      final value = buckets[i];
      final isSelected = i == selected;
      if (value <= 0) {
        // A day without charging is a small tick, not an empty gap.
        canvas.drawCircle(
          Offset(cx, chartH - 2),
          1.1,
          Paint()..color = const Color(0x33FFFFFF),
        );
      } else {
        final h = math.max(3.0, value * scale * reveal);
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barW / 2, chartH - h, barW, h),
          topLeft: Radius.circular(barW / 2.4),
          topRight: Radius.circular(barW / 2.4),
        );
        final shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: colors,
        ).createShader(Rect.fromLTRB(0, 14, 1, chartH));
        if (isSelected) {
          canvas.drawRRect(
            rect.inflate(2),
            Paint()
              ..color = accent.withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
        canvas.drawRRect(
          rect,
          Paint()
            ..shader = shader
            ..color = Colors.white.withValues(
              alpha: selected == null || isSelected ? 1 : 0.45,
            ),
        );
        if (selected != null && !isSelected) {
          canvas.drawRRect(rect, Paint()..color = const Color(0x8C050506));
        }
      }
      if (i == today) {
        canvas.drawCircle(Offset(cx, chartH + 4), 2, Paint()..color = accent);
      }
      final label = i < labels.length ? labels[i] : '';
      if (label.isNotEmpty) {
        _text(
          canvas,
          label,
          Offset(cx, chartH + 6),
          isSelected ? LuxeColors.text : LuxeColors.dim,
        );
      }
    }
    if (selected != null && selected! < n) {
      final cx = slot * (selected! + 0.5);
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, chartH),
        Paint()
          ..color = accent.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(
        Offset(x, a.dy),
        Offset(math.min(x + dash, b.dx), a.dy),
        paint,
      );
      x += dash + gap;
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool alignRight = false,
    bool above = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = alignRight ? at.dx - painter.width : at.dx - painter.width / 2;
    final dy = above ? at.dy - painter.height : at.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.reveal != reveal ||
      old.selected != selected ||
      old.today != today ||
      old.accent != accent ||
      !listEquals(old.colors, colors) ||
      !listEquals(old.labels, labels) ||
      !listEquals(old.buckets, buckets);
}

/// One figure under the month chart.
class HistoryKpi extends StatelessWidget {
  const HistoryKpi({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            color: LuxeColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w500,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: LuxeText.label.copyWith(fontSize: 11.5),
      ),
    ],
  );
}

// ───────────────────────────── Controls ─────────────────────────────

/// Glass pill with a sliding platinum thumb: "Xe này" / "Tất cả xe".
class HistoryScopeToggle extends StatelessWidget {
  const HistoryScopeToggle({
    super.key,
    required this.allVehicles,
    required this.onChanged,
  });
  final bool allVehicles;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget side(String label, bool value) {
      final on = allVehicles == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: on ? null : () => onChanged(value),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: _motion(context, 240),
                style: TextStyle(
                  color: on ? const Color(0xFF0B0C0E) : LuxeColors.muted,
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(label, maxLines: 1),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: LuxeColors.glass,
        border: Border.all(color: LuxeColors.hairline),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: _motion(context, 320),
            curve: LuxeMotion.enter,
            alignment: allVehicles
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [LuxeColors.platinumHi, LuxeColors.platinum],
                  ),
                ),
              ),
            ),
          ),
          Row(children: [side('Xe này', false), side('Tất cả xe', true)]),
        ],
      ),
    );
  }
}

class HistoryChip extends StatelessWidget {
  const HistoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? const Color(0xFF0B0C0E) : LuxeColors.text;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: AnimatedContainer(
            duration: _motion(context, 240),
            curve: LuxeMotion.enter,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: selected
                  ? const LinearGradient(
                      colors: [LuxeColors.platinumHi, LuxeColors.platinum],
                    )
                  : null,
              color: selected ? null : LuxeColors.glass,
              border: Border.all(
                color: selected ? Colors.transparent : LuxeColors.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ] else if (dot != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round glass icon button (export, close, month arrows).
class HistoryGlassButton extends StatelessWidget {
  const HistoryGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LuxeColors.glass,
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: Icon(
              icon,
              size: size * 0.45,
              color: onPressed == null ? LuxeColors.dim : LuxeColors.text,
            ),
          ),
        ),
      ),
    ),
  );
}

// ───────────────────────────── Timeline ─────────────────────────────

class HistoryDayHeader extends StatelessWidget {
  const HistoryDayHeader({
    super.key,
    required this.label,
    required this.totalWh,
    required this.count,
  });
  final String label;
  final double totalWh;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LuxeText.label.copyWith(
              letterSpacing: 1.6,
              color: LuxeColors.platinum,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$count phiên · ${historyEnergy(totalWh)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: LuxeText.label.copyWith(fontSize: 11.5),
          ),
        ),
      ],
    ),
  );
}

/// One session on the vertical rail: node coloured by status, glass card.
class HistoryTimelineTile extends StatelessWidget {
  const HistoryTimelineTile({
    super.key,
    required this.session,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    this.onLongPress,
  });

  final SmartChargingSession session;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = historyStatus(session);
    final started = (session.startedAt ?? session.createdAt).toLocal();
    final meta = [
      DateFormat('HH:mm').format(started),
      formatChargeDuration(historySessionDuration(session)),
      if (session.estimatedCostVnd != null)
        historyCost(session.estimatedCostVnd),
    ].join('  ·  ');
    return Semantics(
      button: true,
      label:
          'Chi tiết phiên sạc ${DateFormat('dd/MM/yyyy').format(session.createdAt)}, trạng thái $statusText',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 26,
              child: CustomPaint(
                painter: _RailPainter(
                  color: statusColor,
                  top: !isFirst,
                  bottom: !isLast,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onTap,
                    onLongPress: onLongPress,
                    child: LuxeGlass(
                      radius: 18,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Wrap: title and energy share a line, and stack
                          // under large text instead of overflowing.
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    session.strategy ==
                                            ChargingStrategy.manualTimed
                                        ? Icons.schedule_rounded
                                        : Icons.auto_awesome_rounded,
                                    size: 15,
                                    color: LuxeColors.platinumMid,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      historyStrategy(session),
                                      style: LuxeText.item.copyWith(
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                historyEnergy(session.energyUsedWh),
                                style: const TextStyle(
                                  color: LuxeColors.platinumHi,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [
                                    ui.FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            maxLines: 2,
                            style: LuxeText.caption.copyWith(fontSize: 12.5),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Text(_socSpanLabel(session), style: _socStyle),
                              HistoryStatusPill(
                                label: statusText,
                                color: statusColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          HistorySocTrack(
                            start: session.startSoc,
                            end:
                                session.actualEndSoc ??
                                session.estimatedSoc ??
                                session.targetSoc,
                            color: statusColor,
                            showLabel: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.color, required this.top, required this.bottom});
  final Color color;
  final bool top;
  final bool bottom;

  static const nodeY = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..strokeWidth = 1.2
      ..color = const Color(0x26FFFFFF);
    if (top) canvas.drawLine(Offset(x, 0), Offset(x, nodeY - 8), line);
    if (bottom) {
      canvas.drawLine(Offset(x, nodeY + 8), Offset(x, size.height), line);
    }
    canvas.drawCircle(
      Offset(x, nodeY),
      9,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      Offset(x, nodeY),
      5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color,
    );
    canvas.drawCircle(Offset(x, nodeY), 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.color != color || old.top != top || old.bottom != bottom;
}

/// "22% → 81%" with the owner's reading, "32% → ~79%" with the estimate,
/// else the target (Task 128: the list showed the target as the end %).
String _socSpanLabel(SmartChargingSession session) {
  final start = '${session.startSoc.round()}%';
  final actual = session.actualEndSoc;
  if (actual != null) return '$start → ${actual.round()}%';
  final estimate = session.estimatedSoc;
  if (estimate != null && session.state.isTerminal) {
    return '$start → ~${estimate.round()}%';
  }
  return '$start · mục tiêu ${session.targetSoc.round()}%';
}

/// Slim 0–100 % track with the session's start → end span lit.
class HistorySocTrack extends StatelessWidget {
  const HistorySocTrack({
    super.key,
    required this.start,
    required this.end,
    this.color = LuxeColors.emerald,
    this.showLabel = true,
  });
  final double start;
  final double end;
  final Color color;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final a = start.clamp(0.0, 100.0) / 100;
    final b = end.clamp(0.0, 100.0) / 100;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 6,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: _motion(context, 900),
              curve: LuxeMotion.enter,
              builder: (context, t, _) => CustomPaint(
                painter: _SocTrackPainter(
                  from: a,
                  to: a + (b - a) * t,
                  color: color,
                ),
              ),
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${start.round()}% → ${end.round()}%',
                style: _socStyle,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SocTrackPainter extends CustomPainter {
  _SocTrackPainter({required this.from, required this.to, required this.color});
  final double from;
  final double to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromLTRBR(
      0,
      y - 1.5,
      size.width,
      y + 1.5,
      const Radius.circular(2),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0x1FFFFFFF));
    final lo = math.min(from, to) * size.width;
    final hi = math.max(from, to) * size.width;
    if (hi - lo < 0.5) return;
    canvas.drawRRect(
      RRect.fromLTRBR(lo, y - 2, hi, y + 2, const Radius.circular(2)),
      Paint()
        ..shader = ui.Gradient.linear(Offset(lo, y), Offset(hi, y), [
          color.withValues(alpha: 0.35),
          color,
        ]),
    );
    canvas.drawCircle(Offset(hi, y), 3, Paint()..color = LuxeColors.platinumHi);
  }

  @override
  bool shouldRepaint(_SocTrackPainter old) =>
      old.from != from || old.to != to || old.color != color;
}

class HistoryStatusPill extends StatelessWidget {
  const HistoryStatusPill({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
  );
}

// ───────────────────────────── Active session ─────────────────────────────

class HistoryActiveCard extends StatelessWidget {
  const HistoryActiveCard({
    super.key,
    required this.session,
    required this.onTap,
    this.powerW,
  });
  final SmartChargingSession session;
  final VoidCallback onTap;
  final double? powerW;

  @override
  Widget build(BuildContext context) {
    final soc = (session.estimatedSoc ?? session.startSoc).clamp(0.0, 100.0);
    final target = session.targetSoc.clamp(0.0, 100.0);
    final cost = session.estimatedCostVnd == null
        ? 'Chưa đặt giá điện'
        : '${historyCost(session.estimatedCostVnd)} tạm tính';
    return Semantics(
      button: true,
      label: 'Phiên đang sạc, mở chi tiết realtime',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: LuxeGlass(
            selected: true,
            radius: 22,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: LuxeColors.emerald,
                        boxShadow: [
                          BoxShadow(
                            color: LuxeColors.emeraldGlow,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('ĐANG SẠC', style: LuxeText.eyebrow),
                    ),
                    Flexible(
                      child: Text(
                        'còn ${formatChargeDuration(session.remaining())}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LuxeText.label.copyWith(color: LuxeColors.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '~${soc.round()}%',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w300,
                            color: LuxeColors.platinumHi,
                          ),
                        ),
                        TextSpan(
                          text: '   mục tiêu ~${target.round()}%',
                          style: LuxeText.caption,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                HistorySocTrack(start: session.startSoc, end: soc),
                const SizedBox(height: 10),
                Text(
                  '${powerW == null ? '— W' : '${powerW!.toStringAsFixed(0)} W'}  ·  ${historyEnergy(session.energyUsedWh)}  ·  $cost',
                  style: LuxeText.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Empty state art ─────────────────────────────

/// A plug glides into a socket, then three pulses of energy run back along
/// the cable and the socket keeps a soft glow. Plays once (no ticker after).
class HistoryEmptyArt extends StatefulWidget {
  const HistoryEmptyArt({super.key});

  @override
  State<HistoryEmptyArt> createState() => _HistoryEmptyArtState();
}

class _HistoryEmptyArtState extends State<HistoryEmptyArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl.status == AnimationStatus.dismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 240,
      height: 150,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) =>
            CustomPaint(painter: _PlugPainter(_ctrl.value)),
      ),
    ),
  );
}

class _PlugPainter extends CustomPainter {
  _PlugPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cy = h * 0.46;
    final connect = LuxeMotion.enter.transform((t / 0.32).clamp(0.0, 1.0));
    final glow = t < 0.3 ? 0.0 : math.min(1.0, (t - 0.3) / 0.12);

    // Halo rings behind the socket.
    final socketC = Offset(w * 0.72, cy);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        socketC,
        44.0 + i * 16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Color.lerp(
            const Color(0x0DFFFFFF),
            LuxeColors.emerald.withValues(alpha: 0.18 - i * 0.05),
            glow,
          )!,
      );
    }

    // Socket plate.
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(center: socketC, width: 64, height: 64),
      const Radius.circular(18),
    );
    if (glow > 0) {
      canvas.drawRRect(
        plate.inflate(4),
        Paint()
          ..color = LuxeColors.emerald.withValues(alpha: 0.28 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = ui.Gradient.linear(
          plate.outerRect.topCenter,
          plate.outerRect.bottomCenter,
          const [Color(0xFF232428), Color(0xFF0D0E10)],
        ),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(
          LuxeColors.hairlineStrong,
          LuxeColors.emerald.withValues(alpha: 0.8),
          glow,
        )!,
    );
    for (final dy in [-10.0, 10.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: socketC + Offset(-14, dy),
            width: 16,
            height: 5,
          ),
          const Radius.circular(2.5),
        ),
        Paint()..color = const Color(0xFF020203),
      );
    }
    // Status LED on the plate.
    canvas.drawCircle(
      socketC + const Offset(16, 0),
      3,
      Paint()
        ..color = Color.lerp(
          const Color(0x33FFFFFF),
          LuxeColors.emerald,
          glow,
        )!,
    );

    // Plug body slides from the left until its prongs sit in the slots.
    final plugRight = lerpDouble(socketC.dx - 82, socketC.dx - 32, connect);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(plugRight - 40, cy - 19, plugRight - 4, cy + 19),
      const Radius.circular(11),
    );
    for (final dy in [-10.0, 10.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            plugRight - 6,
            cy + dy - 2.5,
            plugRight + 12,
            cy + dy + 2.5,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = LuxeColors.platinumMid,
      );
    }
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          body.outerRect.topCenter,
          body.outerRect.bottomCenter,
          const [LuxeColors.platinumHi, LuxeColors.platinum, Color(0xFF9EA2A8)],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Cable from the lower left into the back of the plug.
    final plugLeft = body.outerRect.left;
    final cable = Path()
      ..moveTo(0, h * 0.88)
      ..cubicTo(w * 0.22, h * 0.88, plugLeft - 46, cy, plugLeft, cy);
    canvas.drawPath(
      cable,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.88),
          Offset(plugLeft, cy),
          const [
            Color(0x005E6268),
            LuxeColors.platinumLow,
            LuxeColors.platinumMid,
          ],
          const [0.0, 0.4, 1.0],
        ),
    );

    // Energy pulses travel from the plug back toward the vehicle.
    if (t > 0.34) {
      final metric = cable.computeMetrics().first;
      final q = (t - 0.34) / 0.66;
      for (var k = 0; k < 3; k++) {
        final phase = (q * 1.6 - k * 0.3);
        if (phase <= 0 || phase >= 1) continue;
        final pos = metric.getTangentForOffset(metric.length * (1 - phase));
        if (pos == null) continue;
        final fade = math.sin(phase * math.pi);
        canvas.drawCircle(
          pos.position,
          7,
          Paint()
            ..color = LuxeColors.emerald.withValues(alpha: 0.45 * fade)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawCircle(
          pos.position,
          2.6,
          Paint()..color = LuxeColors.emerald.withValues(alpha: fade),
        );
      }
    }
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_PlugPainter old) => old.t != t;
}
