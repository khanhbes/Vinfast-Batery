import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium battery visualizer with circular gauge + interactive horizontal
/// battery track, matching the EV cockpit reference design.
class BatteryVisualizerV2 extends StatefulWidget {
  const BatteryVisualizerV2({
    super.key,
    required this.currentPercent,
    required this.targetPercent,
    required this.isCharging,
    required this.onTargetChanged,
    this.onCurrentChanged,
    this.batteryCapacityKWh = 3.5,
  });

  final double currentPercent;
  final double targetPercent;
  final bool isCharging;
  final ValueChanged<double> onTargetChanged;
  final ValueChanged<double>? onCurrentChanged;
  final double batteryCapacityKWh;

  @override
  State<BatteryVisualizerV2> createState() => _BatteryVisualizerV2State();
}

class _BatteryVisualizerV2State extends State<BatteryVisualizerV2>
    with SingleTickerProviderStateMixin {
  int? _lastHapticStep;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: CockpitMotion.chargingGlow,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  void _setTarget(double raw) {
    final next = raw.round().clamp(
      (widget.currentPercent.ceil() + 1).clamp(1, 100),
      100,
    );
    if (next == widget.targetPercent.round()) return;
    final step = next ~/ 5;
    if (_lastHapticStep != step) {
      _lastHapticStep = step;
      HapticFeedback.selectionClick();
    }
    widget.onTargetChanged(next.toDouble());
  }

  static const _presets = [
    (value: 80, label: '80%', tag: 'Tối ưu LFP', recommended: true),
    (value: 90, label: '90%', tag: 'Tiêu chuẩn', recommended: false),
    (value: 100, label: '100%', tag: 'Tối đa', recommended: false),
  ];

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final current = widget.currentPercent.round().clamp(0, 100);
    final target = widget.targetPercent.round().clamp(current, 100);

    return CockpitSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Current SOC slider (only in standby) ──
          if (!widget.isCharging && widget.onCurrentChanged != null) ...[
            _CurrentSocInput(
              currentPercent: current,
              onChanged: widget.onCurrentChanged!,
            ),
            const SizedBox(height: 16),
          ],

          // ── Header: "Mục tiêu sạc" + target display ──
          LayoutBuilder(
            builder: (context, constraints) {
              final compactHeader =
                  constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final title = Text(
                'MỤC TIÊU SẠC',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CockpitColors.emeraldStrong,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              );
              final targetValue = Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$target',
                    style: CockpitTypography.numbers(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: CockpitColors.emerald,
                    ),
                  ),
                  Text(
                    '%',
                    style: TextStyle(
                      color: CockpitColors.emerald.withValues(alpha: .7),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
              final lfpBadge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: CockpitColors.emerald.withValues(alpha: .30),
                  ),
                ),
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 12,
                      color: CockpitColors.emerald,
                    ),
                    Text(
                      'Chuẩn LFP',
                      style: TextStyle(
                        color: CockpitColors.emerald,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );

              if (compactHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        targetValue,
                      ],
                    ),
                    if (target <= 80) ...[const SizedBox(height: 8), lfpBadge],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [title, if (target <= 80) lfpBadge],
                    ),
                  ),
                  const SizedBox(width: 8),
                  targetValue,
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // ── Circular Gauge ──
          Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: TweenAnimationBuilder<double>(
                duration: reducedMotion ? Duration.zero : CockpitMotion.battery,
                curve: Curves.easeOutCubic,
                tween: Tween(end: current.toDouble()),
                builder: (context, animatedCurrent, _) => CustomPaint(
                  painter: _CircularGaugePainter(
                    currentPercent: animatedCurrent,
                    targetPercent: target.toDouble(),
                    isCharging: widget.isCharging,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 112,
                          height: 62,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$current%',
                              style: CockpitTypography.numbers(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        if (widget.isCharging)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 12,
                                color: CockpitColors.emerald,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Đang sạc',
                                style: TextStyle(
                                  color: CockpitColors.muted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Interactive horizontal battery track ──
          _InteractiveBatteryTrack(
            currentPercent: current.toDouble(),
            targetPercent: target.toDouble(),
            isCharging: widget.isCharging,
            onTargetChanged: _setTarget,
            glowAnimation: _glowController,
          ),

          const SizedBox(height: 12),

          // ── Fine-tuning steppers ──
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CockpitColors.border),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepperButton(
                      icon: Icons.remove_rounded,
                      onPressed: target > current + 1
                          ? () => _setTarget(target - 1)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$target%',
                        style: CockpitTypography.numbers(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StepperButton(
                      icon: Icons.add_rounded,
                      onPressed: target < 100
                          ? () => _setTarget(target + 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Preset buttons ──
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: CockpitColors.border)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final stacked = constraints.maxWidth < 260 || scale > 1.3;
                final buttons = [
                  for (final preset in _presets)
                    _PresetButton(
                      preset: preset,
                      isActive: target == preset.value,
                      onTap: () =>
                          widget.onTargetChanged(preset.value.toDouble()),
                    ),
                ];
                if (stacked) {
                  return Column(
                    children: [
                      for (var index = 0; index < buttons.length; index++) ...[
                        if (index > 0) const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: buttons[index]),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var index = 0; index < buttons.length; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(child: buttons[index]),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CurrentSocInput extends StatelessWidget {
  const _CurrentSocInput({
    required this.currentPercent,
    required this.onChanged,
  });
  final int currentPercent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .02),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CockpitColors.border),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.battery_5_bar_rounded,
              size: 16,
              color: CockpitColors.emerald,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Mức pin hiện tại',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CockpitColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
              ),
              child: Text(
                '$currentPercent%',
                style: CockpitTypography.numbers(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: CockpitColors.emerald,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              onPressed: currentPercent > 0
                  ? () => onChanged((currentPercent - 1).toDouble())
                  : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: CockpitColors.emerald,
                  inactiveTrackColor: Colors.white.withValues(alpha: .10),
                  thumbColor: CockpitColors.emerald,
                  overlayColor: CockpitColors.emerald.withValues(alpha: .12),
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: currentPercent.toDouble().clamp(0, 100),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: onChanged,
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              onPressed: currentPercent < 100
                  ? () => onChanged((currentPercent + 1).toDouble())
                  : null,
            ),
          ],
        ),
      ],
    ),
  );
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white.withValues(alpha: .05),
        foregroundColor: onPressed != null
            ? CockpitColors.muted
            : CockpitColors.dim.withValues(alpha: .3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.isActive,
    required this.onTap,
  });

  final ({int value, String label, String tag, bool recommended}) preset;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: CockpitMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive
              ? CockpitColors.emerald.withValues(alpha: .16)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? CockpitColors.emeraldStrong
                : CockpitColors.border,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: CockpitColors.emerald.withValues(alpha: .12),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              preset.label,
              textAlign: TextAlign.center,
              style: CockpitTypography.numbers(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isActive ? CockpitColors.emerald : CockpitColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              preset.tag,
              style: TextStyle(color: CockpitColors.muted, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive battery track
// ─────────────────────────────────────────────────────────────────────────────

class _InteractiveBatteryTrack extends StatelessWidget {
  const _InteractiveBatteryTrack({
    required this.currentPercent,
    required this.targetPercent,
    required this.isCharging,
    required this.onTargetChanged,
    required this.glowAnimation,
  });

  final double currentPercent;
  final double targetPercent;
  final bool isCharging;
  final ValueChanged<double> onTargetChanged;
  final Animation<double> glowAnimation;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyWidth = constraints.maxWidth - 12; // terminal width
        void update(Offset local) {
          final pct = (local.dx / bodyWidth).clamp(0.0, 1.0) * 100;
          onTargetChanged(pct);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => update(e.localPosition),
          onHorizontalDragUpdate: (e) => update(e.localPosition),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: glowAnimation,
                    builder: (context, child) => Container(
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF080808),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCharging
                              ? CockpitColors.emerald.withValues(
                                  alpha: .3 + glowAnimation.value * .2,
                                )
                              : Colors.white.withValues(alpha: .08),
                        ),
                        boxShadow: isCharging
                            ? [
                                BoxShadow(
                                  color: CockpitColors.emerald.withValues(
                                    alpha: .12 + glowAnimation.value * .10,
                                  ),
                                  blurRadius: 16,
                                ),
                              ]
                            : null,
                      ),
                      child: TweenAnimationBuilder<double>(
                        duration: reducedMotion
                            ? Duration.zero
                            : CockpitMotion.battery,
                        curve: Curves.easeOutCubic,
                        tween: Tween(end: currentPercent),
                        builder: (context, animCurrent, _) => CustomPaint(
                          painter: _HorizontalBatteryPainter(
                            currentPercent: animCurrent,
                            targetPercent: targetPercent,
                            isCharging: isCharging,
                            glowValue: glowAnimation.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Battery terminal
                const SizedBox(width: 3),
                Container(
                  width: 8,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painters
// ─────────────────────────────────────────────────────────────────────────────

class _CircularGaugePainter extends CustomPainter {
  _CircularGaugePainter({
    required this.currentPercent,
    required this.targetPercent,
    required this.isCharging,
  });

  final double currentPercent;
  final double targetPercent;
  final bool isCharging;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 8.0;
    const startAngle = -math.pi / 2;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Target level arc (faint)
    final targetSweep = (targetPercent / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      targetSweep,
      false,
      Paint()
        ..color = CockpitColors.emerald.withValues(alpha: .15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Current level arc (solid)
    final currentSweep = (currentPercent / 100) * 2 * math.pi;
    if (currentSweep > 0.001) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 1
        ..strokeCap = StrokeCap.round;

      // Gradient for the current arc
      arcPaint.shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + currentSweep,
        colors: const [CockpitColors.emeraldStrong, CockpitColors.emerald],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        currentSweep,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularGaugePainter old) =>
      old.currentPercent != currentPercent ||
      old.targetPercent != targetPercent ||
      old.isCharging != isCharging;
}

class _HorizontalBatteryPainter extends CustomPainter {
  _HorizontalBatteryPainter({
    required this.currentPercent,
    required this.targetPercent,
    required this.isCharging,
    required this.glowValue,
  });

  final double currentPercent;
  final double targetPercent;
  final bool isCharging;
  final double glowValue;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    canvas.save();
    canvas.clipRRect(body);

    // Current fill with gradient
    final currentWidth = size.width * currentPercent.clamp(0, 100) / 100;
    final fillRect = Rect.fromLTWH(0, 0, currentWidth, size.height);
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF059669), // emerald-600
          CockpitColors.emeraldStrong, // emerald-500
          CockpitColors.emerald, // emerald-400
        ],
      ).createShader(fillRect);
    canvas.drawRect(fillRect, fillPaint);

    // Energy wave animation overlay (when charging)
    if (isCharging) {
      final wavePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + glowValue * 2, 0),
          end: Alignment(glowValue * 2, 0),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: .25),
            Colors.transparent,
          ],
        ).createShader(fillRect);
      canvas.drawRect(fillRect, wavePaint);
    }

    // Target fill (zone between current and target)
    if (targetPercent > currentPercent) {
      final targetWidth = size.width * targetPercent.clamp(0, 100) / 100;
      final targetRect = Rect.fromLTWH(
        currentWidth,
        0,
        targetWidth - currentWidth,
        size.height,
      );
      canvas.drawRect(
        targetRect,
        Paint()..color = CockpitColors.emerald.withValues(alpha: .15),
      );
    }

    // ── Tick marks at every 20% ──
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: .18)
      ..strokeWidth = 1.0;
    for (final pct in [20, 40, 60]) {
      final x = size.width * pct / 100;
      canvas.drawLine(Offset(x, 4), Offset(x, size.height - 4), tickPaint);
    }

    // ── 80% marker line (stronger, with dashes) ──
    final marker80X = size.width * 0.80;
    final marker80Paint = Paint()
      ..color = CockpitColors.emerald.withValues(alpha: .6)
      ..strokeWidth = 1.5;
    // Dashed line effect
    const dashHeight = 4.0;
    const gapHeight = 3.0;
    var y = 2.0;
    while (y < size.height - 2) {
      canvas.drawLine(
        Offset(marker80X, y),
        Offset(marker80X, (y + dashHeight).clamp(0, size.height - 2)),
        marker80Paint,
      );
      y += dashHeight + gapHeight;
    }

    // "80%" text label above the marker
    final textPainter = TextPainter(
      text: TextSpan(
        text: '80%',
        style: TextStyle(
          color: CockpitColors.emerald.withValues(alpha: .8),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'JetBrains Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Position above the track (negative y)
    textPainter.paint(canvas, Offset(marker80X - textPainter.width / 2, -1));

    canvas.restore();

    // ── Draggable target thumb (painted outside clip) ──
    final targetX = size.width * targetPercent.clamp(0, 100) / 100;
    final thumbCenter = Offset(targetX, size.height / 2);
    // White thumb background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: thumbCenter, width: 16, height: 32),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white,
    );
    // Grip lines on thumb
    for (var dy = -4.0; dy <= 4; dy += 4) {
      canvas.drawLine(
        Offset(targetX - 3, size.height / 2 + dy),
        Offset(targetX + 3, size.height / 2 + dy),
        Paint()
          ..color = const Color(0xFF1E293B)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HorizontalBatteryPainter old) =>
      old.currentPercent != currentPercent ||
      old.targetPercent != targetPercent ||
      old.isCharging != isCharging ||
      old.glowValue != glowValue;
}
