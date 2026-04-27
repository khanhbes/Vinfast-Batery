import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_colors.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  final _settings = SettingsService();
  AppThemeMode _themeMode = AppThemeMode.system;
  AppLanguage _language = AppLanguage.system;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settings.initialize();
    setState(() {
      _themeMode = _settings.getThemeMode();
      _language = _settings.getLanguage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Giao diện & Ngôn ngữ',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Section
          _buildSectionTitle('Giao diện'),
          const SizedBox(height: 8),
          _buildThemeCard(),
          const SizedBox(height: 24),

          // Language Section
          _buildSectionTitle('Ngôn ngữ'),
          const SizedBox(height: 8),
          _buildLanguageCard(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildThemeCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildThemeOption(
            icon: Icons.brightness_auto,
            title: 'Theo hệ thống',
            subtitle: 'Tự động theo cài đặt hệ thống',
            value: AppThemeMode.system,
          ),
          Divider(height: 1, color: AppColors.border),
          _buildThemeOption(
            icon: Icons.light_mode,
            title: 'Sáng',
            subtitle: 'Giao diện sáng',
            value: AppThemeMode.light,
          ),
          Divider(height: 1, color: AppColors.border),
          _buildThemeOption(
            icon: Icons.dark_mode,
            title: 'Tối',
            subtitle: 'Giao diện tối',
            value: AppThemeMode.dark,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required AppThemeMode value,
  }) {
    final isSelected = _themeMode == value;
    return ListTile(
      onTap: () => _setThemeMode(value),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withAlpha(30)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.primary)
          : const SizedBox(width: 24),
    );
  }

  Widget _buildLanguageCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildLanguageOption(
            flag: '🌐',
            title: 'Theo hệ thống',
            subtitle: 'System language',
            value: AppLanguage.system,
          ),
          Divider(height: 1, color: AppColors.border),
          _buildLanguageOption(
            flag: '🇻🇳',
            title: 'Tiếng Việt',
            subtitle: 'Vietnamese',
            value: AppLanguage.vietnamese,
          ),
          Divider(height: 1, color: AppColors.border),
          _buildLanguageOption(
            flag: '🇬🇧',
            title: 'English',
            subtitle: 'English',
            value: AppLanguage.english,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption({
    required String flag,
    required String title,
    required String subtitle,
    required AppLanguage value,
  }) {
    final isSelected = _language == value;
    return ListTile(
      onTap: () => _setLanguage(value),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withAlpha(30)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(flag, style: const TextStyle(fontSize: 20)),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.primary)
          : const SizedBox(width: 24),
    );
  }

  Future<void> _setThemeMode(AppThemeMode mode) async {
    await _settings.setThemeMode(mode);
    setState(() => _themeMode = mode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã thay đổi giao diện. Khởi động lại app để áp dụng.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _setLanguage(AppLanguage language) async {
    await _settings.setLanguage(language);
    setState(() => _language = language);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã thay đổi ngôn ngữ. Khởi động lại app để áp dụng.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
