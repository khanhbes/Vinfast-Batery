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

  static Duration staggerFor(int index, {Duration step = stagger, Duration max = const Duration(milliseconds: 600)}) {
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
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        final eased = CurvedAnimation(parent: animation, curve: enter, reverseCurve: exit);
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
    final d = duration ?? AppMotion.base;
    final dl = delay ?? AppMotion.staggerFor(index);
    return animate()
        .fadeIn(delay: dl, duration: d, curve: AppMotion.enter)
        .slideY(
          begin: slide,
          end: 0,
          delay: dl,
          duration: d,
          curve: AppMotion.enter,
        );
  }

  /// Pop scale entrance — dùng cho hero badges, FABs.
  Widget appScalePop({Duration? delay, Duration? duration}) {
    return animate().fadeIn(delay: delay, duration: duration ?? AppMotion.fast).scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          delay: delay,
          duration: duration ?? AppMotion.base,
          curve: AppMotion.emphasized,
        );
  }
}
