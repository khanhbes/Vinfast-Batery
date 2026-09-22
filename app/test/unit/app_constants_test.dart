import 'package:flutter_test/flutter_test.dart';

import 'package:vinfast_battery/core/constants/app_constants.dart';

void main() {
  test('accepts emulator host bridge HTTP endpoint for local debug QA', () {
    AppConstants.setCustomApiBaseUrl('http://10.0.2.2:5000');
    expect(AppConstants.apiBaseUrl, 'http://10.0.2.2:5000');
    expect(AppConstants.isApiConfigured, isTrue);
  });

  test('rejects arbitrary insecure HTTP endpoint', () {
    AppConstants.setCustomApiBaseUrl('http://example.com');
    expect(AppConstants.apiBaseUrl, 'http://10.0.2.2:5000');
  });

  test('normalizes a trailing slash on local endpoint', () {
    AppConstants.setCustomApiBaseUrl('http://10.0.2.2:5000///');
    expect(AppConstants.apiBaseUrl, 'http://10.0.2.2:5000');
  });
}
