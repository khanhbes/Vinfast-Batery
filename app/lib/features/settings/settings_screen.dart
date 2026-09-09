import 'package:flutter/material.dart';
import '../../core/widgets/settings_reveal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/smart_charger_credentials_service.dart';
import '../../data/models/smart_charger_binding.dart';
import '../../data/repositories/smart_charger_repository.dart';
import '../../data/services/server_smart_charger_service.dart';

import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/widgets/app_popup.dart';
import '../auth/auth_gate.dart';
import '../notifications/notification_center_screen.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'profile_screen.dart';
import 'vehicle_garage_screen.dart';
import 'guide_screen.dart';
import 'personal_ai_settings_screen.dart';
import 'personal_ai_training_data_screen.dart';
import 'developer_ai_studio_screen.dart';

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
  bool _pushNotifications = true;
  bool _autoSync = true;
  bool _isLoading = false;
  String _userName = '...';
  String _userEmail = '...';
  String _appVersion = '...';
  bool _shellyConfigured = false;
  String _shellyLabel = 'Shelly chưa kết nối';
  bool _developerUnlocked = false;
  int _versionTapCount = 0;

  final _settingsService = SettingsService();
  final _smartChargerCredentials = SmartChargerCredentialsService();

  @override
  void initState() {
    super.initState();
    _settingsService.addListener(_onSettingsChanged);
    _settingsService.initialize();
    _loadSettings();
    _loadAppVersion();
    _loadUserProfile();
    _loadShellyState();
  }

  Future<void> _loadShellyState() async {
    final mode = await SmartChargerRepositoryFactory.currentMode();
    var configured = false;
    var label = 'Shelly chưa kết nối';
    if (mode == SmartChargerConnectionMode.advancedDirect) {
      configured = await _smartChargerCredentials.readProfile() != null;
      if (configured) label = 'Advanced Direct · Cloud/LAN';
    } else {
      try {
        final binding = await ServerSmartChargerService().getBinding();
        configured = binding != null;
        if (binding != null) label = 'Server Cloud · ${binding.displayName}';
      } on Object {
        // Setup Hub displays the actionable server error.
      }
    }
    if (mounted) {
      setState(() {
        _shellyConfigured = configured;
        _shellyLabel = label;
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
    _settingsService.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pushNotifications = prefs.getBool('pushNotifications') ?? true;
      _autoSync = prefs.getBool('autoSync') ?? true;
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

  /// PLAN #3 — Load user profile from Firestore
  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final data = await AuthService().getCurrentUserData();
      if (!mounted) return;
      setState(() {
        _userName = data?['name'] ?? user?.displayName ?? 'Người dùng';
        _userEmail = data?['email'] ?? user?.email ?? '';
      });
    } catch (_) {}
  }

  /// Show About dialog with app info
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'VinFast Battery',
      applicationVersion: _appVersion,
      applicationLegalese:
          '© 2026 VinFast Battery. Hệ thống quản lý pin xe điện.',
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

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppUiColors.of(context).surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Đăng xuất',
          style: TextStyle(color: AppUiColors.of(context).text),
        ),
        content: Text(
          'Bạn có chắc chắn muốn đăng xuất?',
          style: TextStyle(color: AppUiColors.of(context).muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Hủy',
              style: TextStyle(color: AppUiColors.of(context).muted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUiColors.of(context).danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    final result = await AuthService().signOut();
    setState(() => _isLoading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      ref.read(selectedVehicleIdProvider.notifier).state = '';
      ref.read(currentTabProvider.notifier).state = 0;

      // FirebaseAuth.authStateChanges normally makes the root AuthGate show
      // LoginScreen. Replace the complete navigator stack as well so logout
      // is immediate even if a nested page is still transitioning, and the
      // Back button can never return to account data.
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => AuthGate()),
        (_) => false,
      );
    } else {
      AppPopup.showError(result['error'] ?? 'Đăng xuất thất bại');
    }
  }

  Future<void> _manualSync() async {
    setState(() => _isLoading = true);
    final result = await SyncService().performFullSync();
    setState(() => _isLoading = false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true ? 'Đồng bộ thành công' : 'Đồng bộ thất bại',
        ),
        backgroundColor: result['success'] == true
            ? AppUiColors.of(context).primary
            : AppUiColors.of(context).danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUiColors.of(context).background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(
              'Cài đặt',
              style: TextStyle(
                color: AppUiColors.of(context).text,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Cấu hình phương tiện, AI cá nhân và tùy chọn ứng dụng',
              style: TextStyle(
                color: AppUiColors.of(context).muted,
                fontSize: 13,
              ),
            ),
            SizedBox(height: 20),
            _buildProfileCard(),

            SizedBox(height: 26),
            CockpitSectionLabel('Xe và bộ sạc'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.electric_moped_rounded,
                title: 'Phương tiện',
                subtitle: 'Quản lý xe, dung lượng pin và xe đang chọn',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VehicleGarageScreen()),
                ),
              ),
              CockpitSettingsRow(
                icon: Icons.ev_station_rounded,
                title: 'Smart Charger',
                subtitle: _shellyConfigured
                    ? _shellyLabel
                    : 'Shelly chưa kết nối',
                onTap: _openShellySetup,
              ),
            ]),

            SizedBox(height: 26),
            CockpitSectionLabel('Trí tuệ nhân tạo (AI)'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.psychology_alt_rounded,
                title: 'AI cá nhân',
                subtitle: 'Mô hình riêng cho từng tài khoản và xe',
                onTap: _openPersonalAi,
              ),
            ]),

            SizedBox(height: 26),
            CockpitSectionLabel('Thông báo'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.notifications_outlined,
                title: 'Trung tâm thông báo',
                subtitle: 'Cảnh báo sạc, đồng bộ và nhắc nhở',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NotificationCenterScreen()),
                ),
              ),
              CockpitSettingsRow(
                icon: Icons.notifications_active_outlined,
                title: 'Thông báo đẩy',
                subtitle: 'Nhận cảnh báo quan trọng trên thiết bị',
                trailing: _AnimatedToggle(
                  value: _pushNotifications,
                  onChanged: _setPushNotifications,
                ),
                onTap: () => _setPushNotifications(!_pushNotifications),
              ),
            ]),

            SizedBox(height: 26),
            CockpitSectionLabel('Dữ liệu và quyền riêng tư'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.cloud_sync_outlined,
                title: 'Tự động đồng bộ',
                subtitle: 'Đồng bộ dữ liệu với web khi có mạng',
                trailing: _AnimatedToggle(
                  value: _autoSync,
                  onChanged: _setAutoSync,
                ),
                onTap: () => _setAutoSync(!_autoSync),
              ),
              CockpitSettingsRow(
                icon: Icons.sync_rounded,
                title: 'Đồng bộ ngay',
                subtitle: 'Đẩy dữ liệu hiện tại lên web dashboard',
                onTap: _isLoading ? null : _manualSync,
              ),
              CockpitSettingsRow(
                icon: Icons.download_outlined,
                title: 'Tải dữ liệu tài khoản',
                subtitle: 'Xuất toàn bộ dữ liệu người dùng',
                availability: SettingsItemAvailability.comingSoon,
              ),
              CockpitSettingsRow(
                icon: Icons.shield_outlined,
                title: 'Quyền riêng tư và bảo mật',
                subtitle: 'Kiểm soát dữ liệu và quyền truy cập',
                availability: SettingsItemAvailability.comingSoon,
              ),
            ]),

            SizedBox(height: 26),
            CockpitSectionLabel('Ứng dụng'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.palette_outlined,
                title: 'Giao diện, ngôn ngữ và đơn vị',
                subtitle: _getAppearanceValue(),
                onTap: _showAppearanceSheet,
              ),
              CockpitSettingsRow(
                icon: Icons.fingerprint_rounded,
                title: 'Xác thực sinh trắc học',
                subtitle: 'Vân tay hoặc khuôn mặt khi mở ứng dụng',
                availability: SettingsItemAvailability.comingSoon,
              ),
            ]),

            SizedBox(height: 26),
            CockpitSectionLabel('Hỗ trợ'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.help_outline_rounded,
                title: 'Trợ giúp',
                subtitle: 'FAQ và hướng dẫn sử dụng',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => GuideScreen()),
                ),
              ),
              CockpitSettingsRow(
                icon: Icons.info_outline_rounded,
                title: 'Giới thiệu',
                subtitle: _appVersion,
                onTap: _showAboutDialog,
              ),
            ]),

            if (_developerUnlocked) ...[
              SizedBox(height: 26),
              CockpitSectionLabel('Developer Mode'),
              _settingsGroup([
                CockpitSettingsRow(
                  icon: Icons.auto_graph_rounded,
                  title: 'Developer AI Studio',
                  subtitle:
                      'Xem & sửa tập dữ liệu, thâm nhập quá trình fine-tune',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeveloperAiStudioScreen(),
                    ),
                  ),
                ),
                CockpitSettingsRow(
                  icon: Icons.developer_mode_rounded,
                  title: 'Chẩn đoán ứng dụng',
                  subtitle: 'Thông tin build và trạng thái kết nối an toàn',
                  onTap: _showDeveloperSheet,
                ),
                CockpitSettingsRow(
                  icon: Icons.dataset_outlined,
                  title: 'Dữ liệu fine-tune AI (Firestore)',
                  subtitle: 'Xem mẫu học gốc của xe đang chọn',
                  onTap: _openTrainingData,
                ),
              ]),
            ],

            SizedBox(height: 30),
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : _AnimatedSignOutButton(onTap: _signOut),
            SizedBox(height: 22),
            Semantics(
              button: true,
              label:
                  'Phiên bản $_appVersion. Chạm bảy lần để mở Developer Mode',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleVersionTap,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'STABLE CHANNEL $_appVersion',
                      style: TextStyle(
                        color: AppUiColors.of(context).muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Widget _settingsGroup(List<Widget> rows) => SettingsReveal(
    child: CockpitSurface(
      color: AppUiColors.of(context).surface,
      padding: EdgeInsets.all(4),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index != rows.length - 1)
              Divider(height: 1, indent: 58, endIndent: 12),
          ],
        ],
      ),
    ),
  );

  void _setPushNotifications(bool value) {
    setState(() => _pushNotifications = value);
    _saveSetting('pushNotifications', value);
  }

  void _setAutoSync(bool value) {
    setState(() => _autoSync = value);
    _saveSetting('autoSync', value);
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

  Future<void> _showAppearanceSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppUiColors.of(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Giao diện và ngôn ngữ',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 18),
              CockpitSectionLabel('Giao diện'),
              _sheetChoice(
                context,
                icon: Icons.light_mode_rounded,
                title: 'Sáng',
                selected: _settingsService.getThemeMode() == AppThemeMode.light,
                onTap: () async {
                  await _settingsService.setThemeMode(AppThemeMode.light);
                  if (context.mounted) setSheetState(() {});
                },
              ),
              _sheetChoice(
                context,
                icon: Icons.brightness_auto_rounded,
                title: 'Theo hệ thống',
                selected:
                    _settingsService.getThemeMode() == AppThemeMode.system,
                onTap: () async {
                  await _settingsService.setThemeMode(AppThemeMode.system);
                  if (context.mounted) setSheetState(() {});
                },
              ),
              _sheetChoice(
                context,
                icon: Icons.dark_mode_rounded,
                title: 'Dark Cockpit',
                selected: _settingsService.getThemeMode() == AppThemeMode.dark,
                onTap: () async {
                  await _settingsService.setThemeMode(AppThemeMode.dark);
                  setSheetState(() {});
                },
              ),
              _sheetChoice(
                context,
                icon: Icons.brightness_2_rounded,
                title: 'AMOLED',
                selected:
                    _settingsService.getThemeMode() == AppThemeMode.amoled,
                onTap: () async {
                  await _settingsService.setThemeMode(AppThemeMode.amoled);
                  setSheetState(() {});
                },
              ),
              SizedBox(height: 18),
              CockpitSectionLabel('Ngôn ngữ'),
              _sheetChoice(
                context,
                icon: Icons.language_rounded,
                title: 'Tiếng Việt',
                selected:
                    _settingsService.getLanguage() == AppLanguage.vietnamese,
                onTap: () async {
                  await _settingsService.setLanguage(AppLanguage.vietnamese);
                  setSheetState(() {});
                },
              ),
              _sheetChoice(
                context,
                icon: Icons.translate_rounded,
                title: 'English',
                selected: _settingsService.getLanguage() == AppLanguage.english,
                onTap: () async {
                  await _settingsService.setLanguage(AppLanguage.english);
                  setSheetState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sheetChoice(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) => ListTile(
    onTap: onTap,
    minTileHeight: 56,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    tileColor: selected
        ? AppUiColors.of(context).primary.withValues(alpha: .10)
        : Colors.transparent,
    leading: Icon(
      icon,
      color: selected
          ? AppUiColors.of(context).primary
          : AppUiColors.of(context).muted,
    ),
    title: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
    trailing: selected
        ? Icon(
            Icons.check_circle_rounded,
            color: AppUiColors.of(context).primary,
          )
        : null,
  );

  Future<void> _showDeveloperSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppUiColors.of(context).surface,
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
            _diagnosticLine('Smart Charger', _shellyLabel),
            _diagnosticLine('Auto sync', _autoSync ? 'Bật' : 'Tắt'),
            SizedBox(height: 12),
            Text(
              'Cloud key, mật khẩu LAN và token đăng nhập không được hiển thị.',
              style: TextStyle(
                color: AppUiColors.of(context).muted,
                fontSize: 12,
              ),
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
          child: Text(
            label,
            style: TextStyle(color: AppUiColors.of(context).muted),
          ),
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

  // ── Profile Card — PLAN #3 ─────────────────────────────────────

  Widget _buildProfileCard() {
    final initials = _userName.isNotEmpty && _userName != '...'
        ? _userName
              .split(' ')
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfileScreen()),
        ).then((_) {
          _loadUserProfile(); // Refresh after returning
        });
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppUiColors.of(context).surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppUiColors.of(context).borderStrong),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppUiColors.of(context).primarySurface,
                    AppUiColors.of(context).primary,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUiColors.of(context).text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    _userEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppUiColors.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppUiColors.of(context).muted,
              size: 22,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: Offset(0.95, 0.95));
  }

  String _getAppearanceValue() {
    final themeMode = _settingsService.getThemeMode();
    final language = _settingsService.getLanguage();

    final themeText = switch (themeMode) {
      AppThemeMode.system => 'Hệ thống',
      AppThemeMode.light => 'Sáng',
      AppThemeMode.dark => 'Tối',
      AppThemeMode.amoled => 'AMOLED',
    };

    final langText = switch (language) {
      AppLanguage.system => 'Auto',
      AppLanguage.vietnamese => 'VN',
      AppLanguage.english => 'EN',
    };

    return '$themeText • $langText';
  }
}

// =============================================================================
// Animated Widgets
// =============================================================================

class _AnimatedToggle extends StatelessWidget {
  const _AnimatedToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Switch.adaptive(
    value: value,
    onChanged: onChanged,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

class _AnimatedSignOutButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AnimatedSignOutButton({required this.onTap});

  @override
  State<_AnimatedSignOutButton> createState() => _AnimatedSignOutButtonState();
}

class _AnimatedSignOutButtonState extends State<_AnimatedSignOutButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Color(0xFF3D2828),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppUiColors.of(context).danger.withAlpha(77),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout_rounded,
                color: AppUiColors.of(context).danger.withAlpha(204),
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Đăng xuất',
                style: TextStyle(
                  color: AppUiColors.of(context).danger.withAlpha(204),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2);
  }
}
