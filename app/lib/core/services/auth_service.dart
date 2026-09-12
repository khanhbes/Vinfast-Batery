import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'session_service.dart';
import 'sync_service.dart';
import '../../data/services/push_notification_service.dart';
import 'vehicle_policy.dart';
import 'api_service.dart';

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

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncService _syncService = SyncService();
  final SessionService _session = SessionService();

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
      debugPrint('[AuthService] _ensureUserDoc error: $e');
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

      // 2. Cập nhật display name
      await user.updateDisplayName(name);

      // 3. Tạo user document trong Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': email,
        'name': name,
        'phone': phone ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'flutter_app',
        'syncedToWeb': false,
      });

      // 4. Đồng bộ với web dashboard
      final syncResult = await _syncService.syncUserToWeb();

      // 5. Lưu thông tin đăng nhập locally (secure)
      await _session.setLastLoginEmail(email);
      await _session.saveRememberedCredentials(
        email: email,
        password: password,
      );
      await _session.markUserSynced();
      await _session.markAuthenticated();

      return {
        'success': true,
        'user': user,
        'synced': syncResult,
        'message': 'Registration successful',
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'Password is too weak';
          break;
        case 'email-already-in-use':
          errorMessage = 'Email already exists';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address';
          break;
        default:
          errorMessage = 'Registration failed: ${e.message}';
      }
      return {'success': false, 'error': errorMessage, 'code': e.code};
    } catch (e) {
      return {'success': false, 'error': 'Unexpected error: $e'};
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
      await _session.setLastLoginEmail(email);
      await _session.saveRememberedCredentials(
        email: email,
        password: password,
      );
      await _session.markAuthenticated();

      // 2. Đảm bảo user doc tồn tại trước khi update
      await _ensureUserDoc(user);
      await loadVehiclePolicy();

      // 3. Cập nhật last login (safe vì đã ensure doc)
      await _firestore.collection('users').doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
        'lastLoginSource': 'flutter_app',
      });

      // 3. Đồng bộ user với web
      final syncResult = await _syncService.syncUserToWeb();

      // 4. Đồng bộ vehicles
      final vehicleResults = await _syncService.syncAllVehiclesToWeb();

      // 5. Lưu thông tin đăng nhập (secure)
      await _session.markUserSynced();

      // 6. Bắt đầu auto sync
      _syncService.startAutoSync();

      return {
        'success': true,
        'user': user,
        'synced': syncResult,
        'vehicles': vehicleResults,
        'message': 'Login successful',
      };
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No user found with this email';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address';
          break;
        case 'user-disabled':
          errorMessage = 'Account has been disabled';
          break;
        default:
          errorMessage = 'Login failed: ${e.message}';
      }
      return {'success': false, 'error': errorMessage, 'code': e.code};
    } catch (e) {
      return {'success': false, 'error': 'Unexpected error: $e'};
    }
  }

  /// Khôi phục đăng nhập không cần người dùng nhập lại mật khẩu.
  ///
  /// Firebase Auth thường tự persist user trên Android. Method này là lớp
  /// dự phòng khi cold start trả về `currentUser == null` dù user đã từng
  /// đăng nhập và chưa bấm đăng xuất.
  Future<User?> restoreRememberedLogin() async {
    if (_auth.currentUser != null) {
      await _session.markAuthenticated();
      return _auth.currentUser;
    }

    final explicitSignedOut = await _session.wasExplicitSignOut();
    if (explicitSignedOut) return null;

    final credentials = await _session.getRememberedCredentials();
    if (credentials == null) return null;

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: credentials.email,
        password: credentials.password,
      );
      final user = userCredential.user;
      if (user == null) return null;

      await _ensureUserDoc(user);
      await loadVehiclePolicy();
      await _session.setLastLoginEmail(credentials.email);
      await _session.markAuthenticated();
      _syncService.startAutoSync();
      return user;
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] restoreRememberedLogin auth error: ${e.code}');
      switch (e.code) {
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
        case 'user-disabled':
          await _session.clearRememberedCredentials();
          break;
      }
      return null;
    } catch (e) {
      debugPrint('[AuthService] restoreRememberedLogin error: $e');
      return null;
    }
  }

  /// Đăng xuất — chỉ method này được gọi FirebaseAuth.signOut()
  Future<Map<String, dynamic>> logout() async {
    try {
      await PushNotificationService.instance.revokeCurrentUser();
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
      return {'success': false, 'error': 'Logout failed: $e'};
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
      return {'success': false, 'error': 'Failed to add vehicle: $e'};
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
      debugPrint('Error getting current user data: $e');
      return null;
    }
  }

  /// Reset password
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {'success': true, 'message': 'Password reset email sent'};
    } on FirebaseAuthException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'Failed to send reset email',
      };
    } catch (e) {
      return {'success': false, 'error': 'Unexpected error: $e'};
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
        'error': e.message ?? 'Failed to change password',
      };
    } catch (e) {
      return {'success': false, 'error': 'Unexpected error: $e'};
    }
  }
}
