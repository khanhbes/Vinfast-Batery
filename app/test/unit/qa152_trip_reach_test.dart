import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/services/trip_energy_model.dart';

void main() {
  double reach(double soc, {TripConditions c = const TripConditions()}) =>
      TripEnergyModel.reachKm(currentSoc: soc, kmPerPct: 1.2, conditions: c);

  test('the reach is the longest trip that still arrives with the reserve', () {
    final km = reach(88);
    expect(km, greaterThan(40));
    final at = TripEnergyModel.plan(
      distanceKm: km,
      currentSoc: 88,
      kmPerPct: 1.2,
    );
    final past = TripEnergyModel.plan(
      distanceKm: km + 2,
      currentSoc: 88,
      kmPerPct: 1.2,
    );
    expect(at.arrivalLowSoc, greaterThanOrEqualTo(TripEnergyModel.reservePct));
    expect(past.arrivalLowSoc, lessThan(TripEnergyModel.reservePct));
  });

  test('less battery, harder conditions and a round trip reach less far', () {
    expect(reach(40), lessThan(reach(88)));
    expect(
      reach(88, c: const TripConditions(roundTrip: true)),
      lessThan(reach(88) * 0.6),
    );
    expect(
      reach(88, c: const TripConditions(speed: TripSpeed.fast, hilly: true)),
      lessThan(reach(88)),
    );
  });

  test('at or under the reserve there is no reach', () {
    expect(reach(5), 0);
    expect(reach(0), 0);
  });
}
