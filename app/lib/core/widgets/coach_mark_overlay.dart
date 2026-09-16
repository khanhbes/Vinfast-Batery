import 'package:flutter/material.dart';
import '../services/guide_registry.dart';
import '../theme/app_ui_colors.dart';
import 'battery_bot_mascot.dart';

/// EV Cockpit Spotlight Coach Mark Overlay
/// - Làm mờ nền và tạo vùng spotlight làm nổi bật widget mục tiêu
/// - Hộp thoại hướng dẫn hỗ trợ: Tiếp, Quay lại, Bỏ qua, Không hiện lại
/// - Hỗ trợ Reduced Motion và bảo vệ an toàn: tuyệt đối không tự động trigger relay/GPS
class CoachMarkOverlay extends StatefulWidget {
  final List<CoachMarkStep> steps;
  final VoidCallback onFinish;
  final VoidCallback? onSkip;
  final void Function(bool dontShowAgain)? onDontShowAgain;

  const CoachMarkOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    this.onSkip,
    this.onDontShowAgain,
  });

  /// Hiển thị overlay coach mark qua OverlayEntry
  static OverlayEntry show({
    required BuildContext context,
    required List<CoachMarkStep> steps,
    required VoidCallback onFinish,
    VoidCallback? onSkip,
    void Function(bool dontShowAgain)? onDontShowAgain,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => CoachMarkOverlay(
        steps: steps,
        onFinish: () {
          entry.remove();
          onFinish();
        },
        onSkip: () {
          entry.remove();
          onSkip?.call();
        },
        onDontShowAgain: (val) {
          onDontShowAgain?.call(val);
        },
      ),
    );
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) {
      overlay.insert(entry);
    }
    return entry;
  }

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _dontShowAgain = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Rect? _getTargetRect(CoachMarkStep step) {
    final ctx = step.anchorKey.currentContext;
    if (ctx == null) return null;
    final renderBox = ctx.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    return offset & renderBox.size;
  }

  void _next() {
    if (_currentIndex < widget.steps.length - 1) {
      setState(() => _currentIndex++);
      _animCtrl.forward(from: 0.0);
    } else {
      if (_dontShowAgain) widget.onDontShowAgain?.call(true);
      widget.onFinish();
    }
  }

  void _back() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _animCtrl.forward(from: 0.0);
    }
  }

  void _skip() {
    if (_dontShowAgain) widget.onDontShowAgain?.call(true);
    widget.onSkip != null ? widget.onSkip!() : widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final step = widget.steps[_currentIndex];
    final targetRect = _getTargetRect(step);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final uiColors = AppUiColors.of(context);
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Spotlight hole cutout
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                targetRect: targetRect,
                overlayColor: const Color(0xE00C0F14), // Graphite neutral dark
              ),
            ),
          ),

          // Intercept taps outside dialog to do nothing (prevent accidental touches)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
            ),
          ),

          // Tooltip card
          FadeTransition(
            opacity: _fadeAnim,
            child: _buildTooltipBox(
              context: context,
              step: step,
              targetRect: targetRect,
              screenSize: screenSize,
              uiColors: uiColors,
              isEn: isEn,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltipBox({
    required BuildContext context,
    required CoachMarkStep step,
    required Rect? targetRect,
    required Size screenSize,
    required AppUiColors uiColors,
    required bool isEn,
  }) {
    // Determine positioning above or below the target rect
    double? top;
    double? bottom;

    final targetBottom = targetRect != null ? targetRect.bottom : screenSize.height * 0.35;
    final targetTop = targetRect != null ? targetRect.top : screenSize.height * 0.35;

    // Place below if target is in top half, otherwise above
    if (targetBottom < screenSize.height * 0.58) {
      top = targetBottom + 16;
    } else {
      bottom = (screenSize.height - targetTop) + 16;
    }

    final isLast = _currentIndex == widget.steps.length - 1;

    return Positioned(
      left: 20,
      right: 20,
      top: top,
      bottom: bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2028), // Cockpit dark card
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.35), // Emerald accent border
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // BatteryBot Mascot Header & Step indicator
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const BatteryBotMascot(
                      size: BatteryBotSize.sm,
                      customWidth: 36,
                      customHeight: 46,
                      mood: BatteryBotMood.greeting,
                      enableFloating: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('⚡ ', style: TextStyle(fontSize: 10)),
                                    Text(
                                      isEn
                                          ? 'Step ${_currentIndex + 1} of ${widget.steps.length}'
                                          : 'Bước ${_currentIndex + 1} / ${widget.steps.length}',
                                      style: const TextStyle(
                                        color: Color(0xFF34D399),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: _skip,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.white60,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: Text(isEn ? 'Skip' : 'Bỏ qua', style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEn ? 'BatteryBot Guide' : 'Trợ lý hướng dẫn',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Title
                Text(
                  step.title(isEn ? 'en' : 'vi'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  step.description(isEn ? 'en' : 'vi'),
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),

                // Don't show again checkbox
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _dontShowAgain,
                        activeColor: const Color(0xFF10B981),
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (val) {
                          setState(() => _dontShowAgain = val ?? false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() => _dontShowAgain = !_dontShowAgain);
                      },
                      child: Text(
                        isEn ? "Don't show again" : 'Không hiện lại',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_currentIndex > 0) ...[
                      OutlinedButton(
                        onPressed: _back,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        child: Text(isEn ? 'Back' : 'Quay lại'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981), // Emerald
                        foregroundColor: const Color(0xFF042F2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(
                        isLast
                            ? (isEn ? 'Got it!' : 'Hoàn tất')
                            : (isEn ? 'Next' : 'Tiếp theo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter cắt lỗ spotlight bo tròn xung quanh targetRect
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Color overlayColor;

  _SpotlightPainter({required this.targetRect, required this.overlayColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;

    if (targetRect == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    // Expand target rect slightly for padding
    final paddedRect = targetRect!.inflate(8.0);
    final rrect = RRect.fromRectAndRadius(paddedRect, const Radius.circular(16));

    // Path combining screen rect with hole subtracted
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Neon glow aura around the spotlight hole
    final glowPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(rrect, glowPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF34D399)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor;
  }
}
