import 'package:flutter/foundation.dart';

/// Fire-and-forget explore events from features without Riverpod access
/// (e.g. the BatteryBot tool gateway). Buffered until the achievements
/// controller drains them, so nothing is lost before it exists.
class AchievementSignals extends ChangeNotifier {
  AchievementSignals._();
  static final instance = AchievementSignals._();

  final _pending = <String>{};

  void emit(String event) {
    if (_pending.add(event)) notifyListeners();
  }

  /// Returns and clears the buffered events.
  Set<String> drain() {
    final out = {..._pending};
    _pending.clear();
    return out;
  }

  final _hidden = <String>{};

  /// The owner hid a session from History: it must leave the ledger too.
  void sessionHidden(String sessionId) {
    if (_hidden.add(sessionId)) notifyListeners();
  }

  Set<String> drainHidden() {
    final out = {..._hidden};
    _hidden.clear();
    return out;
  }
}
