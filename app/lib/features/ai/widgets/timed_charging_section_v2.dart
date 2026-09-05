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
    with SingleTickerProviderStateMixin {
  int _selectedMinutes = 120; // default: 2 giờ (Khuyên dùng)
  late AnimationController _pulseController;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
    final enabled = widget.readyForControl;

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

        // ── Big circular power button ──
        Center(
          child: SizedBox(
            width: 152,
            height: 152,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow pulse
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
                            color: CockpitColors.emerald.withValues(
                              alpha: .06 + _pulseController.value * .12,
                            ),
                            blurRadius: 28,
                            spreadRadius: 4 + _pulseController.value * 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                // Main button
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('timed-charge-start-button'),
                    onTap: enabled
                        ? () {
                            final duration = _selectedMinutes == -1
                                ? const Duration(hours: 7)
                                : Duration(minutes: _selectedMinutes);
                            widget.onStart(duration);
                          }
                        : null,
                    customBorder: const CircleBorder(),
                    child: AnimatedOpacity(
                      duration: CockpitMotion.standard,
                      opacity: enabled ? 1.0 : 0.35,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: enabled
                              ? const RadialGradient(
                                  colors: [
                                    Color(0xFF34D399), // emerald-400
                                    CockpitColors.emeraldStrong,
                                    Color(0xFF059669), // emerald-600
                                  ],
                                  stops: [0.0, 0.5, 1.0],
                                )
                              : null,
                          color: enabled ? null : CockpitColors.elevated,
                          border: Border.all(
                            color: enabled
                                ? CockpitColors.emerald.withValues(alpha: .4)
                                : CockpitColors.border,
                            width: 2,
                          ),
                          boxShadow: enabled
                              ? [
                                  BoxShadow(
                                    color: CockpitColors.emerald.withValues(
                                      alpha: .30,
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          Icons.power_settings_new_rounded,
                          size: 48,
                          color: enabled
                              ? const Color(0xFF0A0A0A)
                              : CockpitColors.dim,
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
                _buttonLabel,
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
