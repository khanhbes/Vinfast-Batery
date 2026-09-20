import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/dashboard_preferences_service.dart';

/// Modal Bottom Sheet cho phép người dùng:
/// - Kéo thả đổi thứ tự 6 widget nội dung
/// - Bật/tắt hiển thị từng widget (ngăn không cho tắt toàn bộ)
/// - Khôi phục bố cục mặc định
class DashboardCustomizationSheet extends ConsumerWidget {
  const DashboardCustomizationSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DashboardCustomizationSheet(),
    );
  }

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefService = ref.watch(dashboardPreferencesProvider);
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final order = prefService.order;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF13171F), // Cockpit dark sheet
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF2E3846),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEn ? 'Customize Dashboard' : 'Tùy chỉnh bố cục',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isEn
                            ? 'Drag to reorder, toggle switches to show/hide.'
                            : 'Kéo để đổi thứ tự, bật/tắt để ẩn hoặc hiện.',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await prefService.resetToDefault();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isEn
                                ? 'Restored default layout'
                                : 'Đã khôi phục bố cục mặc định',
                          ),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: Text(isEn ? 'Reset' : 'Mặc định'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF242C38)),

          // Reorderable list
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: order.length,
              onReorder: (oldIndex, newIndex) {
                prefService.reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final id = order[index];
                final isVisible = prefService.isVisible(id);
                final title = isEn
                    ? DashboardWidgetId.getTitleEn(id)
                    : DashboardWidgetId.getTitleVi(id);
                final subtitle = isEn ? '' : DashboardWidgetId.getSubtitleVi(id);

                return Container(
                  key: ValueKey('pref_item_$id'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A212D),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isVisible
                          ? const Color(0xFF2E3846)
                          : const Color(0xFF1F2633),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isVisible
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getWidgetIcon(id),
                        color: isVisible
                            ? const Color(0xFF10B981)
                            : Colors.white38,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        color: isVisible ? Colors.white : Colors.white54,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: subtitle.isNotEmpty
                        ? Text(
                            subtitle,
                            softWrap: true,
                            style: TextStyle(
                              color: isVisible
                                  ? const Color(0xFF94A3B8)
                                  : Colors.white30,
                              fontSize: 11.5,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch.adaptive(
                          value: isVisible,
                          activeTrackColor: const Color(0xFF10B981),
                          onChanged: (val) {
                            final success = prefService.toggleVisibility(id, val);
                            if (!success && !val) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isEn
                                        ? 'At least one widget must remain visible.'
                                        : 'Phải giữ lại ít nhất 1 widget nội dung.',
                                  ),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              color: Colors.white38,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom dismiss button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF042F2E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
