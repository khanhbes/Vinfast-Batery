import 'package:flutter/foundation.dart';

@immutable
class ChargingPatterns {
  const ChargingPatterns({
    this.preferredStartHour = 22,
    this.preferredEndHour = 6,
    this.avgTargetSoc = 80.0,
    this.avgSessionsPerWeek = 4.0,
    this.preferNightCharging = true,
    this.avgChargeDurationMinutes = 180,
    this.lastChargingEvent,
  });

  final int preferredStartHour;
  final int preferredEndHour;
  final double avgTargetSoc;
  final double avgSessionsPerWeek;
  final bool preferNightCharging;
  final int avgChargeDurationMinutes;
  final DateTime? lastChargingEvent;

  ChargingPatterns copyWith({
    int? preferredStartHour,
    int? preferredEndHour,
    double? avgTargetSoc,
    double? avgSessionsPerWeek,
    bool? preferNightCharging,
    int? avgChargeDurationMinutes,
    DateTime? lastChargingEvent,
  }) {
    return ChargingPatterns(
      preferredStartHour: preferredStartHour ?? this.preferredStartHour,
      preferredEndHour: preferredEndHour ?? this.preferredEndHour,
      avgTargetSoc: avgTargetSoc ?? this.avgTargetSoc,
      avgSessionsPerWeek: avgSessionsPerWeek ?? this.avgSessionsPerWeek,
      preferNightCharging: preferNightCharging ?? this.preferNightCharging,
      avgChargeDurationMinutes:
          avgChargeDurationMinutes ?? this.avgChargeDurationMinutes,
      lastChargingEvent: lastChargingEvent ?? this.lastChargingEvent,
    );
  }

  factory ChargingPatterns.fromJson(Map<String, dynamic> json) {
    return ChargingPatterns(
      preferredStartHour: (json['preferredStartHour'] as num?)?.toInt() ?? 22,
      preferredEndHour: (json['preferredEndHour'] as num?)?.toInt() ?? 6,
      avgTargetSoc: (json['avgTargetSoc'] as num?)?.toDouble() ?? 80.0,
      avgSessionsPerWeek:
          (json['avgSessionsPerWeek'] as num?)?.toDouble() ?? 4.0,
      preferNightCharging: json['preferNightCharging'] as bool? ?? true,
      avgChargeDurationMinutes:
          (json['avgChargeDurationMinutes'] as num?)?.toInt() ?? 180,
      lastChargingEvent: json['lastChargingEvent'] != null
          ? DateTime.tryParse(json['lastChargingEvent'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'preferredStartHour': preferredStartHour,
        'preferredEndHour': preferredEndHour,
        'avgTargetSoc': avgTargetSoc,
        'avgSessionsPerWeek': avgSessionsPerWeek,
        'preferNightCharging': preferNightCharging,
        'avgChargeDurationMinutes': avgChargeDurationMinutes,
        if (lastChargingEvent != null)
          'lastChargingEvent': lastChargingEvent!.toIso8601String(),
      };
}

@immutable
class TripPatterns {
  const TripPatterns({
    this.avgDailyDistanceKm = 18.5,
    this.avgEnergyConsumptionWhPerKm = 32.0,
    this.peakUsageHours = const [7, 8, 17, 18],
    this.totalTrips = 0,
  });

  final double avgDailyDistanceKm;
  final double avgEnergyConsumptionWhPerKm;
  final List<int> peakUsageHours;
  final int totalTrips;

  TripPatterns copyWith({
    double? avgDailyDistanceKm,
    double? avgEnergyConsumptionWhPerKm,
    List<int>? peakUsageHours,
    int? totalTrips,
  }) {
    return TripPatterns(
      avgDailyDistanceKm: avgDailyDistanceKm ?? this.avgDailyDistanceKm,
      avgEnergyConsumptionWhPerKm:
          avgEnergyConsumptionWhPerKm ?? this.avgEnergyConsumptionWhPerKm,
      peakUsageHours: peakUsageHours ?? this.peakUsageHours,
      totalTrips: totalTrips ?? this.totalTrips,
    );
  }

  factory TripPatterns.fromJson(Map<String, dynamic> json) {
    return TripPatterns(
      avgDailyDistanceKm:
          (json['avgDailyDistanceKm'] as num?)?.toDouble() ?? 18.5,
      avgEnergyConsumptionWhPerKm:
          (json['avgEnergyConsumptionWhPerKm'] as num?)?.toDouble() ?? 32.0,
      peakUsageHours: (json['peakUsageHours'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [7, 8, 17, 18],
      totalTrips: (json['totalTrips'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'avgDailyDistanceKm': avgDailyDistanceKm,
        'avgEnergyConsumptionWhPerKm': avgEnergyConsumptionWhPerKm,
        'peakUsageHours': peakUsageHours,
        'totalTrips': totalTrips,
      };
}

@immutable
class AppUsagePatterns {
  const AppUsagePatterns({
    this.avgSessionMinutes = 3.5,
    this.mostVisitedTabs = const ['dashboard', 'smart_charging'],
    this.preferredTheme = 'dark',
    this.appOpenHours = const [7, 12, 18, 22],
    this.totalSessions = 0,
  });

  final double avgSessionMinutes;
  final List<String> mostVisitedTabs;
  final String preferredTheme;
  final List<int> appOpenHours;
  final int totalSessions;

  AppUsagePatterns copyWith({
    double? avgSessionMinutes,
    List<String>? mostVisitedTabs,
    String? preferredTheme,
    List<int>? appOpenHours,
    int? totalSessions,
  }) {
    return AppUsagePatterns(
      avgSessionMinutes: avgSessionMinutes ?? this.avgSessionMinutes,
      mostVisitedTabs: mostVisitedTabs ?? this.mostVisitedTabs,
      preferredTheme: preferredTheme ?? this.preferredTheme,
      appOpenHours: appOpenHours ?? this.appOpenHours,
      totalSessions: totalSessions ?? this.totalSessions,
    );
  }

  factory AppUsagePatterns.fromJson(Map<String, dynamic> json) {
    return AppUsagePatterns(
      avgSessionMinutes:
          (json['avgSessionMinutes'] as num?)?.toDouble() ?? 3.5,
      mostVisitedTabs: (json['mostVisitedTabs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['dashboard', 'smart_charging'],
      preferredTheme: json['preferredTheme'] as String? ?? 'dark',
      appOpenHours: (json['appOpenHours'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [7, 12, 18, 22],
      totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'avgSessionMinutes': avgSessionMinutes,
        'mostVisitedTabs': mostVisitedTabs,
        'preferredTheme': preferredTheme,
        'appOpenHours': appOpenHours,
        'totalSessions': totalSessions,
      };
}

@immutable
class ChatPreferences {
  const ChatPreferences({
    this.topTopics = const ['charging_schedule', 'battery_health'],
    this.feedbackStats = const {'totalThumbsUp': 0, 'totalThumbsDown': 0},
    this.preferredResponseLength = 'concise',
    this.languagePreference = 'vi',
  });

  final List<String> topTopics;
  final Map<String, dynamic> feedbackStats;
  final String preferredResponseLength;
  final String languagePreference;

  ChatPreferences copyWith({
    List<String>? topTopics,
    Map<String, dynamic>? feedbackStats,
    String? preferredResponseLength,
    String? languagePreference,
  }) {
    return ChatPreferences(
      topTopics: topTopics ?? this.topTopics,
      feedbackStats: feedbackStats ?? this.feedbackStats,
      preferredResponseLength:
          preferredResponseLength ?? this.preferredResponseLength,
      languagePreference: languagePreference ?? this.languagePreference,
    );
  }

  factory ChatPreferences.fromJson(Map<String, dynamic> json) {
    return ChatPreferences(
      topTopics: (json['topTopics'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['charging_schedule', 'battery_health'],
      feedbackStats: json['feedbackStats'] as Map<String, dynamic>? ??
          const {'totalThumbsUp': 0, 'totalThumbsDown': 0},
      preferredResponseLength:
          json['preferredResponseLength'] as String? ?? 'concise',
      languagePreference: json['languagePreference'] as String? ?? 'vi',
    );
  }

  Map<String, dynamic> toJson() => {
        'topTopics': topTopics,
        'feedbackStats': feedbackStats,
        'preferredResponseLength': preferredResponseLength,
        'languagePreference': languagePreference,
      };
}

@immutable
class PersonalInsights {
  const PersonalInsights({
    this.batteryHealthTrend = 'stable',
    this.chargingEfficiencyScore = 0.85,
    this.estimatedMonthlyCostVND = 150000,
    this.nextMaintenanceOdoKm = 10000,
    this.currentOdoKm = 0,
  });

  final String batteryHealthTrend;
  final double chargingEfficiencyScore;
  final int estimatedMonthlyCostVND;
  final int nextMaintenanceOdoKm;
  final int currentOdoKm;

  PersonalInsights copyWith({
    String? batteryHealthTrend,
    double? chargingEfficiencyScore,
    int? estimatedMonthlyCostVND,
    int? nextMaintenanceOdoKm,
    int? currentOdoKm,
  }) {
    return PersonalInsights(
      batteryHealthTrend: batteryHealthTrend ?? this.batteryHealthTrend,
      chargingEfficiencyScore:
          chargingEfficiencyScore ?? this.chargingEfficiencyScore,
      estimatedMonthlyCostVND:
          estimatedMonthlyCostVND ?? this.estimatedMonthlyCostVND,
      nextMaintenanceOdoKm: nextMaintenanceOdoKm ?? this.nextMaintenanceOdoKm,
      currentOdoKm: currentOdoKm ?? this.currentOdoKm,
    );
  }

  factory PersonalInsights.fromJson(Map<String, dynamic> json) {
    return PersonalInsights(
      batteryHealthTrend: json['batteryHealthTrend'] as String? ?? 'stable',
      chargingEfficiencyScore:
          (json['chargingEfficiencyScore'] as num?)?.toDouble() ?? 0.85,
      estimatedMonthlyCostVND:
          (json['estimatedMonthlyCostVND'] as num?)?.toInt() ?? 150000,
      nextMaintenanceOdoKm:
          (json['nextMaintenanceOdoKm'] as num?)?.toInt() ?? 10000,
      currentOdoKm: (json['currentOdoKm'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'batteryHealthTrend': batteryHealthTrend,
        'chargingEfficiencyScore': chargingEfficiencyScore,
        'estimatedMonthlyCostVND': estimatedMonthlyCostVND,
        'nextMaintenanceOdoKm': nextMaintenanceOdoKm,
        'currentOdoKm': currentOdoKm,
      };
}

@immutable
class BehaviorProfile {
  const BehaviorProfile({
    this.schemaVersion = 'behavior-profile/v1',
    required this.userId,
    this.vehicleId,
    required this.updatedAt,
    this.syncedAt,
    this.chargingPatterns = const ChargingPatterns(),
    this.tripPatterns = const TripPatterns(),
    this.appUsage = const AppUsagePatterns(),
    this.chatPreferences = const ChatPreferences(),
    this.personalInsights = const PersonalInsights(),
  });

  final String schemaVersion;
  final String userId;
  final String? vehicleId;
  final DateTime updatedAt;
  final DateTime? syncedAt;
  final ChargingPatterns chargingPatterns;
  final TripPatterns tripPatterns;
  final AppUsagePatterns appUsage;
  final ChatPreferences chatPreferences;
  final PersonalInsights personalInsights;

  factory BehaviorProfile.defaultFor(String userId, [String? vehicleId]) {
    final now = DateTime.now();
    return BehaviorProfile(
      userId: userId,
      vehicleId: vehicleId,
      updatedAt: now,
      syncedAt: now,
    );
  }

  BehaviorProfile copyWith({
    String? schemaVersion,
    String? userId,
    String? vehicleId,
    DateTime? updatedAt,
    DateTime? syncedAt,
    ChargingPatterns? chargingPatterns,
    TripPatterns? tripPatterns,
    AppUsagePatterns? appUsage,
    ChatPreferences? chatPreferences,
    PersonalInsights? personalInsights,
  }) {
    return BehaviorProfile(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      userId: userId ?? this.userId,
      vehicleId: vehicleId ?? this.vehicleId,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
      chargingPatterns: chargingPatterns ?? this.chargingPatterns,
      tripPatterns: tripPatterns ?? this.tripPatterns,
      appUsage: appUsage ?? this.appUsage,
      chatPreferences: chatPreferences ?? this.chatPreferences,
      personalInsights: personalInsights ?? this.personalInsights,
    );
  }

  factory BehaviorProfile.fromJson(Map<String, dynamic> json) {
    return BehaviorProfile(
      schemaVersion:
          json['schemaVersion'] as String? ?? 'behavior-profile/v1',
      userId: json['userId'] as String? ?? '',
      vehicleId: json['vehicleId'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      syncedAt: json['syncedAt'] != null
          ? DateTime.tryParse(json['syncedAt'] as String)
          : null,
      chargingPatterns: json['chargingPatterns'] != null
          ? ChargingPatterns.fromJson(
              json['chargingPatterns'] as Map<String, dynamic>)
          : const ChargingPatterns(),
      tripPatterns: json['tripPatterns'] != null
          ? TripPatterns.fromJson(
              json['tripPatterns'] as Map<String, dynamic>)
          : const TripPatterns(),
      appUsage: json['appUsage'] != null
          ? AppUsagePatterns.fromJson(
              json['appUsage'] as Map<String, dynamic>)
          : const AppUsagePatterns(),
      chatPreferences: json['chatPreferences'] != null
          ? ChatPreferences.fromJson(
              json['chatPreferences'] as Map<String, dynamic>)
          : const ChatPreferences(),
      personalInsights: json['personalInsights'] != null
          ? PersonalInsights.fromJson(
              json['personalInsights'] as Map<String, dynamic>)
          : const PersonalInsights(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'userId': userId,
        if (vehicleId != null) 'vehicleId': vehicleId,
        'updatedAt': updatedAt.toIso8601String(),
        if (syncedAt != null) 'syncedAt': syncedAt!.toIso8601String(),
        'chargingPatterns': chargingPatterns.toJson(),
        'tripPatterns': tripPatterns.toJson(),
        'appUsage': appUsage.toJson(),
        'chatPreferences': chatPreferences.toJson(),
        'personalInsights': personalInsights.toJson(),
      };
}
