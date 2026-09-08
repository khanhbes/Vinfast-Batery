import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vinfast_battery/data/models/shelly_connection.dart';
import 'package:vinfast_battery/data/services/smart_charger_credentials_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const first = ShellyConnectionProfile(
    cloudHost: 'test.shelly.cloud',
    cloudAuthKey: 'test-only',
    deviceId: 'aabb',
  );
  const second = ShellyConnectionProfile(
    cloudHost: 'test.shelly.cloud',
    cloudAuthKey: 'test-only',
    deviceId: 'ccdd',
  );
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Changing profile invalidates verification and clears stale draft',
    () async {
      final service = SmartChargerCredentialsService();
      await service.saveProfile(first);
      await service.saveVerification(
        SmartChargerVerificationState.unverified.copyWith(
          cloudVerified: true,
          safeBootVerified: true,
        ),
      );
      await service.saveDraft(first);
      await service.saveProfile(second);
      expect((await service.readProfile())!.deviceId, second.deviceId);
      expect((await service.readVerification()).readyForControl, isFalse);
      expect(await service.readDraft(), isNull);
    },
  );

  test('Saving identical profile preserves its verification', () async {
    final service = SmartChargerCredentialsService();
    await service.saveProfile(first);
    await service.saveVerification(
      SmartChargerVerificationState.unverified.copyWith(cloudVerified: true),
    );
    await service.saveProfile(first);
    expect((await service.readVerification()).cloudVerified, isTrue);
  });
}
