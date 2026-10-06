import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/guide_registry.dart';
import '../theme/app_motion.dart';
import '../theme/app_ui_colors.dart';
import 'battery_bot_mascot.dart';

/// Explains the highlighted control; never dispatches its action.
class CoachMarkOverlay extends StatefulWidget {
  final List<CoachMarkStep> steps;
  final VoidCallback onFinish;
  final VoidCallback? onSkip;
  final void Function(bool dontShowAgain)? onDontShowAgain;
  final bool showDontShowAgain;

  const CoachMarkOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    this.onSkip,
    this.onDontShowAgain,
    this.showDontShowAgain = true,
  });

  static OverlayEntry? _activeEntry;
  static bool isActive(OverlayEntry entry) => identical(_activeEntry, entry);

  static void dismissActive() {
    final entry = _activeEntry;
    _activeEntry = null;
    entry?.remove();
  }

  static OverlayEntry? show({
    required BuildContext context,
    required List<CoachMarkStep> steps,
    required VoidCallback onFinish,
    VoidCallback? onSkip,
    void Function(bool dontShowAgain)? onDontShowAgain,
    bool showDontShowAgain = true,
    OverlayState? overlay,
  }) {
    final targetOverlay =
        overlay ??
        Overlay.maybeOf(context) ??
        Navigator.maybeOf(context)?.overlay;
    if (targetOverlay == null || steps.isEmpty || !targetOverlay.mounted) {
      return null;
    }
    dismissActive();
    late final OverlayEntry entry;
    void close(VoidCallback? callback) {
      // An obsolete overlay must not close or complete its replacement.
      if (!identical(_activeEntry, entry)) return;
      dismissActive();
      callback?.call();
    }

    entry = OverlayEntry(
      builder: (_) => CoachMarkOverlay(
        steps: steps,
        onFinish: () => close(onFinish),
        onSkip: () => close(onSkip),
        onDontShowAgain: onDontShowAgain,
        showDontShowAgain: showDontShowAgain,
      ),
    );
    _activeEntry = entry;
    targetOverlay.insert(entry);
    return entry;
  }

  @override
  State<CoachMarkOverlay> createState() => _CoachMarkOverlayState();
}

class _CoachMarkOverlayState extends State<CoachMarkOverlay>
    with SingleTickerProviderStateMixin {
  final _surfaceKey = GlobalKey();
  int _index = 0;
  bool _dontShowAgain = false;
  bool _closed = false;
  bool _measurementScheduled = false;
  Rect? _target;
  BuildContext? _revealedContext;
  Rect? _revealedViewport;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _observeNextLayout();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.durationFor(context, AppMotion.fast);
    if (!AppMotion.enabled(context)) {
      _controller.value = 1;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant CoachMarkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.steps.length) _index = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Rect _usableBounds(Size size) {
    final media = MediaQuery.of(context);
    return Rect.fromLTRB(
      media.padding.left + 12,
      media.padding.top + 12,
      math.max(media.padding.left + 12, size.width - media.padding.right - 12),
      math.max(
        media.padding.top + 12,
        size.height -
            math.max(media.viewInsets.bottom, media.padding.bottom) -
            12,
      ),
    );
  }

  /// Observe actual layouts without a timer or scheduling endless new frames.
  /// A late anchor, scroll or keyboard frame will trigger a fresh measurement.
  void _observeNextLayout() {
    if (_measurementScheduled || !mounted || _closed) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted || _closed) return;
      _measureAnchor();
      _observeNextLayout();
    });
  }

  void _measureAnchor() {
    if (widget.steps.isEmpty) return;
    final anchorContext = widget.steps[_index].anchorKey.currentContext;
    final anchor = anchorContext?.findRenderObject();
    final surface = _surfaceKey.currentContext?.findRenderObject();
    Rect? visible;
    if (anchor is RenderBox &&
        anchor.attached &&
        anchor.hasSize &&
        surface is RenderBox &&
        surface.attached &&
        surface.hasSize) {
      final rect =
          surface.globalToLocal(anchor.localToGlobal(Offset.zero)) &
          anchor.size;
      final viewport = _usableBounds(surface.size);
      if (rect.overlaps(viewport) && !rect.isEmpty) {
        visible = rect.intersect(viewport);
      }
      if (anchorContext != null &&
          (rect.top < viewport.top || rect.bottom > viewport.bottom) &&
          (_revealedContext != anchorContext ||
              _revealedViewport != viewport)) {
        _revealedContext = anchorContext;
        _revealedViewport = viewport;
        unawaited(_revealAnchor(anchorContext, _index));
      }
    }
    if (_target != visible) setState(() => _target = visible);
  }

  Future<void> _revealAnchor(BuildContext anchor, int stepIndex) async {
    if (!mounted || !anchor.mounted || stepIndex != _index) return;
    await Scrollable.ensureVisible(
      anchor,
      alignment: .45,
      duration: AppMotion.durationFor(context, AppMotion.base),
      curve: AppMotion.enter,
    );
    // Frame callbacks already watch the layout. Do not act on a stale step.
    if (!mounted || _closed || stepIndex != _index) return;
    _observeNextLayout();
  }

  void _changeStep(int index) {
    setState(() {
      _index = index;
      _target = null;
      _revealedContext = null;
      _revealedViewport = null;
    });
    if (AppMotion.enabled(context)) _controller.forward(from: 0);
  }

  void _next() {
    if (_closed || _target == null) return;
    if (_index + 1 < widget.steps.length) {
      _changeStep(_index + 1);
    } else {
      _close(widget.onFinish);
    }
  }

  void _close(VoidCallback callback) {
    if (_closed) return;
    _closed = true;
    if (_dontShowAgain) widget.onDontShowAgain?.call(true);
    callback();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final step = widget.steps[_index];
    final ui = AppUiColors.of(context);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final language = isEn ? 'en' : 'vi';
    final noMotion = !AppMotion.enabled(context);
    return BlockSemantics(
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounds = _usableBounds(constraints.biggest);
            return Stack(
              key: _surfaceKey,
              fit: StackFit.expand,
              children: [
                // The spotlight is visual only: even the clear cutout blocks taps.
                const Positioned.fill(child: ModalBarrier(dismissible: false)),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SpotlightPainter(
                        _target,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                CustomSingleChildLayout(
                  delegate: _TooltipLayout(
                    bounds,
                    _target,
                    step.tooltipAlignment,
                  ),
                  child: FadeTransition(
                    opacity: _controller.drive(
                      CurveTween(curve: AppMotion.enter),
                    ),
                    child: Semantics(
                      scopesRoute: true,
                      namesRoute: true,
                      explicitChildNodes: true,
                      label: isEn ? 'Quick guide' : 'Hướng dẫn nhanh',
                      child: FocusTraversalGroup(
                        child: Material(
                          key: const ValueKey('coach-tooltip'),
                          color: ui.surface,
                          borderRadius: BorderRadius.circular(20),
                          elevation: 6,
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            key: const ValueKey('coach-tooltip-scroll'),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const ExcludeSemantics(
                                      child: TickerMode(
                                        enabled: false,
                                        child: BatteryBotMascot(
                                          size: BatteryBotSize.avatar,
                                          customWidth: 32,
                                          customHeight: 32,
                                          mood: BatteryBotMood.greeting,
                                          enableFloating: false,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          isEn
                                              ? 'Step ${_index + 1} of ${widget.steps.length}'
                                              : 'Bước ${_index + 1} / ${widget.steps.length}',
                                          style: TextStyle(
                                            color: ui.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _close(
                                        widget.onSkip ?? widget.onFinish,
                                      ),
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                        splashFactory: noMotion
                                            ? NoSplash.splashFactory
                                            : null,
                                        animationDuration:
                                            AppMotion.durationFor(
                                              context,
                                              AppMotion.fast,
                                            ),
                                      ),
                                      child: Text(isEn ? 'Skip' : 'Bỏ qua'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    step.title(language),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(color: ui.text),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _target == null
                                      ? (isEn
                                            ? 'Waiting for this item to appear. You can skip the guide and open it again in Settings.'
                                            : 'Đang đợi mục này hiển thị. Bạn có thể bỏ qua và mở lại hướng dẫn trong Cài đặt.')
                                      : step.description(language),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: ui.muted, height: 1.4),
                                ),
                                if (widget.showDontShowAgain) ...[
                                  const SizedBox(height: 8),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: _dontShowAgain,
                                    onChanged: (value) => setState(
                                      () => _dontShowAgain = value ?? false,
                                    ),
                                    title: Text(
                                      isEn
                                          ? "Don't show again"
                                          : 'Không tự mở lại',
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      if (_index > 0)
                                        OutlinedButton(
                                          onPressed: () =>
                                              _changeStep(_index - 1),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(48, 48),
                                            splashFactory: noMotion
                                                ? NoSplash.splashFactory
                                                : null,
                                            animationDuration:
                                                AppMotion.durationFor(
                                                  context,
                                                  AppMotion.fast,
                                                ),
                                          ),
                                          child: Text(
                                            isEn ? 'Back' : 'Quay lại',
                                          ),
                                        ),
                                      FilledButton(
                                        onPressed: _target == null
                                            ? null
                                            : _next,
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          splashFactory: noMotion
                                              ? NoSplash.splashFactory
                                              : null,
                                          animationDuration:
                                              AppMotion.durationFor(
                                                context,
                                                AppMotion.fast,
                                              ),
                                        ),
                                        child: Text(
                                          _index == widget.steps.length - 1
                                              ? (isEn ? 'Done' : 'Hoàn tất')
                                              : (isEn ? 'Next' : 'Tiếp'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout(this.bounds, this.target, this.preferredAlignment);
  final Rect bounds;
  final Rect? target;
  final Alignment preferredAlignment;
  static const gap = 16.0;

  Rect get _space {
    final anchor = target;
    if (anchor == null) return bounds;
    final above = math.max(0.0, anchor.top - gap - bounds.top);
    final below = math.max(0.0, bounds.bottom - anchor.bottom - gap);
    // Select usable room, respecting the registry hint only when space permits.
    final preferAbove = preferredAlignment.y < 0;
    final useAbove = (preferAbove && above >= 240) || below < above;
    if (math.max(above, below) < 48) return bounds;
    return useAbove
        ? Rect.fromLTWH(bounds.left, bounds.top, bounds.width, above)
        : Rect.fromLTWH(bounds.left, anchor.bottom + gap, bounds.width, below);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(460, bounds.width),
        minWidth: math.min(460, bounds.width),
        maxHeight: _space.height,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final space = _space;
    final anchor = target;
    final top = anchor != null && space.bottom <= anchor.top
        ? space.bottom - childSize.height
        : space.top;
    return Offset(bounds.center.dx - childSize.width / 2, top);
  }

  @override
  bool shouldRelayout(covariant _TooltipLayout oldDelegate) =>
      bounds != oldDelegate.bounds ||
      target != oldDelegate.target ||
      preferredAlignment != oldDelegate.preferredAlignment;
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.targetRect, this.accent);
  final Rect? targetRect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (targetRect != null) {
      final rect = RRect.fromRectAndRadius(
        targetRect!.inflate(6),
        const Radius.circular(14),
      );
      final spotlight = Path()..addRRect(rect);
      canvas.drawPath(
        Path.combine(PathOperation.difference, overlay, spotlight),
        Paint()..color = const Color(0xA9000000),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawPath(overlay, Paint()..color = const Color(0xA9000000));
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect || oldDelegate.accent != accent;
}
