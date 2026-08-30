import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Mức muốn sạc', style: theme.textTheme.titleMedium),
              Text(
                '${widget.value.round()}%',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final bodyWidth = constraints.maxWidth - 14;
              void update(Offset local) => _set(local.dx / bodyWidth * 100);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (event) => update(event.localPosition),
                onHorizontalDragUpdate: (event) => update(event.localPosition),
                child: SizedBox(
                  height: 72,
                  child: CustomPaint(
                    painter: _BatteryTargetPainter(
                      value: widget.value,
                      currentSoc: widget.currentSoc,
                      fill: colors.primary,
                      currentFill: colors.primary.withValues(alpha: 0.34),
                      track: colors.surfaceContainerHighest,
                      outline: colors.outlineVariant,
                    ),
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
                    padding: EdgeInsets.only(right: preset == 100 ? 0 : 8),
                    child: SizedBox(
                      height: 48,
                      child: FilterChip(
                        label: Center(child: Text('$preset%')),
                        selected: widget.value.round() == preset,
                        onSelected: preset >= _minimum
                            ? (_) => _set(preset.toDouble())
                            : null,
                      ),
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

class _BatteryTargetPainter extends CustomPainter {
  const _BatteryTargetPainter({
    required this.value,
    required this.currentSoc,
    required this.fill,
    required this.currentFill,
    required this.track,
    required this.outline,
  });

  final double value;
  final double currentSoc;
  final Color fill;
  final Color currentFill;
  final Color track;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 5, size.width - 14, size.height - 10),
      const Radius.circular(18),
    );
    canvas.drawRRect(body, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(body.deflate(4));
    final inner = body.deflate(4).outerRect;
    canvas.drawRect(
      Rect.fromLTWH(0, inner.top, inner.width * currentSoc / 100, inner.height),
      Paint()..color = currentFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, inner.top, inner.width * value / 100, inner.height),
      Paint()..color = fill,
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
          size.width - 12,
          size.height * .30,
          12,
          size.height * .40,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = outline,
    );
  }

  @override
  bool shouldRepaint(_BatteryTargetPainter old) =>
      old.value != value ||
      old.currentSoc != currentSoc ||
      old.fill != fill ||
      old.track != track;
}
