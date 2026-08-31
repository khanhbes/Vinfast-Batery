import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/smart_charger_credentials_service.dart';
import '../../data/models/smart_charger_binding.dart';
import '../../data/repositories/smart_charger_repository.dart';
import '../../data/services/server_smart_charger_service.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cockpit_design_system.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/widgets/app_popup.dart';
import '../notifications/notification_center_screen.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'appearance_settings_screen.dart';
import 'profile_screen.dart';
import 'vehicle_garage_screen.dart';
import 'guide_screen.dart';
import 'personal_ai_settings_screen.dart';

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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SmartChargerSetupHubScreen()),
    );
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
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(40),
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
      children: const [
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
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Đăng xuất',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Hủy',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Đăng xuất'),
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
      AppPopup.showSuccess('Đã đăng xuất');
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
            ? AppColors.success
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            const Text(
              'Cài đặt',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cấu hình phương tiện, AI cá nhân và tùy chọn ứng dụng',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _buildProfileCard(),

            const SizedBox(height: 26),
            const CockpitSectionLabel('Xe và bộ sạc'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.electric_moped_rounded,
                title: 'Phương tiện',
                subtitle: 'Quản lý xe, dung lượng pin và xe đang chọn',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VehicleGarageScreen(),
                  ),
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

            const SizedBox(height: 26),
            const CockpitSectionLabel('AI và sạc'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.psychology_alt_rounded,
                title: 'AI cá nhân',
                subtitle: 'Mô hình riêng cho từng tài khoản và xe',
                onTap: _openPersonalAi,
              ),
              CockpitSettingsRow(
                icon: Icons.tune_rounded,
                title: 'Tùy chọn Smart Charge',
                subtitle: 'Giá điện, kết nối và giới hạn an toàn 10 giờ',
                onTap: _openShellySetup,
              ),
            ]),

            const SizedBox(height: 26),
            const CockpitSectionLabel('Thông báo'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.notifications_outlined,
                title: 'Trung tâm thông báo',
                subtitle: 'Cảnh báo sạc, đồng bộ và nhắc nhở',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationCenterScreen(),
                  ),
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

            const SizedBox(height: 26),
            const CockpitSectionLabel('Dữ liệu và quyền riêng tư'),
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
              const CockpitSettingsRow(
                icon: Icons.download_outlined,
                title: 'Tải dữ liệu tài khoản',
                subtitle: 'Xuất toàn bộ dữ liệu người dùng',
                availability: SettingsItemAvailability.comingSoon,
              ),
              const CockpitSettingsRow(
                icon: Icons.shield_outlined,
                title: 'Quyền riêng tư và bảo mật',
                subtitle: 'Kiểm soát dữ liệu và quyền truy cập',
                availability: SettingsItemAvailability.comingSoon,
              ),
            ]),

            const SizedBox(height: 26),
            const CockpitSectionLabel('Ứng dụng'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.palette_outlined,
                title: 'Giao diện, ngôn ngữ và đơn vị',
                subtitle: _getAppearanceValue(),
                onTap: _showAppearanceSheet,
              ),
              const CockpitSettingsRow(
                icon: Icons.fingerprint_rounded,
                title: 'Xác thực sinh trắc học',
                subtitle: 'Vân tay hoặc khuôn mặt khi mở ứng dụng',
                availability: SettingsItemAvailability.comingSoon,
              ),
            ]),

            const SizedBox(height: 26),
            const CockpitSectionLabel('Hỗ trợ'),
            _settingsGroup([
              CockpitSettingsRow(
                icon: Icons.help_outline_rounded,
                title: 'Trợ giúp',
                subtitle: 'FAQ và hướng dẫn sử dụng',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GuideScreen()),
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
              const SizedBox(height: 26),
              const CockpitSectionLabel('Developer Mode'),
              _settingsGroup([
                CockpitSettingsRow(
                  icon: Icons.developer_mode_rounded,
                  title: 'Chẩn đoán ứng dụng',
                  subtitle: 'Thông tin build và trạng thái kết nối an toàn',
                  onTap: _showDeveloperSheet,
                ),
              ]),
            ],

            const SizedBox(height: 30),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _AnimatedSignOutButton(onTap: _signOut),
            const SizedBox(height: 22),
            Semantics(
              button: true,
              label:
                  'Phiên bản $_appVersion. Chạm bảy lần để mở Developer Mode',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleVersionTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'STABLE CHANNEL $_appVersion',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
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
    );
  }

  Widget _settingsGroup(List<Widget> rows) => CockpitSurface(
    padding: const EdgeInsets.all(4),
    child: Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          rows[index],
          if (index != rows.length - 1)
            const Divider(height: 1, indent: 58, endIndent: 12),
        ],
      ],
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
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Giao diện và ngôn ngữ',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              const CockpitSectionLabel('Giao diện'),
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
              const SizedBox(height: 18),
              const CockpitSectionLabel('Ngôn ngữ'),
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
        ? CockpitColors.emerald.withValues(alpha: .10)
        : Colors.transparent,
    leading: Icon(
      icon,
      color: selected ? CockpitColors.emerald : CockpitColors.muted,
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: selected
        ? const Icon(Icons.check_circle_rounded, color: CockpitColors.emerald)
        : null,
  );

  Future<void> _showDeveloperSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
            const SizedBox(height: 16),
            _diagnosticLine('Build', _appVersion),
            _diagnosticLine('Smart Charger', _shellyLabel),
            _diagnosticLine('Auto sync', _autoSync ? 'Bật' : 'Tắt'),
            const SizedBox(height: 12),
            const Text(
              'Cloud key, mật khẩu LAN và token đăng nhập không được hiển thị.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _diagnosticLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _sectionHeader(IconData icon, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        ).then((_) {
          _loadUserProfile(); // Refresh after returning
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryContainer, AppColors.primary],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _userEmail,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── Vehicle Garage Card — PLAN #5 ─────────────────────────────

  Widget _buildVehicleGarageCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const VehicleGarageScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.electric_moped_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Garage Xe',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Quản lý xe, thêm xe mới, xem thông số',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Mở',
                style: TextStyle(
                  color: AppColors.background,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── Sync Card ─────────────────────────────────────────────────

  Widget _buildSyncCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          _buildToggleRow(
            title: 'Tự động đồng bộ',
            subtitle: 'Sync dữ liệu tự động lên web',
            value: _autoSync,
            onChanged: (v) {
              setState(() => _autoSync = v);
              _saveSetting('autoSync', v);
            },
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          _buildActionRow(
            title: 'Đồng bộ ngay',
            subtitle: 'Sync tất cả dữ liệu lên web dashboard',
            icon: Icons.sync,
            onTap: _manualSync,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── App Settings Card — PLAN #7 ───────────────────────────────

  Widget _buildAppSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          // Notifications (General)
          _buildTapRow(
            title: 'Thông báo',
            value: 'Xem tất cả thông báo',
            icon: Icons.notifications_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationCenterScreen(),
              ),
            ),
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          // Theme Toggle (Light/Dark)
          _buildTapRow(
            title: 'Giao diện & Ngôn ngữ',
            value: _getAppearanceValue(),
            icon: Icons.palette_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppearanceSettingsScreen(),
                ),
              ).then((_) {
                setState(() {}); // Refresh appearance value
              });
            },
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          // Push Notifications toggle
          _buildToggleRow(
            title: 'Thông báo đẩy',
            subtitle: 'Nhận thông báo cập nhật và nhắc nhở',
            value: _pushNotifications,
            onChanged: (v) {
              setState(() => _pushNotifications = v);
              _saveSetting('pushNotifications', v);
            },
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          _buildTapRow(
            title: 'Smart Charger',
            value: _shellyConfigured ? _shellyLabel : 'Shelly chưa kết nối',
            icon: Icons.ev_station_rounded,
            onTap: _openShellySetup,
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          _buildTapRow(
            title: 'AI cá nhân',
            value: 'Riêng cho từng xe',
            icon: Icons.psychology_alt_rounded,
            onTap: () {
              final vehicleId = ref.read(selectedVehicleIdProvider);
              if (vehicleId.isEmpty) {
                AppPopup.showWarning('Hãy chọn xe trước khi bật AI cá nhân');
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PersonalAiSettingsScreen(vehicleId: vehicleId),
                ),
              );
            },
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          // Biometric Auth — chưa phát triển: hiển thị mờ và chặn tap
          Opacity(
            opacity: 0.45,
            child: IgnorePointer(
              ignoring: true,
              child: _buildDisabledRow(
                title: 'Xác thực sinh trắc học',
                subtitle: 'FaceID / Vân tay khi mở app',
                badge: 'Sắp ra mắt',
              ),
            ),
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          // Help
          _buildTapRow(
            title: 'Trợ giúp',
            value: 'FAQ & Hướng dẫn sử dụng',
            icon: Icons.help_outline_rounded,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuideScreen()),
              );
            },
          ),
          Divider(
            color: AppColors.glassBorder,
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          // About
          _buildTapRow(
            title: 'Giới thiệu',
            value: _appVersion,
            icon: Icons.info_outline_rounded,
            onTap: _showAboutDialog,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── Helper Builders ───────────────────────────────────────────

  Widget _buildTapRow({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              color: AppColors.textTertiary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          _AnimatedToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
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

  Widget _buildDisabledRow({
    required String title,
    required String subtitle,
    required String badge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Animated Widgets
// =============================================================================

class _AnimatedToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AnimatedToggle({required this.value, required this.onChanged});

  @override
  State<_AnimatedToggle> createState() => _AnimatedToggleState();
}

class _AnimatedToggleState extends State<_AnimatedToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0,
      end: 22,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _colorAnimation = ColorTween(
      begin: AppColors.surfaceVariant,
      end: AppColors.primary,
    ).animate(_controller);

    if (widget.value) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(_AnimatedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      widget.value ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: 50,
            height: 28,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _colorAnimation.value,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: _slideAnimation.value,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
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
      duration: const Duration(milliseconds: 150),
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
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF3D2828),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.error.withAlpha(77)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout_rounded,
                color: AppColors.error.withAlpha(204),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Đăng xuất',
                style: TextStyle(
                  color: AppColors.error.withAlpha(204),
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
