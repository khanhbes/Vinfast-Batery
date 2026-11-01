import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/luxe_theme.dart';
import '../../../core/theme/plan_style.dart';
import '../../../core/widgets/app_popup.dart';
import '../../../data/services/charge_estimator.dart';
import 'charge_edit_controls.dart';

/// Charge until a clock time (QA 140): the owner picks when the outlet
/// switches off ("Ngắt lúc 09:30"), and the Shelly hardware timer is armed
/// for the time left at the moment of ON. Replaces the 30 phút…6 giờ
/// presets.
class TimedChargingSectionV2 extends StatefulWidget {
  const TimedChargingSectionV2({
    super.key,
    required this.onStart,
    required this.onOff,
    required this.readyForControl,
    this.disabledReason,
    this.onOpenSetup,
    this.clock = DateTime.now,
  });

  /// Called with the chosen end; the caller confirms and sends it.
  final Future<void> Function(DateTime stopAt) onStart;
  final VoidCallback onOff;
  final bool readyForControl;
  final String? disabledReason;

  /// Opens Shelly setup; shown next to the locked CTA so the reason stays
  /// visible after the header text has scrolled away (UX107-01).
  final VoidCallback? onOpenSetup;

  final DateTime Function() clock;

  /// Shortest and longest charge the outlet's timer accepts here.
  static const minLength = Duration(minutes: 5);
  static const maxLength = Duration(hours: 10);

  /// Steps of the − / + buttons.
  static const step = Duration(minutes: 15);

  /// [end] today, or tomorrow when that time has passed.
  static DateTime stopAtFor(TimeOfDay end, DateTime now) {
    final today = DateTime(now.year, now.month, now.day, end.hour, end.minute);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  /// [length] from [now], rounded up to the next 5 minutes.
  static TimeOfDay endAfter(Duration length, DateTime now) {
    final at = now.add(length);
    var minutes = at.hour * 60 + at.minute;
    if (at.second > 0 || at.millisecond > 0 || at.microsecond > 0) minutes++;
    minutes = (minutes + 4) ~/ 5 * 5 % (24 * 60);
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  @override
  State<TimedChargingSectionV2> createState() => _TimedChargingSectionV2State();
}

class _TimedChargingSectionV2State extends State<TimedChargingSectionV2>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  /// Ultra (QA 140): an aurora ring turns round the button while it is
  /// held and while the ON command runs; never at rest.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  void _syncSpin() {
    final on =
        (_pressed || _submitting) &&
        PlanMotion.effectsOf(context) &&
        !MediaQuery.disableAnimationsOf(context);
    if (on && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!on && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  /// The owner's last charge length, kept when the section is rebuilt after
  /// a charge ends and across app starts (QA 130); a new visit offers the
  /// same length from now.
  static int? _lastMinutes;
  static const _prefsKey = 'timed_charge_minutes';
  late TimeOfDay _end = TimedChargingSectionV2.endAfter(
    Duration(minutes: _lastMinutes ?? 120),
    widget.clock(),
  );
  bool _pressed = false;
  bool _submitting = false;

  /// The length shown ("Sạc 2 giờ 30 phút") follows the clock.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_lastMinutes == null) _restoreLength();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _restoreLength() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getInt(_prefsKey);
      if (saved == null || saved < 5 || saved > 600) return;
      _lastMinutes = saved;
      if (mounted) {
        setState(
          () => _end = TimedChargingSectionV2.endAfter(
            Duration(minutes: saved),
            widget.clock(),
          ),
        );
      }
    } on Object {
      // A remembered choice is a convenience only.
    }
  }

  DateTime get _stopAt =>
      TimedChargingSectionV2.stopAtFor(_end, widget.clock());

  Duration get _length => _stopAt.difference(widget.clock());

  bool get _lengthValid =>
      _length >= TimedChargingSectionV2.minLength &&
      _length <= TimedChargingSectionV2.maxLength;

  void _setEnd(TimeOfDay end) {
    setState(() => _end = end);
    final minutes = (_length.inSeconds / 60).round();
    if (minutes < 5 || minutes > 600) return;
    _lastMinutes = minutes;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_prefsKey, minutes))
        .ignore();
  }

  /// − / +: moves the end by [delta], kept within 5 minutes – 10 hours.
  void _shift(Duration delta) {
    final now = widget.clock();
    var at = _stopAt.add(delta);
    final earliest = now.add(TimedChargingSectionV2.minLength);
    final latest = now.add(TimedChargingSectionV2.maxLength);
    if (at.isBefore(earliest)) at = earliest;
    if (at.isAfter(latest)) at = latest;
    HapticFeedback.selectionClick();
    _setEnd(TimeOfDay(hour: at.hour, minute: at.minute));
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _end,
      helpText: 'NGẮT LÚC',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) _setEnd(picked);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPulse();
      if (mounted) setState(() {});
    } else if (_pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant TimedChargingSectionV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    _syncSpin();
    // Pulse only while the command is really in flight; "ready" is a state,
    // not an activity (LUXE motion rule, Task 125).
    if (!MediaQuery.disableAnimationsOf(context) && _submitting) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  Future<void> _start() async {
    if (_submitting || !widget.readyForControl || !_lengthValid) return;
    HapticFeedback.mediumImpact();
    _ripple.forward(from: 0.0);
    setState(() => _submitting = true);
    _syncPulse();
    try {
      await widget.onStart(_stopAt);
    } catch (_) {
      if (mounted) {
        AppPopup.showMessage(
          'Không gửi được lệnh sạc. Kiểm tra kết nối và thử lại.',
          kind: AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _pressed = false;
        });
        _syncPulse();
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _ripple.dispose();
    _spin.dispose();
    super.dispose();
  }

  String get _buttonLabel {
    final length = _length;
    if (length < TimedChargingSectionV2.minLength) {
      return 'Giờ ngắt phải sau bây giờ ít nhất 5 phút';
    }
    if (length > TimedChargingSectionV2.maxLength) {
      return 'Một phiên sạc tối đa 10 giờ';
    }
    return 'Sạc ${formatChargeDuration(length)}';
  }

  @override
  Widget build(BuildContext context) {
    final plan = PlanStyle.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.readyForControl && !_submitting && _lengthValid;
    final reason =
        widget.disabledReason ??
        'Chưa sẵn sàng bật sạc. Hãy kiểm tra thiết lập Shelly.';
    final now = widget.clock();
    final stopAt = _stopAt;
    final tomorrow = stopAt.day != now.day;
    final clock = formatClock(stopAt);

    return Column(
      key: const ValueKey('timed-mode-v2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeGlass(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('NGẮT LÚC', style: LuxeText.eyebrow),
              const SizedBox(height: 6),
              const Text(
                'Chọn giờ ổ Shelly tự tắt. Chạm giờ để chọn, hoặc dùng − / +.',
                style: LuxeText.caption,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  ChargeStepButton(
                    key: const ValueKey('timed-end-minus'),
                    icon: Icons.remove_rounded,
                    label: 'Sớm hơn 15 phút',
                    onTap: _submitting
                        ? null
                        : () => _shift(-TimedChargingSectionV2.step),
                  ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          'Ngắt lúc $clock${tomorrow ? ' ngày mai' : ''}. '
                          'Chạm để chọn giờ khác.',
                      excludeSemantics: true,
                      child: InkWell(
                        key: const ValueKey('timed-end-picker'),
                        onTap: _submitting ? null : _pick,
                        borderRadius: BorderRadius.circular(18),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 72),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  clock,
                                  key: const ValueKey('timed-end-clock'),
                                  style: TextStyle(
                                    color: plan.accent,
                                    fontSize: 44,
                                    height: 1.05,
                                    fontWeight: FontWeight.w300,
                                    letterSpacing: -1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tomorrow ? 'ngày mai' : 'hôm nay',
                                style: LuxeText.caption,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ChargeStepButton(
                    key: const ValueKey('timed-end-plus'),
                    icon: Icons.add_rounded,
                    label: 'Muộn hơn 15 phút',
                    onTap: _submitting
                        ? null
                        : () => _shift(TimedChargingSectionV2.step),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: LuxeColors.muted,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hẹn giờ được nạp thẳng vào ổ cắm Shelly, an toàn độc lập với điện thoại. Đang sạc vẫn đổi được giờ ngắt.',
                      style: TextStyle(
                        color: LuxeColors.muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: SizedBox.square(
            dimension: 176,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _spin,
                  builder: (context, _) => _spin.isAnimating
                      ? CustomPaint(
                          size: const Size.square(176),
                          painter: _AuroraRingPainter(
                            _spin.value,
                            plan.accentColors,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // Two halo rings travelling outward while the command runs.
                if (_submitting && !reduced)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(176),
                      painter: _HaloPainter(_pulse.value, plan.accent),
                    ),
                  ),
                if (!reduced)
                  AnimatedBuilder(
                    animation: _ripple,
                    builder: (context, _) {
                      final t = _ripple.value;
                      if (t == 0 || _ripple.isCompleted) {
                        return const SizedBox.shrink();
                      }
                      return Transform.scale(
                        scale: 0.9 + 0.5 * Curves.easeOutCubic.transform(t),
                        child: Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: plan.accent.withValues(
                                alpha: 0.7 * (1 - t),
                              ),
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('timed-charge-start-button'),
                    onTap: enabled ? _start : null,
                    onHighlightChanged: (pressed) {
                      setState(() => _pressed = pressed);
                      _syncSpin();
                    },
                    customBorder: const CircleBorder(),
                    child: AnimatedScale(
                      scale: _pressed && !reduced ? 0.95 : 1.0,
                      duration: const Duration(milliseconds: 140),
                      child: AnimatedOpacity(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        opacity: enabled ? 1.0 : 0.4,
                        child: Semantics(
                          label: _submitting
                              ? 'Đang bật sạc'
                              : 'Sạc đến $clock. $_buttonLabel',
                          child: _PowerFace(
                            enabled: enabled,
                            colors: plan.accentColors,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _submitting ? 'Đang bật sạc…' : _buttonLabel,
          key: const ValueKey('timed-charge-label'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _lengthValid ? LuxeColors.text : LuxeColors.champagne,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        if (!widget.readyForControl) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              reason,
              key: const ValueKey('timed-charge-locked-reason'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LuxeColors.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          if (widget.onOpenSetup != null)
            Center(
              child: TextButton.icon(
                key: const ValueKey('timed-charge-open-setup'),
                onPressed: widget.onOpenSetup,
                style: TextButton.styleFrom(foregroundColor: plan.accent),
                icon: const Icon(
                  Icons.settings_input_component_rounded,
                  size: 16,
                ),
                label: const Text('Thiết lập Shelly'),
              ),
            ),
        ],
      ],
    );
  }
}

class _PowerFace extends StatelessWidget {
  const _PowerFace({required this.enabled, required this.colors});
  final bool enabled;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 128,
    height: 128,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [LuxeColors.platinumHi, LuxeColors.platinumMid],
      ),
      boxShadow: [
        BoxShadow(
          color: enabled
              ? colors.first.withValues(alpha: 0.35)
              : const Color(0x00000000),
          blurRadius: 30,
        ),
        const BoxShadow(
          color: Color(0x80000000),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.45),
          colors: enabled
              ? [
                  Color.lerp(colors.first, Colors.white, 0.35)!,
                  colors.first,
                  Color.lerp(colors.last, Colors.black, 0.45)!,
                ]
              : const [
                  Color(0xFF2A2C30),
                  LuxeColors.raised,
                  LuxeColors.surface,
                ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 8,
            child: Container(
              width: 66,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(40),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: enabled ? 0.35 : 0.08),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Icon(
            Icons.power_settings_new_rounded,
            size: 46,
            color: enabled ? PlanColors.ink : LuxeColors.dim,
          ),
        ],
      ),
    ),
  );
}

/// Ultra: a turning ring of the plan's aurora just outside the button.
class _AuroraRingPainter extends CustomPainter {
  _AuroraRingPainter(this.t, this.colors);
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: 70);
    final turn = t * 2 * math.pi;
    final shader = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(turn),
    ).createShader(rect);
    canvas.drawCircle(
      c,
      70,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      c,
      70,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = shader,
    );
    // A spark riding the ring.
    final spark = c + Offset(math.cos(turn), math.sin(turn)) * 70;
    canvas.drawCircle(
      spark,
      4,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_AuroraRingPainter old) =>
      old.t != t || !listEquals(old.colors, colors);
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var k = 0; k < 2; k++) {
      final p = (t + k / 2) % 1.0;
      final r = 64 + 24 * Curves.easeOut.transform(p);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(
            alpha: 0.45 * math.sin(p * math.pi) * (1 - p),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.t != t || old.color != color;
}
