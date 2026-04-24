import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';

/// ========================================================================
/// Daily Brief — Dark Premium V3
/// Thẻ tóm tắt "Việc cần làm ngay" — nền tối, glass borders
/// ========================================================================

class DailyBriefModel {
  final String id;
  final String title;
  final String content;
  final DailyBriefType type;
  final String? actionLabel;

  const DailyBriefModel({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    this.actionLabel,
  });
}

enum DailyBriefType { alert, warning, success, info }

class DailyBriefSection extends StatelessWidget {
  final List<DailyBriefModel> briefs;

  const DailyBriefSection({super.key, required this.briefs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Việc cần làm ngay',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Xem tất cả',
              style: TextStyle(
                color: AppColors.vinfastBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...briefs.asMap().entries.map((entry) {
          final index = entry.key;
          final brief = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < briefs.length - 1 ? 12 : 0,
            ),
            child: _BriefCard(brief: brief, index: index),
          );
        }),
      ],
    );
  }
}

class _BriefCard extends StatelessWidget {
  final DailyBriefModel brief;
  final int index;

  const _BriefCard({required this.brief, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_icon, color: _iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brief.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  brief.content,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (brief.actionLabel != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        brief.actionLabel!,
                        style: TextStyle(
                          color: AppColors.vinfastBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.vinfastBlue,
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideX(begin: -0.1);
  }

  IconData get _icon {
    switch (brief.type) {
      case DailyBriefType.alert:
        return Icons.error_rounded;
      case DailyBriefType.warning:
        return Icons.warning_rounded;
      case DailyBriefType.success:
        return Icons.check_circle_rounded;
      case DailyBriefType.info:
        return Icons.info_rounded;
    }
  }

  Color get _iconColor {
    switch (brief.type) {
      case DailyBriefType.alert:
        return AppColors.error;
      case DailyBriefType.warning:
        return AppColors.warning;
      case DailyBriefType.success:
        return AppColors.success;
      case DailyBriefType.info:
        return AppColors.info;
    }
  }
}
