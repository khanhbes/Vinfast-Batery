import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/smart_charge_history.dart';
import '../../../data/models/smart_charging_session.dart';
import '../../../data/repositories/smart_charger_repository.dart';
import '../../auth/auth_providers.dart';
import '../models/achievement.dart';
import '../services/achievement_engine.dart';
import '../services/achievement_signals.dart';
import '../services/achievement_store.dart';

typedef AchievementHistoryPage =
    Future<SmartChargeHistoryPage> Function({String? cursor});

/// Which families to suggest first when progress ties.
const _suggestOrder = [
  AchievementCategory.sessions,
  AchievementCategory.ai,
  AchievementCategory.energy,
  AchievementCategory.care,
  AchievementCategory.timing,
  AchievementCategory.explore,
  AchievementCategory.streak,
  AchievementCategory.eco,
  AchievementCategory.secret,
];

class AchievementsState {
  const AchievementsState({
    this.loaded = false,
    this.syncing = false,
    this.stats = const AchievementStats(),
    this.unlocked = const {},
    this.pendingCelebrations = const [],
    this.sessions = const [],
  });

  final bool loaded;
  final bool syncing;
  final AchievementStats stats;
  final Map<String, DateTime> unlocked;

  /// Newly unlocked ids waiting for their ceremony.
  final List<String> pendingCelebrations;

  /// The device ledger (finished sessions), newest first — also feeds the
  /// dashboard charging trend without extra reads.
  final List<LedgerSession> sessions;

  int get points => pointsFor(unlocked.keys);
  AchievementRank get rank => AchievementRank.forPoints(points);
  int get unlockedCount => unlocked.length;
  int get total => achievementCatalog.length;

  /// 0..1 towards the next rank (1 at the top rank).
  double get rankProgress {
    final next = rank.next;
    if (next == null) return 1;
    return ((points - rank.minPoints) / (next.minPoints - rank.minPoints))
        .clamp(0.0, 1.0);
  }

  AchievementProgress progressOf(AchievementDef def) => AchievementProgress(
    def: def,
    value: stats.value(def),
    unlockedAt: unlocked[def.id],
  );

  List<AchievementProgress> get all => [
    for (final d in achievementCatalog) progressOf(d),
  ];

  /// Closest locked, non-secret achievements (most progress first).
  List<AchievementProgress> get upNext {
    final locked = all.where((p) => !p.unlocked && !p.def.secret).toList()
      ..sort((a, b) {
        final c = b.fraction.compareTo(a.fraction);
        if (c != 0) return c;
        // Same progress: the one needing the fewest steps first, so a new
        // rider sees "Lần sạc đầu tiên (0/1)" before longer goals.
        final r = (a.def.target - a.value).compareTo(b.def.target - b.value);
        if (r != 0) return r;
        final k = _suggestOrder
            .indexOf(a.def.category)
            .compareTo(_suggestOrder.indexOf(b.def.category));
        return k != 0
            ? k
            : achievementCatalog
                  .indexOf(a.def)
                  .compareTo(achievementCatalog.indexOf(b.def));
      });
    return locked.take(5).toList();
  }

  /// Most recently unlocked first.
  List<AchievementProgress> get recent {
    final list = all.where((p) => p.unlocked).toList()
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    return list;
  }

  AchievementsState copyWith({
    bool? loaded,
    bool? syncing,
    AchievementStats? stats,
    Map<String, DateTime>? unlocked,
    List<String>? pendingCelebrations,
    List<LedgerSession>? sessions,
  }) => AchievementsState(
    loaded: loaded ?? this.loaded,
    syncing: syncing ?? this.syncing,
    stats: stats ?? this.stats,
    unlocked: unlocked ?? this.unlocked,
    pendingCelebrations: pendingCelebrations ?? this.pendingCelebrations,
    sessions: sessions ?? this.sessions,
  );
}

class AchievementsController extends StateNotifier<AchievementsState> {
  AchievementsController({
    required this.uid,
    AchievementLocalStore local = const AchievementLocalStore(),
    AchievementRemote? remote,
    AchievementHistoryPage? historyPage,
    DateTime Function()? clock,
    bool autoLoad = true,
  }) : _local = local,
       _remote = remote,
       _historyPage = historyPage,
       _clock = clock ?? DateTime.now,
       super(const AchievementsState()) {
    AchievementSignals.instance.addListener(_onSignal);
    if (autoLoad) unawaited(load());
  }

  void _onSignal() {
    if (uid == null) return;
    for (final event in AchievementSignals.instance.drain()) {
      unawaited(recordEvent(event));
    }
  }

  @override
  void dispose() {
    AchievementSignals.instance.removeListener(_onSignal);
    super.dispose();
  }

  final String? uid;
  final AchievementLocalStore _local;
  final AchievementRemote? _remote;
  final AchievementHistoryPage? _historyPage;
  final DateTime Function() _clock;

  static const syncInterval = Duration(hours: 6);
  static const _maxPages = 10;

  AchievementLedgerData _data = AchievementLedgerData();
  Future<void>? _loading;
  bool _syncInFlight = false;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final id = uid;
    if (id == null) {
      state = state.copyWith(loaded: true);
      return;
    }
    _data = await _local.load(id);
    // Events emitted before this controller existed.
    _data.events.addAll(AchievementSignals.instance.drain());
    if (!_data.remoteRestored && _remote != null) {
      try {
        final remote = await _remote.load(id);
        for (final e in remote.entries) {
          final mine = _data.unlocked[e.key];
          if (mine == null || e.value.isBefore(mine)) {
            _data.unlocked[e.key] = e.value;
          }
        }
        _data.remoteRestored = true;
      } on Object catch (e) {
        // Rules not deployed / offline: keep the local ledger, retry later.
        debugPrint('[Achievements] remote restore skipped (${e.runtimeType})');
      }
    }
    if (!mounted) return;
    // Restored unlocks are already in the ledger, so only genuinely new
    // ones (e.g. an event recorded before load) reach the ceremony.
    _evaluate(celebrate: true);
    state = state.copyWith(loaded: true);
    await _local.save(id, _data);
  }

  /// Folds sessions the app already has in memory (no extra reads).
  Future<void> ingest(Iterable<SmartChargingSession> sessions) async {
    await load();
    var changed = false;
    for (final s in sessions) {
      final entry = LedgerSession.fromSession(s);
      if (entry == null) continue;
      final old = _data.sessions[entry.id];
      if (old == null ||
          old.state != entry.state ||
          old.energyWh != entry.energyWh) {
        _data.sessions[entry.id] = entry;
        changed = true;
      }
    }
    if (changed) await _commit();
  }

  /// Records an explore event once.
  Future<void> recordEvent(String event) async {
    await load();
    if (_data.events.add(event)) await _commit();
  }

  /// Pages history newest-first until it meets a session already in the
  /// ledger. Throttled so tab switches do not spend Firestore reads.
  Future<void> sync({bool force = false}) async {
    await load();
    final id = uid;
    final page = _historyPage;
    if (id == null || page == null || _syncInFlight) return;
    final last = _data.lastSync;
    if (!force && last != null && _clock().difference(last) < syncInterval) {
      return;
    }
    _syncInFlight = true;
    if (mounted) state = state.copyWith(syncing: true);
    try {
      String? cursor;
      for (var i = 0; i < _maxPages; i++) {
        final result = await page(cursor: cursor);
        var reachedKnown = false;
        for (final s in result.items) {
          final entry = LedgerSession.fromSession(s);
          if (entry == null) continue;
          if (_data.sessions.containsKey(entry.id)) reachedKnown = true;
          _data.sessions[entry.id] = entry;
        }
        cursor = result.nextCursor;
        if (reachedKnown || cursor == null || result.items.isEmpty) break;
      }
      _data.lastSync = _clock();
      await _commit();
    } on Object catch (e) {
      debugPrint('[Achievements] history sync failed (${e.runtimeType})');
    } finally {
      _syncInFlight = false;
      if (mounted) state = state.copyWith(syncing: false);
    }
  }

  /// Hands the waiting ceremonies to the UI exactly once.
  List<String> takeCelebrations() {
    final pending = state.pendingCelebrations;
    if (pending.isNotEmpty) {
      state = state.copyWith(pendingCelebrations: const []);
    }
    return pending;
  }

  Future<void> _commit() async {
    final id = uid;
    if (id == null) return;
    final fresh = _evaluate(celebrate: true);
    await _local.save(id, _data);
    if (fresh.isNotEmpty && _remote != null) {
      final points = pointsFor(_data.unlocked.keys);
      try {
        await _remote.save(
          id,
          unlocked: _data.unlocked,
          points: points,
          rank: AchievementRank.forPoints(points).name,
        );
      } on Object catch (e) {
        debugPrint('[Achievements] remote save skipped (${e.runtimeType})');
      }
    }
  }

  List<String> _evaluate({required bool celebrate}) {
    final stats = AchievementStats.compute(
      _data.sessions.values,
      events: _data.events,
      now: _clock(),
    );
    final fresh = evaluateUnlocks(stats, _data.unlocked);
    final now = _clock();
    for (final id in fresh) {
      _data.unlocked[id] = now;
    }
    if (mounted) {
      state = state.copyWith(
        stats: stats,
        sessions: List.unmodifiable(
          _data.sessions.values.toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
        ),
        unlocked: Map.unmodifiable(_data.unlocked),
        pendingCelebrations: celebrate && fresh.isNotEmpty
            ? [...state.pendingCelebrations, ...fresh]
            : state.pendingCelebrations,
      );
    }
    return fresh;
  }
}

/// History pages for the ledger, via the account's Smart Charge repository.
AchievementHistoryPage _defaultHistoryPage() {
  Future<SmartChargerRepository>? repo;
  return ({String? cursor}) async {
    final r = await (repo ??= SmartChargerRepositoryFactory.create());
    return r.getHistoryPage(limit: 50, cursor: cursor);
  };
}

final achievementsControllerProvider =
    StateNotifierProvider<AchievementsController, AchievementsState>((ref) {
      // Never take the host screen down if auth is unavailable (Firebase
      // not initialised): no account simply means no collection.
      String? uid;
      try {
        uid = ref.watch(currentUidProvider);
      } on Object {
        uid = null;
      }
      return AchievementsController(
        uid: uid,
        remote: uid == null ? null : FirestoreAchievementRemote(),
        historyPage: uid == null ? null : _defaultHistoryPage(),
      );
    });
