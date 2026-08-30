import 'package:shared_preferences/shared_preferences.dart';

import 'server_smart_charger_service.dart';

class ChargingTrainingSyncService {
  ChargingTrainingSyncService({ServerSmartChargerService? server})
    : _server = server;

  static const _queueKey = 'smart_charge.training_queue.v3';
  ServerSmartChargerService? _server;

  ServerSmartChargerService get _client =>
      _server ??= ServerSmartChargerService();

  Future<void> enqueue(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = {...?prefs.getStringList(_queueKey), sessionId}.toList();
    await prefs.setStringList(_queueKey, pending);
  }

  Future<int> flush() async {
    final prefs = await SharedPreferences.getInstance();
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
}
