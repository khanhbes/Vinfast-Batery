import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Danh sách 6 widget có thể tùy chỉnh trên màn hình Tổng quan
class DashboardWidgetId {
  static const quickActions = 'quick_actions';
  static const batteryStatistics = 'battery_statistics';
  static const rangePrediction = 'range_prediction';
  static const batteryHealth = 'battery_health';
  static const recentCharging = 'recent_charging';
  static const efficiencyReference = 'efficiency_reference';

  static const List<String> all = [
    quickActions,
    batteryStatistics,
    rangePrediction,
    batteryHealth,
    recentCharging,
    efficiencyReference,
  ];

  static String getTitleVi(String id) {
    switch (id) {
      case quickActions:
        return 'Hành động nhanh';
      case batteryStatistics:
        return 'Thống kê pin';
      case rangePrediction:
        return 'Dự đoán quãng đường';
      case batteryHealth:
        return 'Sức khỏe pin (SoH)';
      case recentCharging:
        return 'Xu hướng sạc gần đây';
      case efficiencyReference:
        return 'Hiệu suất tiêu thụ';
      default:
        return id;
    }
  }

  static String getTitleEn(String id) {
    switch (id) {
      case quickActions:
        return 'Quick Actions';
      case batteryStatistics:
        return 'Battery Statistics';
      case rangePrediction:
        return 'Range Prediction';
      case batteryHealth:
        return 'Battery Health';
      case recentCharging:
        return 'Recent Charging';
      case efficiencyReference:
        return 'Efficiency Reference';
      default:
        return id;
    }
  }

  static String getSubtitleVi(String id) {
    switch (id) {
      case quickActions:
        return 'Các nút thao tác nhanh: Sạc, Chuyến đi, Bảo dưỡng, Đồng bộ';
      case batteryStatistics:
        return 'Thẻ thông số: SoC, dung lượng, điện áp, chu kỳ sạc';
      case rangePrediction:
        return 'Ước tính khoảng cách đi được theo % pin hiện tại';
      case batteryHealth:
        return 'Điểm đánh giá SoH và tình trạng lão hóa pin';
      case recentCharging:
        return 'Biểu đồ các phiên sạc gần nhất';
      case efficiencyReference:
        return 'Mức tiêu hao năng lượng trung bình Wh/km';
      default:
        return '';
    }
  }
}

/// Dịch vụ quản lý tùy biến bố cục Dashboard & Spotlight tours
class DashboardPreferencesService extends ChangeNotifier {
  /// Scoped instances avoid a disposed singleton leaking across Riverpod
  /// containers (notably after a widget test or a hot restart). The provider
  /// owns this notifier and safely disposes it with its scope.
  DashboardPreferencesService();

  static const _prefOrderKey = 'dashboard_order';
  static const _prefHiddenKey = 'dashboard_hidden';
  static const _prefCompletedToursKey = 'dashboard_completed_tours';
  static const _prefUpdatedAtKey = 'dashboard_updated_at';

  List<String> _order = List.from(DashboardWidgetId.all);
  Set<String> _hidden = <String>{};
  Set<String> _completedTours = <String>{};
  final int _guideSchemaVersion = 1;
  String _updatedAt = DateTime.now().toUtc().toIso8601String();

  bool _initialized = false;
  Timer? _remoteSyncTimer;
  bool _remoteDirty = false;
  bool get isInitialized => _initialized;

  List<String> get order => List.unmodifiable(_order);
  Set<String> get hidden => Set.unmodifiable(_hidden);
  Set<String> get completedTours => Set.unmodifiable(_completedTours);
  String get updatedAt => _updatedAt;

  /// Danh sách widget đang hiển thị theo đúng thứ tự tùy chỉnh
  List<String> get visibleWidgets =>
      _order.where((id) => !_hidden.contains(id)).toList();

  bool isVisible(String widgetId) => !_hidden.contains(widgetId);

  /// Khởi tạo service: nạp từ cache cục bộ (SharedPreferences), sau đó đồng bộ ngầm Firestore
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final cachedOrderJson = prefs.getString(_prefOrderKey);
      if (cachedOrderJson != null) {
        final decoded = List<String>.from(jsonDecode(cachedOrderJson));
        _order = _normalizeOrder(decoded);
      } else {
        _order = List.from(DashboardWidgetId.all);
      }

      final cachedHiddenJson = prefs.getString(_prefHiddenKey);
      if (cachedHiddenJson != null) {
        final decoded = Set<String>.from(jsonDecode(cachedHiddenJson));
        _hidden = decoded.intersection(DashboardWidgetId.all.toSet());
        // Bảo đảm ít nhất 1 widget nội dung được hiển thị
        if (_hidden.length >= _order.length) {
          _hidden.clear();
        }
      }

      final cachedToursJson = prefs.getString(_prefCompletedToursKey);
      if (cachedToursJson != null) {
        _completedTours = Set<String>.from(jsonDecode(cachedToursJson));
      }

      final cachedUpdatedAt = prefs.getString(_prefUpdatedAtKey);
      if (cachedUpdatedAt != null) {
        _updatedAt = cachedUpdatedAt;
      }

      _initialized = true;
      notifyListeners();

      // Đồng bộ ngầm với Firestore theo UID
      // ignore: unawaited_futures
      syncWithFirestore();
    } catch (e) {
      debugPrint('[DashboardPreferencesService] Init error: $e');
      _order = List.from(DashboardWidgetId.all);
      _hidden.clear();
      _initialized = true;
      notifyListeners();
    }
  }

  /// Chuẩn hóa thứ tự widget:
  /// - Giữ lại các ID hợp lệ
  /// - Tự động thêm widget mới vào cuối danh sách
  /// - Bỏ qua ID cũ không còn tồn tại
  List<String> _normalizeOrder(List<String> input) {
    final validSet = DashboardWidgetId.all.toSet();
    final result = <String>[];

    for (final id in input) {
      if (validSet.contains(id) && !result.contains(id)) {
        result.add(id);
      }
    }

    for (final id in DashboardWidgetId.all) {
      if (!result.contains(id)) {
        result.add(id);
      }
    }
    return result;
  }

  /// Thay đổi thứ tự widget
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    if (newIndex < 0 || newIndex > _order.length) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _order.removeAt(oldIndex);
    _order.insert(newIndex, item);
    _updatedAt = DateTime.now().toUtc().toIso8601String();

    notifyListeners();
    await _persistLocal();
    _scheduleRemoteSync();
  }

  /// Bật/tắt hiển thị widget
  /// Không cho phép tắt nếu là widget nội dung hiển thị cuối cùng
  bool toggleVisibility(String widgetId, bool visible) {
    if (!DashboardWidgetId.all.contains(widgetId)) return false;

    if (!visible) {
      // Đếm số widget hiện đang hiển thị
      final currentVisible = visibleWidgets;
      if (currentVisible.length <= 1 && currentVisible.contains(widgetId)) {
        // Không thể ẩn widget cuối cùng
        return false;
      }
      _hidden.add(widgetId);
    } else {
      _hidden.remove(widgetId);
    }

    _updatedAt = DateTime.now().toUtc().toIso8601String();
    notifyListeners();
    _persistLocal();
    _scheduleRemoteSync();
    return true;
  }

  /// Khôi phục bố cục mặc định ban đầu
  Future<void> resetToDefault() async {
    _order = List.from(DashboardWidgetId.all);
    _hidden.clear();
    _updatedAt = DateTime.now().toUtc().toIso8601String();

    notifyListeners();
    await _persistLocal();
    _scheduleRemoteSync();
  }

  /// Đánh dấu tour hướng dẫn đã hoàn thành
  Future<void> markTourCompleted(String tourId) async {
    if (_completedTours.contains(tourId)) return;
    _completedTours.add(tourId);
    _updatedAt = DateTime.now().toUtc().toIso8601String();

    notifyListeners();
    await _persistLocal();
    _scheduleRemoteSync();
  }

  bool isTourCompleted(String tourId) => _completedTours.contains(tourId);

  /// Reset toàn bộ tiến độ tour (để người dùng có thể chạy lại từ đầu)
  Future<void> resetTours() async {
    _completedTours.clear();
    _updatedAt = DateTime.now().toUtc().toIso8601String();

    notifyListeners();
    await _persistLocal();
    _scheduleRemoteSync();
  }

  /// Lưu vào SharedPreferences
  Future<void> _persistLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefOrderKey, jsonEncode(_order));
      await prefs.setString(_prefHiddenKey, jsonEncode(_hidden.toList()));
      await prefs.setString(
        _prefCompletedToursKey,
        jsonEncode(_completedTours.toList()),
      );
      await prefs.setString(_prefUpdatedAtKey, _updatedAt);
    } catch (e) {
      debugPrint('[DashboardPreferencesService] Persist error: $e');
    }
  }

  /// Đồng bộ với Firestore `users/{uid}/appPreferences/ui` (xử lý xung đột LWW theo `updatedAt`)
  Future<void> syncWithFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appPreferences')
          .doc('ui');

      final snapshot = await docRef.get();
      if (!snapshot.exists || snapshot.data() == null) {
        // Chưa có trên cloud -> đẩy bản local lên
        await _syncRemote();
        return;
      }

      final data = snapshot.data()!;
      final remoteUpdatedAtStr = data['updatedAt'] as String?;
      final remoteOrder = (data['dashboardOrder'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();
      final remoteHidden = (data['hiddenDashboardWidgets'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toSet();
      final remoteTours = (data['completedTours'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toSet();

      if (remoteUpdatedAtStr != null) {
        final remoteTime = DateTime.tryParse(remoteUpdatedAtStr);
        final localTime = DateTime.tryParse(_updatedAt);

        if (remoteTime != null &&
            localTime != null &&
            remoteTime.isAfter(localTime)) {
          // Cloud mới hơn -> ghi đè local
          if (remoteOrder != null) {
            _order = _normalizeOrder(remoteOrder);
          }
          if (remoteHidden != null) {
            _hidden = remoteHidden.intersection(DashboardWidgetId.all.toSet());
            if (_hidden.length >= _order.length) _hidden.clear();
          }
          if (remoteTours != null) {
            _completedTours = remoteTours;
          }
          _updatedAt = remoteUpdatedAtStr;
          await _persistLocal();
          notifyListeners();
          return;
        }
      }

      // Local mới hơn hoặc bằng -> đẩy lên cloud
      await _syncRemote();
    } catch (e) {
      debugPrint('[DashboardPreferencesService] Sync error: $e');
    }
  }

  Future<void> _syncRemote() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appPreferences')
          .doc('ui');

      await docRef.set({
        'dashboardOrder': _order,
        'hiddenDashboardWidgets': _hidden.toList(),
        'completedTours': _completedTours.toList(),
        'guideSchemaVersion': _guideSchemaVersion,
        'updatedAt': _updatedAt,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[DashboardPreferencesService] Remote sync failed: $e');
    }
  }

  void _scheduleRemoteSync() {
    _remoteDirty = true;
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer(const Duration(seconds: 2), () async {
      if (!_remoteDirty) return;
      _remoteDirty = false;
      await _syncRemote();
    });
  }

  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    super.dispose();
  }
}

/// Provider toàn ứng dụng cho DashboardPreferencesService
final dashboardPreferencesProvider =
    ChangeNotifierProvider<DashboardPreferencesService>((ref) {
      final service = DashboardPreferencesService();
      if (!service.isInitialized) {
        // ignore: discarded_futures
        service.initialize();
      }
      return service;
    });
