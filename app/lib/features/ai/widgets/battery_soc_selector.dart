import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BatterySocSelector extends StatelessWidget {
  const BatterySocSelector({
    super.key,
    required this.value,
    required this.minimum,
    required this.onChanged,
    this.estimated = true,
  });

  final double value;
  final double minimum;
  final ValueChanged<double> onChanged;
  final bool estimated;

  void _set(double raw) {
    final next = raw.round().clamp(minimum.ceil(), 100).toDouble();
    if (next == value.roundToDouble()) return;
    HapticFeedback.selectionClick();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Mức pin mục tiêu',
      value: '${estimated ? 'ước tính ' : ''}${value.round()} phần trăm',
      increasedValue: '${(value + 1).clamp(minimum, 100).round()} phần trăm',
      decreasedValue: '${(value - 1).clamp(minimum, 100).round()} phần trăm',
      onIncrease: () => _set(value + 1),
      onDecrease: () => _set(value - 1),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(220.0, 360.0);
              const height = 118.0;
              void update(Offset local) =>
                  _set((local.dx / width * 100).clamp(minimum, 100));
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (event) => update(event.localPosition),
                onHorizontalDragUpdate: (event) => update(event.localPosition),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned.fill(
                        right: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: colors.outlineVariant,
                              width: 2,
                            ),
                            color: colors.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        width: 12,
                        height: 42,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.outlineVariant,
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(6),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        right: 16,
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: value / 100,
                              child: Container(
                                width: width,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        right: 12,
                        child: Center(
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
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final preset in const [80, 90, 100])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Center(child: Text('$preset%')),
                      selected: value.round() == preset,
                      onSelected: preset > minimum
                          ? (_) => _set(preset.toDouble())
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChargingBatteryAnimation extends StatelessWidget {
  const ChargingBatteryAnimation({
    super.key,
    required this.startSoc,
    required this.targetSoc,
    required this.progress,
  });
  final double startSoc;
  final double targetSoc;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final disable = MediaQuery.disableAnimationsOf(context);
    final estimated = (startSoc + (targetSoc - startSoc) * progress.clamp(0, 1))
        .clamp(0, 100);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: estimated.toDouble()),
      duration: disable ? Duration.zero : const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final colors = Theme.of(context).colorScheme;
        return Semantics(
          label:
              'Pin ước tính ${value.round()} phần trăm, mục tiêu ${targetSoc.round()} phần trăm',
          child: Column(
            children: [
              SizedBox(
                height: 92,
                child: Stack(
                  children: [
                    Positioned.fill(
                      right: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: colors.outlineVariant,
                            width: 2,
                          ),
                          color: colors.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 28,
                      bottom: 28,
                      width: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      right: 18,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: value / 100,
                            child: Container(color: colors.primary),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mục tiêu ${targetSoc.round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'Pin ước tính ${value.round()}% · Không phải dữ liệu BMS',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
