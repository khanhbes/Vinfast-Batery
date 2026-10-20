import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ai/assistant_sheet.dart';
import '../services/assistant_context_coordinator.dart';
import '../theme/luxe_theme.dart';
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

    // Static: an endless decorative pulse over every tab broke the LUXE
    // motion rule and cost frames (Task 125).
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

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
    final isDocked = coordinator.isDocked;
    // Docked while the user scrolls down: tucked into the edge so it stops
    // covering cards and chips ("Cập nhật % pin & ODO", "100% Đầy pin" —
    // QA 129); about a third stays visible to tap or drag back.
    final effectiveRight = isDocked ? -40.0 : _right;
    final effectiveOpacity = isDocked ? 0.55 : 1.0;
    final effectiveScale = isDocked ? 0.72 : 1.0;
    final showBubble = isBubbleVisible && !isDocked && bubbleText != null;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      bottom: _bottom,
      right: effectiveRight,
      child: GestureDetector(
        onPanUpdate: (details) {
          if (isDocked) {
            ref.read(assistantContextCoordinatorProvider).setDocked(false);
          }
          setState(() {
            // Cập nhật vị trí kéo thả trong vùng an toàn của màn hình
            _bottom = (_bottom - details.delta.dy).clamp(
              16.0,
              screenSize.height - 180.0,
            );
            _right = (_right - details.delta.dx).clamp(
              16.0,
              screenSize.width - 80.0,
            );
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bong bóng lời thoại ngữ cảnh (Proactive Speech Bubble)
            AnimatedOpacity(
              opacity: showBubble ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedScale(
                scale: showBubble ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: showBubble
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
                          color: const Color(0xF2121315),
                          borderRadius: BorderRadius.circular(
                            20,
                          ).copyWith(bottomRight: const Radius.circular(6)),
                          border: Border.all(
                            color: LuxeColors.emerald.withValues(alpha: 0.45),
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x2634D399), blurRadius: 18),
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    _openSheet(initialQuery: bubbleText),
                                child: Text(
                                  bubbleText,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: LuxeColors.text,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Đóng gợi ý Pinova Bot',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              onPressed: () {
                                ref
                                    .read(assistantContextCoordinatorProvider)
                                    .dismissBubble();
                              },
                              icon: const Icon(
                                Icons.close,
                                size: 14,
                                color: LuxeColors.muted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // Nút tròn Mascot nổi (Floating Action Icon)
            AnimatedScale(
              scale: effectiveScale,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: effectiveOpacity,
                duration: const Duration(milliseconds: 250),
                child: ScaleTransition(
                  scale: isBubbleVisible && !isDocked
                      ? _pulseAnimation
                      : const AlwaysStoppedAnimation(1.0),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    elevation: isDocked ? 2 : 6,
                    shadowColor: LuxeColors.emerald.withValues(alpha: 0.4),
                    child: Tooltip(
                      message: 'Mở Pinova Bot',
                      child: Semantics(
                        label: 'Mở Pinova Bot',
                        button: true,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            if (isDocked) {
                              ref
                                  .read(assistantContextCoordinatorProvider)
                                  .setDocked(false);
                            }
                            _openSheet();
                          },
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2A2C30), Color(0xFF0B0C0E)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: isBubbleVisible
                                    ? LuxeColors.emerald
                                    : LuxeColors.emerald.withValues(
                                        alpha: 0.45,
                                      ),
                                width: isBubbleVisible ? 2.0 : 1.3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x3334D399),
                                  blurRadius: 18,
                                ),
                              ],
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
