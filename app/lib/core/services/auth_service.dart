import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'session_service.dart';
import 'sync_service.dart';

/// AuthService - Xử lý đăng ký/đăng nhập đồng bộ với Web Dashboard
class AuthService {
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

      // 2. Đảm bảo user doc tồn tại trước khi update
      await _ensureUserDoc(user);

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
      await _session.setLastLoginEmail(email);
      await _session.markUserSynced();
      await _session.markAuthenticated();

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

  /// Đăng xuất — chỉ method này được gọi FirebaseAuth.signOut()
  Future<Map<String, dynamic>> logout() async {
    try {
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

  /// Thêm xe mới + đồng bộ web
  /// Dùng WriteBatch để tạo Vehicles/{vehicleId} và upsert users/{uid}
  /// cùng lúc, tránh lỗi [cloud_firestore/not-found] khi user doc chưa có.
  Future<Map<String, dynamic>> addVehicle({
    required String model,
    required int year,
    required double batteryCapacity,
    required double currentBattery,
    required double stateOfHealth,
    required double currentOdo,
    required double defaultEfficiency,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      // Đảm bảo user doc tồn tại trước (set merge)
      await _ensureUserDoc(user);

      // Tạo vehicle ref
      final vehicleRef = _firestore.collection('Vehicles').doc();
      final vehicleId = vehicleRef.id;

      // Dùng WriteBatch: tạo xe + update user atomically
      final batch = _firestore.batch();

      // 1. Tạo vehicle document — chuẩn hóa kiểu số:
      //    - Field hiển thị int (currentOdo, currentBattery, lastBatteryPercent,
      //      year, totalCharges, totalTrips) → ép int qua `.round()` để
      //      `VehicleModel.fromFirestore` không crash `double is not int`.
      //    - Field tính toán cần độ chính xác (batteryCapacity, stateOfHealth,
      //      defaultEfficiency) → giữ double.
      batch.set(vehicleRef, {
        'vehicleId': vehicleId,
        'vehicleName': '$model $year',
        'ownerUid': user.uid,
        'model': model,
        'year': year,
        'batteryCapacity': batteryCapacity,
        'currentBattery': currentBattery.round(),
        'stateOfHealth': stateOfHealth,
        'currentOdo': currentOdo.round(),
        'defaultEfficiency': defaultEfficiency,
        'lastBatteryPercent': currentBattery.round(),
        'isDeleted': false,
        'totalCharges': 0,
        'totalTrips': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'flutter_app',
        'syncedToWeb': false,
        'needsSync': true,
      });

      // 2. Upsert user profile (merge: true nên safe khi doc mới tạo)
      final userRef = _firestore.collection('users').doc(user.uid);
      batch.set(userRef, {
        'vehicles': FieldValue.arrayUnion([vehicleId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      // 3. Đồng bộ với web
      final syncResult = await _syncService.syncVehicleToWeb(vehicleId);

      return {
        'success': true,
        'vehicleId': vehicleId,
        'synced': syncResult,
        'message': 'Vehicle added successfully',
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to add vehicle: $e'};
    }
  }

  /// Xóa xe
  Future<Map<String, dynamic>> deleteVehicle(String vehicleId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not logged in'};
      }

      // Kiểm tra ownership
      final vehicleDoc = await _firestore.collection('Vehicles').doc(vehicleId).get();
      if (!vehicleDoc.exists) {
        return {'success': false, 'error': 'Vehicle not found'};
      }

      final vehicleData = vehicleDoc.data()!;
      if (vehicleData['ownerUid'] != user.uid) {
        return {'success': false, 'error': 'Not authorized'};
      }

      // Xóa vehicle
      await _firestore.collection('Vehicles').doc(vehicleId).delete();

      // Cập nhật user
      await _firestore.collection('users').doc(user.uid).update({
        'vehicles': FieldValue.arrayRemove([vehicleId]),
      });

      return {'success': true, 'message': 'Vehicle deleted'};
    } catch (e) {
      return {'success': false, 'error': 'Failed to delete vehicle: $e'};
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

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
        'needsSync': true,
      };

      if (updates != null) {
        updateData.addAll(updates);
      }

      await _firestore.collection('Vehicles').doc(vehicleId).update(updateData);

      // Đồng bộ với web
      final syncResult = await _syncService.syncVehicleToWeb(vehicleId);

      return {
        'success': true,
        'synced': syncResult,
        'message': 'Vehicle updated',
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to update vehicle: $e'};
    }
  }

  /// Lấy danh sách xe của user.
  /// Nếu composite index (ownerUid + createdAt) chưa deploy thì
  /// fallback query chỉ theo ownerUid và sort ở client.
  Future<List<Map<String, dynamic>>> getUserVehicles() async {
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
        debugPrint('[AuthService] Index fallback for getUserVehicles: $indexError');
        final snapshot = await _firestore
            .collection('Vehicles')
            .where('ownerUid', isEqualTo: user.uid)
            .get();
        docs = snapshot.docs;
      }

      final vehicles = docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

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

  /// Lấy thông tin user hiện tại
  Future<Map<String, dynamic>?> getCurrentUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      return doc.data();
    } catch (e) {
      print('Error getting current user data: $e');
      return null;
    }
  }

  /// Reset password
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {'success': true, 'message': 'Password reset email sent'};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.message ?? 'Failed to send reset email'};
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
      return {'success': false, 'error': e.message ?? 'Failed to change password'};
    } catch (e) {
      return {'success': false, 'error': 'Unexpected error: $e'};
    }
  }
}
