import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/luxe_theme.dart';

/// Primary AI action: a wide brushed-platinum pill with a slow light sweep
/// and a sparkle that breathes. [emphasis] marks the final "start" step.
class AIChargeButton extends StatefulWidget {
  const AIChargeButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.enabled = true,
    this.emphasis = false,
    this.busy = false,
  });

  final VoidCallback onPressed;
  final String label;
  final bool enabled;
  final bool emphasis;
  final bool busy;

  @override
  State<AIChargeButton> createState() => _AIChargeButtonState();
}

class _AIChargeButtonState extends State<AIChargeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AIChargeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.enabled && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_sheen.isAnimating) {
      _sheen.repeat();
    } else if (!animate && _sheen.isAnimating) {
      _sheen.stop();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !widget.busy;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.mediumImpact();
                widget.onPressed();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed && !reduced ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedBuilder(
            animation: _sheen,
            builder: (context, _) {
              final t = _sheen.value;
              final sparkle = 0.6 + 0.4 * math.sin(t * 2 * math.pi);
              return Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: enabled
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            LuxeColors.platinumHi,
                            LuxeColors.platinum,
                            Color(0xFFB4B7BC),
                          ],
                        )
                      : null,
                  color: enabled ? null : LuxeColors.glass,
                  border: Border.all(
                    color: widget.emphasis && enabled
                        ? LuxeColors.emerald
                        : enabled
                        ? const Color(0x66FFFFFF)
                        : LuxeColors.hairline,
                    width: widget.emphasis && enabled ? 1.5 : 1,
                  ),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color:
                                (widget.emphasis
                                        ? LuxeColors.emerald
                                        : Colors.white)
                                    .withValues(
                                      alpha: widget.emphasis ? 0.35 : 0.16,
                                    ),
                            blurRadius: 24,
                            spreadRadius: -4,
                          ),
                        ]
                      : null,
                ),
                foregroundDecoration: enabled && !reduced
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: LinearGradient(
                          begin: Alignment(-1.6 + 3.2 * t, -0.4),
                          end: Alignment(-0.9 + 3.2 * t, 0.4),
                          colors: const [
                            Color(0x00FFFFFF),
                            Color(0x8CFFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      )
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF2A2C30),
                        ),
                      )
                    else
                      Opacity(
                        opacity: enabled ? sparkle : 0.5,
                        child: Icon(
                          widget.emphasis
                              ? Icons.bolt_rounded
                              : Icons.auto_awesome_rounded,
                          size: 20,
                          color: enabled
                              ? (widget.emphasis
                                    ? LuxeColors.emeraldDeep
                                    : const Color(0xFF1D1F22))
                              : LuxeColors.dim,
                        ),
                      ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: enabled
                              ? const Color(0xFF0B0C0E)
                              : LuxeColors.dim,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
