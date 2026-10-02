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
  SuggestionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _lastShownKey = 'vinfast_proactive_last_shown_time';
  static const String _dailyCountKey = 'vinfast_proactive_daily_count';
  static const String _dismissedRulesKey = 'vinfast_dismissed_suggestions_v1';

  /// Kiểm tra xem có được phép hiển thị proactive suggestion lúc này không (Rate Limit).
  /// Quy tắc: Tối đa 1 bubble / 30 phút, tối đa 5 lần / ngày.
  Future<bool> canShowProactiveBubble() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // 1. Kiểm tra khoảng cách 30 phút
      final lastShownMillis = prefs.getInt(_lastShownKey) ?? 0;
      final diffMinutes = now.difference(DateTime.fromMillisecondsSinceEpoch(lastShownMillis)).inMinutes;
      if (diffMinutes < 30) return false;

      // 2. Kiểm tra giới hạn 5 lần/ngày
      final countDateStr = prefs.getString('${_dailyCountKey}_date') ?? '';
      final todayStr = '${now.year}-${now.month}-${now.day}';
      int todayCount = prefs.getInt(_dailyCountKey) ?? 0;

      if (countDateStr != todayStr) {
        todayCount = 0;
        await prefs.setString('${_dailyCountKey}_date', todayStr);
        await prefs.setInt(_dailyCountKey, 0);
      }

      if (todayCount >= 5) return false;

      return true;
    } catch (_) {
      return true;
    }
  }

  /// Ghi nhận đã hiển thị một gợi ý chủ động
  Future<void> recordSuggestionShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_lastShownKey, now.millisecondsSinceEpoch);

      final todayStr = '${now.year}-${now.month}-${now.day}';
      final countDateStr = prefs.getString('${_dailyCountKey}_date') ?? '';
      int todayCount = prefs.getInt(_dailyCountKey) ?? 0;

      if (countDateStr != todayStr) {
        todayCount = 1;
        await prefs.setString('${_dailyCountKey}_date', todayStr);
      } else {
        todayCount += 1;
      }
      await prefs.setInt(_dailyCountKey, todayCount);
    } catch (_) {}
  }

  /// Bỏ qua một gợi ý (không hiện lại trong 24 giờ)
  Future<void> dismissSuggestion(String ruleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_dismissedRulesKey) ?? '{}';
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      map[ruleId] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(_dismissedRulesKey, jsonEncode(map));
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
      if (vehicleId != null) 'vehicleId': vehicleId,
      if (currentSoc != null) 'currentSoc': currentSoc.toString(),
      if (currentSoh != null) 'currentSoh': currentSoh.toString(),
      if (odoKm != null) 'odoKm': odoKm.toString(),
      if (chargingStatus != null) 'chargingStatus': chargingStatus,
    };

    final uri = AppConstants.tryBuildApiUri(
      '/api/behavior/suggestions',
      queryParameters: queryParams,
    );

    if (uri == null || !AppConstants.isApiConfigured) {
      // Fallback local logic khi offline
      return _generateLocalFallback(currentSoc, chargingStatus);
    }

    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (decoded['data'] as List<dynamic>?) ?? [];
        final suggestions = list
            .map((item) => ProactiveSuggestion.fromJson(item as Map<String, dynamic>))
            .toList();

        // Lọc bỏ các rule đã bị dismiss trong 24h
        return await _filterDismissed(suggestions);
      }
    } catch (e) {
      debugPrint('[SuggestionService] Lỗi fetchSuggestions: $e');
    }

    return _generateLocalFallback(currentSoc, chargingStatus);
  }

  Future<List<ProactiveSuggestion>> _filterDismissed(List<ProactiveSuggestion> list) async {
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

  List<ProactiveSuggestion> _generateLocalFallback(double? currentSoc, String? status) {
    final soc = currentSoc ?? 50.0;
    if (soc < 20.0 && status != 'charging') {
      return [
        ProactiveSuggestion(
          ruleId: 'R001',
          title: 'Cảnh báo mức pin thấp',
          message: 'Pin xe hiện chỉ còn ${soc.toInt()}%. Bạn nên cắm sạc sớm để an tâm di chuyển!',
          priority: 'HIGH',
          action: 'start_smart_charging',
          suggestedAt: DateTime.now(),
        ),
      ];
    }
    return [];
  }
}
