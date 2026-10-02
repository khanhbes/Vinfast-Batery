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
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final text = suggestions[index];
          return ActionChip(
            label: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: uiColors.text,
              ),
            ),
            backgroundColor: uiColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(19),
              side: BorderSide(
                color: uiColors.border.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            elevation: 0,
            pressElevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            onPressed: () => onSelect(text),
          );
        },
      ),
    );
  }
}
