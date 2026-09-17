import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/auth_service.dart';
import 'package:vinfast_battery/core/services/firebase_bootstrap_coordinator.dart';
import 'package:vinfast_battery/core/services/settings_service.dart';
import 'package:vinfast_battery/core/services/sync_service.dart';
import 'package:vinfast_battery/data/repositories/charge_sample_repository.dart';
import 'package:vinfast_battery/data/repositories/notification_repository.dart';
import 'package:vinfast_battery/data/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseBootstrap Lifecycle & Safe Singletons', () {
    test('FirebaseBootstrapCoordinator.isReady is false without FirebaseApp and does not throw', () {
      expect(FirebaseBootstrapCoordinator.isReady, isFalse);
    });

    test('PushNotificationService instance and setDeepLinkHandler do not throw [core/no-app]', () {
      expect(() {
        PushNotificationService.instance.setDeepLinkHandler((data) {});
      }, returnsNormally);
    });

    test('AuthService and SyncService can be instantiated before Firebase is ready without throwing', () {
      expect(() {
        final auth = AuthService();
        expect(auth, isNotNull);
      }, returnsNormally);

      expect(() {
        final sync = SyncService();
        expect(sync, isNotNull);
      }, returnsNormally);
    });

    test('Repositories can be instantiated before Firebase is ready without throwing', () {
      expect(() {
        final notifRepo = NotificationRepository();
        expect(notifRepo, isNotNull);
      }, returnsNormally);

      expect(() {
        final sampleRepo = ChargeSampleRepository();
        expect(sampleRepo, isNotNull);
      }, returnsNormally);
    });

    test('SettingsService defaults to Vietnamese language on first-run', () {
      final settings = SettingsService();
      expect(settings.getLanguage(), AppLanguage.vietnamese);
      expect(settings.getLocale(), isNotNull);
      expect(settings.getLocale()?.languageCode, 'vi');
    });
  });
}
