import 'package:flutter/material.dart';

import '../../core/services/installed_version.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../ai/bot_release.dart';
import '../ai/services/assistant_api.dart';
import 'privacy_consent.dart';

/// "Giới thiệu" (QA 163): the app's version, Pinova Bot's own version with
/// what changed in each, the server bot's version when it answers, and the
/// public pages. It replaced Material's about dialog (not LUXE).
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.serverVersion});

  /// Tests: the server bot's version without a call.
  final Future<String?>? serverVersion;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<String?> _server = widget.serverVersion ?? _readServer();
  late final Set<String> _open = {PinovaBotRelease.current};

  static Future<String?> _readServer() async {
    final api = AssistantApi(timeout: const Duration(seconds: 8));
    try {
      return (await api.settings()).botVersion;
    } on Object {
      return null;
    } finally {
      api.close();
    }
  }

  @override
  void initState() {
    super.initState();
    PinovaBotRelease.markSeen();
  }

  @override
  Widget build(BuildContext context) => LuxeScaffold(
    title: 'Giới thiệu',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Center(child: Text('Pinova', style: LuxeText.title)),
        const SizedBox(height: 4),
        Center(
          child: FutureBuilder<String?>(
            future: installedVersion,
            builder: (context, snapshot) => Text(
              snapshot.data == null
                  ? 'Quản lý pin và sạc xe máy điện'
                  : 'Phiên bản ${snapshot.data}',
              key: const ValueKey('about-app-version'),
              style: LuxeText.caption,
            ),
          ),
        ),
        const SizedBox(height: 20),
        LuxeGlass(
          key: const ValueKey('about-bot'),
          raised: true,
          radius: 24,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 48,
                child: BatteryBotMascot(
                  displayMode: BatteryBotDisplayMode.avatar,
                  size: BatteryBotSize.avatar,
                  customWidth: 48,
                  mood: BatteryBotMood.happy,
                  enableFloating: false,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pinova Bot ${PinovaBotRelease.current}',
                      key: const ValueKey('about-bot-version'),
                      style: LuxeText.item,
                    ),
                    const SizedBox(height: 2),
                    FutureBuilder<String?>(
                      future: _server,
                      builder: (context, snapshot) => Text(
                        snapshot.data == null
                            ? 'Trợ lý pin & sạc của Pinova'
                            : 'Máy chủ Bot ${snapshot.data}',
                        key: const ValueKey('about-bot-server'),
                        style: LuxeText.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const LuxeSectionLabel('Có gì mới ở Pinova Bot'),
        for (final release in PinovaBotRelease.releases) ...[
          LuxeGlass(
            quiet: true,
            radius: 20,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  expanded: _open.contains(release.version),
                  child: InkWell(
                    key: ValueKey('about-release-${release.version}'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() {
                      _open.contains(release.version)
                          ? _open.remove(release.version)
                          : _open.add(release.version);
                    }),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Phiên bản ${release.version}',
                                    style: LuxeText.item,
                                  ),
                                  Text(release.date, style: LuxeText.caption),
                                ],
                              ),
                            ),
                            Icon(
                              _open.contains(release.version)
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: LuxeColors.platinumMid,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                LuxeFold(
                  alignment: Alignment.topCenter,
                  child: !_open.contains(release.version)
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final change in release.changes)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 7),
                                        child: Icon(
                                          Icons.circle,
                                          size: 5,
                                          color: LuxeColors.platinumMid,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          change,
                                          style: LuxeText.body,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        const LuxeSectionLabel('Thông tin'),
        const LuxeSettingsGroup(
          children: [
            LuxeSettingsRow(
              icon: Icons.description_rounded,
              title: 'Điều khoản sử dụng',
              onTap: PrivacyConsent.openTerms,
            ),
            LuxeSettingsRow(
              icon: Icons.privacy_tip_rounded,
              title: 'Chính sách bảo mật',
              onTap: PrivacyConsent.openPolicy,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '© 2026 Pinova. Quản lý pin và sạc xe máy điện.',
          textAlign: TextAlign.center,
          style: LuxeText.caption,
        ),
      ],
    ),
  );
}
