import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_smart_charger_service.dart';

class ChargingTrainingSyncService {
  ChargingTrainingSyncService({ServerSmartChargerService? server})
    : _server = server;

  static const _queueKey = 'smart_charge.training_queue.v3';
  static const _actualSocQueueKey = 'smart_charge.actual_soc_queue.v1';
  ServerSmartChargerService? _server;

  ServerSmartChargerService get _client =>
      _server ??= ServerSmartChargerService();

  Future<void> enqueue(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = {...?prefs.getStringList(_queueKey), sessionId}.toList();
    await prefs.setStringList(_queueKey, pending);
  }

  /// Direct mode writes its local history first. This separate durable queue
  /// retries the canonical server-side confirmation after an offline period.
  Future<void> enqueueActualSoc(String sessionId, double soc) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = _actualSocQueue(prefs.getString(_actualSocQueueKey));
    pending[sessionId] = soc;
    await prefs.setString(_actualSocQueueKey, jsonEncode(pending));
  }

  Future<int> flush() async {
    final prefs = await SharedPreferences.getInstance();
    await _flushActualSoc(prefs);
    final pending = [...?prefs.getStringList(_queueKey)];
    if (pending.isEmpty) return 0;
    final remaining = <String>[];
    var synced = 0;
    for (final sessionId in pending) {
      try {
        await _client.ingestPersonalTraining(sessionId);
        synced++;
      } catch (_) {
        remaining.add(sessionId);
      }
    }
    await prefs.setStringList(_queueKey, remaining);
    return synced;
  }

  Future<void> _flushActualSoc(SharedPreferences prefs) async {
    final pending = _actualSocQueue(prefs.getString(_actualSocQueueKey));
    if (pending.isEmpty) return;
    final remaining = <String, double>{};
    for (final entry in pending.entries) {
      try {
        await _client.confirmActualSoc(entry.key, entry.value);
      } catch (_) {
        remaining[entry.key] = entry.value;
      }
    }
    if (remaining.isEmpty) {
      await prefs.remove(_actualSocQueueKey);
    } else {
      await prefs.setString(_actualSocQueueKey, jsonEncode(remaining));
    }
  }

  Map<String, double> _actualSocQueue(String? raw) {
    if (raw == null || raw.isEmpty) return <String, double>{};
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return decoded.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    } on Object {
      return <String, double>{};
    }
  }
}
