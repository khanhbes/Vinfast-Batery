import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/onboarding_service.dart';

class InternetConnectionNotice extends StatefulWidget {
  const InternetConnectionNotice({super.key, required this.child});
  final Widget child;

  @override
  State<InternetConnectionNotice> createState() => _InternetNoticeState();
}

class _InternetNoticeState extends State<InternetConnectionNotice> {
  StreamSubscription<ConnectivityResult>? _subscription;
  bool _offline = false;
  bool _apiUnavailable = false;

  @override
  void initState() {
    super.initState();
    _subscription = Connectivity().onConnectivityChanged.listen(_handle);
    unawaited(_retry());
    unawaited(_probeApi());
  }

  Future<void> _retry() async =>
      _handle(await Connectivity().checkConnectivity());

  Future<void> _probeApi() async {
    if (!AppConstants.isApiConfigured) {
      if (mounted) setState(() => _apiUnavailable = true);
      return;
    }
    final result = await ApiService().get('/api/ready');
    if (mounted) setState(() => _apiUnavailable = result['success'] != true);
  }

  void _handle(ConnectivityResult result) {
    final offline = result == ConnectivityResult.none;
    if (offline == _offline) return;
    _offline = offline;
    if (!offline) {
      unawaited(_probeApi());
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          unawaited(OnboardingSyncCoordinator.shared.syncIfPending(uid));
        }
      } catch (_) {
        // Auth bootstrap will retry from AuthGate once Firebase is ready.
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          widget.child,
          if (_offline || _apiUnavailable)
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
                    label: _offline
                        ? 'Mất kết nối Internet. Dữ liệu gần nhất vẫn được giữ.'
                        : 'Máy chủ chưa sẵn sàng. Dữ liệu gần nhất vẫn được giữ.',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 18, color: Theme.of(context).colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _offline
                                  ? 'Ngoại tuyến · đang dùng dữ liệu gần nhất'
                                  : 'Máy chủ chưa sẵn sàng · đang dùng dữ liệu gần nhất',
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
