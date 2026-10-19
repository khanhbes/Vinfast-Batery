import 'dart:math' as math;

import '../models/smart_charging_session.dart';

/// Trip battery-use model (Tasks 126-127), twin of
/// web/assistant/trip_model.py; both are checked against
/// web/tests/fixtures/trip_model_vectors.json.
///
/// %/km = ref × (1 + speed·(v−20) + speed2·(v−20)² + load·(kg−65)/10 + rain),
/// fitted on the owner's own 77 rides (444 km, 04/2026). `ref` comes from the
/// trained trip model, km/% learned from ODO readings, or the catalog.
/// Always an estimate with a range.
abstract final class TripEnergyModel {
  /// The BMS cuts power before 0 % (same as range_estimator.dart).
  static const double reservePct = 5;

  /// Arriving with at least this much in the worst case is "comfortable".
  static const double comfortPct = 20;
  static const double priorSpeed = 0.01221;
  static const double priorSpeed2 = 0.001614;
  static const double priorLoadPer10Kg = 0.03077;
  static const double priorRain = 0.05741;
  static const double refToMean = 0.882;
  static const double refSpeedKmh = 20;
  static const double riderKg = 65;
  static const double secondRiderKg = 62;
  static const double maxCargoKg = 60;
  static const Map<TripSpeed, double> speedPresetsKmh = {
    TripSpeed.slow: 15,
    TripSpeed.normal: 21,
    TripSpeed.fast: 28,
  };
  static const double minSpeedKmh = 8;
  static const double maxSpeedKmh = 34;
  static const double routerToScooter = 0.75;
  static const Map<TripWeather, double> weatherExtra = {
    TripWeather.dry: 1.0,
    TripWeather.rain: 1.0,
    TripWeather.hot: 1.0,
    TripWeather.cold: 1.10,
  };
  static const double hillyFactor = 1.12;
  static const double modelSpread = 0.18;
  static const double odoSpread = 0.18;
  static const double catalogSpread = 0.25;
  static const int minPairs = 2;

  /// Expected ride average speed including stops (km/h).
  static double averageSpeed(
    TripConditions conditions,
    double distanceKm,
    double? durationMin,
  ) {
    final preset = speedPresetsKmh[conditions.speed];
    if (preset != null) return preset;
    if (durationMin == null || durationMin <= 0 || distanceKm <= 0) {
      return speedPresetsKmh[TripSpeed.normal]!;
    }
    // Router durations are for cars; the owner's real scooter averages are
    // about three quarters of that in town.
    final value = distanceKm / (durationMin / 60) * routerToScooter;
    return value.clamp(minSpeedKmh, maxSpeedKmh).toDouble();
  }

  static double payloadKg(TripConditions conditions) =>
      riderKg +
      (conditions.riders >= 2 ? secondRiderKg : 0) +
      conditions.cargoKg.clamp(0, maxCargoKg);

  static double shape(
    TripModelParams params, {
    required double speedKmh,
    required double loadKg,
    required bool rain,
  }) {
    final v = speedKmh.clamp(minSpeedKmh, maxSpeedKmh) - refSpeedKmh;
    final load = (loadKg.clamp(40, 250) - riderKg) / 10;
    var value =
        1 +
        params.speed * v +
        params.speed2 * v * v +
        params.loadPer10Kg * load;
    if (rain) value += params.rain;
    return value.clamp(0.6, 2.0).toDouble();
  }

  static double conditionFactor(
    TripConditions conditions, [
    double distanceKm = 0,
    double? durationMin,
    TripModelParams? params,
  ]) {
    final model = params ?? const TripModelParams(refPctPerKm: 1);
    var factor = shape(
      model,
      speedKmh: averageSpeed(conditions, distanceKm, durationMin),
      loadKg: payloadKg(conditions),
      rain: conditions.weather == TripWeather.rain,
    );
    factor *= weatherExtra[conditions.weather]!;
    if (conditions.hilly) factor *= hillyFactor;
    return factor;
  }

  static double? catalogKmPerPct(double? efficiency, double? sohPct) {
    if (efficiency == null || !efficiency.isFinite || efficiency <= 0) {
      return null;
    }
    final soh = sohPct != null && sohPct > 0 && sohPct <= 100 ? sohPct : 100;
    return efficiency * soh / 100;
  }

  /// Median km per 1 % between consecutive confirmed charges: between
  /// charge N and N+1 the scooter rode odo[N+1] − odo[N] km and used
  /// actualEnd[N] − start[N+1] %.
  static ({double? kmPerPct, int pairs}) learnKmPerPct(
    List<TripChargeReading> readings, {
    double? catalog,
  }) {
    final rows = [...readings]..sort((a, b) => a.endedAt.compareTo(b.endedAt));
    final values = <double>[];
    for (var i = 0; i + 1 < rows.length; i++) {
      final before = rows[i];
      final after = rows[i + 1];
      final km = after.odoKm - before.odoKm;
      final used = before.actualEndSoc - after.startSoc;
      if (km <= 0 || used < 5) continue;
      final value = km / used;
      if (catalog != null && (value < catalog * 0.4 || value > catalog * 2.5)) {
        continue;
      }
      values.add(value);
    }
    if (values.length < minPairs) return (kmPerPct: null, pairs: values.length);
    values.sort();
    final mid = values.length ~/ 2;
    final median = values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
    return (kmPerPct: median, pairs: values.length);
  }

  /// Prior shape on a mixed-riding km/% (catalog or ODO-learned).
  static TripModelParams paramsFromKmPerPct(
    double kmPerPct,
    TripKmSource source,
  ) => TripModelParams(
    refPctPerKm: refToMean / kmPerPct,
    source: source == TripKmSource.model ? TripKmSource.personal : source,
    spread: source == TripKmSource.catalog ? catalogSpread : odoSpread,
  );

  static TripPlan plan({
    required double distanceKm,
    required double currentSoc,
    double? kmPerPct,
    TripKmSource source = TripKmSource.catalog,
    TripModelParams? model,
    TripConditions conditions = const TripConditions(),
    double? durationMin,
    List<double> alternativeKm = const [],
  }) {
    final params =
        model ??
        (kmPerPct != null && kmPerPct > 0
            ? paramsFromKmPerPct(kmPerPct, source)
            : throw ArgumentError('kmPerPct or model required'));
    final distance = math.max(0.0, distanceKm);
    final legs = conditions.roundTrip ? 2 : 1;
    final factor = conditionFactor(conditions, distance, durationMin, params);
    double useFor(TripConditions cond) =>
        distance *
        legs *
        params.refPctPerKm *
        conditionFactor(cond, distance, durationMin, params);
    final use = distance * legs * params.refPctPerKm * factor;
    final low = use * (1 - params.spread);
    final high = use * (1 + params.spread);
    final soc = currentSoc.clamp(0, 100).toDouble();
    final arrival = soc - use;
    final arrivalLow = soc - high;
    final verdict = arrivalLow >= comfortPct
        ? TripVerdict.comfortable
        : arrivalLow >= reservePct
        ? TripVerdict.tight
        : TripVerdict.insufficient;
    final needed = high + comfortPct;
    final suggestions = <TripSuggestion>[];
    if (verdict != TripVerdict.comfortable) {
      if (needed <= 100) {
        if (needed > soc) {
          suggestions.add(
            TripSuggestion.chargeFirst(
              math.min(100, (needed / 5).ceil() * 5).toDouble(),
            ),
          );
        }
      } else {
        final stops =
            ((high - (100 - comfortPct)) / (100 - comfortPct - reservePct))
                .ceil();
        suggestions.add(TripSuggestion.chargeOnTheWay(math.max(1, stops)));
      }
      if (conditions.roundTrip && soc - high / 2 >= reservePct) {
        suggestions.add(const TripSuggestion.chargeAtDestination());
      }
      // The owner's rides cost least around 15-20 km/h average.
      final speed = averageSpeed(conditions, distance, durationMin);
      if (speed > speedPresetsKmh[TripSpeed.normal]! + 0.5) {
        final saved =
            use - useFor(conditions.copyWith(speed: TripSpeed.normal));
        if (saved >= 1) suggestions.add(TripSuggestion.rideEco(_round1(saved)));
      }
    }
    if (alternativeKm.isNotEmpty) {
      final shortest = alternativeKm.reduce(math.min);
      if (shortest < distance - 0.5) {
        final saved =
            (distance - shortest) * legs * params.refPctPerKm * factor;
        suggestions.add(
          TripSuggestion.shorterRoute(_round1(shortest), _round1(saved)),
        );
      }
    }
    return TripPlan(
      distanceKm: distance,
      usePct: use,
      useLowPct: low,
      useHighPct: high,
      arrivalSoc: arrival,
      arrivalLowSoc: arrivalLow,
      verdict: verdict,
      kmPerPct: params.kmPerPct,
      source: params.source,
      factor: factor,
      startNeededSoc: math.min(100, needed),
      avgSpeedKmh: averageSpeed(conditions, distance, durationMin),
      payloadKg: payloadKg(conditions),
      modelSamples: params.samples,
      suggestions: suggestions,
    );
  }

  static double _round1(double value) => (value * 10).roundToDouble() / 10;
}

/// Reference %/km (20 km/h incl. stops, solo, dry) plus relative shape
/// coefficients. A trained model comes from the server (Task 127).
class TripModelParams {
  const TripModelParams({
    required this.refPctPerKm,
    this.speed = TripEnergyModel.priorSpeed,
    this.speed2 = TripEnergyModel.priorSpeed2,
    this.loadPer10Kg = TripEnergyModel.priorLoadPer10Kg,
    this.rain = TripEnergyModel.priorRain,
    this.source = TripKmSource.catalog,
    this.samples = 0,
    this.spread = TripEnergyModel.catalogSpread,
    this.mae,
  });

  final double refPctPerKm;
  final double speed;
  final double speed2;
  final double loadPer10Kg;
  final double rain;
  final TripKmSource source;
  final int samples;
  final double spread;
  final double? mae;

  /// Mixed-riding km per 1 % (what the catalog and ODO measure).
  double get kmPerPct => TripEnergyModel.refToMean / refPctPerKm;

  static TripModelParams? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double? number(Object? value) {
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      return parsed != null && parsed.isFinite ? parsed : null;
    }

    final ref = number(raw['refPctPerKm']);
    if (ref == null || ref < 0.05 || ref > 5) return null;
    return TripModelParams(
      refPctPerKm: ref,
      speed: number(raw['speed']) ?? TripEnergyModel.priorSpeed,
      speed2: number(raw['speed2']) ?? TripEnergyModel.priorSpeed2,
      loadPer10Kg:
          number(raw['loadPer10Kg']) ?? TripEnergyModel.priorLoadPer10Kg,
      rain: number(raw['rain']) ?? TripEnergyModel.priorRain,
      source: TripKmSource.model,
      samples: number(raw['samples'])?.toInt() ?? 0,
      spread: (number(raw['spread']) ?? TripEnergyModel.modelSpread)
          .clamp(0.08, 0.30)
          .toDouble(),
      mae: number(raw['mae']),
    );
  }
}

/// The odometer and battery the owner typed after one charge.
class TripChargeReading {
  const TripChargeReading({
    required this.endedAt,
    required this.startSoc,
    required this.actualEndSoc,
    required this.odoKm,
  });

  final DateTime endedAt;
  final double startSoc;
  final double actualEndSoc;
  final double odoKm;

  static List<TripChargeReading> fromSessions(
    Iterable<SmartChargingSession> sessions,
  ) => [
    for (final s in sessions)
      if (s.state.isTerminal && s.actualEndSoc != null && s.endOdoKm != null)
        TripChargeReading(
          endedAt: s.stoppedAt ?? s.updatedAt,
          startSoc: s.startSoc,
          actualEndSoc: s.actualEndSoc!,
          odoKm: s.endOdoKm!,
        ),
  ];
}

enum TripSpeed { slow, normal, fast, auto }

enum TripWeather { dry, rain, hot, cold }

/// model = trained on the owner's rides; personal = km/% from ODO readings.
enum TripKmSource {
  model('model'),
  personal('odo'),
  catalog('catalog');

  const TripKmSource(this.wire);
  final String wire;
}

enum TripVerdict { comfortable, tight, insufficient }

class TripConditions {
  const TripConditions({
    this.speed = TripSpeed.normal,
    this.riders = 1,
    this.cargoKg = 0,
    this.weather = TripWeather.dry,
    this.hilly = false,
    this.roundTrip = false,
  });

  final TripSpeed speed;
  final int riders;
  final double cargoKg;
  final TripWeather weather;
  final bool hilly;
  final bool roundTrip;

  TripConditions copyWith({
    TripSpeed? speed,
    int? riders,
    double? cargoKg,
    TripWeather? weather,
    bool? hilly,
    bool? roundTrip,
  }) => TripConditions(
    speed: speed ?? this.speed,
    riders: riders ?? this.riders,
    cargoKg: cargoKg ?? this.cargoKg,
    weather: weather ?? this.weather,
    hilly: hilly ?? this.hilly,
    roundTrip: roundTrip ?? this.roundTrip,
  );
}

enum TripSuggestionKind {
  chargeFirst,
  chargeOnTheWay,
  chargeAtDestination,
  rideEco,
  shorterRoute,
}

class TripSuggestion {
  const TripSuggestion._(
    this.kind, {
    this.targetSoc,
    this.stops,
    this.savedPct,
    this.distanceKm,
  });
  const TripSuggestion.chargeFirst(double target)
    : this._(TripSuggestionKind.chargeFirst, targetSoc: target);
  const TripSuggestion.chargeOnTheWay(int stops)
    : this._(TripSuggestionKind.chargeOnTheWay, stops: stops);
  const TripSuggestion.chargeAtDestination()
    : this._(TripSuggestionKind.chargeAtDestination);
  const TripSuggestion.rideEco(double saved)
    : this._(TripSuggestionKind.rideEco, savedPct: saved);
  const TripSuggestion.shorterRoute(double km, double saved)
    : this._(TripSuggestionKind.shorterRoute, distanceKm: km, savedPct: saved);

  final TripSuggestionKind kind;
  final double? targetSoc;
  final int? stops;
  final double? savedPct;
  final double? distanceKm;

  String get wire => switch (kind) {
    TripSuggestionKind.chargeFirst => 'charge_first',
    TripSuggestionKind.chargeOnTheWay => 'charge_on_the_way',
    TripSuggestionKind.chargeAtDestination => 'charge_at_destination',
    TripSuggestionKind.rideEco => 'ride_eco',
    TripSuggestionKind.shorterRoute => 'shorter_route',
  };
}

class TripPlan {
  const TripPlan({
    required this.distanceKm,
    required this.usePct,
    required this.useLowPct,
    required this.useHighPct,
    required this.arrivalSoc,
    required this.arrivalLowSoc,
    required this.verdict,
    required this.kmPerPct,
    required this.source,
    required this.factor,
    required this.startNeededSoc,
    required this.suggestions,
    this.avgSpeedKmh = 21,
    this.payloadKg = 65,
    this.modelSamples = 0,
  });

  final double distanceKm;
  final double usePct;
  final double useLowPct;
  final double useHighPct;
  final double arrivalSoc;
  final double arrivalLowSoc;
  final TripVerdict verdict;
  final double kmPerPct;
  final TripKmSource source;
  final double factor;
  final double startNeededSoc;
  final double avgSpeedKmh;
  final double payloadKg;
  final int modelSamples;
  final List<TripSuggestion> suggestions;

  String get verdictLabel => switch (verdict) {
    TripVerdict.comfortable => 'Đủ pin, thoải mái',
    TripVerdict.tight => 'Đi được nhưng sát',
    TripVerdict.insufficient => 'Không đủ pin',
  };
}
