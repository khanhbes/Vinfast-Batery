import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cockpit_design_system.dart';

/// Premium timed charging section matching the EV cockpit reference.
/// 6-preset duration grid (2×3) + big circular ON/OFF power button +
/// Shelly timer safety note.
class TimedChargingSectionV2 extends StatefulWidget {
  const TimedChargingSectionV2({
    super.key,
    required this.onStart,
    required this.onOff,
    required this.readyForControl,
  });

  final Future<void> Function(Duration duration) onStart;
  final VoidCallback onOff;
  final bool readyForControl;

  @override
  State<TimedChargingSectionV2> createState() => _TimedChargingSectionV2State();
}

class _TimedChargingSectionV2State extends State<TimedChargingSectionV2>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final AnimationController _rippleController;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;
  int _selectedMinutes = 60;
  bool _pressed = false;
  bool _submitting = false;

  static const _presets = [
    // `-1` is a UI-only "start now" choice. It is deliberately translated
    // to the seven-hour device safety timer below; no relay ON is unbounded.
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _rippleScale = Tween<double>(begin: 0.9, end: 1.45).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOutCubic),
    );
    _rippleOpacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      if (_pulseController.isAnimating) _pulseController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _syncPulse();
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
    if (!MediaQuery.disableAnimationsOf(context) &&
        widget.readyForControl &&
        !_submitting) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }
  }

  Future<void> _start() async {
    if (_submitting || !widget.readyForControl) return;
    _rippleController.forward(from: 0.0);
    setState(() => _submitting = true);
    _syncPulse();
    try {
      await widget.onStart(
        _selectedMinutes == -1
            ? const Duration(hours: 7)
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
    _pulseController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  String get _buttonLabel {
    if (_selectedMinutes == -1) return 'Bắt đầu ngay · tự ngắt sau 7 giờ';
    final h = _selectedMinutes ~/ 60;
    final m = _selectedMinutes % 60;
    if (h > 0 && m > 0) return 'Sạc $h giờ $m phút';
    if (h > 0) return 'Sạc ${h * 60} phút';
    return 'Sạc $m phút';
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.readyForControl && !_submitting;

    return Column(
      key: const ValueKey('timed-mode-v2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Content card ──
        CockpitSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: CockpitColors.emerald,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thời gian hẹn giờ',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CockpitColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Bộ sạc tự ngắt bằng bộ đếm giờ phần cứng sau thời gian đã chọn.',
                style: TextStyle(color: CockpitColors.muted, fontSize: 13),
              ),

              const SizedBox(height: 16),

              // ── 2×3 Duration presets grid ──
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final compact = constraints.maxWidth < 340 || textScale > 1.2;
                  return GridView.count(
                    crossAxisCount: compact ? 2 : 3,
                    childAspectRatio: textScale > 1.5
                        ? 1.2
                        : compact
                        ? 1.9
                        : 1.55,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final preset in _presets)
                        _DurationPresetTile(
                          key: ValueKey('timed-preset-${preset.minutes}'),
                          label: preset.label,
                          isSelected: _selectedMinutes == preset.minutes,
                          onTap: () {
                            setState(() => _selectedMinutes = preset.minutes);
                            HapticFeedback.selectionClick();
                          },
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // ── Shelly timer safety note ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CockpitColors.emerald.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CockpitColors.emerald.withValues(alpha: .15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 18,
                      color: CockpitColors.emerald,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Timer được nạp thẳng vào rơ-le Shelly, an toàn độc lập với điện thoại.',
                        style: TextStyle(
                          color: CockpitColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Big circular power button with pulse glow & ripple shockwave ──
        Center(
          child: SizedBox(
            width: 168,
            height: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer breathing glow halo
                if (enabled && !reducedMotion)
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) => Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: CockpitColors.emeraldStrong.withValues(
                              alpha: 0.15 + _pulseController.value * 0.25,
                            ),
                            blurRadius: 32,
                            spreadRadius: 4 + _pulseController.value * 12,
                          ),
                          BoxShadow(
                            color: CockpitColors.emerald.withValues(
                              alpha: 0.10 + _pulseController.value * 0.15,
                            ),
                            blurRadius: 18,
                            spreadRadius: 2 + _pulseController.value * 6,
                          ),
                        ],
                      ),
                    ),
                  ),

                // Expanding shockwave ripple ring on tap
                if (!reducedMotion)
                  AnimatedBuilder(
                    animation: _rippleController,
                    builder: (context, _) {
                      if (_rippleController.value == 0 ||
                          _rippleController.isCompleted) {
                        return const SizedBox.shrink();
                      }
                      return Transform.scale(
                        scale: _rippleScale.value,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: CockpitColors.emeraldStrong.withValues(
                                alpha: _rippleOpacity.value,
                              ),
                              width: 3.0,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // Main button
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
                      scale: _pressed && !reducedMotion ? 0.94 : 1.0,
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      child: AnimatedOpacity(
                        duration: reducedMotion
                            ? Duration.zero
                            : CockpitMotion.standard,
                        opacity: enabled ? 1.0 : 0.35,
                        child: Container(
                          width: 124,
                          height: 124,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: enabled
                                ? const RadialGradient(
                                    colors: [
                                      Color(0xFF6EE7B7), // emerald-300 highlight
                                      CockpitColors.emeraldStrong,
                                      Color(0xFF047857), // emerald-700 depth
                                    ],
                                    stops: [0.0, 0.45, 1.0],
                                  )
                                : null,
                            color: enabled ? null : CockpitColors.elevated,
                            border: Border.all(
                              color: enabled
                                  ? const Color(0xFFA7F3D0).withValues(alpha: 0.6)
                                  : CockpitColors.border,
                              width: 2.5,
                            ),
                            boxShadow: enabled
                                ? [
                                    BoxShadow(
                                      color: CockpitColors.emeraldStrong.withValues(
                                        alpha: 0.38,
                                      ),
                                      blurRadius: 28,
                                      spreadRadius: 3,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Subtle shimmer reflection curve on the top half
                              if (enabled)
                                Positioned(
                                  top: 8,
                                  child: Container(
                                    width: 76,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(40),
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.white.withValues(alpha: 0.32),
                                          Colors.white.withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              Semantics(
                                label: _submitting
                                    ? 'Đang gửi lệnh sạc'
                                    : _buttonLabel,
                                child: Icon(
                                  Icons.power_settings_new_rounded,
                                  size: 50,
                                  color: enabled
                                      ? const Color(0xFF022C22) // dark emerald text
                                      : CockpitColors.dim,
                                ),
                              ),
                            ],
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

        const SizedBox(height: 12),

        // ── Label under button ──
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: CockpitColors.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _submitting ? 'Đang gửi lệnh sạc…' : _buttonLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CockpitColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DurationPresetTile extends StatelessWidget {
  const _DurationPresetTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: CockpitMotion.standard,
        decoration: BoxDecoration(
          color: isSelected
              ? CockpitColors.emerald.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? CockpitColors.emeraldStrong
                : CockpitColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CockpitColors.emerald.withValues(alpha: .10),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? CockpitColors.emerald : CockpitColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}
