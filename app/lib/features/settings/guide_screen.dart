import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/services/guide_registry.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/widgets/app_popup.dart';
import '../../core/widgets/battery_bot_mascot.dart';
import '../../core/widgets/coach_mark_overlay.dart';
import '../../navigation/app_navigation.dart';
import '../smart_charging/smart_charger_setup_hub_screen.dart';
import 'battery_bot_screen.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String? _expandedId;

  void _replayTour() {
    if (!AppNavigation.openTab(context, 0)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showTourAfterAnchorsAttach());
    });
  }

  Future<void> _showTourAfterAnchorsAttach() async {
    final appContext = AppPopup.navigatorKey.currentContext;
    if (appContext == null || !appContext.mounted) return;
    AppNavigation.navigateToTab(appContext, 0);
    final steps = GuideRegistry.getOverviewTourSteps();
    var ready = false;
    for (var frame = 0; frame < 120 && appContext.mounted; frame++) {
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
      if (steps.every((step) => step.anchorKey.currentContext != null)) {
        ready = true;
        break;
      }
    }
    if (!ready || !appContext.mounted) return;
    CoachMarkOverlay.show(
      context: appContext,
      steps: steps,
      showDontShowAgain: false,
      onFinish: () {},
      onSkip: () {},
      onDontShowAgain: (_) {},
    );
  }

  void _open(GuideDestination destination) {
    if (destination.tabIndex case final index?) {
      AppNavigation.openTab(context, index);
      return;
    }
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => destination == GuideDestination.shellySetup
            ? const SmartChargerSetupHubScreen()
            : const BatteryBotScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final ui = AppUiColors.of(context);
    return Scaffold(
      backgroundColor: ui.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    IconButton(
                      tooltip: isEn ? 'Back' : 'Quay lại',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEn ? 'Quick guide' : 'Hướng dẫn nhanh',
                            style: TextStyle(
                              color: ui.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isEn
                                ? 'Learn the main actions, one step at a time.'
                                : 'Tìm nhanh chức năng bạn cần, từng bước một.',
                            style: TextStyle(color: ui.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _TourBanner(isEn: isEn, onPressed: _replayTour),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  isEn ? 'Learn a feature' : 'Chọn chức năng để xem',
                  style: TextStyle(
                    color: ui.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverList.separated(
                itemCount: GuideRegistry.items.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, indent: 58, color: ui.border),
                itemBuilder: (context, index) {
                  final item = GuideRegistry.items[index];
                  return _GuideSection(
                    item: item,
                    isEn: isEn,
                    expanded: _expandedId == item.id,
                    onToggle: () => setState(
                      () =>
                          _expandedId = _expandedId == item.id ? null : item.id,
                    ),
                    onOpen: () => _open(item.destination),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
    );
  }
}

class _TourBanner extends StatelessWidget {
  const _TourBanner({required this.isEn, required this.onPressed});
  final bool isEn;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final ui = AppUiColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: ui.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ui.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.explore_rounded, color: ui.primary, size: 25),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEn
                      ? 'A 4-step tour of the main screens.'
                      : 'Làm quen 4 bước với các màn hình chính.',
                  style: TextStyle(
                    color: ui.text,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(
              isEn ? 'Start tour' : 'Bắt đầu hướng dẫn',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
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
    final ui = AppUiColors.of(context);
    final lang = isEn ? 'en' : 'vi';
    final note = item.note(lang);
    return Column(
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: '${item.title(lang)}. ${item.summary(lang)}',
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ui.primary.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(item.category.icon, color: ui.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title(lang),
                          style: TextStyle(
                            color: ui.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.summary(lang),
                          style: TextStyle(
                            color: ui.muted,
                            height: 1.35,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: ui.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < item.steps(lang).length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}.',
                          style: TextStyle(
                            color: ui.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.steps(lang)[i],
                            style: TextStyle(color: ui.text, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      note,
                      style: TextStyle(
                        color: ui.muted,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      item.destination.actionLabel(lang),
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BotEntry extends StatelessWidget {
  const _BotEntry({required this.isEn, required this.onPressed});
  final bool isEn;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final ui = AppUiColors.of(context);
    return Material(
      color: ui.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn ? 'Ask BatteryBot' : 'Hỏi BatteryBot',
                      style: TextStyle(
                        color: ui.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isEn
                          ? 'Quick help, even offline.'
                          : 'Hỏi nhanh, dùng được cả khi ngoại tuyến.',
                      style: TextStyle(color: ui.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: ui.muted),
            ],
          ),
        ),
      ),
    );
  }
}
