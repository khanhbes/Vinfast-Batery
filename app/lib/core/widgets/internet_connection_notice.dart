import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/connection_coordinator.dart';
import '../services/onboarding_service.dart';

class InternetConnectionNotice extends StatefulWidget {
  const InternetConnectionNotice({super.key, required this.child});
  final Widget child;

  @override
  State<InternetConnectionNotice> createState() => _InternetNoticeState();
}

class _InternetNoticeState extends State<InternetConnectionNotice> {
  final ConnectionCoordinator _connection = ConnectionCoordinator();
  StreamSubscription<ChargingConnectionState>? _statusSubscription;
  ChargingConnectionState _status = const ChargingConnectionState();
  bool _offline = false;
  bool _apiUnavailable = false;

  @override
  void initState() {
    super.initState();
    _statusSubscription = _connection.stream.listen((status) {
      final recovered = status.internetAvailable && !_status.internetAvailable;
      if (mounted) {
        setState(() {
          _status = status;
          _offline = !status.internetAvailable;
          _apiUnavailable = !status.apiReachable;
        });
      }
      if (recovered) {
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            unawaited(OnboardingSyncCoordinator.shared.syncIfPending(uid));
          }
        } catch (_) {
          // AuthGate will retry once Firebase initialization completes.
        }
      }
    });
    unawaited(_connection.start());
    unawaited(_retry());
    unawaited(_probeApi());
  }

  Future<void> _retry() async => _connection.start();

  Future<void> _probeApi() async {
    if (!AppConstants.isApiConfigured) {
      if (mounted) setState(() => _apiUnavailable = true);
      return;
    }
    final result = await ApiService().get('/api/ready');
    final available = result['success'] == true;
    _connection.markApiReachable(available);
    if (mounted) setState(() => _apiUnavailable = !available);
  }

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    unawaited(_connection.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = !_status.internetAvailable
        ? 'Ngoại tuyến · đang dùng dữ liệu gần nhất'
        : !_status.apiReachable || _apiUnavailable
            ? 'Máy chủ chưa sẵn sàng · đang dùng dữ liệu gần nhất'
            : !_status.firebaseReachable
                ? 'Đồng bộ tài khoản đang tạm gián đoạn'
                : !_status.shellyReachable
                    ? 'Bộ sạc chưa kết nối · điều khiển đang bị khóa'
                    : 'Đang kiểm tra kết nối';
    final semanticMessage = !_status.internetAvailable
        ? 'Mất kết nối Internet. Dữ liệu gần nhất vẫn được giữ.'
        : !_status.apiReachable || _apiUnavailable
            ? 'Máy chủ chưa sẵn sàng. Dữ liệu gần nhất vẫn được giữ.'
            : message;
    return Stack(
      children: [
        widget.child,
        if (_offline || _apiUnavailable || !_status.apiReachable || !_status.firebaseReachable || !_status.shellyReachable)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Semantics(
                    liveRegion: true,
                    label: semanticMessage,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              unawaited(_retry());
                              unawaited(_probeApi());
                            },
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
