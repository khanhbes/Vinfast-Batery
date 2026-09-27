import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/shelly_connection.dart';
import 'package:vinfast_battery/data/services/shelly_capability_checker.dart';

void main() {
  const checker = ShellyCapabilityChecker();

  DiscoveredShellyDevice device({
    String model = 'S3PL-00112EU',
    Set<String> meterFields = const {},
    int? generation = 3,
  }) => DiscoveredShellyDevice(
    id: 'shelly-test',
    address: '192.168.1.20',
    model: model,
    generation: generation,
    powerMeterFields: meterFields,
    powerMeterFieldsPresent: meterFields.containsAll(
      DiscoveredShellyDevice.requiredPowerMeterFields,
    ),
  );

  test('allows Plug S Gen3 only after complete meter proof', () {
    expect(checker.isCompatible(device()), isFalse);
    expect(
      checker.isCompatible(
        device(meterFields: DiscoveredShellyDevice.requiredPowerMeterFields),
      ),
      isTrue,
    );
    expect(checker.check(device()), ModelCompatibility.incompatible);
  });

  test('allows another model only after meter capability probe', () {
    expect(checker.isCompatible(device(model: 'Shelly Plus 1PM')), isFalse);
    expect(
      checker.isCompatible(
        device(
          model: 'Shelly Plus 1PM',
          meterFields: DiscoveredShellyDevice.requiredPowerMeterFields,
        ),
      ),
      isTrue,
    );
  });

  test('rejects relay, temperature, or partial meter fields', () {
    expect(
      checker.isCompatible(device(meterFields: const {'apower'})),
      isFalse,
    );
    expect(
      checker.isCompatible(
        device(meterFields: const {'apower', 'voltage', 'current'}),
      ),
      isFalse,
    );
  });

  test('keeps a password-protected known model visible for password entry', () {
    final protected = DiscoveredShellyDevice(
      id: 'shelly-test',
      address: '192.168.1.20',
      model: 'S3PL-00112EU',
      authEnabled: true,
    );
    expect(checker.isCompatible(protected), isFalse);
    expect(checker.isPotentiallyCompatible(protected), isTrue);
  });

  test('profile can be LAN-only without accepting an unsafe public host', () {
    expect(
      const ShellyConnectionProfile(
        deviceId: 'shelly-test',
        model: 'Shelly Plus 1PM',
        lanAddress: '192.168.1.20',
      ).validate(),
      isNull,
    );
    expect(
      const ShellyConnectionProfile(
        deviceId: 'shelly-test',
        cloudHost: 'http://evil.example',
        cloudAuthKey: 'key',
      ).validate(),
      isNotNull,
    );
  });
}
