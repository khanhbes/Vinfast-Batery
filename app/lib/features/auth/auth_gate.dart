import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/services/maintenance_reminder_service.dart';
import '../../data/services/vehicle_model_link_service.dart';
import '../../main.dart' show firebaseInitErrorProvider;
import '../../navigation/app_navigation.dart';
import 'login_screen.dart';

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
  /// Trạng thái khởi tạo: true khi đang chờ Firebase Auth restore lần đầu.
  bool _initializing = true;

  /// Đã có flag `was_authenticated` (lần trước đã login thành công).
  bool _wasAuthenticated = false;

  /// User đã chủ động Đăng xuất (chỉ khi flag này true mới về Login ngay).
  bool _explicitSignedOut = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// Đọc các session marker và chờ Firebase Auth restore.
  ///
  /// - Bình thường: chờ tối đa 3s cho `authStateChanges()` emit lần đầu.
  /// - Cold start sau update / kill task: nếu marker `was_authenticated == true`
  ///   và `explicit_signed_out == false` thì cho phép chờ thêm tối đa 8s
  ///   để token persistence kịp khôi phục (tránh đẩy user về Login nhầm).
  Future<void> _initialize() async {
    // Đọc marker trước để quyết định timeout.
    try {
      _wasAuthenticated = await SessionService().wasAuthenticated();
      _explicitSignedOut = await SessionService().wasExplicitSignOut();
    } catch (e) {
      debugPrint('[AuthGate] Read session markers error: $e');
    }

    // Nếu Firebase init lỗi thì không cần chờ — hiển thị error UI ngay.
    if (ref.read(firebaseInitErrorProvider) != null) {
      if (mounted) setState(() => _initializing = false);
      return;
    }

    final completer = Completer<User?>();
    StreamSubscription<User?>? sub;
    sub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!completer.isCompleted) completer.complete(user);
      sub?.cancel();
    });

    // Cold-start case: cho phép wait lâu hơn để token kịp restore.
    final timeout = (_wasAuthenticated && !_explicitSignedOut)
        ? const Duration(seconds: 8)
        : const Duration(seconds: 3);

    await completer.future.timeout(timeout, onTimeout: () => null);

    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _retryFirebaseInit() async {
    setState(() => _initializing = true);
    try {
      await Firebase.initializeApp();
      ref.read(firebaseInitErrorProvider.notifier).state = null;
    } catch (e) {
      ref.read(firebaseInitErrorProvider.notifier).state = e;
    }
    await _initialize();
  }

  @override
  Widget build(BuildContext context) {
    final initError = ref.watch(firebaseInitErrorProvider);

    // 1) Firebase init lỗi → màn hình lỗi/retry, KHÔNG đẩy về Login.
    if (initError != null && !_initializing) {
      return _BootstrapErrorScreen(
        error: initError,
        onRetry: _retryFirebaseInit,
      );
    }

    // 2) Đang khởi tạo → splash.
    if (_initializing) {
      return _BootstrapSplashScreen(
        message: (_wasAuthenticated && !_explicitSignedOut)
            ? 'Đang khôi phục phiên đăng nhập...'
            : 'Đang khởi động...',
      );
    }

    // 3) Sau init: dùng StreamBuilder theo dõi auth state realtime.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _BootstrapSplashScreen(message: 'Đang xác thực...');
        }
        if (snapshot.hasData && snapshot.data != null) {
          // User đã authenticated → mark session + vào app.
          // ignore: discarded_futures
          SessionService().markAuthenticated();
          return _AuthenticatedRoot(key: ValueKey(snapshot.data!.uid));
        }
        // User null → về Login (không reset markers ở đây để cold-start
        // sau update vẫn được _initialize() phát hiện).
        return const LoginScreen();
      },
    );
  }
}

class _BootstrapSplashScreen extends StatelessWidget {
  final String message;
  const _BootstrapSplashScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _BootstrapErrorScreen({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: AppColors.error, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Không khởi tạo được Firebase',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Kiểm tra kết nối mạng rồi thử lại. Phiên đăng nhập của bạn '
                  'sẽ được khôi phục tự động khi Firebase sẵn sàng.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        error.toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: AppColors.textTertiary
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử lại'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
}

class _AuthenticatedRoot extends ConsumerStatefulWidget {
  const _AuthenticatedRoot({super.key});

  @override
  ConsumerState<_AuthenticatedRoot> createState() => _AuthenticatedRootState();
}

class _AuthenticatedRootState extends ConsumerState<_AuthenticatedRoot> {
  @override
  void dispose() {
    // Khi logout / unmount: gỡ lifecycle observer của AppUpdateService.
    AppUpdateService().stopObservingLifecycle();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check app updates
      await AppUpdateService().initialize(context: context);

      // Initialize notification center and sync models
      await NotificationCenterService().initialize();
      await NotificationCenterService().syncModels();

      // Authenticated bootstrap (di chuyển từ main.dart — chạy SAU khi auth sẵn sàng)
      await _runAuthenticatedBootstrap();
    });
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

    try {
      await VehicleSpecRepository().getAllSpecs();
    } catch (e) {
      debugPrint('[AuthBootstrap] VinFast spec sync error: $e');
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
      debugPrint('[AuthBootstrap] Vehicle fetch error: $e');
    }
    if (vehicleData == null) return;

    // Auto-match VinFast model spec
    try {
      final linkedId = vehicleData['vinfastModelId'] as String?;
      if (linkedId == null || linkedId.isEmpty) {
        final name = vehicleData['vehicleName'] as String? ?? '';
        final match = await VehicleSpecRepository().matchByVehicleName(name);
        if (match != null) {
          await VehicleModelLinkService()
              .linkModel(vehicleId: selectedVehicleId, spec: match);
        }
      }
    } catch (e) {
      debugPrint('[AuthBootstrap] Auto-match error: $e');
    }

    // Maintenance reminder (theo ODO)
    try {
      final odo = (vehicleData['currentOdo'] ?? 0) as num;
      MaintenanceReminderService().checkAndNotify(
        vehicleId: selectedVehicleId,
        currentOdo: odo.toInt(),
      );
    } catch (e) {
      debugPrint('[AuthBootstrap] Maintenance check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe thay đổi selected vehicle → persist vào secure storage.
    ref.listen<String>(selectedVehicleIdProvider, (prev, next) {
      if (prev == next) return;
      // ignore: discarded_futures
      SessionService().setSelectedVehicleId(next);
    });
    return const AppNavigation();
  }
}
