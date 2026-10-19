import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_appearance.dart';
import '../providers/appearance_provider.dart';
import '../theme/luxe_theme.dart';
import 'luxe_slide_to_confirm.dart';

/// The control that switches the charger ON, in the owner's chosen style
/// (QA 131, Cài đặt → Giao diện): slide (default), hold ~1 s, or a single
/// tap. Every style still sits behind the start sheet's acknowledgement or
/// BatteryBot's confirmation card, and the repository checks the backend
/// before any command. Stopping never uses this control.
class ChargeConfirmControl extends StatefulWidget {
  const ChargeConfirmControl({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.lockedLabel,
    this.height = 60,
    this.style,
    this.sliderKey,
  });

  /// Key of the slide control (existing tests and guides find it).
  final Key? sliderKey;

  /// "Vuốt để …" wording; the other styles reword it.
  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final String? lockedLabel;
  final double height;

  /// Overrides the saved choice (tests, previews).
  final ChargeConfirmStyle? style;

  static String reword(String label, ChargeConfirmStyle style) {
    final rest = label.startsWith('Vuốt để ') ? label.substring(8) : label;
    final sentence = rest.isEmpty
        ? rest
        : '${rest[0].toUpperCase()}${rest.substring(1)}';
    return switch (style) {
      ChargeConfirmStyle.slide => label,
      ChargeConfirmStyle.hold => 'Giữ để ${rest.isEmpty ? 'bật sạc' : rest}',
      ChargeConfirmStyle.tap => sentence,
    };
  }

  @override
  State<ChargeConfirmControl> createState() => _ChargeConfirmControlState();
}

class _ChargeConfirmControlState extends State<ChargeConfirmControl> {
  ChargeConfirmStyle _saved = ChargeConfirmStyle.slide;
  ProviderSubscription<ChargeConfirmStyle>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subscription != null) return;
    // Sheets are also built without a ProviderScope (tests): then the
    // default slide applies.
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      _subscription = container.listen<ChargeConfirmStyle>(
        appearanceProvider.select((a) => a.confirm),
        (_, next) {
          if (mounted) setState(() => _saved = next);
        },
        fireImmediately: true,
      );
    } on Object {
      _saved = ChargeConfirmStyle.slide;
    }
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final enabled = widget.enabled;
    final lockedLabel = widget.lockedLabel;
    final height = widget.height;
    final onConfirmed = widget.onConfirmed;
    final chosen = widget.style ?? _saved;
    return switch (chosen) {
      ChargeConfirmStyle.slide => LuxeSlideToConfirm(
        key: widget.sliderKey,
        label: label,
        lockedLabel: lockedLabel,
        enabled: enabled,
        height: height,
        onConfirmed: onConfirmed,
      ),
      ChargeConfirmStyle.hold => LuxeHoldToConfirm(
        label: ChargeConfirmControl.reword(label, chosen),
        lockedLabel: lockedLabel,
        enabled: enabled,
        height: height,
        onConfirmed: onConfirmed,
      ),
      ChargeConfirmStyle.tap => ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: FilledButton.icon(
          key: const ValueKey('charge-confirm-tap'),
          onPressed: enabled
              ? () {
                  HapticFeedback.heavyImpact();
                  onConfirmed();
                }
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: LuxeColors.platinumHi,
            foregroundColor: LuxeColors.background,
            disabledBackgroundColor: LuxeColors.raised,
            disabledForegroundColor: LuxeColors.dim,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
          icon: const Icon(Icons.bolt_rounded),
          label: Text(
            enabled
                ? ChargeConfirmControl.reword(label, chosen)
                : (lockedLabel ?? ChargeConfirmControl.reword(label, chosen)),
            maxLines: 2,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    };
  }
}

/// Press and hold ~1 s: a platinum ring fills around the bolt while the
/// finger stays down; lifting early cancels. The ring only moves while the
/// owner is holding (no idle animation). Screen readers: double tap.
class LuxeHoldToConfirm extends StatefulWidget {
  const LuxeHoldToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.enabled = true,
    this.lockedLabel,
    this.height = 60,
    this.holdFor = const Duration(milliseconds: 1000),
  });

  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final String? lockedLabel;
  final double height;
  final Duration holdFor;

  static const buttonKey = ValueKey('luxe-hold-button');

  @override
  State<LuxeHoldToConfirm> createState() => _LuxeHoldToConfirmState();
}

class _LuxeHoldToConfirmState extends State<LuxeHoldToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: widget.holdFor,
  )..addStatusListener(_onStatus);
  bool _done = false;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _confirm();
  }

  void _confirm() {
    if (_done || !widget.enabled) return;
    _done = true;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
  }

  void _down() {
    if (!widget.enabled || _done) return;
    HapticFeedback.selectionClick();
    _hold.forward(from: _hold.value);
  }

  void _up() {
    if (_done) return;
    _hold.animateBack(0, duration: const Duration(milliseconds: 220));
  }

  @override
  void didUpdateWidget(covariant LuxeHoldToConfirm old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && !_done) _hold.value = 0;
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final text = enabled ? widget.label : (widget.lockedLabel ?? widget.label);
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      onTap: enabled ? _confirm : null,
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) {
            final t = _hold.value;
            return Container(
              key: LuxeHoldToConfirm.buttonKey,
              constraints: BoxConstraints(minHeight: widget.height),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height / 2),
                color: Color.lerp(
                  LuxeColors.glassStrong,
                  LuxeColors.platinumHi.withValues(alpha: 0.18),
                  t,
                ),
                border: Border.all(
                  color: enabled
                      ? LuxeColors.hairlineStrong
                      : LuxeColors.hairline,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: widget.height - 16,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: t,
                            strokeWidth: 3,
                            backgroundColor: LuxeColors.hairline,
                            color: LuxeColors.platinumHi,
                          ),
                        ),
                        Icon(
                          Icons.bolt_rounded,
                          color: enabled
                              ? LuxeColors.platinumHi
                              : LuxeColors.dim,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? LuxeColors.text : LuxeColors.dim,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
