import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import 'api_service.dart';

/// Kiểm tra version mới + remote config từ /api/app/config
/// Hiển thị dialog nếu có bản cập nhật
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  static const _lastCheckKey = 'app_update_last_check';
  static const _checkIntervalHours = 6;

  Map<String, dynamic> _remoteConfig = {};
  Map<String, dynamic> get remoteConfig => _remoteConfig;

  /// Lấy giá trị feature flag từ remote config
  bool featureEnabled(String key, {bool defaultValue = false}) {
    final features = _remoteConfig['features'];
    if (features is Map) return features[key] ?? defaultValue;
    return defaultValue;
  }

  /// Gọi khi app khởi động — fetch config, check update nếu đủ thời gian
  Future<void> initialize({BuildContext? context}) async {
    try {
      await _fetchConfig();
      if (context != null && context.mounted) {
        await _maybeShowUpdateDialog(context);
      }
    } catch (e) {
      debugPrint('[AppUpdate] init error: $e');
    }
  }

  Future<void> _fetchConfig() async {
    try {
      final res = await ApiService().get('/api/app/config');
      if (res['success'] == true && res['data'] is Map) {
        _remoteConfig = Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (e) {
      debugPrint('[AppUpdate] fetch config error: $e');
    }
  }

  Future<void> _maybeShowUpdateDialog(BuildContext context) async {
    if (_remoteConfig.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (now - lastCheck) / 3600000;

    final isForce = _remoteConfig['forceUpdate'] == true;
    if (!isForce && elapsed < _checkIntervalHours) return;

    await prefs.setInt(_lastCheckKey, now);

    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final latestBuild = (_remoteConfig['latestBuild'] as num?)?.toInt() ?? 0;
    final minSupported = (_remoteConfig['minSupportedBuild'] as num?)?.toInt() ?? 0;

    if (latestBuild <= currentBuild) return;

    if (!context.mounted) return;
    _showUpdateDialog(
      context,
      currentVersion: '${info.version}+${info.buildNumber}',
      latestVersion: _remoteConfig['latestVersion'] as String? ?? '',
      latestBuild: latestBuild,
      releaseNotes: _remoteConfig['releaseNotes'] as String? ?? '',
      forceUpdate: isForce || currentBuild < minSupported,
      apkDownloadUrl: '${AppConstants.apiBaseUrl}/api/app/download',
    );
  }

  void _showUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required int latestBuild,
    required String releaseNotes,
    required bool forceUpdate,
    required String apkDownloadUrl,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (_) => _UpdateDialog(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
        apkDownloadUrl: apkDownloadUrl,
      ),
    );
  }

  /// Gọi thủ công để kiểm tra ngay (bỏ qua throttle)
  Future<void> checkNow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await _fetchConfig();
    if (context.mounted) await _maybeShowUpdateDialog(context);
  }
}

class _UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final bool forceUpdate;
  final String apkDownloadUrl;

  const _UpdateDialog({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.apkDownloadUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2D5BFF).withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded, color: Color(0xFF2D5BFF), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Phiên bản mới',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Hiện tại: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text(currentVersion, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Mới nhất: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text(latestVersion, style: const TextStyle(color: Color(0xFF2D5BFF), fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          if (releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                releaseNotes,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
              ),
            ),
          ],
          if (forceUpdate) ...[
            const SizedBox(height: 10),
            const Text(
              '⚠ Bắt buộc cập nhật để tiếp tục sử dụng.',
              style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
            ),
          ],
        ],
      ),
      actions: [
        if (!forceUpdate)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Để sau', style: TextStyle(color: Colors.white38)),
          ),
        FilledButton.icon(
          onPressed: () => _download(context),
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Tải về & Cài đặt'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2D5BFF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Future<void> _download(BuildContext context) async {
    final uri = Uri.parse(apkDownloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!forceUpdate && context.mounted) Navigator.pop(context);
  }
}
