import 'package:package_info_plus/package_info_plus.dart';

/// The installed build, e.g. "1.3.9+212" (QA 141: one source; a constant
/// in code went stale and showed 1.3.0). Null when the platform has no
/// package info (widget tests).
final Future<String?> installedVersion = () async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } on Object {
    return null;
  }
}();
