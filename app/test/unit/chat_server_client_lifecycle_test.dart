import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinfast_battery/core/constants/app_constants.dart';
import 'package:vinfast_battery/data/services/server_smart_charger_service.dart';
import 'package:vinfast_battery/data/services/smart_charger_service.dart';

class _NoAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends http.BaseClient {
  int closed = 0, sent = 0;
  @override
  void close() => closed++;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent++;
    throw StateError('must not send');
  }
}

void main() {
  test('closed chat HTTP service rejects requests and closes once', () async {
    final client = _Client();
    final service = ServerSmartChargerService(client: client, auth: _NoAuth());
    AppConstants.setCustomApiBaseUrl('https://qa.example.com');
    addTearDown(() => AppConstants.setCustomApiBaseUrl(null));
    service.close();
    service.close();
    await expectLater(
      service.getBinding(),
      throwsA(
        isA<SmartChargerException>().having(
          (error) => error.code,
          'code',
          'account_changed',
        ),
      ),
    );
    expect(client.closed, 1);
    expect(client.sent, 0);
  });
}
