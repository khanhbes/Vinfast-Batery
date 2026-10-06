import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/models/onboarding_draft.dart';
import '../../core/services/onboarding_service.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/services/session_service.dart';
import '../../core/widgets/bootstrap_splash.dart';
import '../../core/widgets/internet_connection_notice.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/services/maintenance_reminder_service.dart';
import '../../data/services/vehicle_model_link_service.dart';
import '../../data/services/smart_charger_credentials_service.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import '../../core/services/firebase_bootstrap_coordinator.dart';
import '../../data/repositories/smart_charger_repository.dart';
import '../../data/models/smart_charger_binding.dart';
import '../../main.dart' show firebaseInitErrorProvider;
import '../../navigation/app_navigation.dart';
import 'login_screen.dart';
import 'onboarding_chat_screen.dart';

/// AuthGate: gate có trạng thái khởi động rõ ràng.
///
/// 1. Chờ Firebase Auth restore xong (connectionState != waiting).
/// 2. Nếu user != null → vào AppNavigation.
/// 3. Nếu user == null → kiểm tra:
///    - Nếu explicit_signed_out → về LoginScreen ngay.
///    - Nếu was_authenticated (cold start, chưa restore xong) → chờ thêm timeout.
///    - Ngược lại → LoginScreen.
///
/// Không swallow lỗi Firebase.initializeApp(); nếu init lỗi thì hiện retry.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  static const _firebaseBootstrapTimeout = Duration(seconds: 30);

  /// Trạng thái khởi tạo: true khi đang chờ Firebase Auth restore lần đầu.
  bool _initializing = true;
  bool _retryingFirebaseInit = false;

  /// Đã có flag `was_authenticated` (lần trước đã login thành công).
  bool _wasAuthenticated = false;

  /// User đã chủ động Đăng xuất (chỉ khi flag này true mới về Login ngay).
  bool _explicitSignedOut = false;
  bool _updateCheckStarted = false;
  StreamSubscription<User?>? _authSubscription;
  Stream<User?>? _authStream;
  User? _authUser;
  bool _authResolved = false;
  bool _introFinished = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Đọc các session marker và chờ Firebase Auth restore.
  ///
  /// - Bình thường: chờ tối đa 3s cho `authStateChanges()` emit lần đầu.
  /// - Cold start sau update / kill task: nếu marker `was_authenticated == true`
  ///   và `explicit_signed_out == false` thì cho phép chờ thêm tối đa 8s
  ///   để token persistence kịp khôi phục (tránh đẩy user về Login nhầm).
  Future<void> _initialize() async {
    // Purge credential remnants before any Firebase bootstrap path can return.
    // Auth fields are never prefilled from this legacy store.
    unawaited(SessionService().clearLegacyCredentials());
    // Nếu Firebase init đã có lỗi (ví dụ từ trước hoặc override trong test), hiển thị error UI ngay
    if (ref.read(firebaseInitErrorProvider) != null) {
      if (mounted) setState(() => _initializing = false);
      return;
    }

    // Đọc marker trước để quyết định timeout.
    try {
      _wasAuthenticated = await SessionService().wasAuthenticated();
      _explicitSignedOut = await SessionService().wasExplicitSignOut();
    } catch (e) {
      debugPrint('[AuthGate] Session marker read failed (${e.runtimeType}).');
    }

    // Đảm bảo Firebase sẵn sàng trước khi truy cập bất kỳ Firebase service nào
    if (!FirebaseBootstrapCoordinator.isReady) {
      try {
        await FirebaseBootstrapCoordinator.ensureInitialized().timeout(
          _firebaseBootstrapTimeout,
        );
        ref.read(firebaseInitErrorProvider.notifier).state = null;
      } catch (e) {
        // Native initialization can finish immediately after a timeout on a
        // busy emulator. Do not replace a now-ready app with a stale error.
        if (FirebaseBootstrapCoordinator.isReady) {
          ref.read(firebaseInitErrorProvider.notifier).state = null;
        } else {
          debugPrint(
            '[AuthGate] Firebase initialization failed (${e.runtimeType}).',
          );
          if (mounted) {
            ref.read(firebaseInitErrorProvider.notifier).state = e;
            setState(() => _initializing = false);
          }
          return;
        }
      }
    }

    // Khởi tạo push notification trong nền khi Firebase đã sẵn sàng
    unawaited(
      FirebaseBootstrapCoordinator.initializePushServices().catchError((e) {
        debugPrint('[AuthGate] Push services init error (${e.runtimeType}).');
      }),
    );

    final completer = Completer<User?>();
    try {
      // Keep one auth subscription for this gate. Recreating a StreamBuilder
      // stream during rebuilds can emit a transient waiting state and replace
      // the focused login form with the splash.
      await _authSubscription?.cancel();
      _authStream = FirebaseAuth.instance.authStateChanges();
      _authSubscription = _authStream!.listen((user) {
        ShellyConnectionCoordinator.shared.activateAccount(user?.uid);
        _authUser = user;
        _authResolved = true;
        if (!completer.isCompleted) completer.complete(user);
        if (mounted) setState(() {});
      });

      // Cold-start case: cho phép wait lâu hơn để token kịp restore.
      final timeout = (_wasAuthenticated && !_explicitSignedOut)
          ? const Duration(seconds: 8)
          : const Duration(seconds: 3);

      User? restoredUser;
      restoredUser = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      // A stalled auth stream must not keep the user in an endless splash.
      // The listener remains active and can still promote the session later.
      if (restoredUser == null && !completer.isCompleted) {
        _authResolved = true;
      }

      // Nếu lần trước đã đăng nhập và chưa bấm Đăng xuất, nhưng Firebase vẫn
      // trả null ở cold start, thử khôi phục bằng credential đã mã hóa.
      if (restoredUser == null && _wasAuthenticated && !_explicitSignedOut) {
        restoredUser = FirebaseAuth.instance.currentUser;
        if (restoredUser != null) {
          await SessionService().markAuthenticated();
          _wasAuthenticated = true;
          _explicitSignedOut = false;
        }
      }
    } catch (e) {
      debugPrint('[AuthGate] Auth restore failed (${e.runtimeType}).');
      _authResolved = true;
    }

    if (mounted) {
      setState(() => _initializing = false);
      _scheduleUpdateCheck();
    }
  }

  void _scheduleUpdateCheck() {
    if (_initializing || !_introFinished) return;
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Public endpoint: check app version even before the user signs in.
      AppUpdateService().initialize(context: context);
    });
  }

  Future<void> _retryFirebaseInit() async {
    if (_retryingFirebaseInit) return;
    setState(() {
      _retryingFirebaseInit = true;
      _initializing = true;
    });
    try {
      if (!FirebaseBootstrapCoordinator.isReady) {
        await FirebaseBootstrapCoordinator.ensureInitialized().timeout(
          _firebaseBootstrapTimeout,
        );
      }
      if (!mounted) return;
      unawaited(
        FirebaseBootstrapCoordinator.initializePushServices().catchError((e) {
          debugPrint('[AuthGate] Push retry error (${e.runtimeType}).');
        }),
      );
      ref.read(firebaseInitErrorProvider.notifier).state = null;
    } catch (e) {
      if (!mounted) return;
      if (FirebaseBootstrapCoordinator.isReady) {
        ref.read(firebaseInitErrorProvider.notifier).state = null;
      } else {
        ref.read(firebaseInitErrorProvider.notifier).state = e;
      }
    }
    try {
      await _initialize();
    } finally {
      if (mounted) setState(() => _retryingFirebaseInit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initError = ref.watch(firebaseInitErrorProvider);

    // 1) Firebase init lỗi hoặc chưa sẵn sàng sau khi hết initializing → màn hình lỗi/retry.
    // Tuyệt đối KHÔNG render StreamBuilder hay truy cập FirebaseAuth.instance ở đây.
    Widget content;
    if (_retryingFirebaseInit ||
        ((initError != null || !FirebaseBootstrapCoordinator.isReady) &&
            !_initializing)) {
      content = KeyedSubtree(
        key: const ValueKey('gate-error'),
        child: _BootstrapErrorScreen(
          retrying: _retryingFirebaseInit,
          onRetry: _retryFirebaseInit,
        ),
      );
    } else if (_initializing || !_introFinished) {
      // 2) Đang khởi tạo → splash.
      content = KeyedSubtree(
        key: const ValueKey('gate-splash'),
        child: _BootstrapSplashScreen(
          animate: !_introFinished,
          onFinished: () {
            if (mounted && !_introFinished) {
              setState(() => _introFinished = true);
              _scheduleUpdateCheck();
            }
          },
          message: (_wasAuthenticated && !_explicitSignedOut)
              ? 'Đang khôi phục phiên đăng nhập...'
              : 'Đang khởi động...',
        ),
      );
    } else {
      // 3) Sau init: chỉ dùng StreamBuilder khi Firebase chắc chắn đã sẵn sàng.
      content = KeyedSubtree(
        key: const ValueKey('gate-stream'),
        child: StreamBuilder<User?>(
          stream: _authStream,
          initialData: _authUser,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !_authResolved &&
                snapshot.data == null) {
              return const _BootstrapSplashScreen(
                message: 'Đang xác thực...',
                animate: false,
              );
            }
            if (snapshot.hasData && snapshot.data != null) {
              // User đã authenticated → mark session + vào app.
              // ignore: discarded_futures
              SessionService().markAuthenticated();
              return _AuthenticatedRoot(key: ValueKey(snapshot.data!.uid));
            }
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              // Trường hợp StreamBuilder bắt đầu bằng snapshot null nhưng Firebase
              // đã có currentUser sau bước restore ở _initialize().
              // ignore: discarded_futures
              SessionService().markAuthenticated();
              return _AuthenticatedRoot(key: ValueKey(currentUser.uid));
            }
            // User null → về Login (không reset markers ở đây để cold-start
            // sau update vẫn được _initialize() phát hiện).
            return const LoginScreen();
          },
        ),
      );
    }

    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: content,
    );
  }
}

class _BootstrapSplashScreen extends StatelessWidget {
  final String message;
  final bool animate;
  final VoidCallback? onFinished;
  const _BootstrapSplashScreen({
    required this.message,
    this.animate = true,
    this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    return BootstrapSplash(
      message: message,
      animate: animate,
      onFinished: onFinished,
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  final bool retrying;
  final VoidCallback onRetry;
  const _BootstrapErrorScreen({required this.retrying, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    color: colors.onSurfaceVariant,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa thể mở ứng dụng',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quá trình khởi động đang mất nhiều thời gian. '
                    'Hãy thử lại; bạn không cần nhập lại thông tin.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: retrying ? null : onRetry,
                    icon: retrying
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(retrying ? 'Đang thử lại' : 'Thử lại'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
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

class _AuthenticatedRoot extends ConsumerStatefulWidget {
  const _AuthenticatedRoot({super.key});

  @override
  ConsumerState<_AuthenticatedRoot> createState() => _AuthenticatedRootState();
}

class _AuthenticatedRootState extends ConsumerState<_AuthenticatedRoot>
    with WidgetsBindingObserver {
  static const _profileLoadTimeout = Duration(seconds: 12);

  Future<DocumentSnapshot<Map<String, dynamic>>>? _profileFuture;
  Future<OnboardingDraft?>? _draftFuture;
  String? _draftUid;

  Future<void> _retryPendingOnboarding() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await OnboardingSyncCoordinator.shared.syncIfPending(uid, force: true);
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    _refreshOnboardingRoute();
  }

  void _refreshOnboardingRoute() {
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted || user == null) return;
    // The shell may have cached an empty fleet while the local-first draft
    // was pending. Refresh it after commit/retry instead of leaving the new
    // authoritative vehicle invisible until the next process restart.
    ref.invalidate(allVehiclesProvider);
    setState(() {
      _profileFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_profileLoadTimeout);
      _draftUid = user.uid;
      _draftFuture = OnboardingDraftRepository().load(user.uid);
    });
  }

  @override
  void dispose() {
    // Khi logout / unmount: gỡ lifecycle observer của AppUpdateService.
    AppUpdateService().stopObservingLifecycle();
    WidgetsBinding.instance.removeObserver(this);
    ref.read(activeChargingSessionProvider).clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Initialize notification center and sync models
      await NotificationCenterService().initialize();
      await NotificationCenterService().syncModels();

      // Authenticated bootstrap (di chuyển từ main.dart — chạy SAU khi auth sẵn sàng)
      await _runAuthenticatedBootstrap();
      await AuthService().checkForegroundAccount(force: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // ignore: discarded_futures
    AuthService().checkForegroundAccount();
    // Five-minute cooldown is enforced inside the credentials service.
    // ignore: discarded_futures
    _syncSmartChargerOnForeground();
  }

  Future<void> _syncSmartChargerOnForeground() async {
    try {
      final vehicleId = ref.read(selectedVehicleIdProvider);
      final credentials = SmartChargerCredentialsService();
      final restored = await credentials.restoreFromCloud(vehicleId: vehicleId);
      if (restored != null &&
          (await credentials.readVerification()).readyForControl) {
        await SmartChargerRepositoryFactory.setMode(
          SmartChargerConnectionMode.advancedDirect,
        );
      }
      await ShellyConnectionCoordinator.shared.restore();
    } catch (_) {
      // Offline foreground resume keeps the previously safe local profile.
    }
  }

  /// Thực hiện các tác vụ cần user authenticated:
  /// 0) Khôi phục selected vehicle từ secure session storage.
  /// 1) Đồng bộ catalog VinFast specs (Firestore → cache → local).
  /// 2) Auto-match selected vehicle → VinFast model spec nếu chưa link.
  /// 3) Kiểm tra nhắc bảo dưỡng theo ODO hiện tại.
  Future<void> _runAuthenticatedBootstrap() async {
    // 0) Restore selected vehicle id vào riverpod state
    final selectedVehicleId = await SessionService().getSelectedVehicleId();
    if (mounted && selectedVehicleId != null && selectedVehicleId.isNotEmpty) {
      ref.read(selectedVehicleIdProvider.notifier).state = selectedVehicleId;
    }

    // Restore a previously verified Direct Shelly profile after login. The
    // server returns credentials only through the Firebase-authenticated
    // vault endpoint; an unavailable server never clears local credentials.
    try {
      final credentials = SmartChargerCredentialsService();
      final restored = await credentials.restoreFromCloud(
        vehicleId: selectedVehicleId,
      );
      if (restored != null &&
          (await credentials.readVerification()).readyForControl) {
        await SmartChargerRepositoryFactory.setMode(
          SmartChargerConnectionMode.advancedDirect,
        );
      }
      await ShellyConnectionCoordinator.shared.restore();
    } catch (e) {
      debugPrint(
        '[AuthBootstrap] Smart Charger profile sync error (${e.runtimeType}).',
      );
    }

    try {
      await VehicleSpecRepository().getAllSpecs();
    } catch (e) {
      debugPrint('[AuthBootstrap] VinFast spec sync error (${e.runtimeType}).');
    }

    if (selectedVehicleId == null || selectedVehicleId.isEmpty) return;

    Map<String, dynamic>? vehicleData;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Vehicles')
          .doc(selectedVehicleId)
          .get();
      if (doc.exists) vehicleData = doc.data();
    } catch (e) {
      debugPrint('[AuthBootstrap] Vehicle fetch error (${e.runtimeType}).');
    }
    if (vehicleData == null) return;

    // Auto-match VinFast model spec
    try {
      final linkedId =
          vehicleData['catalogId'] as String? ??
          vehicleData['vinfastModelId'] as String?;
      if (linkedId == null || linkedId.isEmpty) {
        final name = vehicleData['vehicleName'] as String? ?? '';
        final match = await VehicleSpecRepository().matchByVehicleName(name);
        if (match != null) {
          await VehicleModelLinkService().linkModel(
            vehicleId: selectedVehicleId,
            spec: match,
          );
        }
      }
    } catch (e) {
      debugPrint('[AuthBootstrap] Auto-match error (${e.runtimeType}).');
    }

    // Maintenance reminder (theo ODO)
    try {
      final odo = (vehicleData['currentOdo'] ?? 0) as num;
      MaintenanceReminderService().checkAndNotify(
        vehicleId: selectedVehicleId,
        currentOdo: odo.toInt(),
      );
    } catch (e) {
      debugPrint('[AuthBootstrap] Maintenance check error (${e.runtimeType}).');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe thay đổi selected vehicle → persist vào secure storage.
    ref.listen<String>(selectedVehicleIdProvider, (prev, next) {
      if (prev == next) return;
      // ignore: discarded_futures
      SessionService().setSelectedVehicleId(next);
      if (next.isNotEmpty) {
        // ignore: discarded_futures
        _syncSmartChargerOnForeground();
      }
    });

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const InternetConnectionNotice(child: AppNavigation());
    }
    // Retry a persisted onboarding operation whenever the authenticated shell
    // is rebuilt (cold start, foreground restore, or connectivity recovery).
    unawaited(OnboardingSyncCoordinator.shared.syncIfPending(currentUser.uid));

    // Resolve the UID-scoped local draft independently from the profile read.
    // Production rules or a transient Firestore failure must not hide a
    // finalized local-first draft and send the user back to step one.
    if (_draftUid != currentUser.uid) {
      _draftUid = currentUser.uid;
      _draftFuture = OnboardingDraftRepository().load(currentUser.uid);
    }
    _profileFuture ??= FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get()
        .timeout(_profileLoadTimeout);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final createdAt = currentUser.metadata.creationTime;
        final isNew =
            createdAt != null &&
            DateTime.now().difference(createdAt) < const Duration(minutes: 15);

        // Auth can succeed before the first profile write reaches Firestore.
        // Route a new account through its retryable onboarding bootstrap,
        // rather than treating a transient read failure as permission to enter.
        if (snapshot.hasError) {
          return FutureBuilder<OnboardingDraft?>(
            future: _draftFuture,
            builder: (context, draftSnapshot) {
              if (draftSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (draftSnapshot.data?.isEligibleForCommit == true) {
                return InternetConnectionNotice(
                  onboardingPending: true,
                  onRetryOnboarding: _retryPendingOnboarding,
                  child: const AppNavigation(),
                );
              }
              return isNew || draftSnapshot.data != null
                  ? OnboardingChatScreen(onCompleted: _refreshOnboardingRoute)
                  : const InternetConnectionNotice(child: AppNavigation());
            },
          );
        }
        if (!snapshot.hasData) {
          // Restored older accounts can still have unfinished onboarding.
          // Never flash the shell while its profile eligibility is unresolved.
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data?.data();
        return FutureBuilder<OnboardingDraft?>(
          future: _draftFuture,
          builder: (context, draftSnapshot) {
            if (draftSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final draft = draftSnapshot.data;
            // A draft that reached the final step but is waiting for the API
            // must not trap the user on the wizard after a restart. The app
            // shell can show cached data and a retry status strip.
            final syncPending = draft?.isEligibleForCommit == true;
            if (data == null) {
              if (syncPending) {
                return InternetConnectionNotice(
                  onboardingPending: true,
                  onRetryOnboarding: _retryPendingOnboarding,
                  child: const AppNavigation(),
                );
              }
              if (draft != null || isNew) {
                return OnboardingChatScreen(
                  onCompleted: _refreshOnboardingRoute,
                );
              }
              return const InternetConnectionNotice(child: AppNavigation());
            }
            final flowVer = data['registrationFlowVersion'] as int? ?? 1;
            final completedAt = data['onboardingCompletedAt'];
            if (flowVer >= 2 && completedAt == null && !syncPending) {
              return OnboardingChatScreen(onCompleted: _refreshOnboardingRoute);
            }
            return InternetConnectionNotice(
              onboardingPending: completedAt == null && syncPending,
              onRetryOnboarding: _retryPendingOnboarding,
              child: const AppNavigation(),
            );
          },
        );
      },
    );
  }
}
