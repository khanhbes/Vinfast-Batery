import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../models/proactive_suggestion.dart';

final suggestionServiceProvider = Provider<SuggestionService>((ref) {
  return SuggestionService();
});

class SuggestionService {
  SuggestionService({http.Client? client, String? Function()? uidResolver})
    : _client = client ?? http.Client(),
      _uidResolver = uidResolver ?? _firebaseUid;
  final String? Function() _uidResolver;
  static String? _firebaseUid() =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  String get _scope => Uri.encodeComponent(_uidResolver() ?? 'guest');

  final http.Client _client;
  String get _dismissedRulesKey => 'vinfast_dismissed_suggestions_v2_$_scope';

  /// Kiểm tra xem có được phép hiển thị proactive suggestion lúc này không (Rate Limit).
  /// Quy tắc: Tối đa 1 bubble / 30 phút, tối đa 5 lần / ngày.
  Future<bool> canShowProactiveBubble() async {
    final scope = _scope;
    final lastKey = 'vinfast_proactive_last_shown_time_v2_$scope';
    final countKey = 'vinfast_proactive_daily_count_v2_$scope';
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // 1. Kiểm tra khoảng cách 30 phút
      final lastShownMillis = prefs.getInt(lastKey) ?? 0;
      final diffMinutes = now
          .difference(DateTime.fromMillisecondsSinceEpoch(lastShownMillis))
          .inMinutes;
      if (diffMinutes < 30) return false;

      // 2. Kiểm tra giới hạn 5 lần/ngày
      final countDateStr = prefs.getString('${countKey}_date') ?? '';
      final todayStr = '${now.year}-${now.month}-${now.day}';
      int todayCount = prefs.getInt(countKey) ?? 0;

      if (countDateStr != todayStr) {
        todayCount = 0;
        await prefs.setString('${countKey}_date', todayStr);
        await prefs.setInt(countKey, 0);
      }

      if (todayCount >= 5) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ghi nhận đã hiển thị một gợi ý chủ động
  Future<void> recordSuggestionShown() async {
    final scope = _scope;
    final lastKey = 'vinfast_proactive_last_shown_time_v2_$scope';
    final countKey = 'vinfast_proactive_daily_count_v2_$scope';
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(lastKey, now.millisecondsSinceEpoch);

      final todayStr = '${now.year}-${now.month}-${now.day}';
      final countDateStr = prefs.getString('${countKey}_date') ?? '';
      int todayCount = prefs.getInt(countKey) ?? 0;

      if (countDateStr != todayStr) {
        todayCount = 1;
        await prefs.setString('${countKey}_date', todayStr);
      } else {
        todayCount += 1;
      }
      await prefs.setInt(countKey, todayCount);
    } catch (_) {}
  }

  /// Bỏ qua một gợi ý (không hiện lại trong 24 giờ)
  Future<void> dismissSuggestion(String ruleId) async {
    final scope = _scope;
    final dismissedKey = 'vinfast_dismissed_suggestions_v2_$scope';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(dismissedKey) ?? '{}';
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      map[ruleId] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(dismissedKey, jsonEncode(map));
    } catch (_) {}
  }

  /// Lấy danh sách gợi ý proactive từ Backend API
  Future<List<ProactiveSuggestion>> fetchSuggestions({
    required String userId,
    String? vehicleId,
    double? currentSoc,
    double? currentSoh,
    int? odoKm,
    String? chargingStatus,
  }) async {
    final queryParams = {
      'userId': userId,
      'vehicleId': ?vehicleId,
      if (currentSoc != null) 'currentSoc': currentSoc.toString(),
      if (currentSoh != null) 'currentSoh': currentSoh.toString(),
      if (odoKm != null) 'odoKm': odoKm.toString(),
      'chargingStatus': ?chargingStatus,
    };

    final uri = AppConstants.tryBuildApiUri(
      '/api/behavior/suggestions',
      queryParameters: queryParams,
    );

    if (uri == null || !AppConstants.isApiConfigured) {
      // Fallback local logic khi offline
      return _filterDismissed(
        _generateLocalFallback(currentSoc, chargingStatus),
      );
    }

    try {
      final user = Firebase.apps.isEmpty
          ? null
          : FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final token = await user?.getIdToken();
      if (uid == null ||
          uid != userId ||
          uid != _uidResolver() ||
          token == null) {
        return [];
      }
      final res = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (uid != _uidResolver()) return [];
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (decoded['data'] as List<dynamic>?) ?? [];
        final suggestions = list
            .map(
              (item) =>
                  ProactiveSuggestion.fromJson(item as Map<String, dynamic>),
            )
            .toList();

        // Lọc bỏ các rule đã bị dismiss trong 24h
        return await _filterDismissed(suggestions);
      }
    } catch (e) {
      debugPrint('[SuggestionService] Không tải được gợi ý');
    }

    return _filterDismissed(_generateLocalFallback(currentSoc, chargingStatus));
  }

  Future<List<ProactiveSuggestion>> _filterDismissed(
    List<ProactiveSuggestion> list,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dismissedRulesKey) ?? '{}';
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      return list.where((s) {
        if (!map.containsKey(s.ruleId)) return true;
        final dismissedAt = map[s.ruleId] as int? ?? 0;
        final diffHours = (nowMillis - dismissedAt) / (1000 * 3600);
        return diffHours >= 24; // Sau 24h mới hiện lại
      }).toList();
    } catch (_) {
      return list;
    }
  }

  List<ProactiveSuggestion> _generateLocalFallback(
    double? currentSoc,
    String? status,
  ) {
    final soc = currentSoc;
    if (soc != null &&
        soc.isFinite &&
        soc >= 0 &&
        soc < 20.0 &&
        status != 'charging') {
      return [
        ProactiveSuggestion(
          ruleId: 'R001',
          title: 'Cảnh báo mức pin thấp',
          message:
              'Pin xe hiện chỉ còn ${soc.toInt()}%. Bạn nên cắm sạc sớm để an tâm di chuyển!',
          priority: 'HIGH',
          action: 'start_smart_charging',
          suggestedAt: DateTime.now(),
        ),
      ];
    }
    return [];
  }
}
