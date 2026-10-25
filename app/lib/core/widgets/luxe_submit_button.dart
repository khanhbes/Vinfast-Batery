import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';

/// The one "save / send" button (QA 135): label → spinner while the work
/// runs → an emerald tick, so the owner always sees that the input was
/// taken. [onPressed] returns whether it succeeded; a failure goes back to
/// the label (the caller shows the reason). Taps are ignored while busy, so
/// a slow network never sends twice.
class LuxeSubmitButton extends StatefulWidget {
  const LuxeSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busyLabel,
    this.doneLabel = 'Đã lưu',
    this.icon,
    this.outlined = false,
    this.expand = true,
    this.onBusyChanged,
  });

  final String label;
  final String? busyLabel;
  final String doneLabel;
  final IconData? icon;
  final bool outlined;
  final bool expand;

  /// Null disables the button.
  final Future<bool> Function()? onPressed;

  /// Lets a form lock its fields while the request runs.
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<LuxeSubmitButton> createState() => _LuxeSubmitButtonState();
}

enum _Phase { idle, busy, done }

class _LuxeSubmitButtonState extends State<LuxeSubmitButton> {
  _Phase _phase = _Phase.idle;

  Future<void> _run() async {
    final action = widget.onPressed;
    if (action == null || _phase != _Phase.idle) return;
    HapticFeedback.selectionClick();
    setState(() => _phase = _Phase.busy);
    widget.onBusyChanged?.call(true);
    var ok = false;
    try {
      ok = await action();
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    widget.onBusyChanged?.call(false);
    if (!ok) {
      setState(() => _phase = _Phase.idle);
      return;
    }
    // The action closed this sheet/page itself: nothing left to show.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    HapticFeedback.lightImpact();
    setState(() => _phase = _Phase.done);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = luxeReduceMotion(context);
    final busy = _phase == _Phase.busy;
    final done = _phase == _Phase.done;
    final Widget content = switch (_phase) {
      _Phase.busy => Row(
        key: const ValueKey('submit-busy'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              // Still a progress cue when animations are off.
              value: reduce ? 0.7 : null,
              color: widget.outlined ? LuxeColors.text : LuxeColors.background,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.busyLabel ?? 'Đang gửi…',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      _Phase.done => Row(
        key: const ValueKey('submit-done'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.doneLabel, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      _Phase.idle => Row(
        key: const ValueKey('submit-idle'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    };
    final child = AnimatedSwitcher(
      duration: luxeDuration(context, 220),
      child: content,
    );
    final onPressed = widget.onPressed == null
        ? null
        : (busy || done ? () {} : _run);
    final style = done
        ? ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(LuxeColors.emerald),
            foregroundColor: const WidgetStatePropertyAll(
              LuxeColors.background,
            ),
            side: widget.outlined
                ? const WidgetStatePropertyAll(
                    BorderSide(color: LuxeColors.emerald),
                  )
                : null,
          )
        : null;
    final button = widget.outlined
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : FilledButton(onPressed: onPressed, style: style, child: child);
    return Semantics(
      liveRegion: true,
      label: busy
          ? widget.busyLabel ?? 'Đang gửi'
          : (done ? widget.doneLabel : null),
      child: widget.expand
          ? SizedBox(width: double.infinity, child: button)
          : button,
    );
  }
}
