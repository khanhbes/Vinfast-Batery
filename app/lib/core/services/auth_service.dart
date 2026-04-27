import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_service.dart';

/// AuthService - Xử lý đăng ký/đăng nhập đồng bộ với Web Dashboard
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SyncService _syncService = SyncService();

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

      // 5. Lưu thông tin đăng nhập locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_email', email);
      await prefs.setBool('is_logged_in', true);

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

      // 2. Cập nhật last login
      await _firestore.collection('users').doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
        'lastLoginSource': 'flutter_app',
      });

      // 3. Đồng bộ user với web
      final syncResult = await _syncService.syncUserToWeb();

      // 4. Đồng bộ vehicles
      final vehicleResults = await _syncService.syncAllVehiclesToWeb();

      // 5. Lưu thông tin đăng nhập
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_login_email', email);
      await prefs.setBool('is_logged_in', true);

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

  /// Đăng xuất
  Future<Map<String, dynamic>> logout() async {
    try {
      // Dừng auto sync
      _syncService.stopAutoSync();

      // Đăng xuất Firebase
      await _auth.signOut();

      // Xóa thông tin locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_logged_in');
      await prefs.remove('selected_vehicle_id');

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

      // 1. Tạo vehicle document
      final vehicleRef = _firestore.collection('vehicles').doc();
      final vehicleId = vehicleRef.id;

      await vehicleRef.set({
        'vehicleId': vehicleId,
        'ownerUid': user.uid,
        'model': model,
        'year': year,
        'batteryCapacity': batteryCapacity,
        'currentBattery': currentBattery,
        'stateOfHealth': stateOfHealth,
        'currentOdo': currentOdo,
        'defaultEfficiency': defaultEfficiency,
        'lastBatteryPercent': currentBattery,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'flutter_app',
        'syncedToWeb': false,
        'needsSync': true,
      });

      // 2. Cập nhật user profile
      await _firestore.collection('users').doc(user.uid).update({
        'vehicles': FieldValue.arrayUnion([vehicleId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
      final vehicleDoc = await _firestore.collection('vehicles').doc(vehicleId).get();
      if (!vehicleDoc.exists) {
        return {'success': false, 'error': 'Vehicle not found'};
      }

      final vehicleData = vehicleDoc.data()!;
      if (vehicleData['ownerUid'] != user.uid) {
        return {'success': false, 'error': 'Not authorized'};
      }

      // Xóa vehicle
      await _firestore.collection('vehicles').doc(vehicleId).delete();

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

      await _firestore.collection('vehicles').doc(vehicleId).update(updateData);

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

  /// Lấy danh sách xe của user
  Future<List<Map<String, dynamic>>> getUserVehicles() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final snapshot = await _firestore
          .collection('vehicles')
          .where('ownerUid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting user vehicles: $e');
      return [];
    }
  }

  /// Kiểm tra đăng nhập status
  Future<bool> isLoggedIn() async {
    final user = _auth.currentUser;
    if (user != null) return true;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_logged_in') ?? false;
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
