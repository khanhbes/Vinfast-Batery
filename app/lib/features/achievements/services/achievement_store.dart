import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'achievement_engine.dart';

/// Everything the device remembers for one account.
class AchievementLedgerData {
  AchievementLedgerData({
    Map<String, LedgerSession>? sessions,
    Map<String, DateTime>? unlocked,
    Set<String>? events,
    this.lastSync,
    this.lastFullSync,
    this.remoteRestored = false,
  }) : sessions = sessions ?? {},
       unlocked = unlocked ?? {},
       events = events ?? {};

  final Map<String, LedgerSession> sessions;
  final Map<String, DateTime> unlocked;
  final Set<String> events;
  DateTime? lastSync;

  /// Last walk through the whole server history (prunes hidden/junk
  /// sessions and refreshes corrected energy, QA 129).
  DateTime? lastFullSync;
  bool remoteRestored;

  Map<String, Object?> toJson() => {
    'v': 1,
    'sessions': [for (final s in sessions.values) s.toJson()],
    'unlocked': {
      for (final e in unlocked.entries)
        e.key: e.value.toUtc().toIso8601String(),
    },
    'events': events.toList(),
    'lastSync': lastSync?.toUtc().toIso8601String(),
    'lastFullSync': lastFullSync?.toUtc().toIso8601String(),
    'remoteRestored': remoteRestored,
  };

  static AchievementLedgerData fromJson(Map<String, Object?> j) {
    final sessions = <String, LedgerSession>{};
    for (final raw in (j['sessions'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final s = LedgerSession.fromJson(Map<String, Object?>.from(raw));
      if (s != null) sessions[s.id] = s;
    }
    final unlocked = <String, DateTime>{};
    final rawUnlocked = j['unlocked'];
    if (rawUnlocked is Map) {
      for (final e in rawUnlocked.entries) {
        final at = DateTime.tryParse('${e.value}');
        if (at != null) unlocked['${e.key}'] = at;
      }
    }
    return AchievementLedgerData(
      sessions: sessions,
      unlocked: unlocked,
      events: {for (final e in (j['events'] as List? ?? const [])) '$e'},
      lastSync: DateTime.tryParse('${j['lastSync']}'),
      lastFullSync: DateTime.tryParse('${j['lastFullSync']}'),
      remoteRestored: j['remoteRestored'] == true,
    );
  }
}

/// Device ledger, scoped per account.
class AchievementLocalStore {
  const AchievementLocalStore();

  static String _key(String uid) => 'achievements.ledger.v1.$uid';

  Future<AchievementLedgerData> load(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(uid));
      if (raw == null) return AchievementLedgerData();
      return AchievementLedgerData.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on Object catch (e) {
      debugPrint('[Achievements] local load failed (${e.runtimeType})');
      return AchievementLedgerData();
    }
  }

  Future<void> save(String uid, AchievementLedgerData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(uid), jsonEncode(data.toJson()));
    } on Object catch (e) {
      debugPrint('[Achievements] local save failed (${e.runtimeType})');
    }
  }
}

/// Light cross-device backup: one summary document per account, read once
/// per install and written only when something new unlocks.
abstract class AchievementRemote {
  Future<Map<String, DateTime>> load(String uid);
  Future<void> save(
    String uid, {
    required Map<String, DateTime> unlocked,
    required int points,
    required String rank,
  });
}

class FirestoreAchievementRemote implements AchievementRemote {
  FirestoreAchievementRemote([FirebaseFirestore? db]) : _db = db;
  final FirebaseFirestore? _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      (_db ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection('achievements')
          .doc('summary');

  @override
  Future<Map<String, DateTime>> load(String uid) async {
    final snap = await _doc(uid).get().timeout(const Duration(seconds: 8));
    final raw = snap.data()?['unlocked'];
    final out = <String, DateTime>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is Timestamp) out['${e.key}'] = v.toDate();
      }
    }
    return out;
  }

  @override
  Future<void> save(
    String uid, {
    required Map<String, DateTime> unlocked,
    required int points,
    required String rank,
  }) => _doc(uid)
      .set({
        'schemaVersion': 1,
        'unlocked': {
          for (final e in unlocked.entries) e.key: Timestamp.fromDate(e.value),
        },
        'points': points,
        'rank': rank,
        'updatedAt': FieldValue.serverTimestamp(),
      })
      .timeout(const Duration(seconds: 8));
}
