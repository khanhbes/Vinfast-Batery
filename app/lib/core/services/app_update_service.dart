import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import 'api_service.dart';
import 'notification_center_service.dart';

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
  static const _lastNotifiedVersionKey = 'app_update_last_notified_version';
  static const _snoozedVersionKey = 'app_update_snoozed_version';
  static const _snoozedUntilKey = 'app_update_snoozed_until';
  static const _defaultRemindLaterHours = 6;

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
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
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
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final latestBuild = _asInt(_remoteConfig['latestBuild']);
    final minSupported = _asInt(_remoteConfig['minSupportedBuild']);
    final latestVersion = _asString(_remoteConfig['latestVersion']);
    final releaseNotes = _asString(_remoteConfig['releaseNotes']);
    final isForce = _asBool(_remoteConfig['forceUpdate']);
    final delivery = _parseDeliveryMode(_remoteConfig);

    // Không có thông tin hợp lệ → bỏ qua
    if (latestBuild <= 0 || latestVersion.isEmpty) return;
    if (latestBuild <= currentBuild) return;

    final forceUpdate = isForce || currentBuild < minSupported;
    final notificationKey = '$latestVersion+$latestBuild';
    if (prefs.getString(_lastNotifiedVersionKey) != notificationKey) {
      await NotificationCenterService().notifyAppUpdateAvailable(
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        forceUpdate: forceUpdate,
      );
      await prefs.setString(_lastNotifiedVersionKey, notificationKey);
    }

    if (!forceUpdate && _isSnoozed(prefs, notificationKey)) return;

    if (!context.mounted) return;
    final action = await _showUpdateDialog(
      context,
      currentVersion: '${info.version}+${info.buildNumber}',
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      releaseNotes: releaseNotes,
      forceUpdate: forceUpdate,
      deliveryMode: delivery,
      apkDownloadUrl: _resolveDownloadUrl(delivery),
    );
    if (action == _UpdateDialogAction.later) {
      await _snoozeVersion(prefs, notificationKey);
    }
  }

  /// Xác định URL tải APK. Phù hợp với server.py:
  /// - Nếu config có `apkUrl` khởi đầu bằng `http` → dùng trực tiếp.
  /// - Ngược lại trở về `/api/app/download` (server sẽ redirect/serve).
  String _resolveDownloadUrl(_UpdateDeliveryMode deliveryMode) {
    final raw = _asString(_remoteConfig['apkUrl']);
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.isEmpty && deliveryMode == _UpdateDeliveryMode.shorebird) {
      return '';
    }
    return '${AppConstants.apiBaseUrl}/api/app/download';
  }

  bool _isSnoozed(SharedPreferences prefs, String versionKey) {
    final snoozedVersion = prefs.getString(_snoozedVersionKey);
    final snoozedUntil = prefs.getInt(_snoozedUntilKey) ?? 0;
    if (snoozedVersion != versionKey) return false;
    return DateTime.now().millisecondsSinceEpoch < snoozedUntil;
  }

  Future<void> _snoozeVersion(
    SharedPreferences prefs,
    String versionKey,
  ) async {
    final remoteHours = _asInt(_remoteConfig['remindLaterHours']);
    final hours = remoteHours > 0 ? remoteHours : _defaultRemindLaterHours;
    final until = DateTime.now().add(Duration(hours: hours));
    await prefs.setString(_snoozedVersionKey, versionKey);
    await prefs.setInt(_snoozedUntilKey, until.millisecondsSinceEpoch);
  }

  Future<_UpdateDialogAction?> _showUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required int latestBuild,
    required String releaseNotes,
    required bool forceUpdate,
    required _UpdateDeliveryMode deliveryMode,
    required String apkDownloadUrl,
  }) async {
    _dialogShowing = true;
    try {
      return await showDialog<_UpdateDialogAction>(
        context: context,
        barrierDismissible: !forceUpdate,
        builder: (_) => _UpdateDialog(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          latestBuild: latestBuild,
          releaseNotes: releaseNotes,
          forceUpdate: forceUpdate,
          deliveryMode: deliveryMode,
          apkDownloadUrl: apkDownloadUrl,
        ),
      );
    } finally {
      _dialogShowing = false;
    }
  }

  /// Gọi thủ công để kiểm tra ngay (bỏ qua throttle).
  Future<void> checkNow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await prefs.remove(_snoozedVersionKey);
    await prefs.remove(_snoozedUntilKey);
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

enum _UpdateDialogAction { updateNow, later }

enum _UpdateDeliveryMode { apk, shorebird }

_UpdateDeliveryMode _parseDeliveryMode(Map<String, dynamic> config) {
  final raw =
      (config['releaseChannel'] ??
              config['updateChannel'] ??
              config['delivery'] ??
              config['deliveryMode'] ??
              'apk')
          .toString()
          .toLowerCase();
  if (raw.contains('shorebird') ||
      raw.contains('ota') ||
      raw.contains('patch')) {
    return _UpdateDeliveryMode.shorebird;
  }
  return _UpdateDeliveryMode.apk;
}

class _UpdateDialog extends StatefulWidget {
  final String currentVersion;
  final String latestVersion;
  final int latestBuild;
  final String releaseNotes;
  final bool forceUpdate;
  final _UpdateDeliveryMode deliveryMode;
  final String apkDownloadUrl;

  const _UpdateDialog({
    required this.currentVersion,
    required this.latestVersion,
    required this.latestBuild,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.deliveryMode,
    required this.apkDownloadUrl,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  String? _downloadError;

  String get currentVersion => widget.currentVersion;
  String get latestVersion => widget.latestVersion;
  int get latestBuild => widget.latestBuild;
  String get releaseNotes => widget.releaseNotes;
  bool get forceUpdate => widget.forceUpdate;
  _UpdateDeliveryMode get deliveryMode => widget.deliveryMode;
  String get apkDownloadUrl => widget.apkDownloadUrl;

  @override
  Widget build(BuildContext context) {
    final channelLabel = deliveryMode == _UpdateDeliveryMode.shorebird
        ? 'Shorebird OTA'
        : 'Direct APK';

    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              forceUpdate ? 'Cập nhật bắt buộc' : 'Có phiên bản mới',
              style: const TextStyle(
                color: AppColors.textPrimary,
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
                const Text(
                  'Hiện tại: ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  currentVersion,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Mới nhất: ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  latestBuild > 0
                      ? '$latestVersion+$latestBuild'
                      : latestVersion,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(
                channelLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Có gì mới',
                style: TextStyle(
                  color: AppColors.textPrimary,
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
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _buildReleaseNotes(releaseNotes),
              ),
            ],
            if (forceUpdate) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Bắt buộc cập nhật để tiếp tục sử dụng',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: _progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 7),
              Text(
                _progress == null
                    ? 'Đang chuẩn bị bản cập nhật...'
                    : 'Đang tải ${(_progress! * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
            if (_downloadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _downloadError!,
                style: const TextStyle(color: AppColors.error, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!forceUpdate)
          TextButton(
            onPressed: _downloading
                ? null
                : () => Navigator.pop(context, _UpdateDialogAction.later),
            child: const Text(
              'Remind Me Later',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        FilledButton.icon(
          onPressed: _downloading ? null : () => _download(context),
          icon: Icon(
            _downloadError == null
                ? Icons.download_rounded
                : Icons.refresh_rounded,
            size: 16,
          ),
          label: Text(_downloadError == null ? 'Update Now' : 'Thử lại'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _download(BuildContext context) async {
    if (deliveryMode == _UpdateDeliveryMode.shorebird &&
        apkDownloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kênh Shorebird OTA sẽ tự áp dụng bản vá khi app khởi động lại.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (context.mounted) {
        Navigator.pop(context, _UpdateDialogAction.updateNow);
      }
      return;
    }

    if (apkDownloadUrl.isEmpty) {
      setState(
        () => _downloadError = 'Server chưa cấu hình file APK cập nhật.',
      );
      return;
    }

    setState(() {
      _downloading = true;
      _progress = null;
      _downloadError = null;
    });

    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(apkDownloadUrl));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'VinFastBattery_${latestVersion}_$latestBuild.apk',
      );
      sink = file.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted && total > 0) {
          setState(() => _progress = received / total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (!mounted) return;
      setState(() => _progress = 1);
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
      if (!forceUpdate && context.mounted) {
        Navigator.pop(context, _UpdateDialogAction.updateNow);
      }
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _downloadError = 'Tải hoặc mở APK thất bại: $e';
      });
      final uri = Uri.tryParse(apkDownloadUrl);
      if (uri != null && await canLaunchUrl(uri) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bạn có thể thử tải bằng trình duyệt.'),
            action: SnackBarAction(
              label: 'Mở',
              onPressed: () =>
                  launchUrl(uri, mode: LaunchMode.externalApplication),
            ),
          ),
        );
      }
    } finally {
      client.close();
      if (mounted && _downloadError == null) {
        setState(() => _downloading = false);
      }
    }
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
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          height: 1.5,
        ),
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
                const Text(
                  '• ',
                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    line.startsWith('-') || line.startsWith('•')
                        ? line.substring(1).trim()
                        : line,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
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
