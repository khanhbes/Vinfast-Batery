import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/data/models/smart_charge_history.dart';
import 'package:vinfast_battery/data/models/smart_charging_session.dart';
import 'package:vinfast_battery/features/achievements/controllers/achievements_controller.dart';
import 'package:vinfast_battery/features/achievements/models/achievement.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_engine.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_signals.dart';
import 'package:vinfast_battery/features/achievements/services/achievement_store.dart';

LedgerSession ledger(
  String id, {
  DateTime? at,
  bool ai = true,
  double start = 30,
  double target = 80,
  double wh = 2500,
  Duration length = const Duration(hours: 2),
  String state = 'completed',
}) {
  final started = at ?? DateTime(2030, 3, 4, 23, 15);
  return LedgerSession(
    id: id,
    state: state,
    ai: ai,
    startSoc: start,
    targetSoc: target,
    energyWh: wh,
    startedAt: started,
    stoppedAt: started.add(length),
  );
}

SmartChargingSession session(
  String id, {
  String state = 'completed',
  String strategy = 'smart_combined',
  double wh = 2500,
  String startedAt = '2030-03-04T16:15:00Z',
}) => SmartChargingSession.fromJson({
  'session_id': id,
  'vehicle_id': 'VF-001',
  'state': state,
  'strategy': strategy,
  'start_soc': 30,
  'target_soc': 80,
  'predicted_minutes': 60,
  'prediction_source': 'ai_model',
  'created_at': startedAt,
  'updated_at': '2030-03-04T18:15:00Z',
  'started_at': startedAt,
  'ai_stop_at': '2030-03-04T18:15:00Z',
  'hard_deadline_at': '2030-03-04T19:00:00Z',
  'effective_stop_at': '2030-03-04T18:15:00Z',
  'absolute_safety_stop_at': '2030-03-04T22:00:00Z',
  'relay_verified': true,
  'energy_used_wh': wh,
  'version': 2,
});

class FakeRemote implements AchievementRemote {
  Map<String, DateTime> stored = {};
  int saves = 0;
  bool fail = false;

  @override
  Future<Map<String, DateTime>> load(String uid) async {
    if (fail) throw StateError('permission-denied');
    return stored;
  }

  @override
  Future<void> save(
    String uid, {
    required Map<String, DateTime> unlocked,
    required int points,
    required String rank,
  }) async {
    if (fail) throw StateError('permission-denied');
    saves++;
    stored = {...unlocked};
  }
}

void main() {
  group('catalog', () {
    test('has 65 unique achievements across every category', () {
      final ids = achievementCatalog.map((d) => d.id).toSet();
      expect(achievementCatalog.length, 65);
      expect(ids.length, achievementCatalog.length);
      for (final c in AchievementCategory.values) {
        expect(
          achievementCatalog.where((d) => d.category == c),
          isNotEmpty,
          reason: c.name,
        );
      }
      for (final d in achievementCatalog) {
        expect(d.target, greaterThan(0), reason: d.id);
        if (d.metric == AchievementMetric.event) {
          expect(d.event, isNotNull, reason: d.id);
        }
      }
    });

    test('the top rank is reachable but demanding', () {
      final total = pointsFor(achievementCatalog.map((d) => d.id));
      expect(total, greaterThan(AchievementRank.all.last.minPoints));
      expect(AchievementRank.forPoints(0).name, 'Hạng Đồng');
      expect(AchievementRank.forPoints(500).name, 'Hạng Vàng');
      expect(AchievementRank.forPoints(total).next, isNull);
    });
  });

  group('stats', () {
    test('counts only sessions that delivered energy', () {
      final stats = AchievementStats.compute([
        ledger('a'),
        ledger('noload', wh: 0, state: 'completed'),
        ledger('blip', wh: 10),
      ]);
      expect(stats.sessions, 1);
      expect(stats.kwh, closeTo(2.51, 0.001));
    });

    test('classifies care, timing and AI vs timed', () {
      final stats = AchievementStats.compute([
        ledger('night', at: DateTime(2030, 3, 4, 23, 30)),
        ledger('dawn', at: DateTime(2030, 3, 5, 6, 10), target: 100),
        ledger('owl', at: DateTime(2030, 3, 6, 1, 0), target: 88),
        ledger('timed', ai: false, start: 10, at: DateTime(2030, 3, 9, 14)),
      ]);
      expect(stats.aiSessions, 3);
      expect(stats.timedSessions, 1);
      expect(stats.care80, 1);
      expect(stats.goldenStart, 3);
      expect(stats.offPeak, 2);
      expect(stats.nightOwl, 1);
      expect(stats.morning, 1);
      expect(stats.weekend, 1);
      expect(stats.balanceMonths, 1);
      expect(stats.number88, 1);
    });

    test('week and day streaks follow consecutive runs', () {
      final weekly = [
        for (var w = 0; w < 4; w++)
          ledger('w$w', at: DateTime(2030, 3, 4 + 7 * w, 20)),
        ledger('gap', at: DateTime(2030, 5, 20, 20)),
      ];
      final stats = AchievementStats.compute(
        weekly,
        now: DateTime(2030, 3, 27),
      );
      expect(stats.weekStreak, 4);
      expect(stats.currentWeekStreak, 4);
      final daily = [
        for (var d = 0; d < 7; d++)
          ledger('d$d', at: DateTime(2030, 6, 1 + d, 21)),
      ];
      expect(AchievementStats.compute(daily).dayStreak, 7);
    });

    test('unlocks once and labels progress', () {
      final stats = AchievementStats.compute([
        for (var i = 0; i < 5; i++)
          ledger('s$i', at: DateTime(2030, 3, 4 + i, 23)),
      ]);
      final unlocked = <String, DateTime>{};
      final fresh = evaluateUnlocks(stats, unlocked);
      expect(fresh, containsAll(['ses_1', 'ses_5', 'ai_1', 'ai_5', 'kwh_10']));
      for (final id in fresh) {
        unlocked[id] = DateTime(2030);
      }
      expect(evaluateUnlocks(stats, unlocked), isEmpty);
      final ses10 = achievementCatalog.firstWhere((d) => d.id == 'ses_10');
      final p = AchievementProgress(
        def: ses10,
        value: stats.value(ses10),
        unlockedAt: null,
      );
      expect(p.label, '5/10 phiên');
      expect(p.fraction, 0.5);
    });
  });

  group('controller', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AchievementSignals.instance.drain();
    });

    test('ingests sessions, celebrates and backs up once', () async {
      final remote = FakeRemote();
      final c = AchievementsController(uid: 'u1', remote: remote);
      await c.load();
      await c.ingest([session('a'), session('active', state: 'active')]);
      expect(c.state.stats.sessions, 1);
      expect(c.state.unlocked, contains('ses_1'));
      expect(c.takeCelebrations(), contains('ses_1'));
      expect(c.takeCelebrations(), isEmpty);
      expect(remote.saves, 1);
      // Same data again: no new unlock, no extra write.
      await c.ingest([session('a')]);
      expect(remote.saves, 1);
      c.dispose();
    });

    test(
      'ledger survives a restart; remote restores on a new device',
      () async {
        final remote = FakeRemote();
        final first = AchievementsController(uid: 'u2', remote: remote);
        await first.load();
        await first.ingest([session('a')]);
        first.dispose();

        final again = AchievementsController(uid: 'u2', remote: remote);
        await again.load();
        expect(again.state.stats.sessions, 1);
        expect(again.takeCelebrations(), isEmpty);
        again.dispose();

        SharedPreferences.setMockInitialValues({});
        final device2 = AchievementsController(uid: 'u2', remote: remote);
        await device2.load();
        expect(device2.state.unlocked, contains('ses_1'));
        expect(device2.takeCelebrations(), isEmpty);
        device2.dispose();
      },
    );

    test('sync pages history until a known session', () async {
      var calls = 0;
      Future<SmartChargeHistoryPage> page({String? cursor}) async {
        calls++;
        return cursor == null
            ? SmartChargeHistoryPage(
                items: [session('n1'), session('n2')],
                nextCursor: 'p2',
              )
            : SmartChargeHistoryPage(items: [session('n3')]);
      }

      final c = AchievementsController(
        uid: 'u3',
        historyPage: page,
        remote: FakeRemote(),
      );
      await c.sync(force: true);
      expect(calls, 2);
      expect(c.state.stats.sessions, 3);
      await c.sync();
      expect(calls, 2, reason: 'throttled');
      c.dispose();
    });

    test('a new rider is pointed at the first charge', () {
      const fresh = AchievementsState();
      expect(fresh.upNext.first.def.id, 'ses_1');
    });

    test('explore signals and remote failures are tolerated', () async {
      final remote = FakeRemote()..fail = true;
      AchievementSignals.instance.emit(AchievementEvents.collectionOpened);
      final c = AchievementsController(uid: 'u4', remote: remote);
      await c.load();
      expect(c.state.unlocked, contains('explore_collection'));
      AchievementSignals.instance.emit(AchievementEvents.botCharge);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.unlocked, contains('explore_bot'));
      c.dispose();
    });
  });
}
