import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium active charging card matching the EV cockpit reference.
/// Shows animated battery bar, countdown, live metrics, and stop button.
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

  @override
  State<ActiveChargingCardV2> createState() => _ActiveChargingCardV2State();
}

class _ActiveChargingCardV2State extends State<ActiveChargingCardV2>
    with SingleTickerProviderStateMixin {
  bool _showDetails = false;
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

  String get _countdownText {
    final h = widget.remaining.inHours.toString().padLeft(2, '0');
    final m = (widget.remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (widget.remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatEnergy(double wh) => wh >= 1000
      ? '${(wh / 1000).toStringAsFixed(2)} kWh'
      : '${wh.toStringAsFixed(0)} Wh';

  String _formatDuration(Duration d) {
    final totalMin = d.inMinutes;
    if (totalMin <= 0) return 'Đã đầy';
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h == 0) return '$m phút';
    if (m == 0) return '$h giờ';
    return '$h giờ $m phút';
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final current = widget.currentPercent.round().clamp(0, 100);
    final target = widget.targetPercent.round().clamp(0, 100);
    final verifiedColor = widget.timerVerified
        ? CockpitColors.emerald
        : CockpitColors.amber;

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CockpitColors.surface,
          borderRadius: BorderRadius.circular(CockpitRadius.large),
          border: Border.all(
            color: CockpitColors.emerald.withValues(
              alpha: .30 + _glowController.value * .20,
            ),
          ),
          boxShadow: reducedMotion
              ? null
              : [
                  BoxShadow(
                    color: CockpitColors.emerald.withValues(
                      alpha: .08 + _glowController.value * .07,
                    ),
                    blurRadius: 32,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: "Đang sạc" badge + target ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: CockpitColors.emerald,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: CockpitColors.emerald.withValues(alpha: .5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ĐANG SẠC',
                    style: TextStyle(
                      color: verifiedColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: CockpitColors.emerald.withValues(alpha: .30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 14,
                      color: CockpitColors.emerald,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mục tiêu $target%',
                      style: CockpitTypography.numbers(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: CockpitColors.emerald,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── SOC display + countdown ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$current%',
                    style: CockpitTypography.numbers(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    widget.timerVerified ? 'Timer Shelly' : 'Ước tính',
                    style: TextStyle(color: CockpitColors.muted, fontSize: 11),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Còn lại',
                    style: TextStyle(color: CockpitColors.muted, fontSize: 11),
                  ),
                  Text(
                    _countdownText,
                    key: const ValueKey('session-countdown'),
                    style: CockpitTypography.numbers(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: CockpitColors.text,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Animated horizontal battery bar ──
          _ChargingBatteryBar(
            currentPercent: current.toDouble(),
            targetPercent: target.toDouble(),
            glowAnimation: _glowController,
          ),

          const SizedBox(height: 16),

          // ── Stats grid ──
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Còn lại',
                  value: _formatDuration(widget.remaining),
                  detail: 'Xong lúc ${widget.completionTime}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Năng lượng phiên',
                  value: _formatEnergy(widget.sessionEnergyWh),
                  detail: 'Công suất ${widget.powerW.toStringAsFixed(0)} W',
                  valueColor: CockpitColors.emerald,
                ),
              ),
            ],
          ),

          // ── Expandable telemetry ──
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: CockpitColors.border)),
            ),
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.show_chart_rounded,
                              size: 16,
                              color: CockpitColors.emerald,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Chi tiết thông số dòng điện',
                              style: TextStyle(
                                color: CockpitColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        AnimatedRotation(
                          turns: _showDetails ? 0.5 : 0,
                          duration: CockpitMotion.standard,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: CockpitColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _TelemetryChip(
                            label: 'Công suất',
                            value: '${widget.powerW.toStringAsFixed(0)} W',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TelemetryChip(
                            label: 'Điện áp / Dòng',
                            value:
                                '${widget.voltageV.toStringAsFixed(0)}V · ${widget.currentA.toStringAsFixed(1)}A',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TelemetryChip(
                            label: 'Nhiệt độ',
                            value: widget.temperatureC != null
                                ? '${widget.temperatureC!.toStringAsFixed(1)}°C'
                                : '—',
                            valueColor: CockpitColors.emerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: _showDetails
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: CockpitMotion.standard,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Stop button ──
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: widget.onStop,
              style: OutlinedButton.styleFrom(
                foregroundColor: CockpitColors.danger,
                side: BorderSide(
                  color: CockpitColors.danger.withValues(alpha: .4),
                ),
                backgroundColor: CockpitColors.danger.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text(
                'Dừng sạc',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ChargingBatteryBar extends StatefulWidget {
  const _ChargingBatteryBar({
    required this.currentPercent,
    required this.targetPercent,
    required this.glowAnimation,
  });

  final double currentPercent;
  final double targetPercent;
  final Animation<double> glowAnimation;

  @override
  State<_ChargingBatteryBar> createState() => _ChargingBatteryBarState();
}

class _ChargingBatteryBarState extends State<_ChargingBatteryBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final clampedCurrent = widget.currentPercent.clamp(0.0, 100.0);
    final clampedTarget = widget.targetPercent.clamp(0.0, 100.0);

    return AnimatedBuilder(
      animation: Listenable.merge([widget.glowAnimation, _flowController]),
      builder: (context, _) {
        final flowPhase = reducedMotion ? 0.0 : _flowController.value;
        final glowVal = widget.glowAnimation.value;

        return Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1412),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CockpitColors.emerald.withValues(
                alpha: .35 + glowVal * .25,
              ),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: CockpitColors.emerald.withValues(alpha: .10 + glowVal * .10),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final currentWidth = (totalWidth * clampedCurrent / 100).clamp(
                0.0,
                totalWidth,
              );
              final targetX = (totalWidth * clampedTarget / 100).clamp(
                0.0,
                totalWidth,
              );

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Battery segment notches (20%, 40%, 60%, 80%) ──
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BatteryNotchesPainter(),
                    ),
                  ),

                  // ── Active fill with energy flow ──
                  if (currentWidth > 0)
                    AnimatedContainer(
                      duration: reducedMotion
                          ? Duration.zero
                          : CockpitMotion.battery,
                      width: currentWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF047857), // Deep emerald
                            Color(0xFF059669),
                            Color(0xFF10B981), // Emerald strong
                            Color(0xFF34D399), // Mint cyan
                          ],
                          stops: [0.0, 0.35, 0.75, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: .40),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: CustomPaint(
                          painter: _EnergyFlowStreamPainter(
                            phase: flowPhase,
                            glowIntensity: glowVal,
                          ),
                        ),
                      ),
                    ),

                  // ── Leading Edge Pulse Spark (head of charging fill) ──
                  if (currentWidth > 2 && currentWidth < totalWidth)
                    Positioned(
                      left: currentWidth - 3,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 6,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: .9),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: const Color(0xFF34D399).withValues(alpha: .8),
                              blurRadius: 12,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Target indicator line & badge ──
                  Positioned(
                    left: (targetX - 1).clamp(0.0, totalWidth - 2),
                    top: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 2.5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: .6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0F0D).withValues(alpha: .92),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '${clampedTarget.round()}%',
                            style: CockpitTypography.numbers(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          width: 2.5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: .6),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _BatteryNotchesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .12)
      ..strokeWidth = 1.0;

    for (final fraction in [0.25, 0.50, 0.75]) {
      final x = size.width * fraction;
      canvas.drawLine(Offset(x, 4), Offset(x, 10), paint);
      canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height - 4), paint);
    }
  }

  @override
  bool shouldRepaint(_BatteryNotchesPainter oldDelegate) => false;
}

class _EnergyFlowStreamPainter extends CustomPainter {
  const _EnergyFlowStreamPainter({
    required this.phase,
    required this.glowIntensity,
  });

  final double phase;
  final double glowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Diagonal flowing shimmer rays
    final rayWidth = size.height * 1.5;
    final cycleDistance = size.width + rayWidth * 2;
    final currentOffset = -rayWidth + cycleDistance * phase;

    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: .10),
          Colors.white.withValues(alpha: .38 + glowIntensity * .20),
          Colors.white.withValues(alpha: .10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
      ).createShader(
        Rect.fromLTWH(currentOffset, 0, rayWidth, size.height),
      );

    canvas.drawRect(Offset.zero & size, shimmerPaint);

    // Subtle floating energy micro-particles
    final particlePaint = Paint()..color = Colors.white.withValues(alpha: .55);
    final p1X = ((phase * 1.3) % 1.0) * size.width;
    final p2X = (((phase + 0.45) * 1.1) % 1.0) * size.width;
    final p3X = (((phase + 0.8) * 1.2) % 1.0) * size.width;

    canvas.drawCircle(Offset(p1X, size.height * 0.35), 1.5, particlePaint);
    canvas.drawCircle(Offset(p2X, size.height * 0.68), 1.8, particlePaint);
    canvas.drawCircle(Offset(p3X, size.height * 0.22), 1.2, particlePaint);
  }

  @override
  bool shouldRepaint(_EnergyFlowStreamPainter old) =>
      old.phase != phase || old.glowIntensity != glowIntensity;
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: CockpitColors.elevated,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CockpitColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: CockpitColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: CockpitTypography.numbers(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? CockpitColors.text,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            style: TextStyle(color: CockpitColors.dim, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    ),
  );
}

class _TelemetryChip extends StatelessWidget {
  const _TelemetryChip({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .04),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: CockpitColors.border),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(color: CockpitColors.dim, fontSize: 9),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: CockpitTypography.numbers(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: valueColor ?? CockpitColors.text,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}
