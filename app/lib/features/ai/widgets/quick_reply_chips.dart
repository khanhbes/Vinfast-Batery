import 'package:flutter/material.dart';

import '../../../core/theme/luxe_theme.dart';

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

    // Only things the app can do (no station finder, no clock-time
    // schedule, no trip summary — Task 125).
    if (isCharging) {
      return const [
        'Khi nào sạc xong?',
        'Công suất đang sạc',
        'Dừng sạc',
        'Lần sạc gần nhất',
      ];
    }

    if (currentSoc != null && currentSoc! < 20.0) {
      return const [
        'Bật sạc hẹn giờ',
        'Còn đi được bao xa?',
        'Mẹo giữ pin bền',
        'Kết nối ổ Shelly',
      ];
    }

    return const [
      'Pin xe còn bao nhiêu?',
      'Bật sạc hẹn giờ',
      'Lần sạc gần nhất',
      'Mẹo giữ pin bền',
      'Lịch bảo dưỡng',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _getSuggestions();

    return SizedBox(
      height:
          56 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final text = suggestions[index];
          return Center(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => onSelect(text),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: LuxeColors.glass,
                    border: Border.all(color: LuxeColors.hairlineStrong),
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                      color: LuxeColors.text,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
