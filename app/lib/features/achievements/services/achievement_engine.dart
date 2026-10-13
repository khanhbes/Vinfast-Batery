import '../../../data/models/smart_charging_session.dart';
import '../models/achievement.dart';

/// Compact, privacy-light copy of a finished session kept in the local
/// ledger (no device ids, no telemetry).
class LedgerSession {
  const LedgerSession({
    required this.id,
    required this.state,
    required this.ai,
    required this.startSoc,
    required this.targetSoc,
    required this.energyWh,
    required this.startedAt,
    this.stoppedAt,
  });

  final String id;
  final String state;
  final bool ai;
  final double startSoc;
  final double targetSoc;
  final double energyWh;
  final DateTime startedAt;
  final DateTime? stoppedAt;

  static LedgerSession? fromSession(SmartChargingSession s) {
    if (!s.state.isTerminal) return null;
    final energy = s.energyUsedWh > 0
        ? s.energyUsedWh
        : (s.estimatedStoredEnergyWh ?? 0.0);
    return LedgerSession(
      id: s.sessionId,
      state: s.state.wireValue,
      ai: s.strategy != ChargingStrategy.manualTimed,
      startSoc: s.startSoc,
      targetSoc: s.targetSoc,
      energyWh: energy,
      startedAt: s.startedAt ?? s.createdAt,
      // Only a real stop time: updatedAt can move days later (e.g. when the
      // end level is confirmed) and would fake very long sessions.
      stoppedAt: s.stoppedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    's': state,
    'ai': ai,
    'a': startSoc,
    't': targetSoc,
    'e': energyWh,
    'b': startedAt.toUtc().toIso8601String(),
    'x': stoppedAt?.toUtc().toIso8601String(),
  };

  static LedgerSession? fromJson(Map<String, Object?> j) {
    final started = DateTime.tryParse('${j['b']}');
    if (j['id'] is! String || started == null) return null;
    return LedgerSession(
      id: j['id']! as String,
      state: '${j['s']}',
      ai: j['ai'] == true,
      startSoc: (j['a'] as num?)?.toDouble() ?? 0,
      targetSoc: (j['t'] as num?)?.toDouble() ?? 0,
      energyWh: (j['e'] as num?)?.toDouble() ?? 0,
      startedAt: started,
      stoppedAt: j['x'] == null ? null : DateTime.tryParse('${j['x']}'),
    );
  }

  /// Real charging time, or null when unknown or implausible (> 12 h).
  Duration? get duration {
    final stop = stoppedAt;
    if (stop == null || stop.isBefore(startedAt)) return null;
    final d = stop.difference(startedAt);
    return d > const Duration(hours: 12) ? null : d;
  }

  /// A session counts once it really delivered energy (anti-gaming: a
  /// quick ON/OFF or a no-load test is not a charge).
  bool get valid => energyWh >= 20;
}

/// Everything the catalog can measure.
class AchievementStats {
  const AchievementStats({
    this.kwh = 0,
    this.sessions = 0,
    this.aiSessions = 0,
    this.timedSessions = 0,
    this.care80 = 0,
    this.goldenStart = 0,
    this.balanceMonths = 0,
    this.offPeak = 0,
    this.morning = 0,
    this.weekend = 0,
    this.weekStreak = 0,
    this.currentWeekStreak = 0,
    this.activeMonths = 0,
    this.dayStreak = 0,
    this.number88 = 0,
    this.nightOwl = 0,
    this.lightning = 0,
    this.patience = 0,
    this.newYear = 0,
    this.earthDay = 0,
    this.events = const {},
  });

  final double kwh;
  final int sessions;
  final int aiSessions;
  final int timedSessions;
  final int care80;
  final int goldenStart;
  final int balanceMonths;
  final int offPeak;
  final int morning;
  final int weekend;
  final int weekStreak;
  final int currentWeekStreak;
  final int activeMonths;
  final int dayStreak;
  final int number88;
  final int nightOwl;
  final int lightning;
  final int patience;
  final int newYear;
  final int earthDay;
  final Set<String> events;

  /// ~0.4 kg CO₂ avoided per kWh versus a petrol scooter.
  double get co2Kg => kwh * 0.4;

  /// ~35 km per kWh for VinFast electric scooters.
  double get km => kwh * 35;

  double value(AchievementDef def) => switch (def.metric) {
    AchievementMetric.kwh => kwh,
    AchievementMetric.sessions => sessions.toDouble(),
    AchievementMetric.aiSessions => aiSessions.toDouble(),
    AchievementMetric.timedSessions => timedSessions.toDouble(),
    AchievementMetric.care80 => care80.toDouble(),
    AchievementMetric.goldenStart => goldenStart.toDouble(),
    AchievementMetric.balanceMonths => balanceMonths.toDouble(),
    AchievementMetric.offPeak => offPeak.toDouble(),
    AchievementMetric.morning => morning.toDouble(),
    AchievementMetric.weekend => weekend.toDouble(),
    AchievementMetric.weekStreak => weekStreak.toDouble(),
    AchievementMetric.activeMonths => activeMonths.toDouble(),
    AchievementMetric.dayStreak => dayStreak.toDouble(),
    AchievementMetric.co2Kg => co2Kg,
    AchievementMetric.km => km,
    AchievementMetric.number88 => number88.toDouble(),
    AchievementMetric.nightOwl => nightOwl.toDouble(),
    AchievementMetric.lightning => lightning.toDouble(),
    AchievementMetric.patience => patience.toDouble(),
    AchievementMetric.newYear => newYear.toDouble(),
    AchievementMetric.earthDay => earthDay.toDouble(),
    AchievementMetric.event => events.contains(def.event) ? 1 : 0,
  };

  /// 0..1 progress towards [def].
  double progress(AchievementDef def) =>
      (value(def) / def.target).clamp(0.0, 1.0);

  static AchievementStats compute(
    Iterable<LedgerSession> ledger, {
    Set<String> events = const {},
    DateTime? now,
  }) {
    var kwh = 0.0;
    var sessions = 0,
        ai = 0,
        timed = 0,
        care = 0,
        golden = 0,
        offPeak = 0,
        morning = 0,
        weekend = 0,
        n88 = 0,
        night = 0,
        lightning = 0,
        patience = 0,
        newYear = 0,
        earth = 0;
    final balance = <int>{};
    final months = <int>{};
    final weeks = <int>{};
    final days = <int>{};

    for (final s in ledger) {
      kwh += s.energyWh / 1000;
      if (!s.valid) continue;
      final at = s.startedAt.toLocal();
      sessions++;
      if (s.ai) {
        ai++;
        if (s.targetSoc <= 80) care++;
        if (s.targetSoc >= 100) balance.add(at.year * 12 + at.month);
      } else {
        timed++;
      }
      if (s.startSoc >= 20 && s.startSoc <= 40) golden++;
      if (at.hour >= 22 || at.hour < 4) offPeak++;
      if (at.hour < 3) night++;
      if (at.hour >= 5 && at.hour < 8) morning++;
      if (at.weekday >= DateTime.saturday) weekend++;
      if (s.ai && s.targetSoc.round() == 88) n88++;
      final minutes = s.duration?.inMinutes;
      if (minutes != null) {
        if (s.state == 'completed' && minutes > 0 && minutes < 20) {
          lightning++;
        }
        if (minutes >= 300) patience++;
      }
      if (at.month == 1 && at.day == 1) newYear++;
      if (at.month == 4 && at.day == 22) earth++;
      months.add(at.year * 12 + at.month);
      weeks.add(_weekIndex(at));
      days.add(_dayIndex(at));
    }

    final today = (now ?? DateTime.now()).toLocal();
    return AchievementStats(
      kwh: kwh,
      sessions: sessions,
      aiSessions: ai,
      timedSessions: timed,
      care80: care,
      goldenStart: golden,
      balanceMonths: balance.length,
      offPeak: offPeak,
      morning: morning,
      weekend: weekend,
      weekStreak: _longestRun(weeks),
      currentWeekStreak: _runEndingAt(weeks, _weekIndex(today)),
      activeMonths: months.length,
      dayStreak: _longestRun(days),
      number88: n88,
      nightOwl: night,
      lightning: lightning,
      patience: patience,
      newYear: newYear,
      earthDay: earth,
      events: events,
    );
  }

  static int _dayIndex(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Monday-based week number since the epoch.
  static int _weekIndex(DateTime d) => (_dayIndex(d) + 3) ~/ 7;

  static int _longestRun(Set<int> keys) {
    var best = 0;
    for (final k in keys) {
      if (keys.contains(k - 1)) continue;
      var run = 1;
      while (keys.contains(k + run)) {
        run++;
      }
      if (run > best) best = run;
    }
    return best;
  }

  /// Current streak: counts back from this week (or last week, so the
  /// streak survives until the week is over).
  static int _runEndingAt(Set<int> keys, int current) {
    var k = keys.contains(current) ? current : current - 1;
    var run = 0;
    while (keys.contains(k)) {
      run++;
      k--;
    }
    return run;
  }
}

/// Progress of one achievement for display.
class AchievementProgress {
  const AchievementProgress({
    required this.def,
    required this.value,
    required this.unlockedAt,
  });

  final AchievementDef def;
  final double value;
  final DateTime? unlockedAt;

  bool get unlocked => unlockedAt != null;
  double get fraction => unlocked ? 1 : (value / def.target).clamp(0.0, 1.0);

  /// "12/25 phiên" style label.
  String get label {
    if (def.metric == AchievementMetric.event || def.target == 1) {
      return unlocked ? 'Đã mở khóa' : 'Chưa mở khóa';
    }
    String fmt(double v) => v >= 100 || v == v.roundToDouble()
        ? v.round().toString()
        : v.toStringAsFixed(1);
    final shown = value.clamp(0, def.target).toDouble();
    return '${fmt(shown)}/${fmt(def.target)}${def.unit.isEmpty ? '' : ' ${def.unit}'}';
  }
}

/// Unlocks every achievement whose condition is met and that is not yet in
/// [unlocked]; returns the newly unlocked ids (catalog order).
List<String> evaluateUnlocks(
  AchievementStats stats,
  Map<String, DateTime> unlocked,
) => [
  for (final def in achievementCatalog)
    if (!unlocked.containsKey(def.id) && stats.value(def) >= def.target) def.id,
];

int pointsFor(Iterable<String> unlockedIds) {
  final ids = unlockedIds.toSet();
  return achievementCatalog
      .where((d) => ids.contains(d.id))
      .fold(0, (sum, d) => sum + d.points);
}
