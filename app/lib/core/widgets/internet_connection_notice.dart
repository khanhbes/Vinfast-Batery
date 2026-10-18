import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/connection_coordinator.dart';
import '../services/onboarding_service.dart';
import '../theme/luxe_theme.dart';
import 'luxe_connection_notice.dart';

enum _ApiProbeState { checking, ready, unavailable, dependencyUnavailable }

/// A non-blocking connection strip for the authenticated application only.
/// Authentication and password reset remain usable when the app API is down.
class InternetConnectionNotice extends StatefulWidget {
  const InternetConnectionNotice({
    super.key,
    required this.child,
    this.onboardingPending = false,
    this.onRetryOnboarding,
  });
  final Widget child;
  final bool onboardingPending;
  final Future<void> Function()? onRetryOnboarding;

  @override
  State<InternetConnectionNotice> createState() => _InternetNoticeState();
}

class _InternetNoticeState extends State<InternetConnectionNotice>
    with WidgetsBindingObserver {
  final ConnectionCoordinator _connection = ConnectionCoordinator();
  StreamSubscription<ChargingConnectionState>? _statusSubscription;
  ChargingConnectionState _status = const ChargingConnectionState();
  _ApiProbeState _apiState = _ApiProbeState.checking;
  Timer? _retryTimer;
  DateTime? _nextProbeAt;
  int _failureCount = 0;
  int _retryIndex = 0;
  bool _probing = false;
  bool _retrying = false;

  static const _retryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusSubscription = _connection.stream.listen(_onConnectionChanged);
    unawaited(_connection.start());
    unawaited(_probeApi());
  }

  void _onConnectionChanged(ChargingConnectionState status) {
    final recovered = status.internetAvailable && !_status.internetAvailable;
    if (!mounted) return;
    setState(() => _status = status);
    if (recovered) {
      unawaited(_probeApi());
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          unawaited(OnboardingSyncCoordinator.shared.syncIfPending(uid));
        }
      } catch (_) {
        // AuthGate retries when Firebase initialization completes.
      }
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      _retryTimer?.cancel();
      await _connection.start();
      await _probeApi();
      if (mounted && widget.onboardingPending) {
        await widget.onRetryOnboarding?.call();
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _probeApi() async {
    if (_probing || !mounted) return;
    _probing = true;
    if (_apiState == _ApiProbeState.checking && mounted) setState(() {});
    var reachable = false;
    var ready = false;
    if (AppConstants.isApiConfigured) {
      try {
        final health = await ApiService()
            .get('/api/health')
            .timeout(const Duration(seconds: 7));
        reachable = health['success'] == true;
        if (reachable) {
          final readiness = await ApiService()
              .get('/api/ready')
              .timeout(const Duration(seconds: 7));
          ready = readiness['success'] == true;
        }
      } on TimeoutException {
        reachable = false;
      } catch (_) {
        reachable = false;
      }
    }
    _probing = false;
    if (!mounted) return;

    if (ready) {
      _failureCount = 0;
      _retryIndex = 0;
      _retryTimer?.cancel();
      _connection.markApiReachable(true);
      setState(() => _apiState = _ApiProbeState.ready);
      return;
    }

    _failureCount++;
    _connection.markApiReachable(false);
    // Ignore one failed probe during process/network startup. Keep checking;
    // only surface a warning after repeated real failures.
    if (_failureCount >= 2) {
      setState(
        () => _apiState = reachable
            ? _ApiProbeState.dependencyUnavailable
            : _ApiProbeState.unavailable,
      );
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _retryDelays[_retryIndex.clamp(0, _retryDelays.length - 1)];
    if (_retryIndex < _retryDelays.length - 1) _retryIndex++;
    _nextProbeAt = DateTime.now().add(delay);
    _retryTimer = Timer(delay, () => unawaited(_probeApi()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_probeApi());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    unawaited(_statusSubscription?.cancel());
    unawaited(_connection.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same notice as the Charge tab (QA 130): icon, wording, retry button
    // and the countdown to the next automatic probe.
    final (ConnectionIssue, String)? problem = widget.onboardingPending
        ? (ConnectionIssue.server, 'Đang chờ đồng bộ thông tin xe')
        : !_status.internetAvailable
        ? (ConnectionIssue.internet, 'Mất kết nối Internet')
        : switch (_apiState) {
            _ApiProbeState.checking || _ApiProbeState.ready => null,
            _ApiProbeState.unavailable => (
              ConnectionIssue.server,
              'Chưa liên lạc được máy chủ',
            ),
            _ApiProbeState.dependencyUnavailable => (
              ConnectionIssue.server,
              'Máy chủ đang khởi động',
            ),
          };
    if (problem == null) return widget.child;

    return Column(
      children: [
        Material(
          color: LuxeColors.sheet,
          child: SafeArea(
            bottom: false,
            child: LuxeConnectionNotice(
              compact: true,
              issue: problem.$1,
              title: problem.$2,
              autoRetry: false,
              nextRetryAt: _retrying ? null : _nextProbeAt,
              onRetry: _retry,
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
