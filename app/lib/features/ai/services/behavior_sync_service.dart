import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../models/behavior_profile.dart';
import 'behavior_tracker.dart';

final behaviorSyncServiceProvider = Provider<BehaviorSyncService>((ref) {
  final service = BehaviorSyncService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

class BehaviorSyncService {
  BehaviorSyncService({this.ref, this.tracker, http.Client? client})
    : _client = client ?? http.Client();

  final Ref? ref;
  final BehaviorTracker? tracker;
  final http.Client _client;
  Timer? _debounceTimer;
  void dispose() {
    _debounceTimer?.cancel();
    _client.close();
  }

  Future<Map<String, String>> _getHeaders() async {
    String? token;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        token = await user.getIdToken();
      }
    } catch (_) {}

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Khởi động tự động sync định kỳ hoặc khi có thay đổi (debounce 5 phút)
  void scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(minutes: 5), () {
      syncNow();
    });
  }

  /// Đồng bộ ngay lập tức (gọi khi app chuyển sang paused hoặc user yêu cầu)
  Future<bool> syncNow() async {
    final uri = AppConstants.tryBuildApiUri('/api/behavior/sync');
    if (uri == null || !AppConstants.isApiConfigured) return false;

    try {
      final profile =
          tracker?.currentProfile ??
          ref?.read(behaviorTrackerProvider) ??
          BehaviorProfile.defaultFor('');
      if (Firebase.apps.isEmpty ||
          FirebaseAuth.instance.currentUser?.uid != profile.userId) {
        return false;
      }
      final headers = await _getHeaders();
      if (FirebaseAuth.instance.currentUser?.uid != profile.userId ||
          !headers.containsKey('Authorization')) {
        return false;
      }

      final res = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'userId': profile.userId,
              'profile': profile.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        debugPrint('[BehaviorSync] Đồng bộ profile lên server thành công');
        return true;
      }
    } catch (e) {
      debugPrint('[BehaviorSync] Profile sync unavailable.');
    }
    return false;
  }

  /// Nạp profile từ server về máy khi đăng nhập
  Future<BehaviorProfile?> fetchRemoteProfile(
    String userId, [
    String? vehicleId,
  ]) async {
    final path = vehicleId != null
        ? '/api/behavior/profile?userId=$userId&vehicleId=$vehicleId'
        : '/api/behavior/profile?userId=$userId';
    final uri = AppConstants.tryBuildApiUri(path);
    if (uri == null || !AppConstants.isApiConfigured) return null;

    try {
      final headers = await _getHeaders();
      if (Firebase.apps.isEmpty ||
          FirebaseAuth.instance.currentUser?.uid != userId ||
          !headers.containsKey('Authorization')) {
        return null;
      }
      final res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          final remote = BehaviorProfile.fromJson(data);
          if (remote.userId != userId ||
              FirebaseAuth.instance.currentUser?.uid != userId) {
            return null;
          }
          if (tracker != null) {
            tracker!.replaceProfile(remote);
          } else if (ref != null) {
            ref!.read(behaviorTrackerProvider.notifier).replaceProfile(remote);
          }
          return remote;
        }
      }
    } catch (e) {
      debugPrint('[BehaviorSync] Remote profile unavailable.');
    }
    return null;
  }
}
