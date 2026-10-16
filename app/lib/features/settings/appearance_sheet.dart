import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/luxe_settings.dart';

/// Language picker. The app renders the dark LUXE language only (Task 117),
/// so the sheet states that instead of offering light/AMOLED modes.
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GIAO DIỆN', style: LuxeText.eyebrow),
            const SizedBox(height: 6),
            Text(
              'Giao diện và ngôn ngữ',
              style: LuxeText.title.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              'VinFast Battery dùng một giao diện tối Platinum duy nhất để '
              'mọi màn hình đồng bộ và dễ đọc khi sạc ban đêm.',
              style: LuxeText.caption,
            ),
            const LuxeSectionLabel('Ngôn ngữ'),
            LuxeSettingsGroup(
              children: [
                // English is hidden until the app content is translated
                // (Task 125); a half-English UI was misleading.
                for (final (language, title, icon) in const [
                  (
                    AppLanguage.vietnamese,
                    'Tiếng Việt',
                    Icons.language_rounded,
                  ),
                ])
                  LuxeSettingsRow(
                    icon: icon,
                    title: title,
                    accent: settings.getLanguage() == language
                        ? LuxeColors.emerald
                        : null,
                    trailing: AnimatedOpacity(
                      opacity: settings.getLanguage() == language ? 1 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: LuxeColors.emerald,
                      ),
                    ),
                    onTap: () => unawaited(settings.setLanguage(language)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Hiện ứng dụng chỉ có tiếng Việt.',
              key: const ValueKey('appearance-vietnamese-only'),
              style: LuxeText.caption,
            ),
          ],
        ),
      ),
    ),
  );
}
