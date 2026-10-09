import 'package:flutter/material.dart';

import '../../../core/theme/app_ui_colors.dart';

/// Danh sách các chip gợi ý phản hồi nhanh theo ngữ cảnh (Context-aware Quick Reply Chips)
class QuickReplyChips extends StatelessWidget {
  const QuickReplyChips({
    super.key,
    required this.onSelect,
    this.customSuggestions,
    this.currentSoc,
    this.isCharging = false,
  });

  final ValueChanged<String> onSelect;
  final List<String>? customSuggestions;
  final double? currentSoc;
  final bool isCharging;

  List<String> _getSuggestions() {
    if (customSuggestions != null && customSuggestions!.isNotEmpty) {
      return customSuggestions!;
    }

    if (isCharging) {
      return const [
        '⏱️ Khi nào sạc đầy?',
        '⚡ Xem công suất sạc',
        '🛑 Ngắt nguồn sạc',
        '💡 Đặt lịch sạc đêm',
      ];
    }

    if (currentSoc != null && currentSoc! < 20.0) {
      return const [
        '⚡ Bật sạc thông minh ngay',
        '📍 Tìm trạm sạc gần đây',
        '🔋 Còn chạy được bao nhiêu km?',
        '🛡️ Mẹo tránh cạn kiệt cell pin',
      ];
    }

    return const [
      '🔋 Pin xe còn bao nhiêu?',
      '⚡ Bật sạc thông minh',
      '🏍️ Tóm tắt chuyến đi gần nhất',
      '💡 Mẹo tiết kiệm điện',
      '📅 Hẹn giờ sạc lúc 22h',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final uiColors = AppUiColors.of(context);
    final suggestions = _getSuggestions();

    return SizedBox(
      height:
          48 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final text = suggestions[index];
          final isDark = uiColors.dark;
          return ActionChip(
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            label: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: uiColors.text,
              ),
            ),
            backgroundColor: isDark
                ? const Color(0xFF131F33).withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF10B981).withValues(alpha: 0.35)
                    : uiColors.primary.withValues(alpha: 0.35),
                width: 1.1,
              ),
            ),
            elevation: 0,
            pressElevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            onPressed: () => onSelect(text),
          );
        },
      ),
    );
  }
}
