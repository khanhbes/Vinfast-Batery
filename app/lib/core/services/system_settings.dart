import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's own settings for the owner (QA 161: "Cài đặt mạng"
/// on the offline notice). Never changes a setting by itself.
abstract final class SystemSettings {
  static const _channel = MethodChannel('com.vinfast.battery/settings');

  /// Wi-Fi and mobile data settings (Android); this app's page in
  /// Settings on iOS, which has no public link to Wi-Fi. False when the
  /// phone refused.
  static Future<bool> openNetwork() async {
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('network') ?? false;
      }
      return await launchUrl(Uri.parse('app-settings:'));
    } on Object {
      return false;
    }
  }
}
