import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../services/app_connection.dart';
import '../services/system_settings.dart';
import '../theme/luxe_theme.dart';
import 'app_popup.dart';
import 'battery_bot_mascot.dart';
import 'luxe_connection_notice.dart' show ConnectionIssue;

/// QA 161 (owner's choice, 16/11/2026): one way to be offline, on every
/// page.
///
/// - [OfflineDock]: a floating card over the bottom of the screen (above
///   the tab bar on the tabs), with what is wrong, the next automatic try,
///   "Thử lại" and, without Internet, "Cài đặt mạng". The cross folds it
///   into a small pill; it leaves by itself, with a short "Đã kết nối lại",
///   when the server answers. It replaced the strip at the top of the app.
/// - [OfflineStamp]: "Ngoại tuyến · cập nhật lúc 14:05" at the top of every
///   page while offline: the page keeps what it has, marked as old.
/// - [LuxeOfflineEmpty]: a page with nothing saved yet ([ErrorState] while
///   offline): the same cloud, one sentence, "Thử lại".
/// - [OnlineGate]: an action that needs the server says so instead of
///   failing (never on Stop charging).
///
/// All read [AppConnection.instance].
class OfflineDock extends StatefulWidget {
  const OfflineDock({super.key, required this.child});

  final Widget child;

  /// Height of the shell's bottom bar (tabs and charging pill), set by
  /// [OfflineDockInset]; the card sits above it on the tabs.
  static final shellBottom = ValueNotifier<double>(0);

  /// Tracks the top route: the card hides under sheets and dialogs, and
  /// sits lower on pages without the tab bar.
  static final observer = OfflineRouteObserver();

  /// The survey waits to be sent (the shell's "Đang chờ đồng bộ thông tin
  /// xe"): its retry, or null.
  static final pendingSync = ValueNotifier<Future<void> Function()?>(null);

  /// How long "Đã kết nối lại" stays.
  static const recoveredFor = Duration(milliseconds: 2400);

  @override
  State<OfflineDock> createState() => _OfflineDockState();
}

class _OfflineDockState extends State<OfflineDock> {
  final _connection = AppConnection.instance;
  Timer? _ticker;
  Timer? _recoveredTimer;
  bool _collapsed = false;
  bool _retrying = false;
  ConnectionIssue? _shownIssue;
  bool _recovered = false;

  @override
  void initState() {
    super.initState();
    AppConnection.instance.addListener(_changed);
    OfflineDock.shellBottom.addListener(_rebuild);
    OfflineDock.observer.top.addListener(_rebuild);
    OfflineDock.pendingSync.addListener(_rebuild);
    _changed(rebuild: false);
  }

  @override
  void dispose() {
    AppConnection.instance.removeListener(_changed);
    OfflineDock.shellBottom.removeListener(_rebuild);
    OfflineDock.observer.top.removeListener(_rebuild);
    OfflineDock.pendingSync.removeListener(_rebuild);
    _ticker?.cancel();
    _recoveredTimer?.cancel();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _changed({bool rebuild = true}) {
    final link = AppConnection.instance.value;
    if (link.issue != _shownIssue) {
      // A new problem opens the card again.
      if (link.issue != null) _collapsed = false;
      if (link.issue == null &&
          _shownIssue != null &&
          link.recoveredAt != null) {
        _recovered = true;
        _recoveredTimer?.cancel();
        _recoveredTimer = Timer(OfflineDock.recoveredFor, () {
          if (mounted) setState(() => _recovered = false);
        });
      }
      _shownIssue = link.issue;
    }
    if (link.issue != null) _recovered = false;
    // The countdown ticks only while there is one to show.
    final counting = link.issue != null && link.nextProbeAt != null;
    if (counting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _rebuild());
    } else if (!counting) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (rebuild) _rebuild();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      final sync = OfflineDock.pendingSync.value;
      await _connection.retryNow();
      if (sync != null && !_connection.value.offline) await sync();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _connection.value;
    final top = OfflineDock.observer.top.value;
    final sync = OfflineDock.pendingSync.value;
    final show =
        _connection.started &&
        !top.popup &&
        (link.offline || _recovered || sync != null);
    final media = MediaQuery.of(context);
    final shell = OfflineDock.shellBottom.value;
    final bottom = top.first && shell > 0
        ? shell + 10
        : media.viewPadding.bottom + 16 + media.viewInsets.bottom;
    final reduced = media.disableAnimations;
    final Widget card;
    if (!show) {
      card = const SizedBox.shrink(key: ValueKey('offline-none'));
    } else if (!link.offline && sync == null) {
      card = const _RecoveredPill(key: ValueKey('offline-recovered'));
    } else if (_collapsed) {
      card = _OfflinePill(
        key: const ValueKey('offline-pill'),
        onTap: () => setState(() => _collapsed = false),
      );
    } else {
      card = _OfflineCard(
        key: const ValueKey('offline-card'),
        link: link,
        syncPending: !link.offline && sync != null,
        retrying: _retrying || link.checking,
        onRetry: _retry,
        onClose: () => setState(() => _collapsed = true),
      );
    }
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          bottom: bottom,
          child: AnimatedSwitcher(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 320),
            switchInCurve: LuxeMotion.enter,
            switchOutCurve: LuxeMotion.exit,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomLeft,
              children: [...previous, ?current],
            ),
            child: card,
          ),
        ),
      ],
    );
  }
}

/// "Thử lại sau 12 giây" / "Đang thử kết nối…".
String offlineRetryLine(
  AppLinkState link, {
  required bool retrying,
  DateTime? now,
}) {
  if (retrying) return 'Đang thử kết nối…';
  final at = link.nextProbeAt;
  if (at == null) return 'App tự kết nối lại khi có mạng.';
  final seconds = at.difference(now ?? DateTime.now()).inSeconds;
  return seconds <= 0 ? 'Đang thử kết nối…' : 'Tự thử lại sau $seconds giây.';
}

class _OfflineCard extends StatelessWidget {
  const _OfflineCard({
    super.key,
    required this.link,
    required this.syncPending,
    required this.retrying,
    required this.onRetry,
    required this.onClose,
  });

  final AppLinkState link;
  final bool syncPending;
  final bool retrying;
  final Future<void> Function() onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final internet = link.issue == ConnectionIssue.internet;
    final (title, detail, icon) = syncPending
        ? (
            'Đang chờ đồng bộ thông tin xe',
            'Mình sẽ gửi thông tin bạn đã khai ngay khi máy chủ nhận.',
            Icons.cloud_upload_rounded,
          )
        : internet
        ? (
            'Mất kết nối Internet',
            'Mình vẫn giữ dữ liệu đã lưu cho bạn xem. Có mạng là mình tự kết nối lại.',
            Icons.wifi_off_rounded,
          )
        : (
            'Chưa liên lạc được máy chủ',
            'Mình chưa gọi được máy chủ. Bạn vẫn xem được dữ liệu đã lưu; bật sạc tạm khóa, tắt sạc vẫn gửi được.',
            Icons.cloud_off_rounded,
          );
    final reason = link.reason;
    // Never taller than half the screen: with very large text the card
    // scrolls inside instead of covering the page.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: LuxeColors.raisedHigh,
        elevation: 12,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: LuxeColors.hairlineStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // QA 162: Pinova Bot tells it (owner's choice).
                      _BotBadge(
                        mood: retrying
                            ? BatteryBotMood.thinking
                            : syncPending
                            ? BatteryBotMood.idle
                            : BatteryBotMood.worried,
                        icon: icon,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                key: const ValueKey('offline-title'),
                                style: LuxeText.item.copyWith(fontSize: 15.5),
                              ),
                              const SizedBox(height: 3),
                              Text(detail, style: LuxeText.caption),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  offlineRetryLine(link, retrying: retrying),
                                  if (reason != null &&
                                      !internet &&
                                      !syncPending)
                                    'Lý do: $reason.',
                                ].join(' '),
                                key: const ValueKey('offline-retry-line'),
                                style: LuxeText.caption.copyWith(
                                  color: LuxeColors.dim,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Thu gọn thông báo',
                        child: InkResponse(
                          key: const ValueKey('offline-close'),
                          onTap: onClose,
                          radius: 24,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: LuxeColors.platinumMid,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (internet)
                          TextButton.icon(
                            key: const ValueKey('offline-settings'),
                            onPressed: () async {
                              final opened = await SystemSettings.openNetwork();
                              if (!opened) {
                                AppPopup.showWarning(
                                  'Chưa mở được cài đặt mạng',
                                  detail:
                                      'Mở Cài đặt của điện thoại và bật Wi-Fi hoặc dữ liệu di động.',
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: LuxeColors.platinum,
                            ),
                            icon: const Icon(Icons.settings_rounded, size: 18),
                            label: const Text('Cài đặt mạng'),
                          ),
                        FilledButton.icon(
                          key: const ValueKey('offline-retry'),
                          onPressed: retrying ? null : onRetry,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          icon: retrying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Thử lại'),
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
    );
  }
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Semantics(
      button: true,
      label: 'Ngoại tuyến. Mở thông báo kết nối',
      excludeSemantics: true,
      child: Material(
        color: LuxeColors.raisedHigh,
        elevation: 8,
        shape: const StadiumBorder(
          side: BorderSide(color: LuxeColors.hairlineStrong),
        ),
        child: InkWell(
          key: const ValueKey('offline-pill-tap'),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _BotBadge(mood: BatteryBotMood.worried, size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Ngoại tuyến',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LuxeText.label.copyWith(
                        color: LuxeColors.text,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.expand_less_rounded,
                    size: 18,
                    color: LuxeColors.platinumMid,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecoveredPill extends StatelessWidget {
  const _RecoveredPill({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: Semantics(
      liveRegion: true,
      child: Material(
        color: LuxeColors.raisedHigh,
        elevation: 8,
        shape: const StadiumBorder(
          side: BorderSide(color: LuxeColors.emeraldSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BotBadge(mood: BatteryBotMood.celebrating, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Đã kết nối lại',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuxeText.label.copyWith(
                    color: LuxeColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// QA 162 (owner's choice): Pinova Bot on the offline notices, its face
/// for the state (worried, thinking while a retry runs, celebrating when
/// back, sorry on an empty page). [icon], when set, sits on a small
/// champagne mark at its corner so what is wrong still reads at a glance.
/// The face only moves on a change of mood (one reaction) or while
/// thinking, which is a real retry.
class _BotBadge extends StatelessWidget {
  const _BotBadge({required this.mood, required this.size, this.icon});

  final BatteryBotMood mood;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final mark = icon;
    return Semantics(
      label: 'Pinova Bot',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: BatteryBotMascot(
                displayMode: BatteryBotDisplayMode.avatar,
                size: BatteryBotSize.avatar,
                customWidth: size,
                mood: mood,
                enableFloating: false,
              ),
            ),
            if (mark != null)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: LuxeColors.surface,
                    border: Border.all(
                      color: LuxeColors.champagne.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    mark,
                    size: size * 0.24,
                    color: LuxeColors.champagne,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Ngoại tuyến · cập nhật lúc 14:05" at the top of a page while offline;
/// nothing otherwise. Every tab and every [LuxeScaffold] page has it.
class OfflineStamp extends StatelessWidget {
  const OfflineStamp({super.key});

  /// The stamp's words for [lastOnlineAt] ("lúc 14:05", "lúc 14:05 15/11").
  static String text(DateTime? lastOnlineAt, {DateTime? now}) {
    if (lastOnlineAt == null) return 'Ngoại tuyến · đang dùng dữ liệu đã lưu';
    final at = lastOnlineAt.toLocal();
    final today = (now ?? DateTime.now()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final clock = '${two(at.hour)}:${two(at.minute)}';
    final sameDay =
        at.year == today.year && at.month == today.month && at.day == today.day;
    return sameDay
        ? 'Ngoại tuyến · cập nhật lúc $clock'
        : 'Ngoại tuyến · cập nhật lúc $clock ${two(at.day)}/${two(at.month)}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLinkState>(
    valueListenable: AppConnection.instance,
    builder: (context, link, _) {
      if (!AppConnection.instance.started || !link.offline) {
        return const SizedBox.shrink();
      }
      return Semantics(
        container: true,
        child: Padding(
          key: const ValueKey('offline-stamp'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 15,
                color: LuxeColors.champagne,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text(link.lastOnlineAt),
                  style: LuxeText.label.copyWith(color: LuxeColors.muted),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A page with nothing saved to show while offline: the cloud, one line,
/// "Thử lại". Fits inside a list (no scroll view of its own).
class LuxeOfflineEmpty extends StatefulWidget {
  const LuxeOfflineEmpty({super.key, this.title, this.onRetry});

  /// "Chưa tải được lịch bảo dưỡng"; a general line when null.
  final String? title;

  /// Reloads the page; also run by itself when the link comes back.
  final VoidCallback? onRetry;

  @override
  State<LuxeOfflineEmpty> createState() => _LuxeOfflineEmptyState();
}

class _LuxeOfflineEmptyState extends State<LuxeOfflineEmpty> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await AppConnection.instance.retryNow();
      if (!AppConnection.instance.value.offline) widget.onRetry?.call();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('offline-empty'),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BotBadge(
          mood: BatteryBotMood.sorry,
          icon: Icons.cloud_off_rounded,
          size: 60,
        ),
        const SizedBox(height: 16),
        Text(
          widget.title ?? 'Chưa tải được dữ liệu',
          textAlign: TextAlign.center,
          style: LuxeText.item,
        ),
        const SizedBox(height: 6),
        Text(
          'Cần kết nối mạng để tải lần đầu. Trang tự tải lại khi có kết nối.',
          textAlign: TextAlign.center,
          style: LuxeText.body,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _retrying ? null : _retry,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: _retrying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Thử lại'),
        ),
      ],
    ),
  );
}

/// Runs [onBack] once when the link comes back (a page that failed while
/// offline reloads by itself).
class OfflineRecovery extends StatefulWidget {
  const OfflineRecovery({super.key, required this.onBack, required this.child});

  final VoidCallback? onBack;
  final Widget child;

  @override
  State<OfflineRecovery> createState() => _OfflineRecoveryState();
}

class _OfflineRecoveryState extends State<OfflineRecovery> {
  bool _wasOffline = AppConnection.instance.value.offline;

  @override
  void initState() {
    super.initState();
    AppConnection.instance.addListener(_changed);
  }

  @override
  void dispose() {
    AppConnection.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final offline = AppConnection.instance.value.offline;
    if (_wasOffline && !offline) widget.onBack?.call();
    _wasOffline = offline;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Server-only actions while offline: a clear sentence instead of a
/// failure later. Never put Stop charging behind this.
abstract final class OnlineGate {
  static bool get offline =>
      AppConnection.instance.started && AppConnection.instance.value.offline;

  /// False (and says why) while offline. [what]: "bật sạc", "huấn luyện".
  static bool allows(String what) {
    if (!offline) return true;
    AppPopup.showWarning(
      'Cần kết nối để $what',
      detail: 'Kiểm tra Wi-Fi hoặc dữ liệu di động rồi thử lại.',
      userInitiated: true,
    );
    return false;
  }
}

/// Reports the shell's bottom bar height to [OfflineDock.shellBottom].
class OfflineDockInset extends SingleChildRenderObjectWidget {
  const OfflineDockInset({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderInset();
}

class _RenderInset extends RenderProxyBox {
  double _reported = -1;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if ((height - _reported).abs() < 0.5) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) OfflineDock.shellBottom.value = _reported;
    });
  }

  @override
  void detach() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!attached) OfflineDock.shellBottom.value = 0;
    });
    super.detach();
  }
}

/// The top route, for [OfflineDock].
typedef OfflineTop = ({bool first, bool popup});

class OfflineRouteObserver extends NavigatorObserver {
  final top = ValueNotifier<OfflineTop>((first: true, popup: false));

  void _set(Route<dynamic>? route) {
    if (route == null) return;
    final next = (first: route.isFirst, popup: route is PopupRoute);
    if (next != top.value) {
      SchedulerBinding.instance.addPostFrameCallback((_) => top.value = next);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);
}

/// [child] with the [OfflineStamp] above it, once per page: a page inside
/// a stamped page (a tab inside the shell) does not stamp again.
class OfflineStamped extends StatelessWidget {
  const OfflineStamped({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.getInheritedWidgetOfExactType<_Stamped>() != null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OfflineStamp(),
        Expanded(child: _Stamped(child: child)),
      ],
    );
  }
}

class _Stamped extends InheritedWidget {
  const _Stamped({required super.child});

  @override
  bool updateShouldNotify(_Stamped oldWidget) => false;
}
