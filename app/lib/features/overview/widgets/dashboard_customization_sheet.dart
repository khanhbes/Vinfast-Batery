import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/dashboard_preferences_service.dart';
import '../../../core/theme/luxe_theme.dart';
import '../../../core/widgets/luxe_kit.dart';
import '../../../core/widgets/luxe_settings.dart';

/// LUXE sheet (Task 118) cho phép người dùng:
/// - Kéo thả đổi thứ tự 6 widget nội dung (thẻ được "nhấc" lên khi kéo)
/// - Bật/tắt hiển thị từng widget (ngăn không cho tắt toàn bộ)
/// - Khôi phục bố cục mặc định
class DashboardCustomizationSheet extends ConsumerWidget {
  const DashboardCustomizationSheet({super.key});

  static Future<void> show(BuildContext context) => showLuxeSheet<void>(
    context,
    builder: (ctx) => const DashboardCustomizationSheet(),
  );

  IconData _getWidgetIcon(String id) {
    switch (id) {
      case DashboardWidgetId.quickActions:
        return Icons.bolt_rounded;
      case DashboardWidgetId.batteryStatistics:
        return Icons.analytics_rounded;
      case DashboardWidgetId.rangePrediction:
        return Icons.timeline_rounded;
      case DashboardWidgetId.batteryHealth:
        return Icons.health_and_safety_rounded;
      case DashboardWidgetId.recentCharging:
        return Icons.bar_chart_rounded;
      case DashboardWidgetId.efficiencyReference:
        return Icons.speed_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  /// The dragged card lifts: slight scale, deep shadow and an emerald rim.
  Widget _proxyDecorator(Widget child, int index, Animation<double> anim) =>
      AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(anim.value);
          return Transform.scale(
            scale: lerpDouble(1, 1.03, t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55 * t),
                    blurRadius: 24,
                    offset: Offset(0, 10 * t),
                  ),
                  BoxShadow(
                    color: LuxeColors.emerald.withValues(alpha: 0.18 * t),
                    blurRadius: 18,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefService = ref.watch(dashboardPreferencesProvider);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final order = prefService.order;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
            child: LuxeSheetHeader(
              eyebrow: isEn ? 'Overview' : 'Tổng quan',
              title: isEn ? 'Customize Dashboard' : 'Tùy chỉnh bố cục',
              caption: isEn
                  ? 'Drag to reorder, toggle switches to show/hide.'
                  : 'Kéo để đổi thứ tự, bật/tắt để ẩn hoặc hiện.',
              trailing: TextButton.icon(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await prefService.resetToDefault();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEn
                            ? 'Restored default layout'
                            : 'Đã khôi phục bố cục mặc định',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text(isEn ? 'Reset' : 'Mặc định'),
                style: TextButton.styleFrom(
                  foregroundColor: LuxeColors.emerald,
                ),
              ),
            ),
          ),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              proxyDecorator: _proxyDecorator,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: order.length,
              onReorderStart: (_) => HapticFeedback.mediumImpact(),
              onReorder: (oldIndex, newIndex) {
                HapticFeedback.selectionClick();
                prefService.reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final id = order[index];
                final isVisible = prefService.isVisible(id);
                final title = isEn
                    ? DashboardWidgetId.getTitleEn(id)
                    : DashboardWidgetId.getTitleVi(id);
                final subtitle = isEn
                    ? ''
                    : DashboardWidgetId.getSubtitleVi(id);

                return Padding(
                  key: ValueKey('pref_item_$id'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AnimatedOpacity(
                    duration: luxeDuration(context, 240),
                    opacity: isVisible ? 1 : 0.55,
                    child: LuxeGlass(
                      radius: 18,
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          LuxeMedallion(
                            icon: _getWidgetIcon(id),
                            accent: isVisible
                                ? LuxeColors.emerald
                                : LuxeColors.platinumLow,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: LuxeText.item.copyWith(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    softWrap: true,
                                    style: LuxeText.caption.copyWith(
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          LuxeSwitch(
                            value: isVisible,
                            semanticLabel: title,
                            onChanged: (val) {
                              final success = prefService.toggleVisibility(
                                id,
                                val,
                              );
                              if (!success && !val) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEn
                                          ? 'At least one widget must remain visible.'
                                          : 'Phải giữ lại ít nhất 1 widget nội dung.',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Tooltip(
                              message: isEn ? 'Drag to reorder' : 'Kéo để đổi',
                              child: const SizedBox(
                                width: 44,
                                height: 48,
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  color: LuxeColors.platinumMid,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(isEn ? 'Done' : 'Hoàn tất'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
