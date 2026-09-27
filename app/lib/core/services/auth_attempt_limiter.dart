import 'package:shared_preferences/shared_preferences.dart';

/// Device-local friction for repeated failed sign-in submissions. Firebase
/// remains the authority for account-wide abuse protection.
class AuthAttemptLimiter {
  AuthAttemptLimiter({SharedPreferences? preferences})
    : _preferences = preferences;

  static const _failuresKey = 'auth.failed_attempts_ms';
  static const _cooldownKey = 'auth.cooldown_until_ms';
  static const _window = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 60);
  static const _threshold = 5;

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<Duration> remaining() async {
    final prefs = await _prefs;
    final until = prefs.getInt(_cooldownKey);
    if (until == null) return Duration.zero;
    final remaining = DateTime.fromMillisecondsSinceEpoch(
      until,
    ).difference(DateTime.now());
    if (remaining <= Duration.zero) {
      await prefs.remove(_cooldownKey);
      return Duration.zero;
    }
    return remaining;
  }

  Future<Duration> recordInvalidCredential() async {
    final prefs = await _prefs;
    final now = DateTime.now();
    final floor = now.subtract(_window).millisecondsSinceEpoch;
    final failures =
        (prefs.getStringList(_failuresKey) ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>()
            .where((stamp) => stamp >= floor)
            .toList()
          ..add(now.millisecondsSinceEpoch);
    await prefs.setStringList(
      _failuresKey,
      failures.map((stamp) => stamp.toString()).toList(),
    );
    if (failures.length >= _threshold) {
      final until = now.add(_cooldown);
      await prefs.setInt(_cooldownKey, until.millisecondsSinceEpoch);
      return until.difference(now);
    }
    return Duration.zero;
  }

  Future<void> applyCooldown(Duration duration) async {
    final prefs = await _prefs;
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    final previous = prefs.getInt(_cooldownKey) ?? 0;
    await prefs.setInt(_cooldownKey, previous > until ? previous : until);
  }

  Future<void> reset() async {
    final prefs = await _prefs;
    await prefs.remove(_failuresKey);
    await prefs.remove(_cooldownKey);
  }
}
