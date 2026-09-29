import 'package:flutter_test/flutter_test.dart';
import 'package:vinfast_battery/core/constants/beta_capabilities.dart';

void main() {
  test('beta build cannot expose unfinished features by remote configuration', () {
    if (BetaCapabilities.enabled) {
      expect(BetaCapabilities.advancedAi, isFalse);
      expect(BetaCapabilities.tripPlanner, isFalse);
      expect(BetaCapabilities.developerMode, isFalse);
    }
  });
}
