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

  /// Above this SOC the BMS balances cells and power tapers.
  static const double cvStartSoc = 85;
  static const double cvPowerFactor = 0.55;

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

  /// Time from [currentSoc] to [targetSoc]; null when it cannot be known
  /// (no capacity, nothing to charge or invalid input).
  static ChargeEstimate? estimate({
    required double currentSoc,
    required double targetSoc,
    required double capacityWh,
    required double powerW,
    required ChargePowerSource powerSource,
    DateTime? now,
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
    final effective = powerW * efficiency;
    final ccEnd = math.min(to, cvStartSoc);
    final ccWh = ccEnd > from ? capacityWh * (ccEnd - from) / 100 : 0.0;
    final cvFrom = math.max(from, cvStartSoc);
    final cvWh = to > cvFrom ? capacityWh * (to - cvFrom) / 100 : 0.0;
    final ccMinutes = ccWh / effective * 60;
    final cvMinutes = cvWh / (effective * cvPowerFactor) * 60;
    final minutes = (ccMinutes + cvMinutes).ceil().clamp(1, maxMinutes);
    return ChargeEstimate(
      minutes: minutes,
      requiredWh: ccWh + cvWh,
      powerW: powerW,
      powerSource: powerSource,
      finishAt: (now ?? DateTime.now()).add(Duration(minutes: minutes)),
      cvMinutes: cvMinutes.ceil(),
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
