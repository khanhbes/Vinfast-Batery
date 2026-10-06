import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/features/ai/models/behavior_profile.dart';
import 'package:vinfast_battery/features/ai/models/chat_message.dart';
import 'package:vinfast_battery/features/ai/services/behavior_tracker.dart';
import 'package:vinfast_battery/features/ai/services/chat_history_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BehaviorProfile Unit Tests', () {
    test('defaultFor creates standard initial values', () {
      final profile = BehaviorProfile.defaultFor('u123', 'VF01');
      expect(profile.userId, 'u123');
      expect(profile.vehicleId, 'VF01');
      expect(profile.chargingPatterns.avgTargetSoc, 80.0);
      expect(profile.tripPatterns.avgDailyDistanceKm, 18.5);
      expect(profile.chatPreferences.preferredResponseLength, 'concise');
      expect(profile.chatPreferences.feedbackStats['totalThumbsUp'], 0);
    });

    test('toJson and fromJson preserves data accurately', () {
      final original = BehaviorProfile(
        userId: 'u999',
        vehicleId: 'VF-KLARA',
        chargingPatterns: const ChargingPatterns(
          preferredStartHour: 23,
          preferredEndHour: 6,
          avgTargetSoc: 90.0,
          avgSessionsPerWeek: 5.0,
          preferNightCharging: true,
          avgChargeDurationMinutes: 180,
        ),
        tripPatterns: const TripPatterns(
          avgDailyDistanceKm: 28.5,
          avgEnergyConsumptionWhPerKm: 32.0,
          peakUsageHours: [7, 8, 17, 18],
          totalTrips: 12,
        ),
        appUsage: const AppUsagePatterns(
          avgSessionMinutes: 4.2,
          mostVisitedTabs: ['smart_charging', 'dashboard'],
          preferredTheme: 'dark',
          appOpenHours: [20, 21, 22],
          totalSessions: 8,
        ),
        chatPreferences: const ChatPreferences(
          topTopics: ['shelly', 'pin'],
          feedbackStats: {'totalThumbsUp': 5, 'totalThumbsDown': 1},
          preferredResponseLength: 'concise',
          languagePreference: 'vi',
        ),
        personalInsights: const PersonalInsights(
          batteryHealthTrend: 'good',
          chargingEfficiencyScore: 0.92,
          estimatedMonthlyCostVND: 180000,
          nextMaintenanceOdoKm: 12000,
          currentOdoKm: 2500,
        ),
        updatedAt: DateTime(2026, 10, 2, 12, 0, 0),
      );

      final json = original.toJson();
      final restored = BehaviorProfile.fromJson(json);

      expect(restored.userId, original.userId);
      expect(restored.vehicleId, original.vehicleId);
      expect(restored.chargingPatterns.preferredStartHour, 23);
      expect(restored.chargingPatterns.avgTargetSoc, 90.0);
      expect(restored.tripPatterns.avgDailyDistanceKm, 28.5);
      expect(restored.appUsage.mostVisitedTabs.first, 'smart_charging');
      expect(restored.chatPreferences.feedbackStats['totalThumbsUp'], 5);
      expect(restored.chatPreferences.topTopics.contains('pin'), isTrue);
      expect(restored.personalInsights.estimatedMonthlyCostVND, 180000);
    });
  });

  group('BehaviorTracker StateNotifier Tests', () {
    test('trackAppUsage updates visited tabs and active hours', () {
      final tracker = BehaviorTracker();
      tracker.setIdentity(userId: 'test-user', vehicleId: 'VF01');

      tracker.trackAppUsage(tabName: 'smart_charging');
      expect(tracker.state.userId, 'test-user');
      expect(tracker.state.vehicleId, 'VF01');
      expect(tracker.state.appUsage.mostVisitedTabs.first, 'smart_charging');
      expect(tracker.state.appUsage.totalSessions, greaterThan(0));
    });

    test(
      'trackChatInteraction increments topic counts and feedback counts',
      () {
        final tracker = BehaviorTracker();
        tracker.setIdentity(userId: 'test-user');

        tracker.trackChatInteraction(topic: 'pin');
        tracker.trackChatInteraction(topic: 'pin');
        tracker.trackChatInteraction(topic: 'shelly');
        tracker.trackChatInteraction(feedbackRating: 'up');
        tracker.trackChatInteraction(feedbackRating: 'up');
        tracker.trackChatInteraction(feedbackRating: 'down');

        expect(tracker.state.chatPreferences.topTopics.contains('pin'), isTrue);
        expect(tracker.state.chatPreferences.feedbackStats['totalThumbsUp'], 2);
        expect(
          tracker.state.chatPreferences.feedbackStats['totalThumbsDown'],
          1,
        );
      },
    );

    test('trackChargingEvent updates charging pattern values', () {
      final tracker = BehaviorTracker();

      tracker.trackChargingEvent(
        startHour: 22,
        durationMinutes: 120,
        targetSoc: 85.0,
        nightCharging: true,
      );

      expect(tracker.state.chargingPatterns.avgTargetSoc, 81.5);
      expect(tracker.state.chargingPatterns.preferNightCharging, isTrue);
    });

    test('trackTripEvent updates trip pattern stats', () {
      final tracker = BehaviorTracker();

      tracker.trackTripEvent(distanceKm: 30.0, energyWhPerKm: 32.5);

      expect(tracker.state.tripPatterns.totalTrips, greaterThan(0));
      expect(tracker.state.tripPatterns.avgDailyDistanceKm, greaterThan(18.5));
    });
  });

  group('ChatHistoryStorage Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test(
      'saveSessionMessages, listSessions, and loadSessionMessages flow',
      () async {
        final storage = ChatHistoryStorage();

        final messages = [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            content: 'Kiểm tra pin xe Feliz',
            timestamp: DateTime(2026, 10, 2, 10, 0),
          ),
          ChatMessage(
            id: 'm2',
            role: ChatRole.model,
            content: 'Pin Feliz còn 82%, dung lượng tốt.',
            timestamp: DateTime(2026, 10, 2, 10, 1),
          ),
        ];

        await storage.saveSessionMessages(
          'sess-100',
          messages,
          title: 'Hỏi pin xe Feliz',
        );

        final sessions = await storage.listSessions();
        expect(sessions.length, 1);
        expect(sessions.first.sessionId, 'sess-100');
        expect(sessions.first.id, 'sess-100');
        expect(sessions.first.title, 'Hỏi pin xe Feliz');
        expect(sessions.first.messageCount, 2);

        final loadedMsgs = await storage.loadSessionMessages('sess-100');
        expect(loadedMsgs.length, 2);
        expect(loadedMsgs[0].content, 'Kiểm tra pin xe Feliz');
        expect(loadedMsgs[1].content, 'Pin Feliz còn 82%, dung lượng tốt.');

        // Test deleteSession
        await storage.deleteSession('sess-100');
        final afterDeleteSessions = await storage.listSessions();
        expect(afterDeleteSessions, isEmpty);
        final afterDeleteMsgs = await storage.loadSessionMessages('sess-100');
        expect(afterDeleteMsgs, isEmpty);
      },
    );
  });
}
