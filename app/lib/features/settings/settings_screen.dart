import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/beta_capabilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/shelly_connection_coordinator.dart';
import '../../data/services/push_notification_service.dart';

import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/widgets/app_popup.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'appearance_sheet.dart';
import 'appearance_screen.dart';
import '../../core/providers/appearance_provider.dart';
import 'personal_ai_settings_screen.dart';
import 'personal_ai_training_data_screen.dart';
import 'developer_ai_studio_screen.dart';
import '../../core/widgets/luxe_kit.dart';

// =============================================================================
// Settings Screen V5 — PLAN #4, #5, #7
// Profile, Vehicle Garage, Application Settings with toggles
// Cleaned up codebase, dynamic version, fully developed app settings
// =============================================================================

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushNotifications = false;
  bool _isLoading = false;
  String _appVersion = '…';
  String _shellyLabel = 'Shelly chưa kết nối';
  bool _developerUnlocked = false;
  int _versionTapCount = 0;

  final _settingsService = SettingsService();
  StreamSubscription<ShellyConnectionSnapshot>? _shellySubscription;

  @override
  void initState() {
    super.initState();
    _shellySubscription = ShellyConnectionCoordinator.shared.states.listen(
      _applyShellyState,
    );
    _applyShellyState(ShellyConnectionCoordinator.shared.current);
    _settingsService.addListener(_onSettingsChanged);
    PushNotificationService.instance.userChoice.addListener(_onPushChoice);
    _settingsService.initialize();
    _loadSettings();
    _loadAppVersion();
    _loadShellyState();
  }

  Future<void> _loadShellyState() async {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    final snapshot = await ShellyConnectionCoordinator.shared.restore(
      vehicleId: vehicleId.isEmpty ? null : vehicleId,
    );
    _applyShellyState(snapshot);
  }

  void _applyShellyState(ShellyConnectionSnapshot snapshot) {
    if (mounted) {
      setState(() {
        final metrics = snapshot.metricsLine;
        _shellyLabel = [
          snapshot.connectionLabel,
          ?metrics,
          if (snapshot.codeRefreshRequired) 'Thiết bị có mã kết nối mới',
        ].join('\n');
      });
    }
  }

  Future<void> _openShellySetup() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SmartChargerSetupHubScreen()));
    await _loadShellyState();
  }

  @override
  void dispose() {
    _shellySubscription?.cancel();
    _settingsService.removeListener(_onSettingsChanged);
    PushNotificationService.instance.userChoice.removeListener(_onPushChoice);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onPushChoice() {
    final choice = PushNotificationService.instance.userChoice.value;
    if (mounted && choice != null) setState(() => _pushNotifications = choice);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationPermission = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _pushNotifications =
          (prefs.getBool('pushNotifications') ?? false) &&
          notificationPermission.isGranted;
      _developerUnlocked = prefs.getBool('developerModeUnlocked') ?? false;
    });
  }

  /// PLAN #8 — Dynamic version from package_info_plus
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = 'V${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersion = 'V?.?.?');
    }
  }

  /// Show About dialog with app info
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Pinova',
      applicationVersion: _appVersion,
      applicationLegalese: '© 2026 Pinova. Quản lý pin và sạc xe máy điện.',
      applicationIcon: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppUiColors.of(context).primary.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/icons/app_icon.png',
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
      children: [
        SizedBox(height: 12),
        Text(
          'Theo dõi sức khỏe pin, dự đoán thời gian sạc và lên kế hoạch chuyến đi với AI.',
        ),
      ],
    );
  }

  Future<void> _manualSync() async {
    setState(() => _isLoading = true);
    final result = await SyncService().performFullSync();
    setState(() => _isLoading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      AppPopup.showSuccess('Đồng bộ thành công');
    } else {
      AppPopup.showError('Chưa đồng bộ được. Hãy kiểm tra mạng và thử lại.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <Widget>[
      // Task 125: profile, vehicles, Shelly, notification centre, guide and
      // sign-out live on the Settings tab; this page keeps system options
      // only (one row per destination).
      if (BetaCapabilities.advancedAi) ...[
        const LuxeSectionLabel('Trí tuệ nhân tạo (AI)'),
        LuxeSettingsGroup(
          children: [
            LuxeSettingsRow(
              icon: Icons.psychology_alt_rounded,
              title: 'AI cá nhân',
              subtitle: _developerUnlocked
                  ? 'Mô hình riêng cho từng tài khoản và xe'
                  : null,
              onTap: _openPersonalAi,
            ),
          ],
        ),
      ],
      const LuxeSectionLabel('Thông báo'),
      LuxeSettingsGroup(
        children: [
          LuxeSettingsRow(
            icon: Icons.notifications_active_rounded,
            title: 'Thông báo đẩy',
            subtitle: 'Nhận cảnh báo quan trọng trên thiết bị',
            trailing: LuxeSwitch(
              value: _pushNotifications,
              onChanged: _setPushNotifications,
              semanticLabel: 'Thông báo đẩy',
            ),
          ),
        ],
      ),
      const LuxeSectionLabel('Dữ liệu và quyền riêng tư'),
      LuxeSettingsGroup(
        children: [
          // Data lives in Firestore/the API per account; there is no
          // separate sync to switch off (the old toggle did nothing).
          const LuxeSettingsRow(
            key: ValueKey('settings-data-autosaved'),
            icon: Icons.cloud_done_rounded,
            title: 'Dữ liệu tự lưu theo tài khoản',
            subtitle:
                'Xe, lịch sử sạc và bộ nhớ Pinova Bot lưu lên máy chủ khi có mạng',
          ),
          if (_developerUnlocked)
            LuxeSettingsRow(
              icon: Icons.sync_rounded,
              title: 'Đồng bộ ngay',
              subtitle: 'Đẩy dữ liệu hiện tại lên web dashboard',
              onTap: _isLoading ? null : _manualSync,
            ),
        ],
      ),
      const LuxeSectionLabel('Ứng dụng'),
      LuxeSettingsGroup(
        children: [
          LuxeSettingsRow(
            key: const ValueKey('settings-appearance'),
            icon: Icons.palette_rounded,
            title: 'Giao diện',
            subtitle: AppearanceScreen.summary(
              ref.watch(effectiveAppearanceProvider),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
            ),
          ),
          LuxeSettingsRow(
            icon: Icons.language_rounded,
            title: 'Ngôn ngữ',
            subtitle: _getAppearanceValue(),
            onTap: _showAppearanceSheet,
          ),
        ],
      ),
      const LuxeSectionLabel('Hỗ trợ'),
      LuxeSettingsGroup(
        children: [
          LuxeSettingsRow(
            icon: Icons.info_outline_rounded,
            title: 'Giới thiệu',
            subtitle: _appVersion,
            onTap: _showAboutDialog,
          ),
        ],
      ),
      if (BetaCapabilities.developerMode && _developerUnlocked) ...[
        const LuxeSectionLabel('Developer Mode'),
        LuxeSettingsGroup(
          children: [
            LuxeSettingsRow(
              icon: Icons.auto_graph_rounded,
              title: 'Developer AI Studio',
              subtitle: 'Xem & sửa tập dữ liệu, thâm nhập quá trình fine-tune',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DeveloperAiStudioScreen()),
              ),
            ),
            LuxeSettingsRow(
              icon: Icons.developer_mode_rounded,
              title: 'Chẩn đoán ứng dụng',
              subtitle: 'Thông tin build và trạng thái kết nối an toàn',
              onTap: _showDeveloperSheet,
            ),
            LuxeSettingsRow(
              icon: Icons.tune_rounded,
              title: 'Cấu hình nâng cao Shelly',
              subtitle: 'Chế độ trực tiếp, quét subnet, token & API kỹ thuật',
              onTap: _openShellySetup,
            ),
            LuxeSettingsRow(
              icon: Icons.dataset_rounded,
              title: 'Dữ liệu fine-tune AI (Firestore)',
              subtitle: 'Xem mẫu học gốc của xe đang chọn',
              onTap: _openTrainingData,
            ),
          ],
        ),
      ],
      const SizedBox(height: 30),
      Semantics(
        button: true,
        label: BetaCapabilities.developerMode
            ? 'Phiên bản $_appVersion. Chạm bảy lần để mở Developer Mode'
            : 'Phiên bản $_appVersion',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: BetaCapabilities.developerMode ? _handleVersionTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '${BetaCapabilities.enabled ? 'BẢN BETA' : 'BẢN CHÍNH THỨC'} · $_appVersion',
                style: LuxeText.label.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.8,
                  color: LuxeColors.dim,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
                    children: [
                      const LuxeReveal(
                        child: LuxePageHeader(
                          eyebrow: 'Hệ thống',
                          title: 'Cài đặt hệ thống',
                          caption: 'Thông báo đẩy, dữ liệu và giao diện',
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (var i = 0; i < groups.length; i++)
                        LuxeReveal(
                          index: i < 8 ? i ~/ 2 + 1 : 0,
                          child: groups[i],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setPushNotifications(bool value) async {
    final enabled = await PushNotificationService.instance.setEnabledByUser(
      value,
    );
    if (!mounted) return;
    setState(() => _pushNotifications = enabled);
    if (value && !enabled) {
      AppPopup.showWarning(
        'Thông báo chưa được bật',
        detail:
            'Bạn có thể cho phép thông báo trong phần Cài đặt của thiết bị.',
        action: () => openAppSettings(),
        actionLabel: 'MỞ CÀI ĐẶT',
        userInitiated: true,
      );
    }
  }

  void _openPersonalAi() {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) {
      AppPopup.showWarning('Hãy chọn xe trước khi bật AI cá nhân');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalAiSettingsScreen(vehicleId: vehicleId),
      ),
    );
  }

  void _openTrainingData() {
    final vehicleId = ref.read(selectedVehicleIdProvider);
    if (vehicleId.isEmpty) {
      AppPopup.showWarning('Hãy chọn xe trước khi xem dữ liệu fine-tune');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalAiTrainingDataScreen(vehicleId: vehicleId),
      ),
    );
  }

  Future<void> _handleVersionTap() async {
    if (!BetaCapabilities.developerMode) return;
    if (_developerUnlocked) return;
    _versionTapCount += 1;
    final remaining = 7 - _versionTapCount;
    if (remaining > 0) {
      if (_versionTapCount >= 4) {
        AppPopup.showInfo('Chạm thêm $remaining lần để mở Developer Mode');
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('developerModeUnlocked', true);
    if (!mounted) return;
    setState(() => _developerUnlocked = true);
    AppPopup.showSuccess('Đã mở Developer Mode');
  }

  Future<void> _showAppearanceSheet() => showLuxeSheet<void>(
    context,
    isScrollControlled: true,
    builder: (_) => AppearanceSheet(settings: _settingsService),
  );

  Future<void> _showDeveloperSheet() => showLuxeSheet<void>(
    context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Developer Mode',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 16),
            _diagnosticLine('Build', _appVersion),
            _diagnosticLine('Sạc thông minh', _shellyLabel),
            SizedBox(height: 12),
            Text(
              'Cloud key, mật khẩu LAN và token đăng nhập không được hiển thị.',
              style: TextStyle(color: LuxeColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _diagnosticLine(String label, String value) => Padding(
    padding: EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: LuxeColors.muted)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  String _getAppearanceValue() {
    return switch (_settingsService.getLanguage()) {
      AppLanguage.english => 'English',
      _ => 'Tiếng Việt',
    };
  }
}
