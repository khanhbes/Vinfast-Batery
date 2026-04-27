import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/settings_service.dart';
import '../notifications/notification_center_screen.dart';
import 'appearance_settings_screen.dart';

// =============================================================================
// Settings Screen V4
// Profile, Vehicle Garage, Application Settings with toggles
// =============================================================================

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushNotifications = true;
  bool _autoSync = true;
  bool _darkMode = true;
  bool _biometricAuth = false;
  bool _isLoading = false;
  String _userName = 'Khanh Nhim';
  String _userEmail = 'khanhnhim2110@gmail.com';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushNotifications = prefs.getBool('pushNotifications') ?? true;
      _autoSync = prefs.getBool('autoSync') ?? true;
      _darkMode = prefs.getBool('darkMode') ?? true;
      _biometricAuth = prefs.getBool('biometricAuth') ?? false;
      _userName = prefs.getString('userName') ?? 'Khanh Nhim';
      _userEmail = prefs.getString('userEmail') ?? 'khanhnhim2110@gmail.com';
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    
    final result = await AuthService().signOut();
    
    setState(() => _isLoading = false);
    if (!mounted) return;
      
    if (result['success']) {
      // Clear providers
      ref.read(selectedVehicleIdProvider.notifier).state = '';
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Signed out successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      
      // Navigate to login (if exists) or show auth dialog
      _showAuthDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Sign out failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _showAuthDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AuthDialog(),
    );
  }

  Future<void> _manualSync() async {
    setState(() => _isLoading = true);
    
    final result = await SyncService().performFullSync();
    setState(() => _isLoading = false);
    if (!mounted) return;
      
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result['success'] ? 'Synced successfully' : 'Sync failed'),
        backgroundColor: result['success'] ? AppColors.success : AppColors.error,
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
            // App Bar
            SliverToBoxAdapter(
              child: _buildAppBar(),
            ),

            // Title Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your experience',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),
            ),

            // Profile Section
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                icon: Icons.info_outline,
                title: 'PROFILE',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProfileCard(),
              ),
            ),

            // Vehicle Garage Section
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                icon: Icons.directions_car_outlined,
                title: 'VEHICLE GARAGE',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildVehicleGarageCard(),
              ),
            ),

            // Sync Section
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                icon: Icons.sync_outlined,
                title: 'SYNC & DATA',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSyncCard(),
              ),
            ),

            // Application Settings Section
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                icon: Icons.settings_outlined,
                title: 'APPLICATION SETTINGS',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildAppSettingsCard(),
              ),
            ),

            // Sign Out Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _AnimatedSignOutButton(onTap: _signOut),
              ),
            ),

            // Version
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 100),
                child: Center(
                  child: Text(
                    'STABLE CHANNEL V2.4.1',
                    style: TextStyle(
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

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'VinFast Battery',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.primary,
            size: 16,
          ),
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
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          _buildSettingsRow(
            title: 'Personal Information',
            value: _userName.replaceAll(' ', '\n'),
            showArrow: true,
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _buildSettingsRow(
            title: 'Account Email',
            value: _userEmail,
            showArrow: true,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildVehicleGarageCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          _buildSettingsRow(
            title: 'Connection Status',
            value: 'Connected',
            valueColor: AppColors.success,
            showArrow: true,
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _buildSettingsRow(
            title: 'Model Name',
            value: 'VinFast Feliz Neo',
            showArrow: true,
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Linked Devices',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Add',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildAppSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          // Notification Center
          _buildSettingsRowTap(
            title: 'Thông báo',
            value: 'Xem tất cả thông báo',
            showArrow: true,
            onTap: () => _openNotificationCenter(),
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          // Appearance & Language
          _buildSettingsRowTap(
            title: 'Giao diện & Ngôn ngữ',
            value: _getAppearanceValue(),
            showArrow: true,
            onTap: () => _openAppearanceSettings(),
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          // Push Notifications toggle
          _buildToggleRow(
            title: 'Thông báo đẩy',
            subtitle: 'Nhận thông báo cập nhật',
            value: _pushNotifications,
            onChanged: (value) {
              setState(() => _pushNotifications = value);
              _saveSetting('pushNotifications', value);
            },
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          // Biometric Auth toggle
          _buildToggleRow(
            title: 'Xác thực sinh trắc học',
            subtitle: 'Sử dụng vân tay/Face ID',
            value: _biometricAuth,
            onChanged: (value) {
              setState(() => _biometricAuth = value);
              _saveSetting('biometricAuth', value);
            },
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _buildSettingsRowWithButton(
            title: 'User Manual',
            buttonText: 'Open',
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _buildSettingsRowWithButton(
            title: 'Technical Support',
            buttonText: 'Contact',
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildSettingsRow({
    required String title,
    required String value,
    Color? valueColor,
    bool showArrow = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
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
            style: TextStyle(
              color: valueColor ?? AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
          if (showArrow) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsRowWithButton({
    required String title,
    required String buttonText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              buttonText,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          _buildToggleRow(
            title: 'Auto Sync to Web',
            subtitle: 'Sync data automatically',
            value: _autoSync,
            onChanged: (value) {
              setState(() => _autoSync = value);
              _saveSetting('autoSync', value);
            },
          ),
          Divider(color: AppColors.glassBorder, height: 1, indent: 20, endIndent: 20),
          _buildActionRow(
            title: 'Manual Sync Now',
            subtitle: 'Sync all data to web dashboard',
            icon: Icons.sync,
            onTap: _manualSync,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 150.ms).scale(begin: const Offset(0.95, 0.95));
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
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          _AnimatedToggle(
            value: value,
            onChanged: onChanged,
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  // ── Navigation helpers ─────────────────────────────────────────

  void _openNotificationCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
    );
  }

  void _openAppearanceSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
    );
  }

  String _getAppearanceValue() {
    final settings = SettingsService();
    final themeMode = settings.getThemeMode();
    final language = settings.getLanguage();
    
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

  // ── Settings row with tap handler ─────────────────────────────

  Widget _buildSettingsRowTap({
    required String title,
    required String value,
    bool showArrow = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                color: AppColors.textTertiary,
                size: 14,
              ),
            ],
          ],
        ),
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

  const _AnimatedToggle({
    required this.value,
    required this.onChanged,
  });

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
    
    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_AnimatedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
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
            borderRadius: BorderRadius.circular(24),
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
                'Sign Out',
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

class _AuthDialog extends StatefulWidget {
  const _AuthDialog();

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() => _isLoading = true);

    final result = _isSignUp
        ? await AuthService().registerWithEmail(
            email: _emailController.text,
            password: _passwordController.text,
            name: 'User',
          )
        : await AuthService().signInWithEmail(
            email: _emailController.text,
            password: _passwordController.text,
          );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success']) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isSignUp ? 'Account created!' : 'Welcome back!'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Authentication failed'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isSignUp ? 'Create Account' : 'Sign In',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: const TextStyle(color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator(color: AppColors.primary)
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _authenticate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isSignUp ? 'Sign Up' : 'Sign In',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isSignUp = !_isSignUp),
              child: Text(
                _isSignUp ? 'Already have an account? Sign In' : 'Don\'t have an account? Sign Up',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
