import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../data/models/smart_charging_session.dart';

/// Session SOC as a 240° platinum arc: start → end lit emerald, the preset
/// target as a notch. Adapts to compact phones and large text.
class SessionSocSummary extends StatelessWidget {
  const SessionSocSummary({super.key, required this.session});
  final SmartChargingSession session;

  static bool _valid(double? v) =>
      v != null && v.isFinite && v >= 0 && v <= 100;

  String _soc(double? value) => _valid(value) ? '${value!.round()}%' : '—';

  @override
  Widget build(BuildContext context) {
    final confirmed = session.actualEndSoc;
    final estimated = session.estimatedSoc;
    final actualValid = _valid(confirmed);
    final startSoc = session.startSoc >= 0 && session.startSoc <= 100
        ? session.startSoc
        : 0.0;
    // A stored estimate is already the server's reconciled value. Older
    // sessions do not carry a quality field, so do not hide a valid estimate
    // merely because that optional metadata is absent.
    final estimatedValid = _valid(estimated);
    final double? endSoc = actualValid
        ? confirmed
        : (estimatedValid ? estimated : null);
    final gain = endSoc == null
        ? 0.0
        : (endSoc - startSoc).clamp(-100.0, 100.0);
    final endLabel = actualValid
        ? 'Thực tế cuối'
        : (estimatedValid
              ? 'SOC ước tính'
              : (session.state.isTerminal ? 'Ước tính cuối' : 'Hiện tại'));
    // A timed charge started without a target is stored with target =
    // start % (QA 135: "Mục tiêu 11%" for 11 -> 81 %). That is no plan.
    final target =
        _valid(session.targetSoc) && session.targetSoc > startSoc + 0.5
        ? session.targetSoc
        : null;

    return LuxeGlass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tiến trình sạc pin (SOC)',
                      style: TextStyle(
                        color: LuxeColors.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      actualValid
                          ? 'Cuối phiên · đã xác nhận'
                          : (session.state.isTerminal
                                ? 'Ước tính kết thúc'
                                : 'Đang tiếp tục nạp'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: actualValid
                            ? LuxeColors.emerald
                            : LuxeColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (gain > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: LuxeColors.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: LuxeColors.emerald.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '+${gain.round()}% pin',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: LuxeColors.emerald,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: AspectRatio(
                aspectRatio: 1.25,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 1300),
                  curve: LuxeMotion.enter,
                  builder: (context, t, child) => CustomPaint(
                    painter: _SocArcPainter(
                      start: startSoc / 100,
                      end: endSoc == null ? null : endSoc / 100,
                      target: target == null ? null : target / 100,
                      reveal: t,
                    ),
                    child: child,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 34, 40, 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (endSoc == null)
                            const Text(
                              'Chưa có dữ liệu',
                              style: TextStyle(
                                color: LuxeColors.platinum,
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          else
                            LuxeMetalText(
                              _soc(endSoc),
                              style: const TextStyle(
                                fontSize: 44,
                                height: 1.05,
                                fontWeight: FontWeight.w200,
                                fontFeatures: [ui.FontFeature.tabularFigures()],
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(
                            endLabel,
                            style: const TextStyle(
                              color: LuxeColors.emerald,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            spacing: 12,
            children: [
              _Legend(
                color: LuxeColors.platinumMid,
                label: 'Bắt đầu',
                value: _soc(startSoc),
              ),
              _Legend(
                color: LuxeColors.platinumHi,
                label: target == null
                    ? 'Không đặt mục tiêu'
                    : 'Mục tiêu đặt trước: ${_soc(target)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            actualValid
                ? '✓ SOC cuối được ghi nhận theo thông số người dùng xác nhận.'
                : '• Số đo SOC ước tính dựa trên công suất nạp lưới và dung lượng xe.',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: LuxeColors.dim,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.value});
  final Color color;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(color: LuxeColors.muted, fontSize: 12.5),
        ),
      ),
      if (value != null) ...[
        const SizedBox(width: 6),
        Text(
          value!,
          style: const TextStyle(
            color: LuxeColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}

class _SocArcPainter extends CustomPainter {
  _SocArcPainter({
    required this.start,
    required this.end,
    required this.target,
    required this.reveal,
  });

  final double start;
  final double? end;
  final double? target;
  final double reveal;

  static const _from = math.pi * 5 / 6; // 150°
  static const _sweep = math.pi * 4 / 3; // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height / 1.5) - 10;
    final c = Offset(size.width / 2, r + 10);
    final rect = Rect.fromCircle(center: c, radius: r);
    double angle(double f) => _from + _sweep * f.clamp(0.0, 1.0);

    canvas.drawArc(
      rect,
      _from,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = LuxeColors.glassStrong,
    );
    // Fine 10 % graduations outside the track.
    for (var i = 0; i <= 10; i++) {
      final a = angle(i / 10);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * (r + 9),
        c + dir * (r + (i % 5 == 0 ? 15 : 12)),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0x33FFFFFF),
      );
    }

    final e = end;
    if (e != null) {
      final lo = math.min(start, e);
      final hi = lo + (math.max(start, e) - lo) * reveal;
      if (hi - lo > 0.002) {
        final arcPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: angle(lo),
            endAngle: angle(lo) + math.max(0.01, _sweep * (hi - lo)),
            colors: const [LuxeColors.emeraldDeep, LuxeColors.emerald],
          ).createShader(rect);
        canvas.drawArc(
          rect,
          angle(lo),
          _sweep * (hi - lo),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round
            ..color = LuxeColors.emerald.withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
        canvas.drawArc(rect, angle(lo), _sweep * (hi - lo), false, arcPaint);
        final tip = angle(hi);
        canvas.drawCircle(
          c + Offset(math.cos(tip), math.sin(tip)) * r,
          5,
          Paint()..color = LuxeColors.platinumHi,
        );
      }
    }

    // Start marker.
    final s = angle(start);
    canvas.drawCircle(
      c + Offset(math.cos(s), math.sin(s)) * r,
      3.2,
      Paint()..color = LuxeColors.platinumMid,
    );

    // Target notch across the track.
    final tg = target;
    if (tg != null) {
      final a = angle(tg);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * (r - 9),
        c + dir * (r + 9),
        Paint()
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = LuxeColors.platinumHi,
      );
    }
  }

  @override
  bool shouldRepaint(_SocArcPainter old) =>
      old.reveal != reveal ||
      old.start != start ||
      old.end != end ||
      old.target != target;
}
