import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import 'api_service.dart';

/// Kiểm tra version mới + remote config từ /api/app/config và hiển thị
/// dialog cập nhật (optional hoặc forced).
///
/// Lưu ý:
/// - Firebase Auth không bắt buộc cho endpoint này; chỉ cần mạng.
/// - Có [observeLifecycle]/[stopObservingLifecycle] để tự động recheck
///   mỗi khi app trở lại foreground (resume).
class AppUpdateService with WidgetsBindingObserver {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  static const _lastCheckKey = 'app_update_last_check';
  static const _checkIntervalHours = 6;

  Map<String, dynamic> _remoteConfig = {};
  Map<String, dynamic> get remoteConfig => _remoteConfig;

  BuildContext? _hostContext;
  bool _dialogShowing = false;
  bool _observing = false;

  /// Lấy giá trị feature flag từ remote config
  bool featureEnabled(String key, {bool defaultValue = false}) {
    final features = _remoteConfig['features'];
    if (features is Map) {
      final v = features[key];
      if (v is bool) return v;
      if (v == null) return defaultValue;
      return v.toString().toLowerCase() == 'true';
    }
    return defaultValue;
  }

  /// Gọi khi authenticated bootstrap chạy — fetch config và (nếu có context)
  /// hiển thị dialog cập nhật nếu đủ điều kiện.
  Future<void> initialize({BuildContext? context}) async {
    try {
      _hostContext = context;
      await _fetchConfig();
      if (context != null && context.mounted) {
        await _maybeShowUpdateDialog(context);
      }
      observeLifecycle();
    } catch (e) {
      debugPrint('[AppUpdate] init error: $e');
    }
  }

  /// Đăng ký lifecycle observer để recheck khi app resume.
  void observeLifecycle() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  /// Gỡ lifecycle observer (gọi khi logout/dispose root).
  void stopObservingLifecycle() {
    if (!_observing) return;
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final ctx = _hostContext;
    if (ctx == null || !ctx.mounted) return;
    // Refresh config + maybe show dialog (bỏ qua throttle ngắn 5 phút để
    // tránh spam khi user thao tác qua-lại liên tục).
    _refreshAndMaybeShow(ctx, minIntervalMinutes: 5);
  }

  Future<void> _refreshAndMaybeShow(
    BuildContext context, {
    int minIntervalMinutes = 0,
  }) async {
    if (_dialogShowing) return;
    if (minIntervalMinutes > 0) {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
      final elapsedMin =
          (DateTime.now().millisecondsSinceEpoch - lastCheck) / 60000;
      if (elapsedMin < minIntervalMinutes) return;
    }
    await _fetchConfig();
    if (!context.mounted) return;
    await _maybeShowUpdateDialog(context);
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
    if (_dialogShowing) return;

    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedH = (now - lastCheck) / 3600000;

    final isForce = _asBool(_remoteConfig['forceUpdate']);
    if (!isForce && elapsedH < _checkIntervalHours) return;

    await prefs.setInt(_lastCheckKey, now);

    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final latestBuild = _asInt(_remoteConfig['latestBuild']);
    final minSupported = _asInt(_remoteConfig['minSupportedBuild']);
    final latestVersion = _asString(_remoteConfig['latestVersion']);
    final releaseNotes = _asString(_remoteConfig['releaseNotes']);

    // Không có thông tin hợp lệ → bỏ qua
    if (latestBuild <= 0 || latestVersion.isEmpty) return;
    if (latestBuild <= currentBuild) return;

    if (!context.mounted) return;
    _showUpdateDialog(
      context,
      currentVersion: '${info.version}+${info.buildNumber}',
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      releaseNotes: releaseNotes,
      forceUpdate: isForce || currentBuild < minSupported,
      apkDownloadUrl: _resolveDownloadUrl(),
    );
  }

  /// Xác định URL tải APK. Phù hợp với server.py:
  /// - Nếu config có `apkUrl` khởi đầu bằng `http` → dùng trực tiếp.
  /// - Ngược lại trở về `/api/app/download` (server sẽ redirect/serve).
  String _resolveDownloadUrl() {
    final raw = _asString(_remoteConfig['apkUrl']);
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '${AppConstants.apiBaseUrl}/api/app/download';
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
    _dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (_) => _UpdateDialog(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
        apkDownloadUrl: apkDownloadUrl,
      ),
    ).whenComplete(() {
      _dialogShowing = false;
    });
  }

  /// Gọi thủ công để kiểm tra ngay (bỏ qua throttle).
  Future<void> checkNow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await _fetchConfig();
    if (context.mounted) await _maybeShowUpdateDialog(context);
  }

  // ── Parsing helpers (an toàn với payload không đồng bộ type) ─────────

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _asString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }
}

class _UpdateDialog extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final int latestBuild;
  final String releaseNotes;
  final bool forceUpdate;
  final String apkDownloadUrl;

  const _UpdateDialog({
    required this.currentVersion,
    required this.latestVersion,
    required this.latestBuild,
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
          Expanded(
            child: Text(
              forceUpdate ? 'Cập nhật bắt buộc' : 'Có phiên bản mới',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Hiện tại: ',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text(currentVersion,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Mới nhất: ',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text(
                  latestBuild > 0 ? '$latestVersion+$latestBuild' : latestVersion,
                  style: const TextStyle(
                    color: Color(0xFF2D5BFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Có gì mới',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _buildReleaseNotes(releaseNotes),
              ),
            ],
            if (forceUpdate) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B).withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠ Bắt buộc cập nhật để tiếp tục sử dụng',
                  style: TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
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
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không mở được link tải: $apkDownloadUrl'),
          backgroundColor: const Color(0xFFFF6B6B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (!forceUpdate && context.mounted) Navigator.pop(context);
  }

  /// Tách release notes thành các dòng / gạch đầu dòng.
  Widget _buildReleaseNotes(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length <= 1) {
      return Text(
        raw,
        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ',
                    style: TextStyle(color: Color(0xFF2D5BFF), fontSize: 12)),
                Expanded(
                  child: Text(
                    line.startsWith('-') || line.startsWith('•')
                        ? line.substring(1).trim()
                        : line,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
