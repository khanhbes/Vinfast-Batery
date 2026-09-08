import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Hệ thống motion thống nhất cho toàn app — Design System V4.
///
/// Mục tiêu:
/// - Tất cả entrance animations, route transitions, micro-interactions dùng
///   chung 1 bộ duration & curve để feel "premium" và đồng nhất.
/// - Hợp tác với `flutter_animate` (đã có sẵn trong pubspec) để code ngắn gọn.
class AppMotion {
  AppMotion._();

  static bool enabled(BuildContext context) =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  static Duration durationFor(BuildContext context, Duration duration) =>
      enabled(context) ? duration : Duration.zero;

  // ── Durations ──────────────────────────────────────────────────────
  /// Cho micro feedback (ripple, toggle...).
  static const Duration instant = Duration(milliseconds: 80);

  /// Tap response, badge change.
  static const Duration fast = Duration(milliseconds: 180);

  /// Default cho enter / state changes.
  static const Duration base = Duration(milliseconds: 260);

  /// Hero / page transitions.
  static const Duration slow = Duration(milliseconds: 380);

  /// Background, decorative animations.
  static const Duration ambient = Duration(milliseconds: 600);

  // ── Curves ─────────────────────────────────────────────────────────
  /// Entrance: nhanh đầu, dịu cuối (Material 3 Easing.standardDecelerate).
  static const Curve enter = Cubic(0.0, 0.0, 0.0, 1.0);

  /// Exit: nhanh trong, mất tốc dịu cuối (standardAccelerate).
  static const Curve exit = Cubic(0.3, 0.0, 1.0, 1.0);

  /// Standard easeInOut tinh chỉnh.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Cho nhịp pulse / subtle bounce (decorative).
  static const Curve pulse = Curves.easeInOutCubic;

  // ── Stagger ────────────────────────────────────────────────────────
  /// Khoảng cách stagger giữa các item trong list (ms).
  static const Duration stagger = Duration(milliseconds: 60);

  static Duration staggerFor(
    int index, {
    Duration step = stagger,
    Duration max = const Duration(milliseconds: 240),
  }) {
    final ms = (step.inMilliseconds * index).clamp(0, max.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  // ── Page route helpers ─────────────────────────────────────────────

  /// Push 1 widget với fade + slide-up nhẹ (entrance), thay cho
  /// `MaterialPageRoute` mặc định.
  static PageRouteBuilder<T> pageRoute<T>(
    Widget page, {
    bool fullscreenDialog = false,
    Duration duration = base,
    Duration reverseDuration = fast,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
          return child;
        }
        final eased = CurvedAnimation(
          parent: animation,
          curve: enter,
          reverseCurve: exit,
        );
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(eased),
            child: child,
          ),
        );
      },
    );
  }
}

/// Page transitions builder dùng cho `ThemeData.pageTransitionsTheme` —
/// tương đương `AppMotion.pageRoute` nhưng áp dụng tự động cho mọi
/// `MaterialPageRoute`.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }
    final eased = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(eased),
        child: child,
      ),
    );
  }
}

/// Extension trên `Widget` cung cấp các entrance animation chuẩn —
/// wrapper mỏng quanh `flutter_animate` để callers viết ngắn gọn:
///
///   MyCard().appFadeSlideIn(index: i)
///
/// thay cho lặp lại `flutter_animate` config rời rạc khắp app.
extension AppMotionAnimate on Widget {
  /// Fade + slide-up nhẹ. Dùng cho cards / list items.
  Widget appFadeSlideIn({
    int index = 0,
    Duration? delay,
    Duration? duration,
    double slide = 0.08,
  }) {
    return AppReveal(
      duration: duration ?? AppMotion.base,
      delay: delay ?? AppMotion.staggerFor(index),
      offset: Offset(0, (slide * 100).clamp(-12.0, 12.0)),
      child: this,
    );
  }

  /// Pop scale entrance — dùng cho hero badges, FABs.
  Widget appScalePop({Duration? delay, Duration? duration}) {
    return Builder(
      builder: (context) {
        if (!AppMotion.enabled(context)) return this;
        return animate()
            .fadeIn(delay: delay, duration: duration ?? AppMotion.fast)
            .scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1, 1),
              delay: delay,
              duration: duration ?? AppMotion.base,
              curve: AppMotion.emphasized,
            );
      },
    );
  }
}

/// Subtle, one-shot entrance. Layout, focus and hit targets remain available
/// throughout; rebuilds do not restart it and no delayed timers are created.
class AppReveal extends StatelessWidget {
  const AppReveal({
    super.key,
    required this.child,
    this.duration = AppMotion.base,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 8),
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return child;
    final delayMs = delay.inMilliseconds.clamp(0, 240);
    final motionMs = duration.inMilliseconds.clamp(1, 600);
    final total = delayMs + motionMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: AppMotion.enter),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: 0.82 + 0.18 * value,
        child: Transform.translate(offset: offset * (1 - value), child: child),
      ),
    );
  }
}
