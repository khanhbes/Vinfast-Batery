import 'package:flutter/material.dart';

import '../../../core/theme/cockpit_design_system.dart';

class ChargingBatteryAnimationV3 extends StatefulWidget {
  const ChargingBatteryAnimationV3({
    super.key,
    required this.currentSoc,
    required this.targetSoc,
    required this.sampleRevision,
  });

  final double currentSoc;
  final double targetSoc;
  final int sampleRevision;

  @override
  State<ChargingBatteryAnimationV3> createState() =>
      _ChargingBatteryAnimationV3State();
}

class _ChargingBatteryAnimationV3State extends State<ChargingBatteryAnimationV3>
    with SingleTickerProviderStateMixin {
  late double _beginSoc;
  late double _endSoc;
  late final AnimationController _energyWave;

  @override
  void initState() {
    super.initState();
    _beginSoc = widget.currentSoc.clamp(0, 100).toDouble();
    _endSoc = _beginSoc;
    _energyWave = AnimationController(
      vsync: this,
      duration: CockpitMotion.energyWave,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CockpitMotion.enabled(context)) {
      if (!_energyWave.isAnimating) _energyWave.repeat();
    } else {
      _energyWave.stop();
      _energyWave.value = 0;
    }
  }

  @override
  void dispose() {
    _energyWave.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChargingBatteryAnimationV3 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sampleRevision != widget.sampleRevision) {
      _beginSoc = _endSoc;
      _endSoc = widget.currentSoc.clamp(0, 100).toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Pin ước tính ${widget.currentSoc.round()} phần trăm, mục tiêu ${widget.targetSoc.round()} phần trăm',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: _beginSoc, end: _endSoc),
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Column(
          children: [
            SizedBox(
              height: 112,
              child: Stack(
                children: [
                  Positioned.fill(
                    right: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: colors.outlineVariant,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 36,
                    bottom: 36,
                    width: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    right: 20,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AnimatedBuilder(
                        animation: _energyWave,
                        builder: (context, _) => ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: value / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(
                                    -1.8 + (_energyWave.value * 2.8),
                                    0,
                                  ),
                                  end: Alignment(
                                    -.2 + (_energyWave.value * 2.8),
                                    0,
                                  ),
                                  colors: [
                                    colors.primary,
                                    CockpitColors.emerald,
                                    Colors.white.withValues(alpha: .62),
                                    CockpitColors.emeraldStrong,
                                    colors.primary,
                                  ],
                                  stops: const [0, .30, .50, .70, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${value.round()}%',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: value >= 55
                                ? colors.onPrimary
                                : colors.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Mục tiêu ${widget.targetSoc.round()}%',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'Pin ước tính từ dữ liệu phiên sạc',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
