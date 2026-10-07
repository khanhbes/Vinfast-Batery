import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/data/models/smart_charger_capabilities.dart';

void main() {
  test('staging explains the lock without losing read/OFF capability', () {
    final caps = SmartChargerCapabilities.fromJson({
      'canReadStatus': true,
      'canManualOff': true,
      'readyForControl': false,
      'controlBlockedCode': 'STAGING_HARDWARE_DISABLED',
    });
    expect(caps.readyForControl, false);
    expect(caps.canManualOff, true);
    expect(caps.controlBlockedMessage, contains('Máy chủ thử nghiệm'));
  });
  test(
    'missing evidence has an actionable reason instead of silent disable',
    () {
      final caps = SmartChargerCapabilities.fromJson({
        'canReadStatus': true,
        'canReadPower': true,
        'safeBootVerified': true,
        'noLoadTestVerified': false,
      });
      expect(caps.controlBlockedMessage, contains('kiểm tra không tải'));
      expect(caps.readyForControl, false);
    },
  );
  test('unknown provider error is never printed to the UI', () {
    final caps = SmartChargerCapabilities.fromJson({
      'controlBlockedCode': 'internal-host-secret-error',
    });
    expect(caps.controlBlockedMessage, isNot(contains('internal-host')));
  });
}
