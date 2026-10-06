import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/behavior_profile.dart';

final behaviorTrackerProvider =
    StateNotifierProvider<BehaviorTracker, BehaviorProfile>((ref) {
      final tracker = BehaviorTracker();
      tracker.loadLocalProfile();
      return tracker;
    });

class BehaviorTracker extends StateNotifier<BehaviorProfile> {
  BehaviorTracker() : super(BehaviorProfile.defaultFor('local_user'));

  static const String _storageKey = 'vinfast_user_behavior_profile';
  int _identityGeneration = 0;

  BehaviorProfile get currentProfile => state;

  /// Nạp profile đã lưu trong SharedPreferences (local cache)
  Future<void> loadLocalProfile() async {
    final generation = _identityGeneration;
    final uid = state.userId;
    final snapshot = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted ||
          generation != _identityGeneration ||
          !identical(state, snapshot)) {
        return;
      }
      final raw = prefs.getString(
        '${_storageKey}_v2_${Uri.encodeComponent(uid)}',
      );
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final profile = BehaviorProfile.fromJson(json);
        if (profile.userId == uid) state = profile;
      }
    } catch (e) {
      debugPrint('[BehaviorTracker] Local profile unavailable.');
    }
  }

  /// Lưu profile vào SharedPreferences
  Future<void> saveLocalProfile() async {
    final profile = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${_storageKey}_v2_${Uri.encodeComponent(profile.userId)}',
        jsonEncode(profile.toJson()),
      );
    } catch (e) {
      debugPrint('[BehaviorTracker] Profile save unavailable.');
    }
  }

  /// Cập nhật User ID và Vehicle ID khi đăng nhập / đổi xe
  void setIdentity({required String userId, String? vehicleId}) {
    if (userId == state.userId && vehicleId == state.vehicleId) return;
    if (userId != state.userId) {
      _identityGeneration++;
      state = BehaviorProfile.defaultFor(userId, vehicleId);
      loadLocalProfile();
      return;
    }
    state = state.copyWith(userId: userId, vehicleId: vehicleId);
    saveLocalProfile();
  }

  /// Ghi nhận phiên sạc
  void trackChargingEvent({
    required int startHour,
    required double targetSoc,
    int durationMinutes = 180,
    bool nightCharging = true,
  }) {
    final cp = state.chargingPatterns;
    final newAvgTarget = ((cp.avgTargetSoc * 0.7) + (targetSoc * 0.3));
    final newStartHour = ((cp.preferredStartHour * 0.7) + (startHour * 0.3))
        .round();
    final newDuration =
        ((cp.avgChargeDurationMinutes * 0.7) + (durationMinutes * 0.3)).round();

    final updatedCp = cp.copyWith(
      avgTargetSoc: double.parse(newAvgTarget.toStringAsFixed(1)),
      preferredStartHour: newStartHour,
      avgChargeDurationMinutes: newDuration,
      preferNightCharging: nightCharging,
      lastChargingEvent: DateTime.now(),
    );

    state = state.copyWith(
      chargingPatterns: updatedCp,
      updatedAt: DateTime.now(),
    );
    saveLocalProfile();
  }

  /// Ghi nhận chuyến đi
  void trackTripEvent({
    required double distanceKm,
    double energyWhPerKm = 32.0,
  }) {
    final tp = state.tripPatterns;
    final newAvgDistance = ((tp.avgDailyDistanceKm * 0.8) + (distanceKm * 0.2));
    final newAvgEnergy =
        ((tp.avgEnergyConsumptionWhPerKm * 0.8) + (energyWhPerKm * 0.2));

    final updatedTp = tp.copyWith(
      totalTrips: tp.totalTrips + 1,
      avgDailyDistanceKm: double.parse(newAvgDistance.toStringAsFixed(1)),
      avgEnergyConsumptionWhPerKm: double.parse(
        newAvgEnergy.toStringAsFixed(1),
      ),
    );

    state = state.copyWith(tripPatterns: updatedTp, updatedAt: DateTime.now());
    saveLocalProfile();
  }

  /// Ghi nhận truy cập màn hình/tab
  void trackAppUsage({required String tabName, double sessionMinutes = 2.0}) {
    final au = state.appUsage;
    final newTabs = List<String>.from(au.mostVisitedTabs);
    newTabs.remove(tabName);
    newTabs.insert(0, tabName);
    if (newTabs.length > 5) newTabs.removeLast();

    final updatedAu = au.copyWith(
      totalSessions: au.totalSessions + 1,
      mostVisitedTabs: newTabs,
    );

    state = state.copyWith(appUsage: updatedAu, updatedAt: DateTime.now());
    saveLocalProfile();
  }

  /// Ghi nhận tương tác chatbot và feedback 👍/👎
  void trackChatInteraction({String? topic, String? feedbackRating}) {
    final cp = state.chatPreferences;
    final newTopics = List<String>.from(cp.topTopics);
    if (topic != null && topic.isNotEmpty) {
      newTopics.remove(topic);
      newTopics.insert(0, topic);
      if (newTopics.length > 5) newTopics.removeLast();
    }

    final newStats = Map<String, dynamic>.from(cp.feedbackStats);
    if (feedbackRating == 'like' || feedbackRating == 'up') {
      newStats['totalThumbsUp'] = (newStats['totalThumbsUp'] as int? ?? 0) + 1;
    } else if (feedbackRating == 'dislike' || feedbackRating == 'down') {
      newStats['totalThumbsDown'] =
          (newStats['totalThumbsDown'] as int? ?? 0) + 1;
    }

    final updatedCp = cp.copyWith(
      topTopics: newTopics,
      feedbackStats: newStats,
    );

    state = state.copyWith(
      chatPreferences: updatedCp,
      updatedAt: DateTime.now(),
    );
    saveLocalProfile();
  }

  /// Thay thế profile từ server sync
  void replaceProfile(BehaviorProfile newProfile) {
    state = newProfile;
    saveLocalProfile();
  }
}
