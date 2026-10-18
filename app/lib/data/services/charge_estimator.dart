import 'dart:math' as math;

/// Where the charging power behind an estimate came from (Task 122).
enum ChargePowerSource {
  /// Median of the Shelly power measured during the running session.
  measuredLive,

  /// Median of the power measured in recent completed sessions.
  measuredHistory,

  /// The vehicle catalog's rated charger power.
  vehicleSpec,

  /// No data: the standard home charger power (clearly labelled).
  standard,
}

extension ChargePowerSourceLabel on ChargePowerSource {
  String get label => switch (this) {
    ChargePowerSource.measuredLive => 'công suất đang đo',
    ChargePowerSource.measuredHistory => 'công suất các lần sạc gần đây',
    ChargePowerSource.vehicleSpec => 'công suất sạc theo thông số xe',
    ChargePowerSource.standard => 'công suất sạc tiêu chuẩn',
  };
}

/// One physics estimate shared by the Charge tab, the active session card,
/// the charging pill and the Battery monitor, so the same question always
/// gets the same answer. Estimates are display-only, never relay authority.
class ChargeEstimate {
  const ChargeEstimate({
    required this.minutes,
    required this.requiredWh,
    required this.powerW,
    required this.powerSource,
    required this.finishAt,
    required this.cvMinutes,
  });

  final int minutes;
  final double requiredWh;
  final double powerW;
  final ChargePowerSource powerSource;
  final DateTime finishAt;

  /// Minutes spent above [ChargeEstimator.cvStartSoc] (slower top-up).
  final int cvMinutes;

  Duration get duration => Duration(minutes: minutes);
}

abstract final class ChargeEstimator {
  /// Wall-to-battery efficiency of the on-board charger.
  static const double efficiency = 0.9;

  /// Above this SOC the charger slows down (Task 126 defaults, the same as
  /// web/shelly/charge_model.py; the server learns per-vehicle values).
  static const double cvStartSoc = 95;
  static const double cvPowerFactor = 0.75;

  /// Typical VinFast scooter home charger, used only without any data.
  static const double standardPowerW = 400;

  /// A reading below this is idle/standby, not charging.
  static const double minChargingPowerW = 30;

  static const int maxMinutes = 600;

  /// Median of charging-level samples; null when there are too few.
  static double? medianChargingPower(
    Iterable<double> samples, {
    int minSamples = 3,
  }) {
    final values = [
      for (final w in samples)
        if (w.isFinite && w >= minChargingPowerW) w,
    ]..sort();
    if (values.length < minSamples) return null;
    final mid = values.length ~/ 2;
    return values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
  }

  /// Best available power, from measured to nominal.
  static ({double watts, ChargePowerSource source}) pickPower({
    Iterable<double> liveSamples = const [],
    Iterable<double> recentSessionPowers = const [],
    double? specMaxPowerW,
  }) {
    final live = medianChargingPower(liveSamples);
    if (live != null) {
      return (watts: live, source: ChargePowerSource.measuredLive);
    }
    final history = medianChargingPower(recentSessionPowers, minSamples: 1);
    if (history != null) {
      return (watts: history, source: ChargePowerSource.measuredHistory);
    }
    if (specMaxPowerW != null &&
        specMaxPowerW.isFinite &&
        specMaxPowerW >= minChargingPowerW) {
      return (watts: specMaxPowerW, source: ChargePowerSource.vehicleSpec);
    }
    return (watts: standardPowerW, source: ChargePowerSource.standard);
  }

  /// Seconds to deliver [from] -> [to] % at [powerW] wall power, with a
  /// slower tail above [taperStart] (Task 126). Twin of
  /// `charge_model.estimate` on the server; both are checked against
  /// web/tests/fixtures/charge_model_vectors.json.
  static int wallSeconds({
    required double whPerPct,
    required double powerW,
    required double from,
    required double to,
    double taperStart = cvStartSoc,
    double taperRatio = cvPowerFactor,
  }) {
    final start = from.clamp(0, 100).toDouble();
    final target = to.clamp(0, 100).toDouble();
    final taper = taperStart.clamp(0, 100).toDouble();
    final fast = math.max(0.0, math.min(target, taper) - start);
    final slow = math.max(0.0, target - math.max(start, taper));
    final ratio = taperRatio.clamp(0.2, 1.0).toDouble();
    final hours = fast * whPerPct / powerW + slow * whPerPct / (powerW * ratio);
    return math.max(0, (hours * 3600).round());
  }

  /// Battery % after [energyWh] at the wall, from the learned Wh per %.
  static double socAfter({
    required double whPerPct,
    required double startSoc,
    required double energyWh,
  }) {
    final start = startSoc.clamp(0, 100).toDouble();
    if (whPerPct <= 0) return start;
    return (start + math.max(0.0, energyWh) / whPerPct).clamp(start, 100.0);
  }

  /// Time from [currentSoc] to [targetSoc]; null when it cannot be known
  /// (no capacity, nothing to charge or invalid input).
  static ChargeEstimate? estimate({
    required double currentSoc,
    required double targetSoc,
    required double capacityWh,
    required double powerW,
    required ChargePowerSource powerSource,
    DateTime? now,

    /// Learned wall Wh per 1 % (server profile); overrides [capacityWh].
    double? whPerPercent,
  }) {
    if (!currentSoc.isFinite ||
        !targetSoc.isFinite ||
        !capacityWh.isFinite ||
        !powerW.isFinite ||
        capacityWh <= 0 ||
        powerW <= 0) {
      return null;
    }
    final from = currentSoc.clamp(0, 100).toDouble();
    final to = targetSoc.clamp(0, 100).toDouble();
    if (to <= from) return null;
    final whPerPct = whPerPercent ?? capacityWh / 100 / efficiency;
    final seconds = wallSeconds(
      whPerPct: whPerPct,
      powerW: powerW,
      from: from,
      to: to,
    );
    final cvSeconds = wallSeconds(
      whPerPct: whPerPct,
      powerW: powerW,
      from: math.max(from, cvStartSoc),
      to: to,
    );
    final minutes = (seconds / 60).ceil().clamp(1, maxMinutes);
    return ChargeEstimate(
      minutes: minutes,
      requiredWh: whPerPct * (to - from) * efficiency,
      powerW: powerW,
      powerSource: powerSource,
      finishAt: (now ?? DateTime.now()).add(Duration(minutes: minutes)),
      cvMinutes: (cvSeconds / 60).ceil(),
    );
  }
}

/// "1 giờ 10 phút", "45 phút", "2 giờ" — one wording for every surface.
String formatChargeDuration(Duration duration) {
  final totalMinutes = (duration.inSeconds / 60).ceil();
  if (totalMinutes <= 0) return '0 phút';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes phút';
  if (minutes == 0) return '$hours giờ';
  return '$hours giờ $minutes phút';
}

/// Compact "1g10" for tight spots (dial centre, pill).
String formatChargeDurationShort(Duration duration) {
  final totalMinutes = (duration.inSeconds / 60).ceil();
  if (totalMinutes <= 0) return '0p';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}p';
  return '${hours}g${minutes.toString().padLeft(2, '0')}';
}

/// 24 h wall clock, "07:05".
String formatClock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
