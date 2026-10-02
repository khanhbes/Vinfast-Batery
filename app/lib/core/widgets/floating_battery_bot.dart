import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ai/assistant_sheet.dart';
import '../services/assistant_context_coordinator.dart';
import '../theme/app_ui_colors.dart';
import 'battery_bot_mascot.dart';

/// Widget Mascot nổi (Floating Action Bot) kèm bong bóng thoại chủ động (Proactive Speech Bubble)
class FloatingBatteryBot extends ConsumerStatefulWidget {
  const FloatingBatteryBot({
    super.key,
    this.initialBottom = 20.0,
    this.initialRight = 16.0,
  });

  final double initialBottom;
  final double initialRight;

  @override
  ConsumerState<FloatingBatteryBot> createState() => _FloatingBatteryBotState();
}

class _FloatingBatteryBotState extends ConsumerState<FloatingBatteryBot>
    with SingleTickerProviderStateMixin {
  late double _bottom;
  late double _right;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _bottom = widget.initialBottom;
    _right = widget.initialRight;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _openSheet({String? initialQuery}) {
    HapticFeedback.lightImpact();
    ref.read(assistantContextCoordinatorProvider).dismissBubble();
    InteractiveAssistantSheet.show(context, initialQuery: initialQuery);
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final coordinator = ref.watch(assistantContextCoordinatorProvider);
    final isBubbleVisible = coordinator.isBubbleVisible;
    final bubbleText = coordinator.bubbleText;
    final mood = isBubbleVisible ? coordinator.bubbleMood : BatteryBotMood.idle;

    // Tự ẩn khi bàn phím ảo mở
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (isKeyboardOpen) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      bottom: _bottom,
      right: _right,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            // Cập nhật vị trí kéo thả trong vùng an toàn của màn hình
            _bottom = (_bottom - details.delta.dy).clamp(16.0, screenSize.height - 180.0);
            _right = (_right - details.delta.dx).clamp(16.0, screenSize.width - 80.0);
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bong bóng lời thoại ngữ cảnh (Proactive Speech Bubble)
            AnimatedOpacity(
              opacity: isBubbleVisible && bubbleText != null ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedScale(
                scale: isBubbleVisible && bubbleText != null ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: isBubbleVisible && bubbleText != null
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        constraints: BoxConstraints(
                          maxWidth: screenSize.width * 0.72,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: uiColors.surface,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: const Radius.circular(4),
                          ),
                          border: Border.all(
                            color: uiColors.primary.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: uiColors.primary.withValues(alpha: 0.18),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _openSheet(initialQuery: bubbleText),
                                child: Text(
                                  bubbleText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: uiColors.text,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                ref
                                    .read(assistantContextCoordinatorProvider)
                                    .dismissBubble();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: uiColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Nút tròn Mascot nổi (Floating Action Icon)
            ScaleTransition(
              scale: isBubbleVisible ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                elevation: 6,
                shadowColor: uiColors.primary.withValues(alpha: 0.35),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openSheet(),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          uiColors.surface,
                          uiColors.background,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: isBubbleVisible
                            ? uiColors.primary
                            : uiColors.border,
                        width: isBubbleVisible ? 2.0 : 1.2,
                      ),
                    ),
                    child: Center(
                      child: BatteryBotMascot(
                        size: BatteryBotSize.avatar,
                        displayMode: BatteryBotDisplayMode.avatar,
                        mood: mood,
                        enableFloating: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
