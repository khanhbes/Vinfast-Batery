import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'session_service.dart';
import 'sync_service.dart';
import '../../data/services/push_notification_service.dart';
import 'vehicle_policy.dart';
import 'api_service.dart';
import '../../data/repositories/vehicle_spec_repository.dart';
import '../../data/services/smart_charge_telemetry_foreground_service.dart';
import 'dashboard_preferences_service.dart';

/// AuthService - Xử lý đăng ký/đăng nhập đồng bộ với Web Dashboard
class AuthService {
  /// Product limit is server-configurable in V4; this is the safe client
  /// default used before the remote policy is available.
  /// Safe local default; backend/remote config may lower or raise this
  /// within the product guardrail without requiring an APK update.
  static VehiclePolicy vehiclePolicy = const VehiclePolicy();
  static int get maxVehiclesPerAccount => vehiclePolicy.maxVehiclesPerAccount;

  static void configureVehicleLimit(int value) {
    if (value >= 1 && value <= 10) {
      vehiclePolicy = VehiclePolicy(maxVehiclesPerAccount: value);
    }
  }

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final SyncService _syncService = SyncService();
  final SessionService _session = SessionService();
  DateTime? _lastForegroundBootstrap;
  Future<bool>? _foregroundBootstrapTask;

  /// Revalidates Firebase Auth and the small amount of server state needed by
  /// the foreground app. This deliberately avoids a profile Firestore read on
  /// every request and is throttled to protect the free quota.
  Future<bool> checkForegroundAccount({bool force = false}) async {
    final active = _foregroundBootstrapTask;
    if (active != null) return active;
    final now = DateTime.now();
    if (!force &&
        _lastForegroundBootstrap != null &&
        now.difference(_lastForegroundBootstrap!) <
            const Duration(minutes: 15)) {
      return true;
    }
    final task = _checkForegroundAccountInternal();
    _foregroundBootstrapTask = task;
    try {
      return await task;
    } finally {
      _foregroundBootstrapTask = null;
    }
  }

  Future<bool> _checkForegroundAccountInternal() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await user.getIdToken(true);
      final response = await ApiService().get('/api/mobile/bootstrap');
      final status = response['statusCode'];
      if (status == 401 ||
          response['debugCode'] == 'user-disabled' ||
          response['debugCode'] == 'token-revoked') {
        await _auth.signOut();
        return false;
      }
      if (response['success'] == true) {
        _lastForegroundBootstrap = DateTime.now();
        final data = response['data'];
        final revision = data is Map ? data['catalogRevision'] : null;
        if (revision is num) {
          final specs = VehicleSpecRepository();
          specs.applyRemoteRevision(revision.toInt());
          if (specs.needsRemoteRefresh) {
            await specs.getAllSpecs(forceRemote: true);
          }
        }
        return true;
      }
      // Service failures are retryable and must not terminate an offline
      // session.
      return true;
    } catch (error, stack) {
      debugPrint(
        '[AuthService] foreground bootstrap deferred (${error.runtimeType}).',
      );
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      return true;
    }
  }

  /// Đảm bảo document users/{uid} luôn tồn tại.
  /// Dùng set(merge: true) để không ghi đè dữ liệu cũ nếu doc đã có.
  Future<void> _ensureUserDoc(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AuthService] _ensureUserDoc failed (${e.runtimeType}).');
    }
  }

  /// Stream auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Đăng ký tài khoản mới + đồng bộ web
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      // 1. Tạo user trong Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        return {'success': false, 'error': 'Failed to create user'};
      }

      // Server-side bootstrap continues in the background after Auth succeeds.
      const bootstrapPending = true;

      // Firebase Auth account creation is the success boundary. Profile and
      // backend bootstrap failures remain retryable and must not turn an
      // already-created account into a misleading "registration failed" UI.
      try {
        await user.updateDisplayName(name).timeout(const Duration(seconds: 5));
      } catch (error) {
        debugPrint(
          '[AuthService] display name update deferred (${error.runtimeType}).',
        );
      }

      try {
        await Future.wait<void>([
          _session.clearLegacyCredentials(),
          _session.markUserSynced(),
          _session.markAuthenticated(),
        ]).timeout(const Duration(seconds: 5));
      } catch (error) {
        debugPrint(
          '[AuthService] local session bootstrap deferred (${error.runtimeType}).',
        );
      }

      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set({
              'uid': user.uid,
              'email': email,
              'name': name,
              'phone': phone ?? '',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'source': 'flutter_app',
              'syncedToWeb': false,
              'registrationFlowVersion': 2,
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 8));
      } catch (error) {
        debugPrint(
          '[AuthService] profile bootstrap deferred (${error.runtimeType}).',
        );
      }

      // Remaining synchronization is deliberately detached from the form.
      // AuthGate/onboarding can continue from Firebase/local state while this
      // best-effort task retries its server-side bootstrap.
      unawaited(
        _finishRegistrationBootstrap(user: user, name: name, phone: phone),
      );

      return {
        'success': true,
        'user': user,
        'synced': false,
        'bootstrapPending': bootstrapPending,
        'message': 'Registration successful',
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'Mật khẩu chưa đủ mạnh.';
          break;
        case 'email-already-in-use':
          errorMessage = 'Email này đã được đăng ký.';
          break;
        case 'invalid-email':
          errorMessage = 'Email chưa đúng định dạng.';
          break;
        default:
          errorMessage = 'Chưa thể tạo tài khoản lúc này. Vui lòng thử lại.';
      }
      return {'success': false, 'error': errorMessage, 'code': e.code};
    } catch (e) {
      debugPrint('[AuthService] Registration failed (${e.runtimeType}).');
      return {
        'success': false,
        'error': 'Đăng ký thất bại.',
        'code': 'registrationFailed',
        'retryable': true,
      };
    }
  }

  Future<void> _finishRegistrationBootstrap({
    required User user,
    required String name,
    String? phone,
  }) async {
    try {
      await DashboardPreferencesService.seedPendingTourForUser(
        user.uid,
        DashboardPreferencesService.overviewTourId,
      ).timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint(
        '[AuthService] first-run guide seed deferred (${error.runtimeType}).',
      );
    }
    try {
      await ApiService()
          .post('/api/mobile/registration-bootstrap', {
            'name': name.trim(),
            if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          })
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint(
        '[AuthService] registration API bootstrap deferred (${error.runtimeType}).',
      );
    }
    try {
      await _syncService.syncUserToWeb().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint(
        '[AuthService] registration sync deferred (${error.runtimeType}).',
      );
    }
  }

  /// Đăng nhập + đồng bộ dữ liệu
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      // 1. Đăng nhập Firebase Auth
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        return {'success': false, 'error': 'Login failed'};
      }

      // Lưu phiên ngay sau khi Firebase Auth xác thực thành công. Các bước
      // đồng bộ phía sau có thể chậm/lỗi mạng nhưng không nên làm mất login.
      await _session.clearLegacyCredentials();
      await _session.markAuthenticated();
      unawaited(_syncAfterLogin(user));

      return {'success': true, 'user': user, 'message': 'Login successful'};
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          errorMessage = 'Email hoặc mật khẩu chưa chính xác.';
          break;
        case 'too-many-requests':
          errorMessage = 'Bạn đã thử đăng nhập nhiều lần. Hãy đợi rồi thử lại.';
          break;
        case 'invalid-email':
          errorMessage = 'Email không đúng định dạng.';
          break;
        case 'user-disabled':
          errorMessage =
              'Tài khoản hiện không thể đăng nhập. Hãy liên hệ hỗ trợ.';
          break;
        default:
          errorMessage = 'Chưa thể đăng nhập lúc này. Vui lòng thử lại.';
      }
      return {'success': false, 'error': errorMessage, 'code': e.code};
    } catch (e) {
      debugPrint('[AuthService] Login error (${e.runtimeType}).');
      return {
        'success': false,
        'error': 'Đăng nhập thất bại.',
        'code': 'loginFailed',
        'retryable': true,
      };
    }
  }

  Future<void> _syncAfterLogin(User user) async {
    try {
      await _ensureUserDoc(user);
      await loadVehiclePolicy();
      await _firestore.collection('users').doc(user.uid).set({
        'lastLogin': FieldValue.serverTimestamp(),
        'lastLoginSource': 'flutter_app',
      }, SetOptions(merge: true));
      await _syncService.syncUserToWeb();
      await _syncService.syncAllVehiclesToWeb();
      await _session.markUserSynced();
      _syncService.startAutoSync();
    } catch (error, stack) {
      debugPrint(
        '[AuthService] post-login sync deferred: ${error.runtimeType}',
      );
      if (kDebugMode) debugPrintStack(stackTrace: stack);
    }
  }

  /// Khôi phục đăng nhập không cần người dùng nhập lại mật khẩu.
  ///
  /// Firebase Auth thường tự persist user trên Android. Method này là lớp
  /// dự phòng khi cold start trả về `currentUser == null` dù user đã từng
  /// đăng nhập và chưa bấm đăng xuất.
  Future<User?> restoreRememberedLogin() async {
    await _session.clearLegacyCredentials();
    if (_auth.currentUser != null) {
      await _session.markAuthenticated();
      return _auth.currentUser;
    }

    return null;
  }

  /// Đăng xuất — chỉ method này được gọi FirebaseAuth.signOut()
  Future<Map<String, dynamic>> logout() async {
    try {
      try {
        await PushNotificationService.instance.revokeCurrentUser().timeout(
          const Duration(seconds: 5),
        );
      } catch (error) {
        // A failed API revocation must not trap the previous account in UI.
        debugPrint(
          '[AuthService] push revocation deferred (${error.runtimeType})',
        );
      }
      // Stop the local telemetry worker only. Do not send a relay OFF command;
      // the Shelly timer remains the hardware safety authority and another
      // device may continue monitoring the account-scoped session.
      try {
        await SmartChargeTelemetryForegroundService.stop().timeout(
          const Duration(seconds: 5),
        );
      } catch (error) {
        // A missing foreground-service plugin must not prevent Firebase sign-out.
        debugPrint(
          '[AuthService] telemetry worker stop deferred (${error.runtimeType})',
        );
      }
      // Dừng auto sync
      _syncService.stopAutoSync();

      // Đánh dấu explicit sign out trước khi sign out Firebase
      await _session.markExplicitSignedOut();

      // Đăng xuất Firebase
      await _auth.signOut();

      // Xóa session metadata (giữ lại lastLoginEmail để prefill)
      await _session.clearSession();

      return {'success': true, 'message': 'Logout successful'};
    } catch (e) {
      debugPrint('[AuthService] Logout error (${e.runtimeType})');
      return {
        'success': false,
        'error': 'Đăng xuất thất bại.',
        'code': 'logoutFailed',
        'retryable': true,
      };
    }
  }

  /// Alias for logout - used by UI
  Future<Map<String, dynamic>> signOut() => logout();

  /// Alias for register - used by UI
  Future<Map<String, dynamic>> registerWithEmail({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) => register(email: email, password: password, name: name, phone: phone);

  /// Alias for login - used by UI
  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) => login(email: email, password: password);

  /// Add a vehicle from the reviewed global catalog. Manufacturer-controlled
  /// values are resolved by the server and are never accepted from the app.
  Future<Map<String, dynamic>> addVehicle({
    required String catalogId,
    String? nickname,
    String? licensePlate,
    int initialOdo = 0,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      await _ensureUserDoc(user);
      final result = await ApiService().post('/api/user/vehicles', {
        'catalogId': catalogId,
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
        if (licensePlate != null && licensePlate.trim().isNotEmpty)
          'licensePlate': licensePlate.trim(),
        'initialOdo': initialOdo,
      });
      final data = result['data'];
      if (result['success'] == true && data is Map) {
        return {
          ...result,
          'vehicleId': data['vehicleId']?.toString() ?? '',
          'synced': true,
        };
      }
      return result;
    } catch (e) {
      debugPrint('[AuthService] Add vehicle error: $e');
      return {
        'success': false,
        'error': 'Không thể thêm xe.',
        'code': 'vehicleAddFailed',
        'retryable': true,
      };
    }
  }

  /// Archives a vehicle so its charging history and audit trail remain
  /// recoverable. Kept under the old method name for installed callers.
  Future<Map<String, dynamic>> deleteVehicle(String vehicleId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      // Kiểm tra ownership
      final vehicleDoc = await _firestore
          .collection('Vehicles')
          .doc(vehicleId)
          .get();
      if (!vehicleDoc.exists) {
        return {'success': false, 'error': 'Vehicle not found'};
      }

      final vehicleData = vehicleDoc.data()!;
      if (vehicleData['ownerUid'] != user.uid) {
        return {'success': false, 'error': 'Not authorized'};
      }

      // Never archive a vehicle while its charger session is arming/active.
      // The session owns the device safety timer; changing the vehicle
      // context here would make subsequent reconciliation ambiguous.
      try {
        final activeSessions = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('smartChargingSessions')
            .where('vehicleId', isEqualTo: vehicleId)
            .where('state', whereIn: const ['arming', 'active'])
            .limit(1)
            .get();
        if (activeSessions.docs.isNotEmpty) {
          return {
            'success': false,
            'error': 'Không thể lưu trữ xe khi đang có phiên sạc hoạt động',
            'code': 'activeChargingSession',
          };
        }
      } catch (_) {
        // If the optional composite index is unavailable, do a narrower
        // ownership-scoped read and enforce the same guard client-side.
        final sessions = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('smartChargingSessions')
            .where('vehicleId', isEqualTo: vehicleId)
            .get();
        final hasActive = sessions.docs.any((doc) {
          final state = doc.data()['state'];
          return state == 'arming' || state == 'active';
        });
        if (hasActive) {
          return {
            'success': false,
            'error': 'Không thể lưu trữ xe khi đang có phiên sạc hoạt động',
            'code': 'activeChargingSession',
          };
        }
      }

      final vehicleRef = _firestore.collection('Vehicles').doc(vehicleId);
      final userRef = _firestore.collection('users').doc(user.uid);
      await _firestore.runTransaction((transaction) async {
        final vehicleSnapshot = await transaction.get(vehicleRef);
        final userSnapshot = await transaction.get(userRef);
        final current = vehicleSnapshot.data() ?? <String, dynamic>{};
        if (current['ownerUid'] != user.uid) {
          throw StateError('vehicleNotAuthorized');
        }
        final userData = userSnapshot.data() ?? <String, dynamic>{};
        final listedVehicles =
            (userData['vehicles'] as List<dynamic>?)
                ?.whereType<String>()
                .toSet() ??
            <String>{};
        final storedCount = userData['activeVehicleCount'];
        final activeCount = storedCount is num
            ? storedCount.toInt()
            : listedVehicles.length;
        final alreadyArchived =
            current['isArchived'] == true || current['archivedAt'] != null;
        transaction.set(vehicleRef, {
          'isArchived': true,
          'archivedAt': FieldValue.serverTimestamp(),
          'archivedBy': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(userRef, {
          'vehicles': FieldValue.arrayRemove([vehicleId]),
          'activeVehicleCount': alreadyArchived
              ? activeCount
              : (activeCount - 1).clamp(0, 100),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      return {'success': true, 'message': 'Vehicle archived', 'archived': true};
    } on StateError catch (error) {
      if (error.message == 'vehicleNotAuthorized') {
        return {'success': false, 'error': 'Not authorized'};
      }
      return {'success': false, 'error': error.message};
    } catch (e) {
      return {'success': false, 'error': 'Failed to delete vehicle: $e'};
    }
  }

  Future<Map<String, dynamic>> restoreVehicle(String vehicleId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {'success': false, 'error': 'Not logged in'};
      final ref = _firestore.collection('Vehicles').doc(vehicleId);
      final userRef = _firestore.collection('users').doc(user.uid);
      try {
        await _firestore.runTransaction((transaction) async {
          final snap = await transaction.get(ref);
          if (!snap.exists || snap.data()?['ownerUid'] != user.uid) {
            throw StateError('vehicleNotAuthorized');
          }
          final userSnapshot = await transaction.get(userRef);
          final userData = userSnapshot.data() ?? <String, dynamic>{};
          final listedVehicles =
              (userData['vehicles'] as List<dynamic>?)
                  ?.whereType<String>()
                  .toSet() ??
              <String>{};
          final storedCount = userData['activeVehicleCount'];
          final activeVehicleCount = storedCount is num
              ? storedCount.toInt()
              : listedVehicles.length;
          if (activeVehicleCount >= maxVehiclesPerAccount) {
            throw StateError('vehicleLimitReached');
          }
          transaction.set(ref, {
            'isArchived': false,
            'archivedAt': FieldValue.delete(),
            'archivedBy': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          transaction.set(userRef, {
            'vehicles': FieldValue.arrayUnion([vehicleId]),
            'activeVehicleCount': activeVehicleCount + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
      } on StateError catch (error) {
        if (error.message == 'vehicleLimitReached') {
          return {
            'success': false,
            'error': 'Đã đạt giới hạn xe hoạt động',
            'code': 'vehicleLimitReached',
          };
        }
        if (error.message == 'vehicleNotAuthorized') {
          return {'success': false, 'error': 'Not authorized'};
        }
        rethrow;
      }
      return {'success': true, 'message': 'Vehicle restored'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to restore vehicle: $e'};
    }
  }

  /// Cập nhật thông tin xe
  Future<Map<String, dynamic>> updateVehicle({
    required String vehicleId,
    Map<String, dynamic>? updates,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      const personalFields = {
        'nickname',
        'licensePlate',
        'currentOdo',
        'currentBattery',
        'lastBatteryPercent',
        'stateOfHealth',
        'avatarColor',
        'hasBatteryData',
        'hasSohData',
        'hasOdoData',
      };
      final safeUpdates = <String, dynamic>{};
      updates?.forEach((key, value) {
        if (personalFields.contains(key)) safeUpdates[key] = value;
      });
      if (safeUpdates.length != (updates?.length ?? 0)) {
        return {
          'success': false,
          'error': 'Thông số kỹ thuật của xe chỉ do catalog quản lý.',
        };
      }
      return ApiService().patch('/api/user/vehicles/$vehicleId', safeUpdates);
    } catch (e) {
      return {'success': false, 'error': 'Failed to update vehicle: $e'};
    }
  }

  /// Lấy danh sách xe của user.
  /// Nếu composite index (ownerUid + createdAt) chưa deploy thì
  /// fallback query chỉ theo ownerUid và sort ở client.
  Future<List<Map<String, dynamic>>> getUserVehicles({
    bool includeArchived = false,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      try {
        // Ưu tiên: dùng index ownerUid + createdAt desc
        final snapshot = await _firestore
            .collection('Vehicles')
            .where('ownerUid', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .get();
        docs = snapshot.docs;
      } catch (indexError) {
        // Fallback: query chỉ ownerUid, sort ở client
        debugPrint(
          '[AuthService] Index fallback for getUserVehicles: $indexError',
        );
        final snapshot = await _firestore
            .collection('Vehicles')
            .where('ownerUid', isEqualTo: user.uid)
            .get();
        docs = snapshot.docs;
      }

      final vehicles = docs
          .where((doc) {
            final data = doc.data();
            if (data['isDeleted'] == true) return false;
            if (includeArchived) return true;
            return data['isArchived'] != true && data['archivedAt'] == null;
          })
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .toList();

      // Client-side sort (mới nhất trước)
      vehicles.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return (bTime as Comparable).compareTo(aTime);
      });

      return vehicles;
    } catch (e) {
      debugPrint('[AuthService] Error getting user vehicles: $e');
      return [];
    }
  }

  /// Kiểm tra đăng nhập status — Firebase Auth là source of truth.
  Future<bool> isLoggedIn() async {
    return _auth.currentUser != null;
  }

  /// Loads the server-configured active-vehicle limit. Invalid or unavailable
  /// values leave the safe local default unchanged.
  Future<void> loadVehiclePolicy() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _firestore.collection('users').doc(user.uid).get();
      final configured = snapshot.data()?['maxActiveVehicles'];
      if (configured is num) configureVehicleLimit(configured.round());
    } catch (_) {
      // Policy fetch is best effort; creation remains guarded by the default.
    }
  }

  /// Lấy thông tin user hiện tại
  Future<Map<String, dynamic>?> getCurrentUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      return doc.data();
    } catch (e) {
      debugPrint(
        '[AuthService] Current user data read failed (${e.runtimeType}).',
      );
      return null;
    }
  }

  /// Reset password
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {'success': true, 'message': 'Password reset email sent'};
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return {
          'success': true,
          'message':
              'Nếu tài khoản phù hợp tồn tại, email hướng dẫn đã được gửi.',
        };
      }
      return {
        'success': false,
        'error': e.code == 'too-many-requests'
            ? 'Bạn vừa gửi yêu cầu gần đây. Hãy đợi một chút rồi thử lại.'
            : 'Chưa thể gửi email lúc này. Kiểm tra kết nối rồi thử lại.',
        'code': e.code,
      };
    } catch (_) {
      return {
        'success': false,
        'error': 'Chưa thể gửi email lúc này. Kiểm tra kết nối rồi thử lại.',
        'code': 'resetFailed',
      };
    }
  }

  /// Đổi mật khẩu
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      // Re-authenticate
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);

      return {'success': true, 'message': 'Password changed successfully'};
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'error': e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Mật khẩu hiện tại chưa chính xác.'
            : e.code == 'weak-password'
            ? 'Mật khẩu mới chưa đủ mạnh.'
            : 'Chưa thể đổi mật khẩu lúc này. Vui lòng thử lại.',
        'code': e.code,
      };
    } catch (e) {
      debugPrint('[AuthService] Password change failed (${e.runtimeType}).');
      return {
        'success': false,
        'error': 'Chưa thể đổi mật khẩu lúc này. Vui lòng thử lại.',
        'code': 'passwordChangeFailed',
      };
    }
  }
}
