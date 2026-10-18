import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';
import 'luxe_soc_dial.dart';

/// Live session: the dial in read-only charging mode (emerald fill with a
/// breathing head, target mark), a second-by-second countdown, live meter
/// readings and the stop action.
class ActiveChargingCardV2 extends StatefulWidget {
  const ActiveChargingCardV2({
    super.key,
    required this.currentPercent,
    required this.targetPercent,
    required this.remaining,
    required this.completionTime,
    required this.sessionEnergyWh,
    required this.powerW,
    required this.voltageV,
    required this.currentA,
    required this.temperatureC,
    required this.timerVerified,
    required this.onStop,
    this.estimatedSoc,
    this.isStopping = false,
    this.isStarting = false,
    this.estimateNote,
    this.stopAwaitingReadback = false,
    this.countdownLabel = 'Shelly tự ngắt sau · lúc',
    this.socCaption,
  });

  final double currentPercent;
  final double targetPercent;
  final Duration remaining;
  final String completionTime;
  final double sessionEnergyWh;
  final double powerW;
  final double voltageV;
  final double currentA;
  final double? temperatureC;
  final bool timerVerified;
  final VoidCallback onStop;
  final double? estimatedSoc;
  final bool isStopping;
  final bool isStarting;

  /// "Đạt mục tiêu ~X · khoảng HH:mm" from the live SOC and measured power
  /// (Task 122); null until real measurements exist.
  final String? estimateNote;

  /// OFF was accepted; waiting for Shelly Cloud to report it.
  final bool stopAwaitingReadback;

  /// What the countdown counts to (target charge vs. device timer).
  final String countdownLabel;

  /// Under the % (default "ước tính · mục tiêu X%"); a timed charge has no
  /// target (QA 130 showed "mục tiêu 100%" for 30 minutes).
  final String? socCaption;

  @override
  State<ActiveChargingCardV2> createState() => _ActiveChargingCardV2State();
}

class _ActiveChargingCardV2State extends State<ActiveChargingCardV2>
    with TickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  // The countdown interpolates between server updates.
  late DateTime _anchor = DateTime.now();
  bool _reduced = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_started && reduced == _reduced) return;
    _started = true;
    _reduced = reduced;
    if (reduced) {
      _flow.stop();
      _enter.value = 1;
    } else {
      _flow.repeat();
      if (_enter.isDismissed) _enter.forward();
    }
  }

  @override
  void didUpdateWidget(ActiveChargingCardV2 old) {
    super.didUpdateWidget(old);
    if (old.remaining != widget.remaining) _anchor = DateTime.now();
  }

  @override
  void dispose() {
    _flow.dispose();
    _enter.dispose();
    super.dispose();
  }

  Duration get _left {
    final left = widget.remaining - DateTime.now().difference(_anchor);
    return left.isNegative ? Duration.zero : left;
  }

  String _clock(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _energy(double wh) => wh >= 1000
      ? '${(wh / 1000).toStringAsFixed(2)} kWh'
      : '${wh.toStringAsFixed(0)} Wh';

  @override
  Widget build(BuildContext context) {
    final current = widget.currentPercent.round().clamp(0, 100);
    final target = widget.targetPercent.round().clamp(0, 100);
    final transitional = widget.isStopping || widget.isStarting;
    final statusColor = transitional
        ? LuxeColors.champagne
        : LuxeColors.emerald;
    final statusText = widget.stopAwaitingReadback
        ? 'ĐÃ GỬI LỆNH TẮT · CHỜ XÁC NHẬN'
        : widget.isStopping
        ? 'ĐANG TẮT...'
        : widget.isStarting
        ? 'ĐANG XÁC NHẬN...'
        : 'ĐANG SẠC';

    return LuxeGlass(
      selected: !transitional,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _flow,
                builder: (context, _) {
                  final pulse = 0.5 + 0.5 * math.sin(_flow.value * 2 * math.pi);
                  return Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(
                            alpha: 0.35 + 0.35 * pulse,
                          ),
                          blurRadius: 6 + 6 * pulse,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: _Chip(
                  icon: widget.timerVerified
                      ? Icons.verified_user_rounded
                      : Icons.info_outline_rounded,
                  label: widget.timerVerified ? 'Hẹn giờ Shelly' : 'Ước tính',
                  accent: widget.timerVerified,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              final size = math.min(c.maxWidth, 300.0);
              return Center(
                child: SizedBox.square(
                  dimension: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_flow, _enter]),
                          builder: (context, _) => CustomPaint(
                            painter: LuxeDialPainter(
                              current: current.toDouble(),
                              target: target.toDouble(),
                              enter: _enter.value,
                              flow: _flow.value,
                              charging: true,
                            ),
                          ),
                        ),
                      ),
                      // Only the short centre lines live inside the dial; they
                      // wrap instead of shrinking everything (Task 127).
                      Center(
                        child: SizedBox.square(
                          dimension: size * 0.64,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: size * 0.64,
                              child: _centre(current, target),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.estimateNote != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.estimateNote!,
              key: const ValueKey('session-estimate-note'),
              textAlign: TextAlign.center,
              // Estimates are champagne; emerald only marks what was
              // verified (the relay status above) — LUXE rule, QA 129.
              style: const TextStyle(
                color: LuxeColors.champagne,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cells = [
                _Metric(
                  label: 'Công suất',
                  value: '${widget.powerW.round()} W',
                ),
                _Metric(
                  label: 'Điện áp',
                  value: '${widget.voltageV.toStringAsFixed(0)} V',
                ),
                _Metric(
                  label: 'Dòng',
                  value: '${widget.currentA.toStringAsFixed(1)} A',
                ),
                _Metric(
                  label: 'Đã nạp',
                  value: _energy(widget.sessionEnergyWh),
                ),
              ];
              final perRow = c.maxWidth < 300 ? 2 : 4;
              final w = (c.maxWidth - 8 * (perRow - 1)) / perRow;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cell in cells) SizedBox(width: w, child: cell),
                ],
              );
            },
          ),
          if (widget.temperatureC != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.thermostat_rounded,
                  size: 14,
                  color: LuxeColors.platinumMid,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Nhiệt độ ổ cắm ${widget.temperatureC!.toStringAsFixed(0)}°C',
                    style: const TextStyle(
                      color: LuxeColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: widget.isStopping ? null : widget.onStop,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF59E9E),
              side: BorderSide(
                color: const Color(0xFFF59E9E).withValues(alpha: 0.45),
              ),
              backgroundColor: const Color(0x14F59E9E),
            ),
            icon: const Icon(Icons.stop_rounded, size: 20),
            label: const Text('Dừng sạc'),
          ),
        ],
      ),
    );
  }

  Widget _centre(int current, int target) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            LuxeMetalText(
              '$current',
              style: const TextStyle(
                fontSize: 56,
                height: 1.0,
                fontWeight: FontWeight.w200,
                letterSpacing: -1.5,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
            const Text(
              '%',
              style: TextStyle(
                color: LuxeColors.champagne,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 2),
      Text(
        widget.socCaption ?? 'ước tính · mục tiêu $target%',
        textAlign: TextAlign.center,
        style: const TextStyle(color: LuxeColors.muted, fontSize: 13),
      ),
      const SizedBox(height: 12),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedBuilder(
          animation: _flow,
          builder: (context, _) => Text(
            _clock(_left),
            key: const ValueKey('session-countdown'),
            style: const TextStyle(
              color: LuxeColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        '${widget.countdownLabel} ${widget.completionTime}',
        key: const ValueKey('session-countdown-label'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: LuxeColors.muted, fontSize: 13),
      ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.accent});
  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: accent ? const Color(0x1A34D399) : LuxeColors.glass,
      border: Border.all(
        color: accent
            ? LuxeColors.emerald.withValues(alpha: 0.35)
            : LuxeColors.hairline,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: accent ? LuxeColors.emerald : LuxeColors.muted,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? LuxeColors.emerald : LuxeColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: LuxeColors.glass,
      border: Border.all(color: LuxeColors.hairline),
    ),
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
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: [ui.FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: LuxeColors.dim, fontSize: 11),
        ),
      ],
    ),
  );
}
