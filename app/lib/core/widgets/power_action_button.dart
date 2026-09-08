import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Prominent charging action. Animations never delay or repeat the callback.
class PowerActionButton extends StatefulWidget {
  const PowerActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.stopping = false,
  });
  final VoidCallback? onPressed;
  final String label;
  final bool stopping;

  @override
  State<PowerActionButton> createState() => _PowerActionButtonState();
}

class _PowerActionButtonState extends State<PowerActionButton> {
  final _states = WidgetStatesController();
  bool _pressed = false;
  @override
  void initState() {
    super.initState();
    _states.addListener(_onStatesChanged);
  }

  void _onStatesChanged() {
    void update() {
      if (!mounted) return;
      final pressed = _states.value.contains(WidgetState.pressed);
      if (_pressed != pressed) setState(() => _pressed = pressed);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: !reduced && _pressed ? .98 : 1,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: FilledButton.icon(
        statesController: _states,
        onPressed: widget.stopping ? null : widget.onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        icon: const Icon(Icons.power_settings_new_rounded),
        label: Text(
          widget.stopping ? 'Đang ngắt nguồn…' : widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    );
  }
}
