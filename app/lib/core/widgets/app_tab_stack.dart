import 'package:flutter/material.dart';
import '../theme/app_motion.dart';

/// Retains tab state and scroll positions; only the selected tab ticks.
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
    duration: AppMotion.base,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant AppTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
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
      final progress = AppMotion.enter.transform(_controller.value);
      return Opacity(
        opacity: .9 + .1 * progress,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - progress)),
          child: child,
        ),
      );
    },
  );
}
