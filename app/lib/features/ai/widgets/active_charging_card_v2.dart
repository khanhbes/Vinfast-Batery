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

class _ChargingBatteryBar extends StatelessWidget {
  const _ChargingBatteryBar({
    required this.currentPercent,
    required this.targetPercent,
    required this.glowAnimation,
  });

  final double currentPercent;
  final double targetPercent;
  final Animation<double> glowAnimation;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: glowAnimation,
      builder: (context, _) => Container(
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CockpitColors.emerald.withValues(
              alpha: .3 + glowAnimation.value * .15,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final currentWidth = width * currentPercent.clamp(0, 100) / 100;
            final targetX = width * targetPercent.clamp(0, 100) / 100;

            return Stack(
              children: [
                // Current fill
                AnimatedContainer(
                  duration: reducedMotion
                      ? Duration.zero
                      : CockpitMotion.battery,
                  width: currentWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF059669),
                        CockpitColors.emeraldStrong,
                        CockpitColors.emerald,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CockpitColors.emerald.withValues(alpha: .20),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  // Energy wave overlay
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      painter: _EnergyWavePainter(phase: glowAnimation.value),
                    ),
                  ),
                ),

                // Target indicator line
                Positioned(
                  left: targetX - 1,
                  top: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 2,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${targetPercent.round()}%',
                          style: CockpitTypography.numbers(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EnergyWavePainter extends CustomPainter {
  const _EnergyWavePainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1 + phase * 3, 0),
        end: Alignment(-0.5 + phase * 3, 0),
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: .22),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_EnergyWavePainter old) => old.phase != phase;
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
