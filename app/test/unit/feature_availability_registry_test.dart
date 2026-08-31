import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/models/feature_availability.dart';
import 'package:vinfast_battery/core/services/feature_availability_registry.dart';

void main() {
  test(
    'AI is disabled when model is unavailable, manual setup remains distinct',
    () {
      const registry = FeatureAvailabilityRegistry(chargerReady: true);
      expect(
        registry.smartCharge(ai: true).state,
        FeatureAvailabilityState.disabled,
      );
      expect(registry.smartCharge().enabled, isTrue);
    },
  );

  test('offline state preserves a specific reason', () {
    const registry = FeatureAvailabilityRegistry(online: false);
    expect(registry.smartCharge().state, FeatureAvailabilityState.offline);
  });

  test('manual timed charging remains available over LAN while offline', () {
    const registry = FeatureAvailabilityRegistry(
      online: false,
      chargerReady: true,
      lanAvailable: true,
    );
    expect(registry.smartCharge().enabled, isTrue);
    expect(
      registry.smartCharge(ai: true).state,
      FeatureAvailabilityState.offline,
    );
  });

  test('missing vehicle data blocks LAN manual charging', () {
    const registry = FeatureAvailabilityRegistry(
      online: false,
      chargerReady: true,
      lanAvailable: true,
      hasVehicleData: false,
    );
    expect(registry.smartCharge().state, FeatureAvailabilityState.needsData);
  });
}
