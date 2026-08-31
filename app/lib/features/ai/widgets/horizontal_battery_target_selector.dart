import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';

class HorizontalBatteryTargetSelector extends StatefulWidget {
  const HorizontalBatteryTargetSelector({
    super.key,
    required this.value,
    required this.currentSoc,
    required this.onChanged,
  });

  final double value;
  final double currentSoc;
  final ValueChanged<double> onChanged;

  @override
  State<HorizontalBatteryTargetSelector> createState() =>
      _HorizontalBatteryTargetSelectorState();
}

class _HorizontalBatteryTargetSelectorState
    extends State<HorizontalBatteryTargetSelector> {
  int? _lastHapticStep;

  double get _minimum =>
      (widget.currentSoc.ceil() + 1).clamp(1, 100).toDouble();

  void _set(double raw) {
    final next = raw.round().clamp(_minimum.round(), 100).toDouble();
    if (next == widget.value.roundToDouble()) return;
    final step = next ~/ 5;
    if (_lastHapticStep != step) {
      _lastHapticStep = step;
      HapticFeedback.selectionClick();
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final selectedPreset = const [80, 90, 100].contains(widget.value.round())
        ? <int>{widget.value.round()}
        : <int>{};
    return Semantics(
      label: 'Mức pin muốn sạc',
      value: '${widget.value.round()} phần trăm',
      increasedValue:
          '${(widget.value + 1).clamp(_minimum, 100).round()} phần trăm',
      decreasedValue:
          '${(widget.value - 1).clamp(_minimum, 100).round()} phần trăm',
      onIncrease: () => _set(widget.value + 1),
      onDecrease: () => _set(widget.value - 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.onSurfaceVariant.withValues(alpha: .55),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Hiện tại ~${widget.currentSoc.round()}%',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('Mục tiêu ', style: theme.textTheme.labelLarge),
              Text(
                '${widget.value.round()}%',
                key: const ValueKey('battery-target-value'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final bodyWidth = (constraints.maxWidth - 16).clamp(
                1.0,
                double.infinity,
              );
              void update(Offset local) =>
                  _set((local.dx / bodyWidth).clamp(0.0, 1.0) * 100);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (event) => update(event.localPosition),
                onHorizontalDragUpdate: (event) => update(event.localPosition),
                child: SizedBox(
                  height: 86,
                  child: TweenAnimationBuilder<double>(
                    duration: reducedMotion
                        ? Duration.zero
                        : CockpitMotion.battery,
                    curve: Curves.easeOutCubic,
                    tween: Tween<double>(end: widget.value),
                    builder: (context, animatedValue, _) => CustomPaint(
                      painter: _BatteryTargetPainter(
                        value: animatedValue,
                        currentSoc: widget.currentSoc,
                        fill: colors.primary,
                        currentFill: colors.primary.withValues(alpha: 0.22),
                        track: colors.surfaceContainerHighest,
                        outline: colors.outlineVariant,
                        marker: colors.onSurfaceVariant,
                        surface: colors.surface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                for (final preset in const [80, 90, 100]) ...[
                  if (preset != 80)
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: colors.outlineVariant,
                    ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: selectedPreset.contains(preset),
                      enabled: preset >= _minimum,
                      label: 'Chọn mục tiêu $preset phần trăm',
                      child: InkWell(
                        onTap: preset >= _minimum
                            ? () => _set(preset.toDouble())
                            : null,
                        child: AnimatedContainer(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          alignment: Alignment.center,
                          color: selectedPreset.contains(preset)
                              ? colors.primary
                              : Colors.transparent,
                          child: Text(
                            '$preset%',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: selectedPreset.contains(preset)
                                  ? colors.onPrimary
                                  : preset >= _minimum
                                  ? colors.onSurface
                                  : colors.onSurface.withValues(alpha: .35),
                              fontWeight: selectedPreset.contains(preset)
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: 'Giảm 1%',
                onPressed: widget.value > _minimum
                    ? () => _set(widget.value - 1)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Chạm hoặc kéo trên pin · bước 1%',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                tooltip: 'Tăng 1%',
                onPressed: widget.value < 100
                    ? () => _set(widget.value + 1)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatteryTargetPainter extends CustomPainter {
  const _BatteryTargetPainter({
    required this.value,
    required this.currentSoc,
    required this.fill,
    required this.currentFill,
    required this.track,
    required this.outline,
    required this.marker,
    required this.surface,
  });

  final double value;
  final double currentSoc;
  final Color fill;
  final Color currentFill;
  final Color track;
  final Color outline;
  final Color marker;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    const terminalWidth = 12.0;
    const terminalGap = 4.0;
    final bodyWidth = size.width - terminalWidth - terminalGap;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 7, bodyWidth, size.height - 14),
      const Radius.circular(20),
    );
    canvas.drawRRect(body, Paint()..color = track);

    final innerBody = body.deflate(5);
    canvas.save();
    canvas.clipRRect(innerBody);
    final inner = innerBody.outerRect;
    canvas.drawRect(
      Rect.fromLTWH(
        inner.left,
        inner.top,
        inner.width * currentSoc.clamp(0, 100) / 100,
        inner.height,
      ),
      Paint()..color = currentFill,
    );
    final currentWidth = inner.width * currentSoc.clamp(0, 100) / 100;
    final targetWidth = inner.width * value.clamp(0, 100) / 100;
    canvas.drawRect(
      Rect.fromLTWH(
        inner.left + currentWidth,
        inner.top,
        (targetWidth - currentWidth).clamp(0, inner.width),
        inner.height,
      ),
      Paint()..color = fill,
    );
    final shine = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: .18), Colors.transparent],
      ).createShader(inner);
    canvas.drawRect(
      Rect.fromLTWH(inner.left, inner.top, inner.width, inner.height * .48),
      shine,
    );
    canvas.restore();

    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bodyWidth + terminalGap,
          size.height * .30,
          terminalWidth,
          size.height * .40,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = outline,
    );

    final currentX =
        inner.left + inner.width * currentSoc.clamp(0, 100).toDouble() / 100;
    canvas.drawLine(
      Offset(currentX, inner.top + 5),
      Offset(currentX, inner.bottom - 5),
      Paint()
        ..color = marker.withValues(alpha: .72)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    final targetX =
        inner.left + inner.width * value.clamp(0, 100).toDouble() / 100;
    canvas.drawCircle(
      Offset(targetX, size.height / 2),
      9,
      Paint()..color = surface,
    );
    canvas.drawCircle(
      Offset(targetX, size.height / 2),
      7,
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_BatteryTargetPainter old) =>
      old.value != value ||
      old.currentSoc != currentSoc ||
      old.fill != fill ||
      old.track != track ||
      old.outline != outline ||
      old.marker != marker ||
      old.surface != surface;
}
