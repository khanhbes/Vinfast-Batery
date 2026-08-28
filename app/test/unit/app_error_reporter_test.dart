import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/app_error_reporter.dart';

void main() {
  setUp(() {
    AppErrorReporter.clear();
  });

  group('AppErrorReporter', () {
    test('stores error and stack trace', () {
      final error = Exception('Something went wrong');
      final stack = StackTrace.current;

      AppErrorReporter.report(
        error,
        stack,
        source: 'TestService',
        endpoint: '/api/test',
        statusCode: 500,
        debugCode: 'INTERNAL_ERROR',
      );

      expect(AppErrorReporter.entries.length, 1);
      final entry = AppErrorReporter.entries.first;
      expect(entry.source, 'TestService');
      expect(entry.message, contains('Something went wrong'));
      expect(entry.endpoint, '/api/test');
      expect(entry.statusCode, 500);
      expect(entry.debugCode, 'INTERNAL_ERROR');
      expect(entry.stackTrace.isNotEmpty, true);
    });

    test('stores max 50 entries and orders newest first', () {
      for (var i = 1; i <= 60; i++) {
        AppErrorReporter.report(
          'Error $i',
          null,
          source: 'BatchTest',
        );
      }

      expect(AppErrorReporter.entries.length, 50);
      // Newest should be at index 0 (Error 60)
      expect(AppErrorReporter.entries.first.message, 'Error 60');
      // Oldest remaining entry should be Error 11 (60 - 50 + 1)
      expect(AppErrorReporter.entries.last.message, 'Error 11');
    });

    test('redacts Bearer tokens', () {
      const sensitive = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.secret';
      final redacted = AppErrorReporter.redactSecrets(sensitive);
      expect(redacted, contains('Bearer ***'));
      expect(redacted, isNot(contains('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9')));
    });

    test('redacts passwords in URLs and JSON', () {
      const jsonStr = '{"username": "admin", "password": "super_secret_password_123"}';
      final redacted = AppErrorReporter.redactSecrets(jsonStr);
      expect(redacted, contains('"password": "***"'));
      expect(redacted, isNot(contains('super_secret_password_123')));
    });

    test('redacts API keys and auth keys', () {
      const text = 'api_key=AIzaSyD_SECRET_KEY_HERE&auth_key=shelly_auth_key_12345';
      final redacted = AppErrorReporter.redactSecrets(text);
      expect(redacted, contains('api_key=***'));
      expect(redacted, contains('auth_key=***'));
      expect(redacted, isNot(contains('AIzaSyD_SECRET_KEY_HERE')));
      expect(redacted, isNot(contains('shelly_auth_key_12345')));
    });

    test('redacts refresh tokens and cookies', () {
      const header = 'refresh_token=rt_987654321, cookie=session_id_abcdef';
      final redacted = AppErrorReporter.redactSecrets(header);
      expect(redacted, contains('refresh_token=***'));
      expect(redacted, contains('cookie=***'));
      expect(redacted, isNot(contains('rt_987654321')));
      expect(redacted, isNot(contains('session_id_abcdef')));
    });

    test('toCopyableString formats nicely', () {
      AppErrorReporter.report(
        'Database connection lost',
        StackTrace.fromString('line 1\nline 2'),
        source: 'Database',
        endpoint: '/db/connect',
        statusCode: 503,
        debugCode: 'DB_UNAVAILABLE',
        debugDetail: 'timeout after 5s',
      );

      final entry = AppErrorReporter.entries.first;
      final text = entry.toCopyableString();
      expect(text, contains('Source: Database'));
      expect(text, contains('Endpoint: /db/connect'));
      expect(text, contains('HTTP Status: 503'));
      expect(text, contains('Debug Code: DB_UNAVAILABLE'));
      expect(text, contains('Detail: timeout after 5s'));
      expect(text, contains('Error: Database connection lost'));
      expect(text, contains('--- Stack Trace ---'));
    });
  });
}
