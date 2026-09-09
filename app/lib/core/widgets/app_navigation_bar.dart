import 'package:flutter/material.dart';
import '../theme/cockpit_design_system.dart';
import '../theme/app_ui_colors.dart';

/// Equal-width, uniform destinations with smooth animations and emerald glow indicator.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const destinations = [
    (Icons.dashboard_rounded, 'Tổng quan'),
    (Icons.bolt_rounded, 'Sạc pin'),
    (Icons.history_rounded, 'Lịch sử'),
    (Icons.tune_rounded, 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    final ui = AppUiColors.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);

    return Container(
      decoration: BoxDecoration(
        color: (Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
                ui.surface)
            .withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: ui.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: ui.dark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: SizedBox(
            height: 58,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < destinations.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      selected: selectedIndex == i,
                      button: true,
                      label: 'Tab ${destinations[i].$2}',
                      hint: 'Chuyển sang màn hình ${destinations[i].$2}',
                      onTap: () => onSelected(i),
                      child: InkWell(
                        key: ValueKey('navigation-destination-$i'),
                        onTap: () => onSelected(i),
                        borderRadius:
                            BorderRadius.circular(CockpitRadius.medium),
                        splashColor:
                            CockpitColors.emerald.withValues(alpha: 0.15),
                        highlightColor:
                            CockpitColors.emerald.withValues(alpha: 0.08),
                        child: AnimatedContainer(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: selectedIndex == i
                                ? CockpitColors.emerald.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(CockpitRadius.medium),
                            border: Border.all(
                              color: selectedIndex == i
                                  ? CockpitColors.emerald.withValues(alpha: 0.3)
                                  : Colors.transparent,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedScale(
                                duration: duration,
                                curve: Curves.easeOutBack,
                                scale: selectedIndex == i ? 1.12 : 1.0,
                                child: Icon(
                                  destinations[i].$1,
                                  size: 22,
                                  color: selectedIndex == i
                                      ? CockpitColors.emeraldStrong
                                      : ui.muted,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                destinations[i].$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: CockpitTypography.label(
                                  fontSize: 11,
                                  fontWeight: selectedIndex == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selectedIndex == i
                                      ? CockpitColors.emeraldStrong
                                      : ui.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
