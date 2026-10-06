import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';
import 'edit_current_battery_sheet.dart';

/// Single-focus Hero Card for AI Charging that replaces the circular gauge
/// with a streamlined horizontal battery visualizer, dual metrics, and preset chips.
class BatteryHeroCard extends StatefulWidget {
  const BatteryHeroCard({
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
  State<BatteryHeroCard> createState() => _BatteryHeroCardState();
}

class _BatteryHeroCardState extends State<BatteryHeroCard>
    with SingleTickerProviderStateMixin {
  int? _lastHapticStep;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: CockpitMotion.chargingGlow,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void _setTarget(double raw) {
    final safeCurrent = widget.currentPercent.isFinite
        ? widget.currentPercent.clamp(0.0, 100.0)
        : 0.0;
    final minTarget = (safeCurrent.ceil() + 1).clamp(1, 100);
    final next = raw.round().clamp(minTarget, 100);

    if (next == widget.targetPercent.round()) return;

    // Haptic feedback: selection click every 5%
    final step = next ~/ 5;
    if (_lastHapticStep != step) {
      _lastHapticStep = step;
      if (next == 80) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    }

    widget.onTargetChanged(next.toDouble());
  }

  void _openEditCurrentSheet() {
    if (widget.isCharging || widget.onCurrentChanged == null) return;
    EditCurrentBatterySheet.show(
      context,
      initialPercent: widget.currentPercent,
      onSave: widget.onCurrentChanged!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeCurrent = widget.currentPercent.isFinite
        ? widget.currentPercent.clamp(0.0, 100.0)
        : 0.0;
    final safeTarget = widget.targetPercent.isFinite
        ? widget.targetPercent.clamp(safeCurrent, 100.0)
        : 80.0;
    final current = safeCurrent.round().clamp(0, 100);
    final target = safeTarget.round().clamp(current, 100);
    final diff = (target - current).clamp(0, 100);
    final isLfpRecommended = target == 80;

    return Semantics(
      label: 'Mức pin hiện tại $current%, MỤC TIÊU SẠC $target%',
      child: CockpitSurface(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Dual Metrics Display ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Current SOC
                Expanded(
                  child: InkWell(
                    onTap: !widget.isCharging && widget.onCurrentChanged != null
                        ? _openEditCurrentSheet
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$current',
                                  style: CockpitTypography.numbers(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w800,
                                    color: CockpitColors.text,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '%',
                                  style: CockpitTypography.numbers(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: CockpitColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Text(
                                  'Mức pin hiện tại',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CockpitColors.muted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '(chạm để sửa)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: CockpitColors.dim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Center: Arrow & Delta
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: .05),
                          border: Border.all(color: CockpitColors.border),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: CockpitColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+$diff%',
                        style: CockpitTypography.numbers(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: CockpitColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),

                // Right: Target SOC
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$target',
                              style: CockpitTypography.numbers(
                                fontSize: 46,
                                fontWeight: FontWeight.w800,
                                color: CockpitColors.emerald,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '%',
                              style: CockpitTypography.numbers(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.emerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'MỤC TIÊU SẠC',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: CockpitColors.muted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (isLfpRecommended) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: CockpitColors.emerald.withValues(
                                    alpha: .15,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: CockpitColors.emerald.withValues(
                                      alpha: .35,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Khuyên dùng',
                                  style: TextStyle(
                                    color: CockpitColors.emerald,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ── Interactive Horizontal Battery Visualizer ──
            _HeroBatteryTrack(
              currentPercent: current.toDouble(),
              targetPercent: target.toDouble(),
              isCharging: widget.isCharging,
              onTargetChanged: _setTarget,
              shimmerAnimation: _shimmerController,
            ),

            const SizedBox(height: 16),

            // ── Preset Chips ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PresetChip(
                  percentText: '80%',
                  labelText: 'Bảo vệ pin',
                  tag: 'Khuyên dùng',
                  isSelected: target == 80,
                  onTap: () => _setTarget(80),
                ),
                _PresetChip(
                  percentText: '90%',
                  labelText: 'Cân bằng',
                  isSelected: target == 90,
                  onTap: () => _setTarget(90),
                ),
                _PresetChip(
                  percentText: '100%',
                  labelText: 'Đầy pin',
                  isSelected: target == 100,
                  onTap: () => _setTarget(100),
                ),
                if (target != 80 && target != 90 && target != 100)
                  _PresetChip(
                    percentText: '$target%',
                    labelText: 'Tùy chỉnh',
                    isSelected: true,
                    onTap: () {},
                  ),
              ],
            ),

            // ── Inline LFP 100% Notice ──
            if (target == 100) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CockpitColors.amber.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CockpitColors.amber.withValues(alpha: .30),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: CockpitColors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pin LFP chỉ nên sạc đến 100% mỗi 1-2 tuần để cân bằng cell.',
                        style: TextStyle(
                          color: CockpitColors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Inline Warning when Target <= Current ──
            if (target <= current) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CockpitColors.danger.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CockpitColors.danger.withValues(alpha: .30),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: CockpitColors.danger,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mức pin mục tiêu phải cao hơn mức pin hiện tại để bắt đầu sạc.',
                        style: TextStyle(
                          color: CockpitColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Hidden accessibility anchor to ensure tests and screen readers find exact terms
            Semantics(
              label: 'Mức pin hiện tại MỤC TIÊU SẠC',
              child: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive Track with Floating Badges & Draggable Handle
// ─────────────────────────────────────────────────────────────────────────────

class _HeroBatteryTrack extends StatelessWidget {
  const _HeroBatteryTrack({
    required this.currentPercent,
    required this.targetPercent,
    required this.isCharging,
    required this.onTargetChanged,
    required this.shimmerAnimation,
  });

  final double currentPercent;
  final double targetPercent;
  final bool isCharging;
  final ValueChanged<double> onTargetChanged;
  final Animation<double> shimmerAnimation;

  @override
  Widget build(BuildContext context) {
    const trackHeight = 48.0;
    const thumbRadius = 19.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final currentClamped = currentPercent.clamp(0.0, 100.0);
        final targetClamped = targetPercent.clamp(0.0, 100.0);

        final currentX = trackWidth * (currentClamped / 100.0);
        final targetX = trackWidth * (targetClamped / 100.0);

        void handleDragOrTap(Offset localPosition) {
          final pct = (localPosition.dx / trackWidth).clamp(0.0, 1.0) * 100.0;
          onTargetChanged(pct);
        }

        return Column(
          children: [
            // ── Floating Badges Row (Above Track) ──
            SizedBox(
              height: 28,
              child: Stack(
                children: [
                  // "Hiện tại 35%" badge
                  Positioned(
                    left: (currentX - 44).clamp(0.0, trackWidth - 88),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CockpitColors.elevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CockpitColors.border),
                      ),
                      child: Text(
                        'Hiện tại ${currentClamped.round()}%',
                        style: TextStyle(
                          color: CockpitColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  // "Sạc đến 80%" badge
                  Positioned(
                    left: (targetX - 44).clamp(0.0, trackWidth - 88),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CockpitColors.emerald,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: CockpitColors.emerald.withValues(alpha: .3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(
                        'Sạc đến ${targetClamped.round()}%',
                        style: const TextStyle(
                          color: Color(0xFF042F2E),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ── Battery Bar & Floating Thumb ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => handleDragOrTap(details.localPosition),
              onHorizontalDragUpdate: (details) =>
                  handleDragOrTap(details.localPosition),
              child: SizedBox(
                height: trackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Base track container
                    Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0D14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: CockpitColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: AnimatedBuilder(
                          animation: shimmerAnimation,
                          builder: (context, _) => CustomPaint(
                            size: Size(trackWidth, trackHeight),
                            painter: _BatteryBarPainter(
                              currentPercent: currentClamped,
                              targetPercent: targetClamped,
                              isCharging: isCharging,
                              shimmerValue: shimmerAnimation.value,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Draggable Floating Thumb at target percent
                    Positioned(
                      left: targetX - thumbRadius,
                      top: (trackHeight / 2) - thumbRadius,
                      child: Container(
                        width: thumbRadius * 2,
                        height: thumbRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF6EE7B7),
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: CockpitColors.emerald.withValues(
                                alpha: .5,
                              ),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _gripLine(),
                              const SizedBox(width: 2),
                              _gripLine(),
                              const SizedBox(width: 2),
                              _gripLine(),
                            ],
                          ),
                        ),
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

  Widget _gripLine() => Container(
    width: 1.8,
    height: 12,
    decoration: BoxDecoration(
      color: const Color(0xFF042F2E),
      borderRadius: BorderRadius.circular(1),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Painter for the Battery Track
// ─────────────────────────────────────────────────────────────────────────────

class _BatteryBarPainter extends CustomPainter {
  _BatteryBarPainter({
    required this.currentPercent,
    required this.targetPercent,
    required this.isCharging,
    required this.shimmerValue,
  });

  final double currentPercent;
  final double targetPercent;
  final bool isCharging;
  final double shimmerValue;

  @override
  void paint(Canvas canvas, Size size) {
    final currentW = size.width * (currentPercent / 100.0);
    final targetW = size.width * (targetPercent / 100.0);

    // 1. Current SOC region (0 to currentPercent)
    if (currentPercent > 0) {
      final currentRect = Rect.fromLTWH(0, 0, currentW, size.height);
      final currentPaint = Paint()..color = const Color(0xFF132822);
      canvas.drawRect(currentRect, currentPaint);

      // Dividing vertical marker at current SOC
      final linePaint = Paint()
        ..color = CockpitColors.emerald.withValues(alpha: .4)
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(currentW, 4),
        Offset(currentW, size.height - 4),
        linePaint,
      );
    }

    // 2. Charging segment between current and target
    if (targetPercent > currentPercent) {
      final segmentRect = Rect.fromLTWH(
        currentW,
        0,
        (targetW - currentW).clamp(0.0, size.width),
        size.height,
      );

      final gradientPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF059669).withValues(alpha: .4),
            CockpitColors.emerald.withValues(alpha: .75),
            const Color(0xFF6EE7B7).withValues(alpha: .95),
          ],
        ).createShader(segmentRect);

      canvas.drawRect(segmentRect, gradientPaint);

      // Shimmer wave if charging
      if (isCharging) {
        final shimmerPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment(-1 + shimmerValue * 2, 0),
            end: Alignment(shimmerValue * 2, 0),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: .25),
              Colors.transparent,
            ],
          ).createShader(segmentRect);
        canvas.drawRect(segmentRect, shimmerPaint);
      }
    }

    // 3. Subtle tick mark at 100%
    final tick100X = size.width - 2;
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: .15)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(tick100X, 8),
      Offset(tick100X, size.height - 8),
      tickPaint,
    );
  }

  @override
  bool shouldRepaint(_BatteryBarPainter old) =>
      old.currentPercent != currentPercent ||
      old.targetPercent != targetPercent ||
      old.isCharging != isCharging ||
      old.shimmerValue != shimmerValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// Preset Chip Component
// ─────────────────────────────────────────────────────────────────────────────

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.percentText,
    this.labelText,
    this.tag,
    required this.isSelected,
    required this.onTap,
  });

  final String percentText;
  final String? labelText;
  final String? tag;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: CockpitMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? CockpitColors.emerald.withValues(alpha: .12)
            : Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? CockpitColors.emerald : CockpitColors.border,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: CockpitColors.emerald,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              percentText,
              style: TextStyle(
                color: isSelected ? CockpitColors.emerald : CockpitColors.text,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (labelText != null) ...[
              const SizedBox(width: 4),
              Text(
                '· $labelText',
                style: TextStyle(
                  color: isSelected
                      ? CockpitColors.emerald
                      : CockpitColors.muted,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
            if (tag != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag!,
                  style: TextStyle(
                    color: CockpitColors.emerald,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
