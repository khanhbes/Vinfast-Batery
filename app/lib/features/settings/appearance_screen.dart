import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/appearance_provider.dart';
import '../../core/theme/luxe_theme.dart';
import '../../core/widgets/charge_confirm_control.dart';
import '../../core/widgets/luxe_kit.dart';
import '../../core/widgets/luxe_settings.dart';
import '../../core/widgets/seven_segment_text.dart';
import '../../core/providers/entitlement_provider.dart';
import '../../data/models/app_appearance.dart';
import '../../data/models/entitlement.dart';
import '../premium/premium_gate.dart';

/// Cài đặt → Giao diện (QA 131): the Overview layout, the Charge tab layout
/// and how the charger is switched ON. Saved per account, so every phone
/// signed in shows the same choice.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  static String summary(AppAppearance a) =>
      'Tổng quan: ${a.dashboard.label} · Sạc: ${a.charge.label}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Layouts are Pro (QA 135); the ON confirmation style is free.
    final layoutsAllowed = ref.watch(
      entitlementProvider.select(
        (plan) => plan.allows(PremiumFeature.appearance),
      ),
    );
    final appearance = ref.watch(effectiveAppearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    void layout(VoidCallback apply) => layoutsAllowed
        ? apply()
        : PremiumGate.showUpgrade(context, PremiumFeature.appearance);
    return LuxeScaffold(
      title: 'Giao diện',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const Text(
            'Chọn cách hiển thị Tổng quan, tab Sạc pin và cách bật sạc. '
            'Lựa chọn lưu theo tài khoản: các điện thoại đăng nhập cùng tài '
            'khoản hiển thị giống nhau.',
            style: LuxeText.caption,
          ),
          if (!layoutsAllowed) ...[
            const SizedBox(height: 12),
            const LuxeNotice(
              key: ValueKey('appearance-premium-notice'),
              icon: Icons.workspace_premium_outlined,
              color: LuxeColors.champagne,
              message:
                  'Kiểu Tổng quan và tab Sạc thuộc gói Pro. Kiểu bật sạc '
                  'bên dưới dùng được ở mọi gói.',
            ),
          ],
          const LuxeSectionLabel('Tổng quan'),
          _OptionGrid(
            children: [
              for (final style in DashboardStyle.values)
                _OptionTile(
                  key: ValueKey('appearance-dashboard-${style.id}'),
                  title: style.label,
                  caption: style.caption,
                  selected: appearance.dashboard == style,
                  preview: _DashboardPreview(style),
                  locked: !layoutsAllowed && style != DashboardStyle.values.first,
                  onTap: () => layout(() => notifier.setDashboard(style)),
                ),
            ],
          ),
          const LuxeSectionLabel('Tab Sạc pin'),
          _OptionGrid(
            children: [
              for (final style in ChargeStyle.values)
                _OptionTile(
                  key: ValueKey('appearance-charge-${style.id}'),
                  title: style.label,
                  caption: style.caption,
                  selected: appearance.charge == style,
                  preview: _ChargePreview(style),
                  locked: !layoutsAllowed && style != ChargeStyle.values.first,
                  onTap: () => layout(() => notifier.setCharge(style)),
                ),
            ],
          ),
          const LuxeSectionLabel('Bật sạc'),
          LuxeSettingsGroup(
            children: [
              for (final style in ChargeConfirmStyle.values)
                LuxeSettingsRow(
                  key: ValueKey('appearance-confirm-${style.id}'),
                  icon: switch (style) {
                    ChargeConfirmStyle.slide => Icons.swipe_right_alt_rounded,
                    ChargeConfirmStyle.hold => Icons.touch_app_rounded,
                    ChargeConfirmStyle.tap => Icons.ads_click_rounded,
                  },
                  title: style.label,
                  subtitle: style.caption,
                  accent: appearance.confirm == style
                      ? LuxeColors.emerald
                      : null,
                  trailing: appearance.confirm == style
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: LuxeColors.emerald,
                        )
                      : const SizedBox(width: 24),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setConfirm(style);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (appearance.confirm == ChargeConfirmStyle.tap)
            const LuxeNotice(
              key: ValueKey('appearance-tap-warning'),
              icon: Icons.warning_amber_rounded,
              color: LuxeColors.champagne,
              message:
                  'Bấm 1 lần dễ bật nhầm hơn (ví dụ khi để điện thoại trong '
                  'túi). Bạn vẫn phải đánh dấu ô xác nhận trước, và ổ sạc vẫn '
                  'tự ngắt theo hẹn giờ. Dừng sạc luôn là một nút bấm.',
            )
          else
            const LuxeNotice(
              icon: Icons.lock_outline_rounded,
              message: 'Dừng sạc luôn là một nút bấm thường để tắt được ngay.',
            ),
          const SizedBox(height: 16),
          const Text('XEM THỬ', style: LuxeText.eyebrow),
          const SizedBox(height: 8),
          ChargeConfirmControl(
            key: ValueKey(
              'appearance-confirm-preview-${appearance.confirm.id}',
            ),
            label: 'Vuốt để thử (không bật sạc)',
            onConfirmed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đúng rồi — đây chỉ là thử, không bật sạc.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Two per row, one when the text is large on a narrow phone.
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final perRow = box.maxWidth / scale >= 300 ? 2 : 1;
      final width = (box.maxWidth - 12 * (perRow - 1)) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.title,
    required this.caption,
    required this.selected,
    required this.preview,
    required this.onTap,
    this.locked = false,
  });

  final String title;
  final String caption;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;

  /// Not in the plan (QA 135): shows a PRO tag, tapping explains.
  final bool locked;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label:
        '$title. $caption${selected ? '. Đang dùng' : ''}'
        '${locked ? '. Gói Pro' : ''}',
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected ? const Color(0x1434D399) : LuxeColors.glass,
            border: Border.all(
              color: selected
                  ? LuxeColors.emerald.withValues(alpha: 0.6)
                  : LuxeColors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: LuxeColors.background,
                  border: Border.all(color: LuxeColors.hairline),
                ),
                padding: const EdgeInsets.all(8),
                // A sketch: fixed text size so it scales as a picture.
                child: ExcludeSemantics(
                  child: MediaQuery.withNoTextScaling(
                    child: FittedBox(fit: BoxFit.contain, child: preview),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LuxeText.item.copyWith(fontSize: 14.5),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: LuxeColors.emerald,
                    )
                  else if (locked)
                    const PremiumBadge(tier: PlanTier.pro),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: LuxeText.caption.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Tiny static sketches of each layout (no real data).
class _DashboardPreview extends StatelessWidget {
  const _DashboardPreview(this.style);

  final DashboardStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 96,
    child: switch (style) {
      DashboardStyle.luxe => const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.electric_moped_rounded,
            size: 44,
            color: LuxeColors.platinum,
          ),
          SizedBox(height: 4),
          _Bar(fill: 0.7),
        ],
      ),
      DashboardStyle.lcd => const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SevenSegmentText('68', height: 40, semanticsLabel: ''),
          SizedBox(width: 6),
          Text('%', style: TextStyle(color: LuxeColors.platinum, fontSize: 14)),
          SizedBox(width: 12),
          SevenSegmentText('4818', height: 22, semanticsLabel: ''),
        ],
      ),
      DashboardStyle.compact => GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.5,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: LuxeColors.glassStrong,
                border: Border.all(color: LuxeColors.hairline),
              ),
            ),
        ],
      ),
      DashboardStyle.minimal => const Center(
        child: SizedBox.square(
          dimension: 84,
          child: LuxeRing(value: 0.7, size: 84, stroke: 7),
        ),
      ),
    },
  );
}

class _ChargePreview extends StatelessWidget {
  const _ChargePreview(this.style);

  final ChargeStyle style;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    height: 96,
    child: switch (style) {
      ChargeStyle.dial => const Center(
        child: LuxeRing(value: 0.63, size: 86, stroke: 8),
      ),
      ChargeStyle.bar => const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '63% → 80%',
            style: TextStyle(color: LuxeColors.text, fontSize: 16),
          ),
          SizedBox(height: 8),
          _Bar(fill: 0.63, target: 0.8),
        ],
      ),
      ChargeStyle.lcd => const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SevenSegmentText('63', height: 38, semanticsLabel: ''),
          SizedBox(height: 6),
          SevenSegmentText('0:38', height: 18, semanticsLabel: ''),
        ],
      ),
      ChargeStyle.detail => GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2.4,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final t in const ['412 W', '231 V', '1.8 A', '96 Wh'])
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: LuxeColors.glassStrong,
              ),
              child: Text(
                t,
                style: const TextStyle(color: LuxeColors.text, fontSize: 11),
              ),
            ),
        ],
      ),
    },
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fill, this.target});

  final double fill;
  final double? target;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 10,
    child: Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: LuxeColors.glassStrong,
          ),
        ),
        FractionallySizedBox(
          widthFactor: fill,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: LuxeColors.emerald,
            ),
          ),
        ),
        if (target != null)
          Align(
            alignment: Alignment(target! * 2 - 1, 0),
            child: Container(width: 2, color: LuxeColors.platinumHi),
          ),
      ],
    ),
  );
}
