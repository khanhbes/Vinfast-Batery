import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/pinova_api.dart';
import 'tip.dart';

/// QA 163: the "Mẹo nhỏ" list and what this phone remembers about it (seen,
/// saved, the daily tip switch). The bundled asset answers at once and
/// offline; `/api/tips` replaces it when the server has a newer list (admin
/// edits). Seen and saved stay on the phone: per-viewer conveniences.
class TipLibrary extends ChangeNotifier {
  TipLibrary({
    Future<String> Function()? asset,
    Future<Map<String, dynamic>> Function()? remote,
  }) : _asset = asset ?? (() => rootBundle.loadString(assetPath)),
       _remote = remote ?? (() => PinovaApi().get('/api/tips'));

  static TipLibrary instance = TipLibrary();

  static const assetPath = 'assets/tips/tips_vi.json';
  static const _seenKey = 'tips.seen.v1';
  static const _savedKey = 'tips.saved.v1';
  static const _lastDayKey = 'tips.daily.lastDay.v1';
  static const _dailyKey = 'tips.daily.enabled.v1';
  static const _morningKey = 'assistant.morning.enabled.v1';

  final Future<String> Function() _asset;
  final Future<Map<String, dynamic>> Function() _remote;

  List<Tip> _tips = const [];
  final Set<String> _seen = {};
  final Set<String> _saved = {};
  String? _lastDay;
  bool _daily = true;
  bool _morning = true;
  bool _loaded = false;
  Future<void>? _loading;

  List<Tip> get tips => _tips;
  bool get loaded => _loaded;
  Set<String> get seen => Set.unmodifiable(_seen);
  Set<String> get saved => Set.unmodifiable(_saved);

  /// "Mẹo mỗi ngày" in Pinova Bot's settings.
  bool get dailyEnabled => _daily;

  /// "Chào buổi sáng" in Pinova Bot's settings.
  bool get morningEnabled => _morning;

  /// Loads once (asset, then prefs, then the server's list in the back).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _tips = _parse(jsonDecode(await _asset()));
    } on Object {
      _tips = const [];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _seen.addAll(prefs.getStringList(_seenKey) ?? const []);
      _saved.addAll(prefs.getStringList(_savedKey) ?? const []);
      _lastDay = prefs.getString(_lastDayKey);
      _daily = prefs.getBool(_dailyKey) ?? true;
      _morning = prefs.getBool(_morningKey) ?? true;
    } on Object {
      // No storage: the defaults, nothing remembered.
    }
    _loaded = true;
    notifyListeners();
    unawaited(refresh());
  }

  /// The server's list (admin edits); kept as is when it cannot be read.
  Future<void> refresh() async {
    try {
      final remote = _parse(await _remote());
      if (remote.isNotEmpty) {
        _tips = remote;
        notifyListeners();
      }
    } on Object {
      // Offline or an older server: the bundled list stays.
    }
  }

  static List<Tip> _parse(Object? data) {
    final list = data is Map ? data['tips'] : null;
    return [for (final raw in (list as List? ?? const [])) ?Tip.fromMap(raw)];
  }

  Tip? byId(String id) => _tips.where((t) => t.id == id).firstOrNull;

  Future<void> markSeen(String id) async {
    if (!_seen.add(id)) return;
    notifyListeners();
    await _write((p) => p.setStringList(_seenKey, _seen.toList()));
  }

  Future<void> toggleSaved(String id) async {
    _saved.contains(id) ? _saved.remove(id) : _saved.add(id);
    notifyListeners();
    await _write((p) => p.setStringList(_savedKey, _saved.toList()));
  }

  Future<void> setDailyEnabled(bool on) async {
    _daily = on;
    notifyListeners();
    await _write((p) => p.setBool(_dailyKey, on));
  }

  Future<void> setMorningEnabled(bool on) async {
    _morning = on;
    notifyListeners();
    await _write((p) => p.setBool(_morningKey, on));
  }

  static String dayKey(DateTime now) => '${now.year}-${now.month}-${now.day}';

  /// The daily tip was already told today.
  bool toldToday(DateTime now) => _lastDay == dayKey(now);

  Future<void> markTold(DateTime now) async {
    _lastDay = dayKey(now);
    await _write((p) => p.setString(_lastDayKey, _lastDay!));
  }

  Future<void> _write(Future<bool> Function(SharedPreferences) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } on Object {
      // Remembered for this run only.
    }
  }
}
