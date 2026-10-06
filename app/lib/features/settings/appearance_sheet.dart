import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/theme/cockpit_design_system.dart';

/// Listens while mounted; persistence finishing after dismissal never calls
/// setState on a closed sheet. SettingsService owns persistence/error handling.
class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({super.key, required this.settings});
  final SettingsService settings;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Giao diện và ngôn ngữ',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const CockpitSectionLabel('Giao diện'),
            for (final (mode, title, icon) in const [
              (AppThemeMode.light, 'Sáng', Icons.light_mode_rounded),
              (
                AppThemeMode.system,
                'Theo hệ thống',
                Icons.brightness_auto_rounded,
              ),
              (AppThemeMode.dark, 'Dark Cockpit', Icons.dark_mode_rounded),
              (AppThemeMode.amoled, 'AMOLED', Icons.brightness_2_rounded),
            ])
              _choice(
                context,
                title,
                icon,
                settings.getThemeMode() == mode,
                () => unawaited(settings.setThemeMode(mode)),
              ),
            const SizedBox(height: 18),
            const CockpitSectionLabel('Ngôn ngữ'),
            for (final (language, title, icon) in const [
              (AppLanguage.vietnamese, 'Tiếng Việt', Icons.language_rounded),
              (AppLanguage.english, 'English', Icons.translate_rounded),
            ])
              _choice(
                context,
                title,
                icon,
                settings.getLanguage() == language,
                () => unawaited(settings.setLanguage(language)),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _choice(
    BuildContext context,
    String title,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    final colors = AppUiColors.of(context);
    return ListTile(
      onTap: onTap,
      minTileHeight: 56,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: selected
          ? colors.primary.withValues(alpha: .10)
          : Colors.transparent,
      leading: Icon(icon, color: selected ? colors.primary : colors.muted),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: colors.primary)
          : null,
    );
  }
}
