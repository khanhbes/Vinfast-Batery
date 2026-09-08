import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  final _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    // initialize() an toàn: guản nội bộ đã kiểm tra bằng `_initialized`.
    _settings.initialize();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  AppThemeMode get _themeMode => _settings.getThemeMode();
  AppLanguage get _language => _settings.getLanguage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Giao diện & Ngôn ngữ',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Theme Section
          _buildSectionTitle('Giao diện'),
          SizedBox(height: 8),
          _buildThemeCard(),
          SizedBox(height: 24),

          // Language Section
          _buildSectionTitle('Ngôn ngữ'),
          SizedBox(height: 8),
          _buildLanguageCard(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildThemeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _buildThemeOption(
            icon: Icons.brightness_auto_rounded,
            title: 'Theo hệ thống',
            subtitle: 'Tự đổi sáng và tối theo thiết bị',
            value: AppThemeMode.system,
          ),
          _buildThemeOption(
            icon: Icons.light_mode_rounded,
            title: 'Sáng',
            subtitle: 'Nền sáng, chữ rõ và điểm nhấn xanh',
            value: AppThemeMode.light,
          ),
          _buildThemeOption(
            icon: Icons.dark_mode,
            title: 'Dark Cockpit',
            subtitle: 'Nền gần đen, cân bằng độ tương phản',
            value: AppThemeMode.dark,
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _buildThemeOption(
            icon: Icons.brightness_2_rounded,
            title: 'AMOLED',
            subtitle: 'Nền đen tuyệt đối, tiết kiệm pin màn hình OLED',
            value: AppThemeMode.amoled,
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
              ? Theme.of(context).colorScheme.primary.withAlpha(30)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : SizedBox(width: 24),
    );
  }

  Widget _buildLanguageCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _buildLanguageOption(
            flag: '🌐',
            title: 'Theo hệ thống',
            subtitle: 'System language',
            value: AppLanguage.system,
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _buildLanguageOption(
            flag: '🇻🇳',
            title: 'Tiếng Việt',
            subtitle: 'Vietnamese',
            value: AppLanguage.vietnamese,
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
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
              ? Theme.of(context).colorScheme.primary.withAlpha(30)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Text(flag, style: TextStyle(fontSize: 20))),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : SizedBox(width: 24),
    );
  }

  Future<void> _setThemeMode(AppThemeMode mode) async {
    await _settings.setThemeMode(mode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã áp dụng giao diện mới'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setLanguage(AppLanguage language) async {
    await _settings.setLanguage(language);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã áp dụng ngôn ngữ mới'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
