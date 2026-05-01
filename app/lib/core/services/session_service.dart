import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SessionService - Lưu trữ metadata phiên đăng nhập một cách an toàn.
///
/// - Bảo mật: dùng [FlutterSecureStorage] (Android Keystore) cho `selectedVehicleId`
///   và `lastLoginEmail`.
/// - Tương thích ngược: vẫn ghi mirror vào [SharedPreferences] với key
///   `selected_vehicle_id` để các module legacy đang đọc đồng bộ tiếp tục chạy.
/// - Khởi tạo lần đầu (sau update): nếu secure storage chưa có giá trị nhưng
///   SharedPreferences có thì migrate sang secure storage.
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  // Secure keys
  static const _kSelectedVehicleId = 'session.selected_vehicle_id';
  static const _kLastLoginEmail = 'session.last_login_email';

  // Mirror keys (giữ tương thích với code cũ)
  static const _kPrefSelectedVehicleId = 'selected_vehicle_id';
  static const _kPrefLastLoginEmail = 'last_login_email';
  static const _kPrefLastUserSync = 'last_user_sync';
  static const _kPrefLastFullSync = 'last_full_sync';

  // Session state markers
  static const _kPrefWasAuthenticated = 'was_authenticated';
  static const _kPrefExplicitSignedOut = 'explicit_signed_out';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _migrated = false;

  /// Migrate giá trị từ SharedPreferences sang secure storage (lần đầu).
  Future<void> _ensureMigrated() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final secVehicle = await _safeRead(_kSelectedVehicleId);
      final prefVehicle = prefs.getString(_kPrefSelectedVehicleId);
      if ((secVehicle == null || secVehicle.isEmpty) &&
          prefVehicle != null &&
          prefVehicle.isNotEmpty) {
        await _safeWrite(_kSelectedVehicleId, prefVehicle);
      }
      final secEmail = await _safeRead(_kLastLoginEmail);
      final prefEmail = prefs.getString(_kPrefLastLoginEmail);
      if ((secEmail == null || secEmail.isEmpty) &&
          prefEmail != null &&
          prefEmail.isNotEmpty) {
        await _safeWrite(_kLastLoginEmail, prefEmail);
      }
    } catch (e) {
      debugPrint('[SessionService] Migration error: $e');
    }
  }

  // ── Selected vehicle ───────────────────────────────────────────────

  Future<String?> getSelectedVehicleId() async {
    await _ensureMigrated();
    final secure = await _safeRead(_kSelectedVehicleId);
    if (secure != null && secure.isNotEmpty) return secure;
    // Fallback prefs (transition window)
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kPrefSelectedVehicleId);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSelectedVehicleId(String? vehicleId) async {
    final value = vehicleId ?? '';
    await _safeWrite(_kSelectedVehicleId, value);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value.isEmpty) {
        await prefs.remove(_kPrefSelectedVehicleId);
      } else {
        await prefs.setString(_kPrefSelectedVehicleId, value);
      }
    } catch (e) {
      debugPrint('[SessionService] Mirror prefs error: $e');
    }
  }

  // ── Last login email ───────────────────────────────────────────────

  Future<String?> getLastLoginEmail() async {
    await _ensureMigrated();
    final secure = await _safeRead(_kLastLoginEmail);
    if (secure != null && secure.isNotEmpty) return secure;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kPrefLastLoginEmail);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastLoginEmail(String email) async {
    await _safeWrite(_kLastLoginEmail, email);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefLastLoginEmail, email);
    } catch (_) {}
  }

  // ── Sync timestamps (non-sensitive) ────────────────────────────────

  Future<void> markUserSynced() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefLastUserSync, DateTime.now().toIso8601String());
  }

  Future<DateTime?> getLastUserSync() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_kPrefLastUserSync);
    return iso == null ? null : DateTime.tryParse(iso);
  }

  Future<DateTime?> getLastFullSync() async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_kPrefLastFullSync);
    return iso == null ? null : DateTime.tryParse(iso);
  }

  // ── Session state markers ──────────────────────────────────────────

  /// Đánh dấu user đã đăng nhập thành công.
  /// Gọi sau login/register thành công.
  Future<void> markAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefWasAuthenticated, true);
      await prefs.setBool(_kPrefExplicitSignedOut, false);
    } catch (e) {
      debugPrint('[SessionService] markAuthenticated error: $e');
    }
  }

  /// Đánh dấu user đã đăng xuất chủ động (bấm nút Đăng xuất).
  /// Chỉ khi có flag này, app mới về màn hình Login khi mở lại.
  Future<void> markExplicitSignedOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefExplicitSignedOut, true);
      await prefs.setBool(_kPrefWasAuthenticated, false);
    } catch (e) {
      debugPrint('[SessionService] markExplicitSignedOut error: $e');
    }
  }

  /// Kiểm tra user đã từng đăng nhập thành công chưa.
  Future<bool> wasAuthenticated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kPrefWasAuthenticated) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra user đã bấm Đăng xuất chưa.
  Future<bool> wasExplicitSignOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kPrefExplicitSignedOut) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Logout / cleanup ───────────────────────────────────────────────

  /// Xóa metadata phiên hiện tại. Giữ lại `lastLoginEmail` để form đăng nhập
  /// có thể prefill — truyền `keepLastEmail = false` để xóa luôn.
  Future<void> clearSession({bool keepLastEmail = true}) async {
    await _safeDelete(_kSelectedVehicleId);
    if (!keepLastEmail) {
      await _safeDelete(_kLastLoginEmail);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefSelectedVehicleId);
      await prefs.remove('is_logged_in');
      await prefs.remove(_kPrefLastUserSync);
      await prefs.remove('user_synced_to_web');
      await prefs.remove(_kPrefWasAuthenticated);
      // N.B.: không remove _kPrefExplicitSignedOut ở đây
      // vì flag này được set TRƯỚC khi gọi clearSession
      if (!keepLastEmail) {
        await prefs.remove(_kPrefLastLoginEmail);
      }
    } catch (e) {
      debugPrint('[SessionService] clearSession prefs error: $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Future<String?> _safeRead(String key) async {
    try {
      return await _secure.read(key: key);
    } catch (e) {
      debugPrint('[SessionService] secure read $key error: $e');
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (e) {
      debugPrint('[SessionService] secure write $key error: $e');
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _secure.delete(key: key);
    } catch (e) {
      debugPrint('[SessionService] secure delete $key error: $e');
    }
  }
}
