import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// PremiumCard — pattern card thống nhất toàn app.
///
/// Tính chất:
/// - Padding mặc định 16, radius 20, border `glassBorder`, fill `card`.
/// - Có press feedback (scale-down nhẹ) khi `onTap != null` — không cần
///   wrap thêm `GestureDetector` ngoài.
/// - Nếu `selected` = true: viền chuyển sang `primary` để indicate selection.
/// - Tham số `gradient`/`tint` cho phép tô nhẹ bề mặt trong các case đặc biệt
///   (active state, AI highlight…).
class PremiumCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final Color? backgroundColor;
  final Color? borderColor;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.backgroundColor,
    this.borderColor,
    this.gradient,
    this.boxShadow,
  });

  @override
  State<PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<PremiumCard> {
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool v) {
    if (!_interactive) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? AppColors.card;
    final border = widget.borderColor ??
        (widget.selected ? AppColors.primary : AppColors.glassBorder);

    Widget card = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      transform: Matrix4.identity()..scale(_pressed ? 0.985 : 1.0),
      transformAlignment: Alignment.center,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.gradient == null ? bg : null,
        gradient: widget.gradient,
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: border,
          width: widget.selected ? 1.4 : 1,
        ),
        boxShadow: widget.boxShadow,
      ),
      child: widget.child,
    );

    if (!_interactive) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: card,
    );
  }
}
