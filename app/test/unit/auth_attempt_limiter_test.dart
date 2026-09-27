import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/services/auth_attempt_limiter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cooldown begins on the fifth invalid credential in the window',
    () async {
      final limiter = AuthAttemptLimiter();
      for (var attempt = 1; attempt <= 4; attempt++) {
        expect(await limiter.recordInvalidCredential(), Duration.zero);
      }

      final remaining = await limiter.recordInvalidCredential();
      expect(remaining.inSeconds, inInclusiveRange(58, 60));
      expect((await limiter.remaining()).inSeconds, inInclusiveRange(58, 60));
    },
  );

  test('successful authentication clears device-local failures', () async {
    final limiter = AuthAttemptLimiter();
    await limiter.recordInvalidCredential();
    await limiter.reset();

    expect(await limiter.remaining(), Duration.zero);
    expect(await limiter.recordInvalidCredential(), Duration.zero);
  });
}
