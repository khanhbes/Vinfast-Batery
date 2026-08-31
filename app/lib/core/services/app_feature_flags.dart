import 'package:shared_preferences/shared_preferences.dart';

class AppFeatureFlags {
  AppFeatureFlags._();

  static const smartChargeDesignV2 = 'ui.smart_charge_v2';
  static const aiDashboardDesignV2 = 'ui.ai_dashboard_v2';
  static const fullAppDesignV2 = 'ui.full_app_v2';
  /// V4 rollout switch. Defaults on after the V4 shell is deployed, while
  /// remote config can turn it off for rollback during staged rollout.
  static const fullAppV4 = 'ui.full_app_v4';

  static Future<bool> enabled(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ??
        (key == smartChargeDesignV2 || key == fullAppV4);
  }

  /// Called by remote-config sync. Unknown flags are ignored so a malformed
  /// server payload cannot silently enable unfinished UI phases.
  static Future<void> apply(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      smartChargeDesignV2,
      aiDashboardDesignV2,
      fullAppDesignV2,
      fullAppV4,
    ]) {
      final value = values[key];
      if (value is bool) await prefs.setBool(key, value);
    }
  }
}
