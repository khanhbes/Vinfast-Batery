import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/luxe_theme.dart';

/// Where the last tapped tile sits on screen (QA 151). The tile records it
/// just before its `onTap`; the route opened by that tap takes it once.
abstract final class LuxeExpandOrigin {
  static Rect? _rect;

  static void mark(BuildContext context) {
    final box = context.findRenderObject();
    _rect = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  static Rect? take() {
    final rect = _rect;
    _rect = null;
    return rect;
  }
}

/// A page that grows out of the tile that opened it and folds back into it
/// (QA 151), instead of sliding in like every other page. Without an origin,
/// or with Giảm chuyển động, it is an ordinary page.
class LuxeExpandRoute<T> extends PageRouteBuilder<T> {
  LuxeExpandRoute({required WidgetBuilder builder, Rect? origin})
    : super(
        pageBuilder: (context, _, _) => builder(context),
        transitionDuration: const Duration(milliseconds: 440),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        transitionsBuilder: (context, animation, _, child) {
          if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
            return child;
          }
          final curved = CurvedAnimation(
            parent: animation,
            curve: LuxeMotion.enter,
            reverseCurve: LuxeMotion.exit,
          );
          if (origin == null) {
            return FadeTransition(opacity: curved, child: child);
          }
          return AnimatedBuilder(
            animation: curved,
            child: child,
            builder: (context, child) {
              final t = curved.value;
              return Opacity(
                opacity: (t / 0.45).clamp(0.0, 1.0),
                child: ClipPath(
                  clipper: _ExpandClipper(origin, t),
                  child: child,
                ),
              );
            },
          );
        },
      );
}

class _ExpandClipper extends CustomClipper<Path> {
  const _ExpandClipper(this.origin, this.t);
  final Rect origin;
  final double t;

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.lerp(origin, Offset.zero & size, t)!,
        Radius.circular(lerpDouble(22, 0, t)!),
      ),
    );

  @override
  bool shouldReclip(_ExpandClipper old) => old.t != t || old.origin != origin;
}
