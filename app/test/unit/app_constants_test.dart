import 'package:flutter_test/flutter_test.dart';

import 'package:vinfast_battery/core/constants/app_constants.dart';

void main() {
  tearDown(() => AppConstants.setCustomApiBaseUrl(null));

  test('accepts emulator host bridge HTTP endpoint for local debug QA', () {
    AppConstants.setCustomApiBaseUrl('http://10.0.2.2:5000');
    expect(AppConstants.apiBaseUrl, 'http://10.0.2.2:5000');
    expect(AppConstants.isApiConfigured, isTrue);
  });

  test('rejects arbitrary insecure HTTP endpoint', () {
    AppConstants.setCustomApiBaseUrl(null);
    final baseline = AppConstants.apiBaseUrl;
    AppConstants.setCustomApiBaseUrl('http://example.com');
    expect(AppConstants.apiBaseUrl, baseline);
    expect(AppConstants.apiBaseUrl, isNot('http://example.com'));
  });

  test('normalizes a trailing slash on local endpoint', () {
    AppConstants.setCustomApiBaseUrl('http://10.0.2.2:5000///');
    expect(AppConstants.apiBaseUrl, 'http://10.0.2.2:5000');
  });

  test('builds an absolute API URI from a configured endpoint', () {
    AppConstants.setCustomApiBaseUrl('http://10.0.2.2:5000');
    final uri = AppConstants.tryBuildApiUri('/api/mobile/push-tokens/device');
    expect(
      uri?.toString(),
      'http://10.0.2.2:5000/api/mobile/push-tokens/device',
    );
    expect(uri?.host, '10.0.2.2');
  });
}
