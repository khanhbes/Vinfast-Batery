import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_connection.dart';
import '../services/onboarding_service.dart';
import 'offline_dock.dart';

/// Starts the app's connection check for the signed-in app and stops it on
/// sign-out. Authentication and password reset stay usable when the API is
/// down.
///
/// QA 161 (owner's choice): no strip at the top any more. Being offline is
/// shown by the floating [OfflineDock] card and the [OfflineStamp] on each
/// page; the check itself is [AppConnection] (without the sign-in token,
/// whose slow refresh looked like a dead server).
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
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppConnection.instance.addListener(_changed);
    unawaited(AppConnection.instance.start());
    _syncPending();
  }

  @override
  void didUpdateWidget(InternetConnectionNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPending();
  }

  void _syncPending() {
    final retry = widget.onRetryOnboarding;
    final value = widget.onboardingPending ? (retry ?? () async {}) : null;
    // Set after this frame: listeners rebuild the dock above.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) OfflineDock.pendingSync.value = value;
    });
  }

  /// Back online: the survey waiting to be sent goes now.
  void _changed() {
    final offline = AppConnection.instance.value.offline;
    if (_wasOffline && !offline) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          unawaited(OnboardingSyncCoordinator.shared.syncIfPending(uid));
        }
      } catch (_) {
        // AuthGate retries when Firebase initialization completes.
      }
    }
    _wasOffline = offline;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppConnection.instance.check(force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppConnection.instance.removeListener(_changed);
    AppConnection.instance.stop();
    if (widget.onboardingPending) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => OfflineDock.pendingSync.value = null,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
