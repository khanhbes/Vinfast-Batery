import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../widgets/luxe_connection_notice.dart' show ConnectionIssue;

/// What the app knows about its link to the Pinova server (QA 161).
@immutable
class AppLinkState {
  const AppLinkState({
    this.issue,
    this.reason,
    this.nextProbeAt,
    this.lastOnlineAt,
    this.checking = false,
    this.recoveredAt,
  });

  /// Null while the server answers. Only [ConnectionIssue.internet] and
  /// [ConnectionIssue.server] are used here; the Shelly plug has its own.
  final ConnectionIssue? issue;

  /// Why the last check failed, in plain words ("hết thời gian chờ",
  /// "HTTP 503"), so a screenshot tells where the fault is.
  final String? reason;

  /// When the next automatic check runs.
  final DateTime? nextProbeAt;

  /// The last time the server answered (kept across app starts): the
  /// "cập nhật lúc" on every page.
  final DateTime? lastOnlineAt;

  /// A check is in flight.
  final bool checking;

  /// When the link came back, for the short "Đã kết nối lại".
  final DateTime? recoveredAt;

  bool get offline => issue != null;

  AppLinkState copyWith({
    ConnectionIssue? Function()? issue,
    String? Function()? reason,
    DateTime? Function()? nextProbeAt,
    DateTime? lastOnlineAt,
    bool? checking,
    DateTime? Function()? recoveredAt,
  }) => AppLinkState(
    issue: issue == null ? this.issue : issue(),
    reason: reason == null ? this.reason : reason(),
    nextProbeAt: nextProbeAt == null ? this.nextProbeAt : nextProbeAt(),
    lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
    checking: checking ?? this.checking,
    recoveredAt: recoveredAt == null ? this.recoveredAt : recoveredAt(),
  );
}

/// The result of one look at the server.
enum ProbeOutcome { ready, starting, failed }

typedef ServerProbe =
    Future<({ProbeOutcome outcome, String? reason})> Function();

/// One source of truth for "is the app online" (QA 161). Before, the top
/// strip ran its own check with the account's sign-in token: a slow token
/// refresh looked like a dead server ("Chưa liên lạc được máy chủ" while
/// the server answered). The check now asks `/api/ready` without a token,
/// and every API call that reaches the server, or fails to, updates it.
///
/// Started by the signed-in shell, stopped on sign-out; the floating
/// notice, the page stamp and [ErrorState] all read it.
class AppConnection extends ValueNotifier<AppLinkState> {
  AppConnection({
    ServerProbe? probe,
    Connectivity? connectivity,
    DateTime Function()? clock,
  }) : _probe = probe ?? _readyProbe,
       _connectivity = connectivity,
       _clock = clock ?? DateTime.now,
       super(const AppLinkState());

  static AppConnection instance = AppConnection();

  final ServerProbe _probe;
  final Connectivity? _connectivity;
  final DateTime Function() _clock;

  StreamSubscription<ConnectivityResult>? _network;
  Timer? _retry;
  int _failures = 0;
  int _retryIndex = 0;
  bool _internet = true;
  bool _started = false;
  bool _probing = false;

  /// Signed-in shells holding the check: AuthGate swaps one for another
  /// (the new one starts before the old one stops).
  int _holders = 0;

  /// Started (a signed-in session): the notice shows only then.
  bool get started => _started;

  /// One failed check is ignored (a cold start, a network hand-over); the
  /// app says it is offline from the second.
  static const failuresBeforeNotice = 2;

  static const retryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  static const _lastOnlineKey = 'app_connection.last_online_at';

  Future<void> start() async {
    _holders++;
    if (_started) return;
    _started = true;
    unawaited(_loadLastOnline());
    try {
      ServicesBinding.instance;
      final connectivity = _connectivity ?? Connectivity();
      _network = connectivity.onConnectivityChanged.listen(
        _onNetwork,
        onError: (_) {},
      );
      _onNetwork(await connectivity.checkConnectivity());
    } on Object {
      // No plugin (unit tests): the server check alone decides.
    }
    await check();
  }

  void stop() {
    if (_holders > 0) _holders--;
    if (_holders > 0) return;
    _started = false;
    _retry?.cancel();
    unawaited(_network?.cancel());
    _network = null;
    _failures = 0;
    _retryIndex = 0;
    _internet = true;
    // Called while the tree is torn down (sign-out): listeners rebuild
    // after this frame.
    scheduleMicrotask(() {
      if (!_started) value = AppLinkState(lastOnlineAt: value.lastOnlineAt);
    });
  }

  /// "Thử lại": check now, whatever the countdown says.
  Future<void> retryNow() => check(force: true);

  Future<void> check({bool force = false}) async {
    if (_probing || (!_started && !force)) return;
    _probing = true;
    _retry?.cancel();
    value = value.copyWith(checking: true);
    final result = await _probe();
    _probing = false;
    if (!_started) {
      value = value.copyWith(checking: false);
      return;
    }
    switch (result.outcome) {
      case ProbeOutcome.ready:
        _online();
      case ProbeOutcome.starting:
      case ProbeOutcome.failed:
        _failed(
          result.outcome == ProbeOutcome.starting
              ? 'máy chủ đang khởi động'
              : result.reason,
        );
    }
  }

  /// An API call got an answer from the server (any HTTP status).
  void sawServer() {
    if (!_started) return;
    if (value.offline || _failures > 0) {
      _online();
    } else {
      _touch();
    }
  }

  /// An API call could not reach the server: check soon.
  void missedServer() {
    if (!_started || _probing) return;
    if (_retry?.isActive == true && value.offline) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 1), () => unawaited(check()));
  }

  /// Tests: the phone's network went away or came back.
  @visibleForTesting
  void debugNetwork({required bool online}) =>
      _onNetwork(online ? ConnectivityResult.wifi : ConnectivityResult.none);

  void _onNetwork(ConnectivityResult result) {
    final online = result != ConnectivityResult.none;
    if (online == _internet) return;
    _internet = online;
    if (!online) {
      _failures = failuresBeforeNotice;
      _show(ConnectionIssue.internet, 'điện thoại không có mạng');
      _retry?.cancel();
      value = value.copyWith(nextProbeAt: () => null, checking: false);
    } else {
      // Wi-Fi or mobile data is back: the server decides.
      unawaited(check(force: true));
    }
  }

  void _online() {
    final wasOffline = value.offline;
    _failures = 0;
    _retryIndex = 0;
    _retry?.cancel();
    final now = _clock();
    value = AppLinkState(
      lastOnlineAt: now,
      recoveredAt: wasOffline ? now : null,
    );
    unawaited(_saveLastOnline(now));
  }

  void _touch() {
    final now = _clock();
    final last = value.lastOnlineAt;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    value = value.copyWith(lastOnlineAt: now);
    unawaited(_saveLastOnline(now));
  }

  void _failed(String? reason) {
    _failures++;
    if (!_internet) {
      _show(ConnectionIssue.internet, 'điện thoại không có mạng');
    } else if (_failures >= failuresBeforeNotice) {
      _show(ConnectionIssue.server, reason);
    }
    final delay = retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)];
    if (_retryIndex < retryDelays.length - 1) _retryIndex++;
    final at = _clock().add(delay);
    value = value.copyWith(checking: false, nextProbeAt: () => at);
    _retry = Timer(delay, () => unawaited(check()));
  }

  void _show(ConnectionIssue issue, String? reason) {
    value = value.copyWith(
      issue: () => issue,
      reason: () => reason,
      recoveredAt: () => null,
    );
  }

  Future<void> _loadLastOnline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = DateTime.tryParse(prefs.getString(_lastOnlineKey) ?? '');
      if (saved != null && value.lastOnlineAt == null) {
        value = value.copyWith(lastOnlineAt: saved);
      }
    } on Object {
      // A missing time only drops "cập nhật lúc".
    }
  }

  Future<void> _saveLastOnline(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastOnlineKey, at.toIso8601String());
    } on Object {
      // Same.
    }
  }

  /// `GET /api/ready` without the sign-in token (public, cheap).
  static Future<({ProbeOutcome outcome, String? reason})> _readyProbe() async {
    final uri = AppConstants.tryBuildApiUri('/api/ready');
    if (uri == null) {
      return (outcome: ProbeOutcome.failed, reason: 'chưa cấu hình máy chủ');
    }
    try {
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return (outcome: ProbeOutcome.ready, reason: null);
      }
      if (response.statusCode == 503) {
        return (outcome: ProbeOutcome.starting, reason: 'HTTP 503');
      }
      return (
        outcome: ProbeOutcome.failed,
        reason: 'HTTP ${response.statusCode}',
      );
    } on TimeoutException {
      return (outcome: ProbeOutcome.failed, reason: 'hết thời gian chờ');
    } on SocketException catch (e) {
      final lookup = e.message.toLowerCase().contains('host lookup');
      return (
        outcome: ProbeOutcome.failed,
        reason: lookup
            ? 'không tìm thấy địa chỉ máy chủ'
            : 'không mở được kết nối',
      );
    } on HandshakeException {
      return (outcome: ProbeOutcome.failed, reason: 'lỗi kết nối bảo mật');
    } on Object {
      return (outcome: ProbeOutcome.failed, reason: 'lỗi mạng');
    }
  }
}
