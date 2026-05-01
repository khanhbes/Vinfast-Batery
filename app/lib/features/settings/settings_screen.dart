import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/widgets/app_popup.dart';
import '../notifications/notification_center_screen.dart';
import 'appearance_settings_screen.dart';
import 'profile_screen.dart';
import 'vehicle_garage_screen.dart';
import 'guide_screen.dart';

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
  bool _biometricAuth = false;
  bool _isLoading = false;
  String _userName = '...';
  String _userEmail = '...';
  String _appVersion = '...';

  final _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _settingsService.addListener(_onSettingsChanged);
    _settingsService.initialize();
    _loadSettings();
    _loadAppVersion();
    _loadUserProfile();
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
      _biometricAuth = prefs.getBool('biometricAuth') ?? false;
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
      applicationLegalese: '© 2026 VinFast Battery. Hệ thống quản lý pin xe điện.',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.electric_bolt_rounded, color: AppColors.primary, size: 32),
      ),
      children: const [
        SizedBox(height: 12),
        Text('Theo dõi sức khỏe pin, dự đoán thời gian sạc và lên kế hoạch chuyến đi với AI.'),
      ],
    );
  }

  /// PLAN #7 — Show "Coming Soon" snackbar
  void _showComingSoon(String featureName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.construction_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('$featureName: Đang phát triển — sẽ ra mắt sớm!')),
          ],
        ),
        backgroundColor: AppColors.primaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
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
        title: const Text('Đăng xuất', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        content: Text(result['success'] == true ? 'Đồng bộ thành công' : 'Đồng bộ thất bại'),
        backgroundColor: result['success'] == true ? AppColors.success : AppColors.error,
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
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cài đặt',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Quản lý tài khoản & cài đặt ứng dụng',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
            ),

            // Profile Section — PLAN #3
            _sectionHeader(Icons.person_outline_rounded, 'HỒ SƠ'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProfileCard(),
              ),
            ),

            // Vehicle Garage — PLAN #5
            _sectionHeader(Icons.directions_car_outlined, 'GARAGE XE'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildVehicleGarageCard(),
              ),
            ),

            // Sync Section
            _sectionHeader(Icons.sync_outlined, 'ĐỒNG BỘ'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSyncCard(),
              ),
            ),

            // Application Settings — PLAN #7
            _sectionHeader(Icons.settings_outlined, 'CÀI ĐẶT ỨNG DỤNG'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildAppSettingsCard(),
              ),
            ),

            // Sign Out
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _AnimatedSignOutButton(onTap: _signOut),
              ),
            ),

            // Version — PLAN #8
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 100),
                child: Center(
                  child: Text(
                    'STABLE CHANNEL $_appVersion',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
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
        ? _userName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())).then((_) {
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
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
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
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 22),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ── Vehicle Garage Card — PLAN #5 ─────────────────────────────

  Widget _buildVehicleGarageCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const VehicleGarageScreen()));
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
              child: const Icon(Icons.electric_moped_rounded, color: AppColors.primary, size: 24),
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
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),

          // Theme Toggle (Light/Dark)
          _buildTapRow(
            title: 'Giao diện & Ngôn ngữ',
            value: _getAppearanceValue(),
            icon: Icons.palette_outlined,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen())).then((_) {
                setState(() {}); // Refresh appearance value
              });
            },
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),

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
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),

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
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),

          // Help
          _buildTapRow(
            title: 'Trợ giúp',
            value: 'FAQ & Hướng dẫn sử dụng',
            icon: Icons.help_outline_rounded,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen()));
            },
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),

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
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              value,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, color: AppColors.textTertiary, size: 14),
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
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
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
                  Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
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
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
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
    _slideAnimation = Tween<double>(begin: 0, end: 22).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
                        BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
              Icon(Icons.logout_rounded, color: AppColors.error.withAlpha(204), size: 18),
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
