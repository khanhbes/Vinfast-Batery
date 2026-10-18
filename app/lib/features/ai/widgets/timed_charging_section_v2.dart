import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/luxe_theme.dart';

/// Timed charging: six duration presets on glass and a platinum power
/// button with an emerald core. Every choice arms the Shelly hardware timer.
class TimedChargingSectionV2 extends StatefulWidget {
  const TimedChargingSectionV2({
    super.key,
    required this.onStart,
    required this.onOff,
    required this.readyForControl,
    this.disabledReason,
    this.onOpenSetup,
  });

  final Future<void> Function(Duration duration) onStart;
  final VoidCallback onOff;
  final bool readyForControl;
  final String? disabledReason;

  /// Opens Shelly setup; shown next to the locked CTA so the reason stays
  /// visible after the header text has scrolled away (UX107-01).
  final VoidCallback? onOpenSetup;

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
  /// The owner's last choice, kept when the section is rebuilt after a
  /// charge ends and across app starts (QA 130: 30 phút reset to 2 giờ).
  static int? _lastSelectedMinutes;
  static const _prefsKey = 'timed_charge_minutes';
  int _selectedMinutes = _lastSelectedMinutes ?? 120;
  bool _pressed = false;
  bool _submitting = false;

  static const _presets = [
    // `-1` is a UI-only "start now" choice. It is deliberately translated
    // to the six-hour device safety timer below; no relay ON is unbounded.
    (minutes: -1, label: 'Ngay lập tức'),
    (minutes: 30, label: '30 phút'),
    (minutes: 60, label: '1 giờ'),
    (minutes: 120, label: '2 giờ'),
    (minutes: 240, label: '4 giờ'),
    (minutes: 360, label: '6 giờ'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_lastSelectedMinutes == null) _restoreSelection();
  }

  Future<void> _restoreSelection() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getInt(_prefsKey);
      if (saved == null || !_presets.any((p) => p.minutes == saved)) return;
      _lastSelectedMinutes = saved;
      if (mounted) setState(() => _selectedMinutes = saved);
    } on Object {
      // A remembered choice is a convenience only.
    }
  }

  void _select(int minutes) {
    _lastSelectedMinutes = minutes;
    setState(() => _selectedMinutes = minutes);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_prefsKey, minutes))
        .ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPulse();
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
    // Pulse only while the command is really in flight; "ready" is a state,
    // not an activity (LUXE motion rule, Task 125).
    if (!MediaQuery.disableAnimationsOf(context) && _submitting) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  Future<void> _start() async {
    if (_submitting || !widget.readyForControl) return;
    HapticFeedback.mediumImpact();
    _ripple.forward(from: 0.0);
    setState(() => _submitting = true);
    _syncPulse();
    try {
      await widget.onStart(
        _selectedMinutes == -1
            ? const Duration(hours: 6)
            : Duration(minutes: _selectedMinutes),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không gửi được lệnh sạc. Kiểm tra kết nối và thử lại.',
            ),
          ),
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
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _ripple.dispose();
    super.dispose();
  }

  String get _buttonLabel {
    if (_selectedMinutes == -1) return 'Bắt đầu ngay · tự ngắt sau 6 giờ';
    final h = _selectedMinutes ~/ 60;
    final m = _selectedMinutes % 60;
    if (h > 0 && m > 0) return 'Sạc $h giờ $m phút';
    if (h > 0) return 'Sạc $h giờ';
    return 'Sạc $m phút';
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.readyForControl && !_submitting;
    final reason =
        widget.disabledReason ??
        'Chưa sẵn sàng bật sạc. Hãy kiểm tra thiết lập Shelly.';

    return Column(
      key: const ValueKey('timed-mode-v2'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeGlass(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('THỜI GIAN HẸN GIỜ', style: LuxeText.eyebrow),
              const SizedBox(height: 6),
              const Text(
                'Bộ sạc tự ngắt bằng bộ đếm giờ phần cứng sau thời gian đã chọn.',
                style: LuxeText.caption,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final perRow = constraints.maxWidth < 300 || scale > 1.3
                      ? 2
                      : 3;
                  final w = (constraints.maxWidth - 8 * (perRow - 1)) / perRow;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in _presets)
                        SizedBox(
                          width: w,
                          child: _PresetTile(
                            key: ValueKey('timed-preset-${preset.minutes}'),
                            label: preset.label,
                            selected: _selectedMinutes == preset.minutes,
                            onTap: () {
                              _select(preset.minutes);
                              HapticFeedback.selectionClick();
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: LuxeColors.emerald,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hẹn giờ được nạp thẳng vào ổ cắm Shelly, an toàn độc lập với điện thoại.',
                      style: TextStyle(
                        color: LuxeColors.muted,
                        fontSize: 12,
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
                // Two halo rings travelling outward while ready.
                if (enabled && !reduced)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      size: const Size.square(176),
                      painter: _HaloPainter(_pulse.value),
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
                              color: LuxeColors.emerald.withValues(
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
                    onHighlightChanged: (pressed) =>
                        setState(() => _pressed = pressed),
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
                              ? 'Đang gửi lệnh sạc'
                              : _buttonLabel,
                          child: _PowerFace(enabled: enabled),
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
          _submitting ? 'Đang gửi lệnh sạc…' : _buttonLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LuxeColors.text,
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
                style: TextButton.styleFrom(
                  foregroundColor: LuxeColors.emerald,
                ),
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

/// Brushed platinum bezel, emerald glass core, power glyph.
class _PowerFace extends StatelessWidget {
  const _PowerFace({required this.enabled});
  final bool enabled;

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
          color: enabled ? const Color(0x5534D399) : const Color(0x00000000),
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
              ? const [
                  Color(0xFF6EE7B7),
                  LuxeColors.emeraldDeep,
                  Color(0xFF065F46),
                ]
              : const [Color(0xFF2A2C30), Color(0xFF17181B), Color(0xFF0E0F11)],
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
            color: enabled ? const Color(0xFF022C22) : LuxeColors.dim,
          ),
        ],
      ),
    ),
  );
}

class _HaloPainter extends CustomPainter {
  _HaloPainter(this.t);
  final double t;

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
          ..color = LuxeColors.emerald.withValues(
            alpha: 0.45 * math.sin(p * math.pi) * (1 - p),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.t != t;
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: const Color(0x1434D399),
        child: LuxeGlass(
          selected: selected,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Center(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? LuxeColors.emerald : LuxeColors.text,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
