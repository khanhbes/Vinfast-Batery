import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/connection_coordinator.dart';
import '../services/onboarding_service.dart';

enum _ApiProbeState { checking, ready, unavailable, dependencyUnavailable }

/// A non-blocking connection strip for the authenticated application only.
/// Authentication and password reset remain usable when the app API is down.
class InternetConnectionNotice extends StatefulWidget {
  const InternetConnectionNotice({super.key, required this.child});
  final Widget child;

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
  int _failureCount = 0;
  int _retryIndex = 0;
  bool _probing = false;

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
    _retryTimer?.cancel();
    await _connection.start();
    await _probeApi();
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
    final String? message = switch (_apiState) {
      _ApiProbeState.checking || _ApiProbeState.ready => null,
      _ApiProbeState.unavailable => 'Không kết nối được máy chủ ứng dụng.',
      _ApiProbeState.dependencyUnavailable =>
        'Máy chủ đang khởi động. Một số dữ liệu có thể chưa cập nhật.',
    };
    final internetMessage = !_status.internetAvailable
        ? 'Mất kết nối Internet. Dữ liệu gần nhất vẫn được giữ.'
        : message;
    if (internetMessage == null) return widget.child;

    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: colors.errorContainer,
              child: Semantics(
                liveRegion: true,
                label: internetMessage,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          internetMessage,
                          style: TextStyle(
                            color: colors.onErrorContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
