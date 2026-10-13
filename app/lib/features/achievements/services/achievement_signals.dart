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
}
