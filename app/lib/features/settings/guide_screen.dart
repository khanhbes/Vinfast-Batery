import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/guide_registry.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../navigation/app_navigation.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import '../ai/assistant_sheet.dart';

/// Luxe quick guide: a tour hero, expandable feature cards with numbered
/// steps on a hairline rail, and a BatteryBot entry. Bilingual (vi/en).
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String? _expandedId;

  void _replayTour() {
    AppNavigation.replayOverviewTour(context);
  }

  void _open(GuideDestination destination) {
    if (destination.tabIndex case final index?) {
      AppNavigation.openTab(context, index);
      return;
    }
    // One BatteryBot (Task 125): the main assistant sheet, which also has
    // the on-device basic mode offline. push, not pushReplacement, so Back
    // returns to the guide.
    if (destination == GuideDestination.batteryBot) {
      InteractiveAssistantSheet.show(context);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SmartChargerSetupHubScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    return Theme(
      data: LuxeTheme.of(context),
      child: Scaffold(
        backgroundColor: LuxeColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LuxeBackdrop(),
            SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    sliver: SliverToBoxAdapter(
                      child: LuxeReveal(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tooltip(
                              message: isEn ? 'Back' : 'Quay lại',
                              child: Material(
                                type: MaterialType.transparency,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: LuxeColors.glass,
                                      border: Border.all(
                                        color: LuxeColors.hairline,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 20,
                                      color: LuxeColors.text,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              isEn ? 'GUIDE' : 'HƯỚNG DẪN',
                              style: LuxeText.eyebrow,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isEn ? 'Quick guide' : 'Hướng dẫn nhanh',
                              style: LuxeText.title,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isEn
                                  ? 'Learn the main actions, one step at a time.'
                                  : 'Tìm nhanh chức năng bạn cần, từng bước một.',
                              style: LuxeText.caption,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: LuxeReveal(
                        index: 1,
                        child: _TourBanner(isEn: isEn, onPressed: _replayTour),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LuxeSectionLabel(
                        isEn ? 'Learn a feature' : 'Chọn chức năng để xem',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverList.separated(
                      itemCount: GuideRegistry.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = GuideRegistry.items[index];
                        return LuxeReveal(
                          index: index < 6 ? index + 2 : 0,
                          child: _GuideSection(
                            item: item,
                            isEn: isEn,
                            expanded: _expandedId == item.id,
                            onToggle: () {
                              HapticFeedback.selectionClick();
                              setState(
                                () => _expandedId = _expandedId == item.id
                                    ? null
                                    : item.id,
                              );
                            },
                            onOpen: () => _open(item.destination),
                          ),
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    sliver: SliverToBoxAdapter(
                      child: _BotEntry(
                        isEn: isEn,
                        onPressed: () => _open(GuideDestination.batteryBot),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourBanner extends StatelessWidget {
  const _TourBanner({required this.isEn, required this.onPressed});
  final bool isEn;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => LuxeGlass(
    selected: true,
    radius: 24,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const LuxeMedallion(
              icon: Icons.explore_outlined,
              accent: LuxeColors.emerald,
              size: 46,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                isEn
                    ? 'A 4-step tour of the main screens.'
                    : 'Làm quen 4 bước với các màn hình chính.',
                style: const TextStyle(
                  color: LuxeColors.text,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: onPressed,
          child: Text(
            isEn ? 'Start tour' : 'Bắt đầu hướng dẫn',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.item,
    required this.isEn,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });
  final GuideItem item;
  final bool isEn;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final lang = isEn ? 'en' : 'vi';
    final note = item.note(lang);
    final steps = item.steps(lang);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LuxeGlass(
      selected: expanded,
      radius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: '${item.title(lang)}. ${item.summary(lang)}',
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LuxeMedallion(
                        icon: item.category.icon,
                        accent: expanded ? LuxeColors.emerald : null,
                        size: 42,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title(lang),
                              style: const TextStyle(
                                color: LuxeColors.text,
                                fontWeight: FontWeight.w500,
                                fontSize: 15.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.summary(lang),
                              style: LuxeText.caption.copyWith(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          color: LuxeColors.platinumMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 320),
            curve: LuxeMotion.enter,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < steps.length; i++)
                          _Step(
                            number: i + 1,
                            text: steps[i],
                            last: i == steps.length - 1,
                          ),
                        if (note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 2),
                            child: Text(
                              note,
                              style: LuxeText.caption.copyWith(fontSize: 12.5),
                            ),
                          ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: onOpen,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: Text(
                            item.destination.actionLabel(lang),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Numbered step on a hairline rail.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text, required this.last});
  final int number;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LuxeColors.emerald.withValues(alpha: 0.12),
                  border: Border.all(
                    color: LuxeColors.emerald.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: LuxeColors.emerald,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: LuxeColors.hairlineStrong,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            child: Text(
              text,
              style: const TextStyle(
                color: LuxeColors.text,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _BotEntry extends StatelessWidget {
  const _BotEntry({required this.isEn, required this.onPressed});
  final bool isEn;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onPressed,
      child: LuxeGlass(
        radius: 22,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const BatteryBotMascot(
              size: BatteryBotSize.avatar,
              mood: BatteryBotMood.happy,
              customWidth: 48,
              customHeight: 48,
              enableFloating: false,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEn ? 'Ask Pinova Bot' : 'Hỏi Pinova Bot',
                    style: const TextStyle(
                      color: LuxeColors.text,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isEn
                        ? 'Quick help, even offline.'
                        : 'Hỏi về app, xe, pin và sạc.',
                    style: LuxeText.caption.copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: LuxeColors.dim),
          ],
        ),
      ),
    ),
  );
}
