import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/luxe_theme.dart';

/// Slide-to-confirm for energizing actions: the platinum knob must travel the
/// whole track, so a stray tap can never switch a relay ON. Releasing early
/// springs back. Screen-reader users activate it with a double tap (the
/// slide gesture is not available to them). No looping animation.
class LuxeSlideToConfirm extends StatefulWidget {
  const LuxeSlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.lockedLabel,
    this.icon = Icons.bolt_rounded,
    this.height = 60,
  });

  final String label;

  /// Shown instead of [label] while disabled (e.g. "tick the box first").
  final String? lockedLabel;
  final VoidCallback onConfirmed;
  final bool enabled;
  final IconData icon;
  final double height;

  static const knobKey = ValueKey('luxe-slide-knob');

  @override
  State<LuxeSlideToConfirm> createState() => _LuxeSlideToConfirmState();
}

class _LuxeSlideToConfirmState extends State<LuxeSlideToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pos = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  double _travel = 1;
  bool _done = false;
  bool _crossedHalf = false;

  @override
  void didUpdateWidget(covariant LuxeSlideToConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pos.value > 0 && !_done) _springBack();
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  void _springBack() {
    _crossedHalf = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pos.value = 0;
    } else {
      _pos.animateBack(0, curve: Curves.easeOutBack);
    }
  }

  void _confirm() {
    if (_done || !widget.enabled) return;
    _done = true;
    HapticFeedback.heavyImpact();
    _pos.animateTo(1, duration: const Duration(milliseconds: 140));
    widget.onConfirmed();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled || _done) return;
    _pos.value = (_pos.value + d.delta.dx / _travel).clamp(0.0, 1.0);
    if (!_crossedHalf && _pos.value > 0.5) {
      _crossedHalf = true;
      HapticFeedback.selectionClick();
    }
  }

  void _onEnd(DragEndDetails d) {
    if (!widget.enabled || _done) return;
    final flung = (d.primaryVelocity ?? 0) > 1400 && _pos.value > 0.6;
    if (_pos.value >= 0.92 || flung) {
      _confirm();
    } else {
      _springBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final knob = h - 8;
    final enabled = widget.enabled;
    final text = enabled ? widget.label : (widget.lockedLabel ?? widget.label);
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      hint: enabled ? 'Vuốt sang phải, hoặc chạm đúp để xác nhận' : null,
      onTap: enabled ? _confirm : null,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          _travel = (box.maxWidth - knob - 8).clamp(1.0, double.infinity);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            child: AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final t = _pos.value;
                return Container(
                  height: h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(h / 2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF151619), Color(0xFF0B0C0E)],
                    ),
                    border: Border.all(
                      color: enabled
                          ? Color.lerp(
                              LuxeColors.hairlineStrong,
                              LuxeColors.emerald,
                              t,
                            )!
                          : LuxeColors.hairline,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Emerald trail behind the knob.
                      Positioned(
                        left: 4,
                        top: 4,
                        bottom: 4,
                        width: knob + _travel * t,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(knob / 2),
                            gradient: LinearGradient(
                              colors: [
                                LuxeColors.emerald.withValues(alpha: 0.0),
                                LuxeColors.emerald.withValues(
                                  alpha: 0.28 * t + 0.04,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(left: knob + 14, right: 18),
                          child: Center(
                            child: Opacity(
                              opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: enabled
                                            ? LuxeColors.platinum
                                            : LuxeColors.dim,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  if (enabled) ...[
                                    const SizedBox(width: 8),
                                    for (var i = 0; i < 3; i++)
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 16,
                                        color: LuxeColors.platinumMid
                                            .withValues(alpha: 0.35 + 0.2 * i),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 4 + _travel * t,
                        top: 4,
                        child: Container(
                          key: LuxeSlideToConfirm.knobKey,
                          width: knob,
                          height: knob,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: enabled
                                ? const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      LuxeColors.platinumHi,
                                      LuxeColors.platinum,
                                      Color(0xFFB9BCC1),
                                    ],
                                  )
                                : null,
                            color: enabled ? null : const Color(0xFF1D1F22),
                            boxShadow: enabled
                                ? [
                                    BoxShadow(
                                      color: LuxeColors.emerald.withValues(
                                        alpha: 0.15 + 0.35 * t,
                                      ),
                                      blurRadius: 14 + 10 * t,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            enabled ? widget.icon : Icons.lock_outline_rounded,
                            size: knob * 0.44,
                            color: enabled
                                ? Color.lerp(
                                    const Color(0xFF0B0C0E),
                                    LuxeColors.emeraldDeep,
                                    t,
                                  )
                                : LuxeColors.dim,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
