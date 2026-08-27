import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_status.dart';

void main() {
  test('parses normal doubles and relay state', () {
    final status = SmartChargerStatus.fromJson({
      'online': true,
      'relay': true,
      'power_w': 410.5,
      'voltage_v': 228.9,
      'current_a': 1.79,
      'frequency_hz': 49.8,
      'temperature_c': 46.2,
      'energy_wh': 10.5,
    });

    expect(status.online, isTrue);
    expect(status.relay, isTrue);
    expect(status.powerW, 410.5);
    expect(status.temperatureC, 46.2);
  });

  test('parses integer zero as double', () {
    final status = SmartChargerStatus.fromJson({
      'online': true,
      'relay': false,
      'power_w': 0,
    });
    expect(status.powerW, 0.0);
    expect(status.powerW, isA<double>());
  });

  test('allows null temperature and defaults missing telemetry', () {
    final status = SmartChargerStatus.fromJson({
      'online': false,
      'relay': false,
      'temperature_c': null,
    });
    expect(status.online, isFalse);
    expect(status.relay, isFalse);
    expect(status.temperatureC, isNull);
    expect(status.voltageV, 0.0);
    expect(status.currentA, 0.0);
    expect(status.frequencyHz, 0.0);
    expect(status.energyWh, 0.0);
  });

  test('rejects malformed required boolean fields', () {
    expect(
      () => SmartChargerStatus.fromJson({'online': 'yes', 'relay': false}),
      throwsFormatException,
    );
  });
}
