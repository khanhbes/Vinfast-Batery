import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/luxe_theme.dart';

/// Retains tab state and scroll positions; only the selected tab ticks.
/// Switching plays a LUXE shared-axis entrance: the new tab fades up from
/// the side it lives on (right when moving forward, left when moving back).
/// The charging overlay should stay outside this visual transition.
class AppTabStack extends StatefulWidget {
  const AppTabStack({super.key, required this.index, required this.children})
    : assert(index >= 0 && index < children.length);

  final int index;
  final List<Widget> children;

  @override
  State<AppTabStack> createState() => _AppTabStackState();
}

class _AppTabStackState extends State<AppTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  /// +1 when the new tab sits to the right of the old one, -1 otherwise.
  double _direction = 1;

  @override
  void didUpdateWidget(covariant AppTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
      if (AppMotion.enabled(context)) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.enabled(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          TickerMode(enabled: i == widget.index, child: widget.children[i]),
      ],
    ),
    builder: (context, child) {
      final progress = LuxeMotion.enter.transform(_controller.value);
      return Opacity(
        opacity: .55 + .45 * progress,
        child: Transform.translate(
          offset: Offset(18 * _direction * (1 - progress), 0),
          child: child,
        ),
      );
    },
  );
}
