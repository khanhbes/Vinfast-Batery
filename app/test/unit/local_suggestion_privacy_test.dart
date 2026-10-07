import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/features/ai/services/suggestion_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'production suggestions never upload account or vehicle metadata',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('{}', 200);
      });
      AppConstants.setCustomApiBaseUrl('https://qa.example.com');
      addTearDown(() => AppConstants.setCustomApiBaseUrl(null));
      final service = SuggestionService(
        client: client,
        uidResolver: () => 'qa-owner',
      );
      addTearDown(service.dispose);
      final result = await service.fetchSuggestions(
        userId: 'qa-owner',
        vehicleId: 'qa-car',
        currentSoc: 14,
      );
      expect(result.single.action, 'open_smart_charging');
      expect(requests, 0);
      expect(
        await service.fetchSuggestions(
          userId: 'different-owner',
          currentSoc: 14,
        ),
        isEmpty,
      );
      expect(
        await service.fetchSuggestions(
          userId: 'qa-owner',
          currentSoc: double.nan,
        ),
        isEmpty,
      );
      expect(await service.fetchSuggestions(userId: 'qa-owner'), isEmpty);
      expect(requests, 0);
    },
  );
}
