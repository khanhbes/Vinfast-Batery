/// Charge-history quality rules (Task 126), twin of
/// web/shelly/history_quality.py; both are checked against
/// web/tests/fixtures/charge_history_quality_vectors.json.
///
/// A junk log delivered (almost) no energy and has no battery % the user
/// confirmed: relay tests without a load, double taps, commands cancelled
/// within seconds. It is hidden from history and statistics, never deleted.
abstract final class ChargeHistoryQuality {
  static const double junkMaxEnergyWh = 30;
  static const String shellySource = 'shelly_smart_charging';
  static const Set<String> _nonterminal = {
    'arming',
    'starting',
    'active',
    'stopping',
    'unknown',
  };

  static double? _number(Object? value) {
    if (value is num) return value.isFinite ? value.toDouble() : null;
    return double.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic> _session(Map<String, dynamic> log) {
    final raw = log['smartChargingSession'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static double? energyWh(Map<String, dynamic> log) {
    final session = _session(log);
    for (final value in [
      log['gridEnergyWh'],
      log['energyWh'],
      session['energy_used_wh'],
    ]) {
      final number = _number(value);
      if (number != null) return number < 0 ? 0 : number;
    }
    final kwh = _number(log['energyKwh']);
    return kwh == null ? null : (kwh < 0 ? 0 : kwh * 1000);
  }

  static double? confirmedEndSoc(Map<String, dynamic> log) {
    final session = _session(log);
    for (final value in [
      log['actualEndSoc'],
      log['confirmedEndSoc'],
      session['actual_end_soc'],
    ]) {
      final number = _number(value);
      if (number != null && number >= 0 && number <= 100) return number;
    }
    return null;
  }

  static String state(Map<String, dynamic> log) {
    final session = _session(log);
    return (log['sessionState'] ?? session['state'] ?? log['status'] ?? '')
        .toString();
  }

  static bool _set(Object? value) =>
      value != null && value != false && value.toString().isNotEmpty;

  /// User- or system-hidden, deleted or archived.
  static bool isHidden(Map<String, dynamic> log) =>
      log['isDeleted'] == true ||
      log['isArchived'] == true ||
      _set(log['archivedAt']) ||
      _set(log['hiddenByUserAt']) ||
      _set(log['hiddenAt']);

  /// `(kind, reason)`: kind is `standard`, `junk` or `active`.
  static (String, String) classify(Map<String, dynamic> log) {
    final source = log['source'];
    if (source != null && source != shellySource) return ('standard', 'manual');
    if (_nonterminal.contains(state(log))) return ('active', 'in_progress');
    if (confirmedEndSoc(log) != null) return ('standard', 'user_confirmed');
    final energy = energyWh(log);
    if (energy == null) return ('junk', 'no_energy_data');
    if (energy < junkMaxEnergyWh) return ('junk', 'below_min_energy');
    return ('standard', 'energy');
  }

  /// Shown in normal history: not hidden and not junk.
  static bool isVisible(Map<String, dynamic> log) =>
      !isHidden(log) && classify(log).$1 != 'junk';
}
