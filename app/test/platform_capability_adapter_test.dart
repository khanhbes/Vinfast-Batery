import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/services/platform_capability_adapter.dart';

void main() {
  test('platform adapter reports the host and iOS hybrid policy', () {
    expect(PlatformCapabilityAdapter.operatingSystem, Platform.operatingSystem);
    expect(
      PlatformCapabilityAdapter.supportsContinuousForegroundService,
      Platform.isAndroid,
    );
    expect(PlatformCapabilityAdapter.bundleId, 'com.khanhbes.vinfastbattery');
  });
}
